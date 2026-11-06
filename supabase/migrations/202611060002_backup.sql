begin;
create function public.export_business() returns jsonb language plpgsql security definer set search_path='' as $$declare b uuid;begin
 perform private.require(public.is_owner(),'Only the owner can export a business');b:=public.current_business();
 return jsonb_build_object('format',1,'business_id',b,'exported_at',now(),'business',(select to_jsonb(x) from public.businesses x where id=b),'customers',coalesce((select jsonb_agg(to_jsonb(x)) from public.customers x where business_id=b),'[]'),'opportunities',coalesce((select jsonb_agg(to_jsonb(x)) from public.opportunities x where business_id=b),'[]'),'events',coalesce((select jsonb_agg(to_jsonb(x)) from public.events x where business_id=b),'[]'),'activity',coalesce((select jsonb_agg(to_jsonb(x)) from public.activity x where business_id=b),'[]'));
end$$;
revoke all on function public.export_business() from public,anon;grant execute on function public.export_business() to authenticated;
-- The worker verifies the signed export and owner identity before this service-only transaction.
create function public.restore_business(tenant uuid,snapshot jsonb,owner_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare r jsonb;old_business uuid;begin
 perform private.require(auth.role()='service_role','Server authorization required');perform private.require(exists(select 1 from public.memberships where user_id=owner_id and business_id=tenant and role='owner' and active),'Active owner required');
 perform private.require((snapshot->>'business_id')::uuid=tenant and snapshot->>'format'='1','Backup belongs to a different business or format');
 perform pg_advisory_xact_lock(hashtextextended(tenant::text,0));
 for r in select * from jsonb_array_elements(snapshot->'customers') loop
  perform private.require((r->>'business_id')::uuid=tenant,'Cross-business backup rejected');select business_id into old_business from public.customers where id=(r->>'id')::uuid;perform private.require(old_business is null or old_business=tenant,'Record identity belongs to another business');
  insert into public.customers(id,business_id,name,phone,phone_original,version) values((r->>'id')::uuid,tenant,r->>'name',r->>'phone',r->>'phone_original',(r->>'version')::int+1) on conflict(id) do update set name=excluded.name,phone=excluded.phone,phone_original=excluded.phone_original,version=public.customers.version+1;
 end loop;
 for r in select * from jsonb_array_elements(snapshot->'opportunities') loop
  perform private.require((r->>'business_id')::uuid=tenant,'Cross-business backup rejected');select business_id into old_business from public.opportunities where id=(r->>'id')::uuid;perform private.require(old_business is null or old_business=tenant,'Record identity belongs to another business');
  insert into public.opportunities(id,business_id,customer_id,stage,archived,version,data,updated_at) values((r->>'id')::uuid,tenant,(r->>'customer_id')::uuid,r->>'stage',(r->>'archived')::boolean,(r->>'version')::int+1,r->'data',now()) on conflict(id) do update set stage=excluded.stage,archived=excluded.archived,data=excluded.data,version=public.opportunities.version+1,updated_at=now();
 end loop;
 for r in select * from jsonb_array_elements(snapshot->'events') loop
  perform private.require((r->>'business_id')::uuid=tenant,'Cross-business backup rejected');select business_id into old_business from public.events where id=(r->>'id')::uuid;perform private.require(old_business is null or old_business=tenant,'Record identity belongs to another business');
  insert into public.events(id,business_id,opportunity_id,type,status,version,data,scheduled_at) values((r->>'id')::uuid,tenant,(r->>'opportunity_id')::uuid,r->>'type',r->>'status',(r->>'version')::int+1,r->'data',(r->>'scheduled_at')::timestamptz) on conflict(id) do update set status=excluded.status,data=excluded.data,scheduled_at=excluded.scheduled_at,version=public.events.version+1;
 end loop;
 -- Restoring a snapshot never erases newer audit history. The signed original history remains in the backup.
 perform private.audit(tenant,null,'Business backup restored',jsonb_build_object('exported_at',snapshot->>'exported_at','owner_id',owner_id),'Owner restore');return '{"ok":true}';
end$$;
revoke all on function public.restore_business(uuid,jsonb,uuid) from public,anon,authenticated;grant execute on function public.restore_business(uuid,jsonb,uuid) to service_role;
create function public.claim_push(tenant uuid) returns boolean language plpgsql security definer set search_path='' as $$declare revision bigint;begin
 perform private.require(auth.role()='service_role','Server authorization required');select coalesce(max(id),0) into revision from public.activity where business_id=tenant;
 insert into private.requests(business_id,key,actor,fingerprint,response) values(tenant,'push:'||revision,'server','', '{}') on conflict do nothing;return found;
end$$;
revoke all on function public.claim_push(uuid) from public,anon,authenticated;grant execute on function public.claim_push(uuid) to service_role;
commit;
