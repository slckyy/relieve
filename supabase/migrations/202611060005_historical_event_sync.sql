create or replace function private.sync_event(b uuid,job uuid,kind text,appt jsonb,description text,reactivate boolean default false) returns void language plpgsql security definer set search_path='' as $$declare e public.events;nm text;begin
 select * into e from public.events where business_id=b and opportunity_id=job and type=kind;
 if appt is null or appt='null'::jsonb then update public.events set status='canceled',version=version+1,data=data||jsonb_build_object('canceledAt',now()) where business_id=b and opportunity_id=job and type=kind and status='active';return;end if;
 if e.id is not null and e.status<>'active' and not reactivate then update public.events set data=data||jsonb_build_object('appointment',appt,'details',description),scheduled_at=(appt->>'instant')::timestamptz,version=version+1 where id=e.id;return;end if;
 select c.name into nm from public.opportunities o join public.customers c on c.id=o.customer_id and c.business_id=o.business_id where o.id=job and o.business_id=b;
 insert into public.events(business_id,opportunity_id,type,status,data,scheduled_at) values(b,job,kind,'active',jsonb_build_object('name',nm||' · '||kind,'details',description,'appointment',appt),(appt->>'instant')::timestamptz)
 on conflict(business_id,opportunity_id,type) do update set status='active',version=public.events.version+1,data=excluded.data,scheduled_at=excluded.scheduled_at;
end$$;
