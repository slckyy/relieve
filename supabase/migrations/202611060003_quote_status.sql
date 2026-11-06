create or replace function public.command(p jsonb,request_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.memberships;b public.businesses;o public.opportunities;prev jsonb;d jsonb;c public.customers;e public.events;act text;result jsonb;cached private.requests;fingerprint text;v bigint;appt jsonb;followup jsonb;quote_status text;part jsonb;loss jsonb;newstage text;day text;typ text;field text;
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
     quote_status:=coalesce(p->>'status',d#>>'{quoting,status}','Not yet quoted');perform private.require(quote_status in ('Not yet quoted','Quote given — awaiting decision','Accepted'),'Choose a valid quote status');
     v:=case when coalesce(p->>'amount','')='' then null else private.amount(p->>'amount',coalesce((p->>'free')::boolean,false)) end;
     perform private.require(quote_status='Not yet quoted' or v is not null,'Record the estimate amount first');perform private.require(quote_status<>'Accepted' or d#>>'{quoting,status}'='Accepted' or coalesce((p->>'approved')::boolean,false),'Confirm actual customer approval');
     part:=coalesce(d->'quoting','{}')||jsonb_build_object('method',p->>'method','address',private.txt(p->>'address','Address',p->>'method'='In person'),'details',private.txt(p->>'details','Quote details'),'appointment',appt,'followup',followup,'estimate',v,'status',quote_status);
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
