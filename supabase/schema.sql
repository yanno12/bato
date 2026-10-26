-- Run once in a NEW Supabase project's SQL editor. Browser clients use only a
-- publishable/anon key. Never expose the service_role key in Vite or Vercel.
begin;
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null check (length(display_name) between 1 and 100),
 email text not null,
 role text not null default 'sender' check (role in ('sender','shipper','admin')),
 suspended boolean not null default false,
 created_at timestamptz not null default now()
);
create table public.memberships (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 active_until timestamptz not null,
 source text not null default 'manual' check (source in ('manual','billing')),
 updated_at timestamptz not null default now()
);
create table public.listings (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
 kind text not null check (kind in ('departure','cargo')),
 status text not null default 'pending' check (status in ('pending','approved','hidden')),
 payload jsonb not null check (jsonb_typeof(payload) = 'object'),
 created_at timestamptz not null default now()
);
create table public.admin_audit (
 id bigint generated always as identity primary key,
 actor_id uuid references public.profiles(id),
 action text not null,
 target_id uuid not null,
 details jsonb not null default '{}',
 created_at timestamptz not null default now()
);

create function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=(select auth.uid()) and role='admin' and not suspended);
$$;
create function public.is_active_user() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=(select auth.uid()) and not suspended);
$$;
create function public.can_ship() returns boolean language sql stable security definer set search_path='' as $$
 select public.is_admin() or exists (
 select 1 from public.profiles p join public.memberships m on m.user_id=p.id
 where p.id=(select auth.uid()) and p.role='shipper' and not p.suspended and m.active_until>now());
$$;
create function public.handle_signup() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,email,display_name,role)
 values (new.id,coalesce(new.email,''),left(coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'),''),'Member'),100),
 case when new.raw_user_meta_data->>'account_type'='shipper' then 'shipper' else 'sender' end);
 return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_signup();

-- Validate payload server-side, not just in the browser. Store only public
-- fields here: email/contact details and photos do not belong in public listings.
create function public.validate_listing() returns trigger language plpgsql set search_path='' as $$
declare d text; k text; depart date; cutoff date;
begin
 if new.kind not in ('departure','cargo') then raise exception 'Invalid listing kind'; end if;
 if jsonb_typeof(new.payload)<>'object' then raise exception 'Invalid payload'; end if;
 for k in select jsonb_object_keys(new.payload) loop
  if k not in ('origin','destination','port','ack','description','date','deadline','space','volume','company','name') then
   raise exception 'Unsupported public field: %',k;
  end if;
 end loop;
 foreach k in array array['origin','destination','description','date'] loop
  if nullif(trim(new.payload->>k),'') is null then raise exception 'Missing field: %',k; end if;
 end loop;
 if length(new.payload->>'origin')>100 or length(new.payload->>'description')>1500 or length(coalesce(new.payload->>'company',''))>100 or length(coalesce(new.payload->>'name',''))>100 then raise exception 'Field too long'; end if;
 d=new.payload->>'destination';
 if d not in ('Lomé','Accra (Tema)','Lagos','Abidjan','Dakar','Conakry','Cotonou','Bamako','Niamey') then raise exception 'Unsupported destination'; end if;
 depart=(new.payload->>'date')::date;
 if depart is null then raise exception 'Missing date'; end if;
 if d in ('Bamako','Niamey') then
  if coalesce(new.payload->>'port','') not in ('Lomé','Accra (Tema)','Lagos','Abidjan','Dakar','Conakry','Cotonou') or coalesce(new.payload->>'ack','')<>'on' then raise exception 'Arrival port and pickup acknowledgment required'; end if;
 end if;
 if new.kind='departure' then
  cutoff=(new.payload->>'deadline')::date;
  if cutoff is null or cutoff>depart or coalesce((new.payload->>'space')::numeric,0)<=0 or nullif(trim(new.payload->>'company'),'') is null then raise exception 'Invalid departure details'; end if;
 else
  if coalesce((new.payload->>'volume')::numeric,0)<=0 or nullif(trim(new.payload->>'name'),'') is null then raise exception 'Invalid cargo details'; end if;
 end if;
 return new;
end;
$$;
create trigger validate_listing before insert or update of payload,kind on public.listings for each row execute function public.validate_listing();

alter table public.profiles enable row level security;
alter table public.memberships enable row level security;
alter table public.listings enable row level security;
alter table public.admin_audit enable row level security;
create policy profile_read on public.profiles for select to authenticated using(id=(select auth.uid()) or public.is_admin());
create policy membership_read on public.memberships for select to authenticated using(user_id=(select auth.uid()) or public.is_admin());
create function public.listing_owner_active(owner uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=owner and not suspended);
$$;
create policy listing_public_read on public.listings for select to anon,authenticated using(status='approved' and public.listing_owner_active(owner_id));
create policy listing_owner_read on public.listings for select to authenticated using((owner_id=(select auth.uid()) and public.is_active_user()) or public.is_admin());
create policy listing_insert on public.listings for insert to authenticated with check (
 owner_id=(select auth.uid()) and status='pending' and public.is_active_user()
 and (kind='cargo' or public.can_ship())
);
create policy audit_read on public.admin_audit for select to authenticated using(public.is_admin());

-- Only trusted RPCs can change roles, suspend users, moderate listings or grant
-- memberships. Public signup metadata can never grant admin privileges.
create function public.admin_update_user(target uuid,new_role text,new_suspended boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Admin access required'; end if;
 if target=(select auth.uid()) then raise exception 'Cannot change your own admin access'; end if;
 if new_role not in ('sender','shipper','admin') or new_role is null or new_suspended is null then raise exception 'Invalid profile update'; end if;
 update public.profiles set role=new_role,suspended=new_suspended where id=target;
 if not found then raise exception 'User not found'; end if;
 insert into public.admin_audit(actor_id,action,target_id,details) values(auth.uid(),'update_user',target,jsonb_build_object('role',new_role,'suspended',new_suspended));
end;
$$;
create function public.admin_moderate_listing(target uuid,new_status text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Admin access required'; end if;
 if new_status not in ('approved','hidden','pending') or new_status is null then raise exception 'Invalid listing status'; end if;
 update public.listings set status=new_status where id=target;
 if not found then raise exception 'Listing not found'; end if;
 insert into public.admin_audit(actor_id,action,target_id,details) values(auth.uid(),'moderate_listing',target,jsonb_build_object('status',new_status));
end;
$$;
create function public.admin_set_membership(target uuid,expires_at timestamptz) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Admin access required'; end if;
 if expires_at is null then raise exception 'Expiry required'; end if;
 if not exists(select 1 from public.profiles where id=target and role='shipper') then raise exception 'Shipper account required'; end if;
 insert into public.memberships(user_id,active_until,source) values(target,expires_at,'manual')
 on conflict(user_id) do update set active_until=excluded.active_until,source='manual',updated_at=now();
 insert into public.admin_audit(actor_id,action,target_id,details) values(auth.uid(),'manual_membership',target,jsonb_build_object('active_until',expires_at));
end;
$$;
-- Explicit privileges avoid relying on project default grants. RLS remains
-- enabled for all browser-readable tables. No direct browser writes to profiles,
-- memberships or moderation status are granted.
revoke all on public.profiles,public.memberships,public.listings,public.admin_audit from anon,authenticated;
grant select on public.listings to anon,authenticated;
grant insert(owner_id,kind,payload) on public.listings to authenticated;
grant select on public.profiles,public.memberships,public.admin_audit to authenticated;
revoke execute on function public.handle_signup(),public.validate_listing() from public,anon,authenticated;
revoke execute on function public.admin_update_user(uuid,text,boolean),public.admin_moderate_listing(uuid,text),public.admin_set_membership(uuid,timestamptz) from public,anon;
grant execute on function public.admin_update_user(uuid,text,boolean),public.admin_moderate_listing(uuid,text),public.admin_set_membership(uuid,timestamptz) to authenticated;
revoke execute on function public.is_admin(),public.is_active_user(),public.can_ship() from public,anon;
grant execute on function public.is_admin(),public.is_active_user(),public.can_ship() to authenticated;
revoke execute on function public.listing_owner_active(uuid) from public;
grant execute on function public.listing_owner_active(uuid) to anon,authenticated;
create index listing_owner_idx on public.listings(owner_id);
create index listing_status_idx on public.listings(status,created_at desc);
commit;
