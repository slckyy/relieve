import {createClient} from '@supabase/supabase-js';
import webpush from 'web-push';
const json=(data,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
function fail(message,status=400){const e=new Error(message);e.status=status;throw e;}
async function body(req,max=20000){if(Number(req.headers.get('content-length'))>max)fail('Request is too large',413);const reader=req.body?.getReader();if(!reader)return {};let size=0,parts=[];while(true){const {value,done}=await reader.read();if(done)break;size+=value.length;if(size>max){await reader.cancel();fail('Request is too large',413);}parts.push(value);}const bytes=new Uint8Array(size);let pos=0;for(const part of parts){bytes.set(part,pos);pos+=part.length;}try{return JSON.parse(new TextDecoder().decode(bytes));}catch{fail('Invalid request JSON');}}
async function ok(q){const {data,error}=await q;if(error)throw error;return data;}
async function digest(v){return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(v)))].map(v=>v.toString(16).padStart(2,'0')).join('');}
async function sign(v,key){const k=await crypto.subtle.importKey('raw',new TextEncoder().encode(key),{name:'HMAC',hash:'SHA-256'},false,['sign']);return [...new Uint8Array(await crypto.subtle.sign('HMAC',k,new TextEncoder().encode(v)))].map(v=>v.toString(16).padStart(2,'0')).join('');}
function safeEqual(a,b){if(typeof a!=='string'||a.length!==b.length)return false;let diff=0;for(let i=0;i<a.length;i++)diff|=a.charCodeAt(i)^b.charCodeAt(i);return diff===0;}
async function push(admin,tenant,env,testUser){if(!env.VAPID_PRIVATE_KEY)return {configured:false};if(!testUser&&!await ok(admin.rpc('claim_push',{tenant})))return {queued:false};let q=admin.from('push_subscriptions').select('*').eq('business_id',tenant);if(testUser)q=q.eq('user_id',testUser);const subscriptions=await ok(q.limit(100)),active=await ok(admin.from('memberships').select('user_id').eq('business_id',tenant).eq('active',true));let accepted=0,failed=0;for(const row of subscriptions){if(!active.some(m=>m.user_id===row.user_id))continue;const host=new URL(row.endpoint).hostname;if(!/^(fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|[a-z0-9.-]+\.push\.apple\.com|web\.push\.apple\.com|[a-z0-9.-]+\.notify\.windows\.com)$/.test(host))continue;try{const d=webpush.generateRequestDetails(row.subscription,JSON.stringify({body:testUser?'Your relieve notification test.':'Your business has new activity. Open relieve to view.'}),{vapidDetails:{subject:env.APP_ORIGIN,publicKey:env.VAPID_PUBLIC_KEY,privateKey:env.VAPID_PRIVATE_KEY},TTL:3600});const response=await fetch(d.endpoint,{method:d.method,headers:d.headers,body:d.body});if(response.ok)accepted++;else{failed++;if([404,410].includes(response.status))await admin.from('push_subscriptions').delete().eq('id',row.id);}}catch{failed++;}}return {accepted,failed,deliveryVerified:false};}
export default {async fetch(req,env,ctx){const url=new URL(req.url);if(!url.pathname.startsWith('/api/'))return env.ASSETS.fetch(req);try{
 const origin=env.APP_ORIGIN||url.origin;if(req.method==='OPTIONS')return new Response(null,{status:204});
 if(req.headers.get('origin')&&req.headers.get('origin')!==origin)fail('Origin not allowed',403);
 if(url.pathname==='/api/push-config'&&req.method==='GET')return json({publicKey:env.VAPID_PUBLIC_KEY||null});
 if(req.method!=='POST')fail('Method not allowed',405);
 if(!req.headers.get('content-type')?.includes('application/json'))fail('Use application/json',415);
 const admin=createClient(env.SUPABASE_URL,env.SUPABASE_SECRET_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
 if(url.pathname==='/api/submit'){
  const p=await body(req);if(!p||typeof p!=='object'||Object.keys(p).sort().join(',')!=='name,phone,request,requestKey')fail('Provide only name, phone and work request');
  if(!/^[0-9a-f-]{36}$/i.test(p.requestKey||''))fail('A valid request key is required');
  const tenant=env.DEMO_BUSINESS_ID;if(!tenant)fail('This website is not connected yet',503);
  const r=await ok(admin.rpc('website_intake',{tenant,p:{name:p.name,phone:p.phone,request:p.request},request_key:p.requestKey,ip_hash:await digest((req.headers.get('CF-Connecting-IP')||'local')+env.RATE_LIMIT_SALT)}));
  ctx.waitUntil(push(admin,tenant,env).catch(()=>{}));return json({received:true,reference:r.id});
 }
 const access=req.headers.get('authorization')?.replace(/^Bearer /,'');if(!access)fail('Sign in required',401);const {data:auth,error}=await admin.auth.getUser(access);if(error||!auth.user)fail('Sign in required',401);
 const m=await ok(admin.from('memberships').select('*').eq('user_id',auth.user.id).eq('active',true).maybeSingle());if(!m)fail('Business access required',403);
 const p=await body(req,url.pathname==='/api/restore'?4*1024*1024:20000);
 if(url.pathname==='/api/notify'){ctx.waitUntil(push(admin,m.business_id,env).catch(()=>{}));return json({queued:true});}
 if(url.pathname==='/api/push-test')return json(await push(admin,m.business_id,env,m.user_id));
 if(m.role!=='owner')fail('Owner access required',403);
 if(url.pathname==='/api/invite'){
  if(typeof p.email!=='string'||!/^\S+@\S+\.\S+$/.test(p.email)||typeof p.name!=='string'||!p.name.trim()||p.name.length>200)fail('Enter worker name and sign-in email');
  const {data:invite,error}=await admin.auth.admin.generateLink({type:'invite',email:p.email.toLowerCase(),options:{redirectTo:origin+'/#invite'}});if(error)throw error;
  const user=invite.user;const exists=await ok(admin.from('memberships').select('business_id,role').eq('user_id',user.id).maybeSingle());if(exists)fail('This identity already has a business membership. Use worker recovery for existing staff.',409);
  await ok(admin.from('memberships').insert({user_id:user.id,business_id:m.business_id,name:p.name.trim(),role:'worker',active:true}));
  await ok(admin.from('activity').insert({business_id:m.business_id,user_id:m.user_id,actor:m.name,action:'Worker invitation created',data:{name:p.name}}));return json({link:invite.properties.action_link});
 }
 if(url.pathname==='/api/worker-recovery'){
  const worker=await ok(admin.from('memberships').select('*').eq('business_id',m.business_id).eq('user_id',p.userId).eq('role','worker').eq('active',true).single());const {data}=await admin.auth.admin.getUserById(worker.user_id);const {data:link,error}=await admin.auth.admin.generateLink({type:'recovery',email:data.user.email,options:{redirectTo:origin+'/#recovery'}});if(error)throw error;return json({link:link.properties.action_link});
 }
 if(url.pathname==='/api/backup'){
  if(!env.BACKUP_SIGNING_KEY)fail('Backup signing is not configured',503);const user=createClient(env.SUPABASE_URL,env.SUPABASE_PUBLISHABLE_KEY,{global:{headers:{Authorization:'Bearer '+access}},auth:{persistSession:false}});const snapshot=await ok(user.rpc('export_business'));return json({snapshot,signature:await sign(JSON.stringify(snapshot),env.BACKUP_SIGNING_KEY)});
 }
 if(url.pathname==='/api/restore'){
  if(!env.BACKUP_SIGNING_KEY)fail('Backup signing is not configured',503);if(p.confirm!==true||p.backup?.snapshot?.business_id!==m.business_id)fail('Confirm a backup for this business');const expected=await sign(JSON.stringify(p.backup.snapshot),env.BACKUP_SIGNING_KEY);if(!safeEqual(p.backup.signature,expected))fail('Invalid backup signature',403);return json(await ok(admin.rpc('restore_business',{tenant:m.business_id,snapshot:p.backup.snapshot,owner_id:m.user_id})));
 }
 fail('Unknown endpoint',404);
 }catch(e){return json({error:e.status?e.message:e.code==='P0001'?e.message:'Could not complete the request. Please retry; no unconfirmed state is shown as saved.'},e.status||400);}}};
