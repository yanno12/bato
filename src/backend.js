import {createClient} from '@supabase/supabase-js';
const url=import.meta.env.VITE_SUPABASE_URL;
const key=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY||import.meta.env.VITE_SUPABASE_ANON_KEY;
export const configured=Boolean(url&&key);
export const db=configured?createClient(url,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}}):null;
export let session=null,profile=null,membership=null;
export const accountState={loading:configured,error:''};
let notify=()=>{};
const fail=r=>{if(r.error)throw r.error;return r.data};
export const hasMembership=()=>profile?.role==='admin'||(profile?.role==='shipper'&&membership&&new Date(membership.active_until)>new Date());
export async function refreshAccount(){
 session=fail(await db.auth.getSession()).session;profile=null;membership=null;
 if(session){profile=fail(await db.from('profiles').select('*').eq('id',session.user.id).single());membership=fail(await db.from('memberships').select('*').eq('user_id',session.user.id).maybeSingle());}
 accountState.loading=false;accountState.error='';
}
export async function initAccount(callback){
 notify=callback;if(!db)return;
 db.auth.onAuthStateChange((event)=>{
  // Never await a Supabase call inside its auth callback (auth lock).
  setTimeout(async()=>{try{await refreshAccount()}catch(e){profile=null;membership=null;accountState.error=e.message}notify(event)},0);
 });
 try{await refreshAccount()}catch(e){accountState.loading=false;accountState.error=e.message}notify();
}
export async function signOut(){fail(await db.auth.signOut());session=null;profile=null;membership=null;notify();}
export async function readListings(){return fail(await db.from('listings').select('*').order('created_at',{ascending:false}));}
export function publicPayload(kind,input){
 const keys=kind==='departure'?['origin','destination','port','ack','description','date','deadline','space','company']:['origin','destination','port','ack','description','date','volume','name'];
 return Object.fromEntries(keys.filter(k=>input[k]!==undefined).map(k=>[k,input[k]]));
}
export async function createListing(kind,input){
 if(!session||!profile||profile.suspended)throw Error('Sign in with an active account.');
 if(kind==='departure'&&!hasMembership())throw Error('An active shipper membership is required.');
 return fail(await db.from('listings').insert({owner_id:session.user.id,kind,payload:publicPayload(kind,input)}).select().single());
}
export async function adminData(){
 const [users,listings,memberships,audit]=await Promise.all([
 db.from('profiles').select('*').order('created_at',{ascending:false}),
 db.from('listings').select('*').order('created_at',{ascending:false}),
 db.from('memberships').select('*'),db.from('admin_audit').select('*').order('created_at',{ascending:false}).limit(30)]);
 return{users:fail(users),listings:fail(listings),memberships:fail(memberships),audit:fail(audit)};
}
export async function adminAction(name,args){return fail(await db.rpc(name,args));}
