-- relieve: all business writes go through transactional commands; no client table writes.
begin;
create schema if not exists private;
revoke all on schema private from public,anon,authenticated;
create table public.businesses(id uuid primary key default gen_random_uuid(),name text not null,timezone text not null default 'America/Chicago',review_link text not null default 'google.com',review_verified boolean not null default false,phone text not null default '',is_demo boolean not null default false,version int not null default 1);
create table public.memberships(user_id uuid primary key references auth.users(id),business_id uuid not null references public.businesses(id),name text not null,role text not null check(role in ('owner','worker')),active boolean not null default true);
create index membership_business on public.memberships(business_id);
create table public.customers(id uuid primary key default gen_random_uuid(),business_id uuid not null references public.businesses(id),name text not null,phone text not null,phone_original text not null,version int not null default 1,unique(business_id,id));
create index customer_phone on public.customers(business_id,phone);
create table public.opportunities(id uuid primary key default gen_random_uuid(),business_id uuid not null references public.businesses(id),customer_id uuid not null,stage text not null check(stage in ('Acquisition','Quoting','Work','Review','Done','Lost')),archived boolean not null default false,version int not null default 1,data jsonb not null,updated_at timestamptz not null default now(),unique(business_id,id),foreign key(business_id,customer_id) references public.customers(business_id,id));
create index opportunity_list on public.opportunities(business_id,stage,archived,updated_at desc,id);
create index opportunity_customer on public.opportunities(business_id,customer_id);
create table public.events(id uuid primary key default gen_random_uuid(),business_id uuid not null references public.businesses(id),opportunity_id uuid,type text not null check(type in ('Quoting','Work','Follow-up','Manual')),status text not null default 'active' check(status in ('active','completed','canceled')),version int not null default 1,data jsonb not null,scheduled_at timestamptz not null,foreign key(business_id,opportunity_id) references public.opportunities(business_id,id),unique(business_id,opportunity_id,type));
create index event_list on public.events(business_id,scheduled_at,id);
create table public.activity(id bigint generated always as identity primary key,business_id uuid not null references public.businesses(id),user_id uuid,actor text not null,opportunity_id uuid,action text not null,at timestamptz not null default now(),data jsonb not null default '{}');
create index activity_business on public.activity(business_id,id desc);
create index activity_opportunity on public.activity(business_id,opportunity_id,id desc);
create table public.notification_reads(user_id uuid primary key references auth.users(id),last_id bigint not null default 0);
create table public.push_subscriptions(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),business_id uuid not null references public.businesses(id),endpoint text not null unique,subscription jsonb not null,created_at timestamptz not null default now());
create table private.requests(business_id uuid not null,key text not null,actor text not null,fingerprint text not null,response jsonb not null,created_at timestamptz not null default now(),primary key(business_id,key,actor));
create table private.rate_limits(key text primary key,count int not null,expires timestamptz not null);
create table private.worker_invites(id uuid primary key default gen_random_uuid(),business_id uuid not null references public.businesses(id),email text not null,name text not null,created_by uuid not null,created_at timestamptz default now());

create function private.member() returns public.memberships language sql stable security definer set search_path='' as $$select m from public.memberships m where m.user_id=auth.uid() and m.active$$;
create function public.current_business() returns uuid language sql stable security definer set search_path='' as $$select (private.member()).business_id$$;
create function public.is_owner() returns boolean language sql stable security definer set search_path='' as $$select coalesce((private.member()).role='owner',false)$$;
revoke all on function public.current_business(),public.is_owner() from public,anon;
grant execute on function public.current_business(),public.is_owner() to authenticated;
alter table public.businesses enable row level security;
alter table public.memberships enable row level security;
alter table public.customers enable row level security;
alter table public.opportunities enable row level security;
alter table public.events enable row level security;
alter table public.activity enable row level security;
alter table public.notification_reads enable row level security;
alter table public.push_subscriptions enable row level security;
create policy business_read on public.businesses for select to authenticated using(id=(select public.current_business()));
create policy membership_read on public.memberships for select to authenticated using(user_id=auth.uid() or (business_id=(select public.current_business()) and (select public.is_owner())));
create policy customer_read on public.customers for select to authenticated using(business_id=(select public.current_business()));
create policy job_read on public.opportunities for select to authenticated using(business_id=(select public.current_business()) and (not archived or (select public.is_owner())));
create policy event_read on public.events for select to authenticated using(business_id=(select public.current_business()));
create policy activity_read on public.activity for select to authenticated using(business_id=(select public.current_business()));
create policy reads_own on public.notification_reads for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid() and public.current_business() is not null);
create policy push_own on public.push_subscriptions for all to authenticated using(user_id=auth.uid() and business_id=(select public.current_business())) with check(user_id=auth.uid() and business_id=(select public.current_business()));
revoke all on public.businesses,public.memberships,public.customers,public.opportunities,public.events,public.activity,public.notification_reads,public.push_subscriptions from anon,authenticated;
grant select on public.businesses,public.memberships,public.customers,public.opportunities,public.events,public.activity to authenticated;
grant select,insert,update,delete on public.notification_reads,public.push_subscriptions to authenticated;
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;

create function private.require(ok boolean,message text) returns void language plpgsql as $$begin if not coalesce(ok,false) then raise exception '%',message using errcode='P0001';end if;end$$;
create function private.txt(value text,label text,required boolean default true,maximum int default 10000) returns text language plpgsql as $$begin value:=btrim(coalesce(value,''));perform private.require((not required or length(value)>0) and length(value)<=maximum,label||' is required or too long');return value;end$$;
create function private.phone(value text) returns text language plpgsql as $$begin value:=regexp_replace(coalesce(value,''),'[[:space:]().-]','','g');if value~'^\d{10}$' then value:='+1'||value;elsif value~'^1\d{10}$' then value:='+'||value;end if;perform private.require(value~'^\+[1-9]\d{7,14}$','Enter a valid phone number, including country code');return value;end$$;
create function private.day(value text,label text) returns text language plpgsql as $$declare d date;begin perform private.require(value~'^\d{4}-\d{2}-\d{2}$',label||' is required');d:=value::date;perform private.require(to_char(d,'YYYY-MM-DD')=value,label||' is invalid');return value;end$$;
create function private.amount(value text,free boolean default false) returns bigint language plpgsql as $$declare n bigint;begin perform private.require(value~'^\d{1,9}(\.\d{1,2})?$','Enter a nonnegative amount with at most two decimals');n:=round(value::numeric*100);perform private.require(n>0 or free,'Confirm that this is a genuinely free job');return n;end$$;
create function private.appointment(day text,clock text,zone text,required boolean default false) returns jsonb language plpgsql as $$declare local_time timestamp; instant timestamptz;begin
 if coalesce(day,'')='' then perform private.require(not required and coalesce(clock,'')='','An appointment date is required');return null;end if;
 perform private.day(day,'Appointment date');perform private.require(coalesce(clock,'')='' or clock~'^([01]\d|2[0-3]):[0-5]\d$','Appointment time is invalid');
 local_time:=(day||'T'||coalesce(nullif(clock,''),'00:00'))::timestamp;instant:=local_time at time zone zone;
 perform private.require(instant at time zone zone=local_time and (instant-interval '1 hour') at time zone zone<>local_time and (instant+interval '1 hour') at time zone zone<>local_time,'That local time is skipped or repeated by daylight saving; choose another time');
 return jsonb_build_object('date',day,'time',coalesce(clock,''),'timezone',zone,'instant',instant);
end$$;
create function private.audit(b uuid,job uuid,action text,details jsonb default '{}',actor text default null) returns void language sql security definer set search_path='' as $$insert into public.activity(business_id,user_id,actor,opportunity_id,action,data) values(b,auth.uid(),coalesce(actor,(private.member()).name,'Website'),job,action,details)$$;
create function private.sync_event(b uuid,job uuid,kind text,appt jsonb,description text,reactivate boolean default false) returns void language plpgsql security definer set search_path='' as $$declare e public.events;nm text;begin
 select * into e from public.events where business_id=b and opportunity_id=job and type=kind;
 if appt is null or appt='null'::jsonb then update public.events set status='canceled',version=version+1,data=data||jsonb_build_object('canceledAt',now()) where business_id=b and opportunity_id=job and type=kind and status='active';return;end if;
 if e.id is not null and e.status<>'active' and not reactivate then return;end if;
 select c.name into nm from public.opportunities o join public.customers c on c.id=o.customer_id and c.business_id=o.business_id where o.id=job and o.business_id=b;
 insert into public.events(business_id,opportunity_id,type,status,data,scheduled_at) values(b,job,kind,'active',jsonb_build_object('name',nm||' · '||kind,'details',description,'appointment',appt),(appt->>'instant')::timestamptz)
 on conflict(business_id,opportunity_id,type) do update set status='active',version=public.events.version+1,data=excluded.data,scheduled_at=excluded.scheduled_at;
end$$;
create function private.add_request(b uuid,p jsonb,source text) returns jsonb language plpgsql security definer set search_path='' as $$declare cid uuid;oid uuid;matches jsonb;num text;nm text;req text;demo boolean;begin
 nm:=private.txt(p->>'name','Customer name',true,200);num:=private.phone(p->>'phone');req:=private.txt(p->>'request','Customer work request');
 select is_demo into demo from public.businesses where id=b;
 if demo then perform private.require(num~'^\+1[2-9]\d{2}55501\d{2}$','Demo only: use a fictional US number such as (417) 555-0100');end if;
 select jsonb_agg(jsonb_build_object('id',id,'name',name)) into matches from public.customers where business_id=b and phone=num;
 if matches is not null then
   if source='website' then select id into cid from public.customers where business_id=b and phone=num and lower(name)=lower(nm) order by id limit 1;
   elsif coalesce(p->>'customerId','')<>'' then select id into cid from public.customers where business_id=b and phone=num and id=(p->>'customerId')::uuid;perform private.require(cid is not null,'Select a matching returning customer');
   elsif not coalesce((p->>'sharedPhone')::boolean,false) then raise exception 'Returning customer confirmation required' using detail=matches::text;end if;
 end if;
 if cid is null then insert into public.customers(business_id,name,phone,phone_original) values(b,nm,num,p->>'phone') returning id into cid;end if;
 insert into public.opportunities(business_id,customer_id,stage,data) values(b,cid,'Acquisition',jsonb_build_object('request',req,'createdAt',now(),'stageEnteredAt',now(),'stageDates',jsonb_build_object('Acquisition',now()),'source',source,'submittedName',nm,'notes','','losses','[]'::jsonb)) returning id into oid;
 perform private.audit(b,oid,case when source='website' then 'Website request received' else 'Customer request added' end,jsonb_build_object('source',source));return jsonb_build_object('id',oid);
end$$;

create function public.command(p jsonb,request_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.memberships;b public.businesses;o public.opportunities;prev jsonb;d jsonb;c public.customers;e public.events;act text;result jsonb;cached private.requests;fingerprint text;v bigint;appt jsonb;followup jsonb;status text;part jsonb;loss jsonb;newstage text;day text;typ text;field text;
begin
 m:=private.member();perform private.require(m.user_id is not null,'Sign in with an authorized business account');select * into b from public.businesses where id=m.business_id;
 perform pg_advisory_xact_lock(hashtextextended(b.id::text,0));
 act:=p->>'action';fingerprint:=md5(p::text);
 select * into cached from private.requests where business_id=b.id and key=request_key::text and actor=m.user_id::text;
 if found then perform private.require(cached.fingerprint=fingerprint,'Retry key does not match this action');return cached.response;end if;
 if act='addCustomer' then result:=private.add_request(b.id,p,'manual');
 elsif act='settings' then
   perform private.require(m.role='owner','Only the owner can change business settings');perform private.require(b.version=(p->>'version')::int,'Conflict: refresh the latest business settings');
   perform private.require(exists(select 1 from pg_timezone_names where name=p->>'timezone'),'Choose a valid IANA timezone');
   perform private.require(p->>'reviewLink'='google.com' or ((p->>'reviewLink')~'^https://([a-z0-9-]+\.)?(google\.com|g\.page|maps\.app\.goo\.gl)/.+' and coalesce((p->>'reviewVerified')::boolean,false)),'Confirm a direct HTTPS Google review destination for this business');
   update public.businesses set name=private.txt(p->>'name','Business name',true,200),timezone=p->>'timezone',phone=case when coalesce(p->>'phone','')='' then '' else private.phone(p->>'phone') end,review_link=p->>'reviewLink',review_verified=(p->>'reviewLink'<>'google.com'),version=version+1 where id=b.id;
   perform private.audit(b.id,null,'Business settings changed',jsonb_build_object('before',to_jsonb(b)));result:='{"ok":true}';
 elsif act='removeWorker' then
   perform private.require(m.role='owner','Only the owner can manage staff');update public.memberships set active=false where business_id=b.id and user_id=(p->>'id')::uuid and role='worker';perform private.require(found,'Worker not found');perform private.audit(b.id,null,'Worker access removed');result:='{"ok":true}';
 elsif act='resetDemo' then
   perform private.require(m.role='owner' and b.is_demo and p->>'confirm'='ARCHIVE DEMO','This action is only available to the demo owner');
   update public.opportunities set archived=true,version=version+1,updated_at=now() where business_id=b.id and not archived;
   update public.events set status='canceled',version=version+1 where business_id=b.id and status='active';
   perform private.audit(b.id,null,'Demo records archived');result:='{"ok":true}';
 elsif act in ('saveEvent','cancelEvent','deleteEvent','completeEvent') then
   if coalesce(p->>'id','')<>'' then select * into e from public.events where id=(p->>'id')::uuid and business_id=b.id;perform private.require(e.id is not null,'Event not found');perform private.require(e.version=(p->>'version')::int,'Conflict: refresh this event');end if;
   if e.opportunity_id is not null then
     select * into o from public.opportunities where id=e.opportunity_id and business_id=b.id;
     perform private.require(o.version=(p->>'opportunityVersion')::int,'Conflict: refresh the linked job');perform private.require(not o.archived and o.stage<>'Lost','Recover or restore the job before changing its appointment');
     perform private.require(act in ('saveEvent','cancelEvent'),'Linked appointments are retained; cancel instead of deleting');
     typ:=case when e.type='Work' then 'work' else 'quoting' end;field:=case when e.type='Follow-up' then 'followup' else 'appointment' end;d:=o.data;prev:=d;
     perform private.require(not (e.type='Work' and d#>>'{work,finishedDate}' is not null),'Completed work cannot be rescheduled');
     if act='cancelEvent' then perform private.require((p->>'confirm')::boolean,'Confirm cancellation');appt:=null;else appt:=private.appointment(p->>'date',p->>'time',b.timezone,true);end if;
     d:=jsonb_set(d,array[typ,field],coalesce(appt,'null'::jsonb));
     perform private.sync_event(b.id,o.id,e.type,appt,private.txt(p->>'details','Event details',false),true);
     update public.opportunities set data=d,version=version+1,updated_at=now() where id=o.id;
     perform private.audit(b.id,o.id,'Linked appointment updated',jsonb_build_object('before',prev,'after',d));result:=jsonb_build_object('id',e.id);
   else
     if act='saveEvent' then
       appt:=private.appointment(p->>'date',p->>'time',b.timezone,true);d:=jsonb_build_object('name',private.txt(p->>'name','Event name',true,200),'details',private.txt(p->>'details','Event details',false),'appointment',appt);
       if e.id is null then insert into public.events(business_id,type,data,scheduled_at) values(b.id,'Manual',d,(appt->>'instant')::timestamptz) returning * into e;
       else update public.events set data=d,scheduled_at=(appt->>'instant')::timestamptz,version=version+1,status=case when coalesce((p->>'reactivate')::boolean,false) then 'active' else status end where id=e.id;end if;
     else perform private.require(e.id is not null and coalesce((p->>'confirm')::boolean,false),'Confirm event action');
       if act='deleteEvent' then delete from public.events where id=e.id;else update public.events set status=case when act='completeEvent' then 'completed' else 'canceled' end,version=version+1,data=data||jsonb_build_object('closedAt',now()) where id=e.id;end if;
     end if;
     perform private.audit(b.id,null,act,jsonb_build_object('before',to_jsonb(e),'after',d));result:=jsonb_build_object('id',e.id);
   end if;
 else
   select * into o from public.opportunities where id=(p->>'id')::uuid and business_id=b.id;
   perform private.require(o.id is not null,'Job not found');perform private.require(o.version=(p->>'version')::int,'Conflict: someone changed this job. Refresh before saving');perform private.require(not o.archived or act='restore','Restore the archived job before editing');
   d:=o.data;prev:=d;newstage:=o.stage;
   if act='editCustomer' then
     select * into c from public.customers where id=o.customer_id and business_id=b.id;perform private.require(c.version=(p->>'customerVersion')::int,'Conflict: refresh this customer profile');
     perform private.require(not exists(select 1 from public.customers where business_id=b.id and phone=private.phone(p->>'phone') and id<>c.id) or coalesce((p->>'sharedPhone')::boolean,false),'Confirm that this number is legitimately shared by another customer');
     if b.is_demo then perform private.require(private.phone(p->>'phone')~'^\+1[2-9]\d{2}55501\d{2}$','Demo requires a reserved 555-01xx phone number');end if;
     update public.customers set name=private.txt(p->>'name','Customer name',true,200),phone=private.phone(p->>'phone'),phone_original=p->>'phone',version=version+1 where id=c.id;
     d:=d||jsonb_build_object('request',private.txt(p->>'request','Customer work request'));perform private.audit(b.id,o.id,'Customer profile corrected',jsonb_build_object('before',to_jsonb(c),'affects','Shared profile across jobs'));
   elsif act in ('quote','editQuote') then
     perform private.require(case when act='quote' then o.stage='Acquisition' else d?'quoting' end,'Quoting is unavailable for this job');
     perform private.require(p->>'method' in ('In person','By phone','Remote'),'Choose a quoting method');
     appt:=private.appointment(p->>'date',p->>'time',b.timezone);followup:=private.appointment(p->>'followupDate',p->>'followupTime',b.timezone);
     status:=coalesce(p->>'status',d#>>'{quoting,status}','Not yet quoted');perform private.require(status in ('Not yet quoted','Quote given — awaiting decision','Accepted'),'Choose a valid quote status');
     v:=case when coalesce(p->>'amount','')='' then null else private.amount(p->>'amount',coalesce((p->>'free')::boolean,false)) end;
     perform private.require(status='Not yet quoted' or v is not null,'Record the estimate amount first');perform private.require(status<>'Accepted' or d#>>'{quoting,status}'='Accepted' or coalesce((p->>'approved')::boolean,false),'Confirm actual customer approval');
     part:=coalesce(d->'quoting','{}')||jsonb_build_object('method',p->>'method','address',private.txt(p->>'address','Address',p->>'method'='In person'),'details',private.txt(p->>'details','Quote details'),'appointment',appt,'followup',followup,'estimate',v,'status',status);
     d:=d||jsonb_build_object('quoting',part);if act='quote' then newstage:='Quoting';end if;
     perform private.sync_event(b.id,o.id,'Quoting',appt,part->>'details',act='quote' or coalesce((p->>'reactivate')::boolean,false));
     perform private.sync_event(b.id,o.id,'Follow-up',followup,'Quote decision follow-up',coalesce((p->>'reactivate')::boolean,false));
   elsif act in ('scheduleWork','editWork') then
     perform private.require(case when act='scheduleWork' then o.stage='Quoting' else d?'work' end,'Work scheduling is unavailable');
     perform private.require(act<>'scheduleWork' or coalesce((p->>'approved')::boolean,false),'Confirm that the customer approved this quote');
     appt:=private.appointment(p->>'date',p->>'time',b.timezone,act='scheduleWork');v:=private.amount(p->>'amount',coalesce((p->>'free')::boolean,false));
     part:=coalesce(d->'work','{}')||jsonb_build_object('address',private.txt(p->>'address','Address',false),'amount',v,'details',private.txt(p->>'details','Work details'),'appointment',appt);
     if act='scheduleWork' then part:=part||jsonb_build_object('approvedAt',now());d:=jsonb_set(d,'{quoting,status}','"Accepted"');newstage:='Work';update public.events set status='completed',version=version+1,data=data||jsonb_build_object('completedAt',now()) where business_id=b.id and opportunity_id=o.id and type in ('Quoting','Follow-up') and status='active';end if;
     d:=d||jsonb_build_object('work',part);if part->>'finishedDate' is null then perform private.sync_event(b.id,o.id,'Work',appt,part->>'details',act='scheduleWork' or coalesce((p->>'reactivate')::boolean,false));end if;
   elsif act in ('complete','editCompletion') then
     perform private.require(case when act='complete' then o.stage='Work' else d#>>'{work,finishedDate}' is not null end,'Completed work is unavailable');perform private.require(coalesce((p->>'confirm')::boolean,false),'Confirm actual work completion');
     day:=private.day(p->>'date','Date work was finished');perform private.require(day::date<=(now() at time zone b.timezone)::date,'Completion cannot be in the future');
     d:=jsonb_set(d,'{work}',(d->'work')||jsonb_build_object('finalAmount',private.amount(p->>'amount',coalesce((p->>'free')::boolean,false)),'exactWork',private.txt(p->>'details','Exact work done'),'finishedDate',day));
     if act='complete' then newstage:='Review';d:=d||'{"review":{"outcome":"Pending"}}';end if;
     update public.events set status='completed',version=version+1,data=data||jsonb_build_object('completedAt',now(),'actualCompletionDate',day) where business_id=b.id and opportunity_id=o.id and type='Work';
   elsif act in ('review','editReview') then
     perform private.require(case when act='review' then o.stage='Review' else d?'review' end,'Review is unavailable');perform private.require(p->>'outcome' in ('Sent','Skipped'),'Choose sent or skipped');
     part:=jsonb_build_object('outcome',p->>'outcome','recordedAt',now(),'recordedBy',m.name);
     if p->>'outcome'='Sent' then perform private.require(coalesce((p->>'confirm')::boolean,false),'Acknowledge that you actually sent the request');day:=private.day(p->>'date','Date review was sent');perform private.require(day::date<=(now() at time zone b.timezone)::date and day::date>=(d#>>'{work,finishedDate}')::date,'Review date must follow completion and cannot be in the future');part:=part||jsonb_build_object('sentDate',day,'delivery','Manually recorded; delivery not verified');
     else part:=part||jsonb_build_object('reason',private.txt(p->>'reason','Skip reason',false));end if;
     d:=d||jsonb_build_object('review',part);if act='review' then newstage:='Done';end if;
   elsif act='lost' then
     perform private.require(o.stage in ('Acquisition','Quoting','Work'),'Only Acquisition, Quoting or Work can move to Lost');loss:=jsonb_build_object('reason',private.txt(p->>'reason','Reason for losing'),'from',o.stage,'at',now());d:=jsonb_set(d,'{losses}',coalesce(d->'losses','[]')||jsonb_build_array(loss));newstage:='Lost';
     update public.events set status='canceled',version=version+1,data=data||jsonb_build_object('canceledAt',now(),'cancelReason','Job moved to Lost') where business_id=b.id and opportunity_id=o.id and status='active' and scheduled_at>now();
   elsif act='recover' then
     perform private.require(o.stage='Lost' and coalesce((p->>'confirm')::boolean,false),'Confirm recovery');loss:=d->'losses'->-1;newstage:=loss->>'from';d:=jsonb_set(d,array['losses',(jsonb_array_length(d->'losses')-1)::text],loss||jsonb_build_object('recoveredAt',now()));
   elsif act in ('archive','restore') then
     perform private.require(coalesce((p->>'confirm')::boolean,false),'Confirm archive action');perform private.require(case when act='archive' then o.stage='Done' else m.role='owner' end,'Only Done jobs may be archived; only the owner may restore');o.archived:=act='archive';
   elsif act='opportunityNote' then d:=d||jsonb_build_object('notes',private.txt(p->>'notes','Notes',false,30000));
   else raise exception 'Unknown action';end if;
   if newstage<>o.stage then d:=d||jsonb_build_object('stageEnteredAt',now(),'stageDates',coalesce(d->'stageDates','{}')||jsonb_build_object(newstage,now()));end if;
   update public.opportunities set stage=newstage,archived=o.archived,data=d,version=version+1,updated_at=now() where id=o.id and business_id=b.id;
   perform private.audit(b.id,o.id,act,jsonb_build_object('before',prev,'after',d,'previousStage',o.stage,'stage',newstage));result:=jsonb_build_object('id',o.id);
 end if;
 insert into private.requests(business_id,key,actor,fingerprint,response) values(b.id,request_key::text,m.user_id::text,fingerprint,result);return result;
end$$;
revoke all on function public.command(jsonb,uuid) from public,anon;
grant execute on function public.command(jsonb,uuid) to authenticated;

create function public.business_summary() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('counts',coalesce((select jsonb_object_agg(stage,n) from(select stage,count(*) n from public.opportunities where business_id=public.current_business() and not archived group by stage)s),'{}'),'customers',(select count(*) from public.customers where business_id=public.current_business()),'quoted',(select coalesce(sum((data#>>'{quoting,estimate}')::bigint),0) from public.opportunities where business_id=public.current_business() and stage='Quoting' and not archived and data#>>'{quoting,status}'='Quote given — awaiting decision'),'scheduled',(select coalesce(sum((data#>>'{work,amount}')::bigint),0) from public.opportunities where business_id=public.current_business() and stage='Work' and not archived),'completed',(select coalesce(sum((data#>>'{work,finalAmount}')::bigint),0) from public.opportunities where business_id=public.current_business() and data#>>'{work,finishedDate}' is not null),'archived',(select count(*) from public.opportunities where business_id=public.current_business() and archived),'revision',(select coalesce(max(id),0) from public.activity where business_id=public.current_business()))
$$;
revoke all on function public.business_summary() from public,anon;grant execute on function public.business_summary() to authenticated;

-- Only the server-side website handler may call intake. Tenant id never comes from a visitor.
create function public.website_intake(tenant uuid,p jsonb,request_key uuid,ip_hash text) returns jsonb language plpgsql security definer set search_path='' as $$declare existing private.requests;res jsonb;n int;k text;begin
 perform private.require(auth.role()='service_role','Server authorization required');perform private.require(exists(select 1 from public.businesses where id=tenant),'Website tenant is not configured');
 perform pg_advisory_xact_lock(hashtextextended(tenant::text,0));
 select * into existing from private.requests where business_id=tenant and key=request_key::text and actor='website';
 if found then perform private.require(existing.fingerprint=md5(p::text),'Retry body changed');return existing.response;end if;
 foreach k in array array['minute:'||tenant||':'||ip_hash||':'||to_char(now(),'YYYYMMDDHH24MI'),'day:'||tenant||':'||ip_hash||':'||current_date,'global:'||tenant||':'||current_date] loop
  insert into private.rate_limits values(k,1,now()+interval '2 days') on conflict(key) do update set count=private.rate_limits.count+1 returning count into n;
  perform private.require(n<=case when k like 'minute:%' then 5 when k like 'day:%' then 40 else 500 end,'Too many requests. Please try again later');
 end loop;
 delete from private.rate_limits where expires<now();res:=private.add_request(tenant,p,'website');insert into private.requests(business_id,key,actor,fingerprint,response) values(tenant,request_key::text,'website',md5(p::text),res);return res;
end$$;
revoke all on function public.website_intake(uuid,jsonb,uuid,text) from public,anon,authenticated;grant execute on function public.website_intake(uuid,jsonb,uuid,text) to service_role;
revoke all on all functions in schema private from public,anon,authenticated;
commit;
