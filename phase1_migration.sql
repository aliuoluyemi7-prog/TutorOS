-- ============================================
-- TUTOR OS — PHASE 1 MIGRATION (FINAL, CORRECTED)
-- Canonical definition of the Phase 1 database, matching the live,
-- tested Supabase project as of Phase 1 sign-off.
--
-- Incorporates two production fixes discovered during live testing,
-- folded into the original migration rather than kept as separate
-- patch files:
--   1. business_members RLS self-referencing recursion fix
--      (original policies queried business_members from within a
--      policy ON business_members, causing infinite recursion).
--   2. Missing table grants fix
--      (with "Automatically expose new tables" off, Supabase does not
--      auto-grant base table privileges to the `authenticated` role —
--      RLS alone is not enough; the underlying GRANT is a separate,
--      required layer).
--
-- ============================================
-- IDEMPOTENCY / SAFETY
-- ============================================
-- This migration is SAFE TO RE-RUN on a database that already has it
-- applied. It is NOT destructive: it never drops a table, never drops
-- a column, and never deletes data.
--   - Tables:    created with IF NOT EXISTS (existing tables/data are
--                left untouched if already present).
--   - Indexes:   created with IF NOT EXISTS.
--   - Functions: created with OR REPLACE (safe — redefines behavior,
--                does not touch table data).
--   - Triggers:  dropped and recreated (DROP ... IF EXISTS, then
--                CREATE) — safe, triggers hold no data of their own.
--   - Policies:  dropped and recreated (DROP POLICY IF EXISTS, then
--                CREATE POLICY) — safe, policies hold no data of
--                their own, only access rules.
--   - Grants:    GRANT is naturally idempotent in Postgres.
--
-- On a FRESH Supabase project, running this once produces the complete
-- Phase 1 database. On the EXISTING live project (already patched),
-- re-running this is a no-op for tables/data and simply reconfirms the
-- current trigger/policy/grant definitions — it will not wipe or alter
-- any rows in profiles, businesses, business_settings, or business_members.
-- ============================================

create extension if not exists "pgcrypto"; -- gen_random_uuid()

-- ============================================
-- 1. TABLES
-- ============================================

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  email text not null,
  phone text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  business_type text not null check (business_type in ('independent_tutor','tutoring_centre','agency')),
  owner_id uuid not null references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists business_settings (
  business_id uuid primary key references businesses(id) on delete cascade,
  timezone text not null default 'Africa/Lagos',
  country text,
  default_currency text not null default 'NGN',
  invoice_prefix text not null default 'INV',
  default_session_duration_minutes int not null default 60,
  date_format text not null default 'DD/MM/YYYY',
  whatsapp_number text,
  logo_url text,
  plan_id uuid, -- reserved for future subscription/plans architecture, unused in Phase 1
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists business_members (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  profile_id uuid not null references profiles(id) on delete cascade,
  role text not null check (role in ('owner','administrator','tutor','parent')),
  status text not null default 'active' check (status in ('active','invited','suspended')),
  invited_at timestamptz,
  joined_at timestamptz default now(),
  created_at timestamptz not null default now(),
  unique (business_id, profile_id)
);

-- ============================================
-- 2. INDEXES
-- ============================================

create index if not exists idx_business_members_profile on business_members(profile_id);
create index if not exists idx_business_members_business on business_members(business_id);
create index if not exists idx_businesses_owner on businesses(owner_id);
-- business_settings.business_id is already indexed (it's the primary key)

-- ============================================
-- 3. TRIGGERS
-- ============================================

create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_profiles_updated_at on profiles;
create trigger trg_profiles_updated_at before update on profiles
  for each row execute function set_updated_at();

drop trigger if exists trg_businesses_updated_at on businesses;
create trigger trg_businesses_updated_at before update on businesses
  for each row execute function set_updated_at();

drop trigger if exists trg_business_settings_updated_at on business_settings;
create trigger trg_business_settings_updated_at before update on business_settings
  for each row execute function set_updated_at();

-- Auto-create a profiles row whenever a new auth.users row appears
create or replace function handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''), new.email);
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ============================================
-- 4. TRANSACTIONAL ONBOARDING RPC
-- ============================================
-- Atomically creates a business, its owner membership, and its settings
-- row in one transaction — if any step fails, everything rolls back.
-- security definer, but reads the caller's identity exclusively from
-- auth.uid() — there is no parameter through which a caller can supply
-- a different owner_id/profile_id, so this cannot be used to create a
-- business on someone else's behalf.

create or replace function create_business(
  p_name text,
  p_business_type text,
  p_country text default null,
  p_default_currency text default 'NGN',
  p_timezone text default 'Africa/Lagos'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'Business name is required';
  end if;

  if p_business_type not in ('independent_tutor','tutoring_centre','agency') then
    raise exception 'Invalid business_type';
  end if;

  insert into businesses (name, business_type, owner_id)
  values (trim(p_name), p_business_type, auth.uid())
  returning id into v_business_id;

  insert into business_members (business_id, profile_id, role, status, joined_at)
  values (v_business_id, auth.uid(), 'owner', 'active', now());

  insert into business_settings (business_id, country, default_currency, timezone)
  values (v_business_id, p_country, coalesce(nullif(p_default_currency, ''), 'NGN'), coalesce(nullif(p_timezone, ''), 'Africa/Lagos'));

  return v_business_id;
end;
$$;

revoke all on function create_business(text, text, text, text, text) from public;
grant execute on function create_business(text, text, text, text, text) to authenticated;

-- ============================================
-- 4b. RECURSION-SAFE OWNERSHIP HELPER
-- ============================================
-- PRODUCTION FIX #1: business_members RLS recursion.
--
-- The original "owner reads/manages all memberships" policies queried
-- business_members from within a policy defined ON business_members.
-- Postgres must re-evaluate the table's RLS to service that inner
-- query, which re-triggers the same policy — infinite recursion.
--
-- Fix: a SECURITY DEFINER function. It runs as the function owner
-- (the table owner, e.g. postgres), who bypasses RLS by default in
-- Postgres — breaking the self-referencing loop while still checking
-- exactly the same ownership condition the policy needs.

create or replace function is_active_owner_of_business(p_business_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from business_members
    where business_id = p_business_id
      and profile_id = auth.uid()
      and role = 'owner'
      and status = 'active'
  );
$$;

revoke all on function is_active_owner_of_business(uuid) from public;
grant execute on function is_active_owner_of_business(uuid) to authenticated;

-- ============================================
-- 5. ROW LEVEL SECURITY
-- ============================================
-- All four Phase 1 tables have RLS enabled with no exceptions. There is
-- no Phase 1 table that relies on frontend filtering alone — every read
-- and write is authorized at the database layer.
--
-- business_members is the trust root: every other policy (aside from
-- the two on profiles, which key directly off auth.uid()) checks for a
-- matching row here — profile_id = auth.uid(), status = 'active', and
-- an appropriate role where relevant. Change or remove that row and
-- access changes immediately, on the very next query, not on next login.

alter table profiles enable row level security;
alter table businesses enable row level security;
alter table business_settings enable row level security;
alter table business_members enable row level security;

-- ---------- profiles ----------
drop policy if exists "profiles: self read" on profiles;
create policy "profiles: self read"
on profiles for select
using (id = auth.uid());

drop policy if exists "profiles: self update" on profiles;
create policy "profiles: self update"
on profiles for update
using (id = auth.uid());
-- No insert policy: profile rows are created only via handle_new_user()
-- (security definer trigger), never by direct client insert.

-- ---------- business_members ----------
drop policy if exists "members: self read own memberships" on business_members;
create policy "members: self read own memberships"
on business_members for select
using (profile_id = auth.uid());

-- Recursion-safe versions (production fix #1) — use the SECURITY
-- DEFINER helper above instead of a self-referencing subquery.
drop policy if exists "members: owner reads all memberships in their business" on business_members;
create policy "members: owner reads all memberships in their business"
on business_members for select
using (is_active_owner_of_business(business_members.business_id));

drop policy if exists "members: owner manages memberships" on business_members;
create policy "members: owner manages memberships"
on business_members for all
using (is_active_owner_of_business(business_members.business_id));
-- No general insert policy beyond the above: the only insert path in
-- Phase 1 is create_business() (security definer). The "owner manages
-- memberships" policy covers Phase 2+ invite flows for the owner.

-- ---------- businesses ----------
drop policy if exists "businesses: members can read their business" on businesses;
create policy "businesses: members can read their business"
on businesses for select
using (
  exists (
    select 1 from business_members bm
    where bm.business_id = businesses.id
      and bm.profile_id = auth.uid()
      and bm.status = 'active'
  )
);

drop policy if exists "businesses: owner can update" on businesses;
create policy "businesses: owner can update"
on businesses for update
using (
  exists (
    select 1 from business_members bm
    where bm.business_id = businesses.id
      and bm.profile_id = auth.uid()
      and bm.role = 'owner'
      and bm.status = 'active'
  )
);
-- No insert policy: businesses are created only via create_business().
-- No delete policy: deleting a business isn't a Phase 1 feature: this
-- is intentional, not an oversight — nobody, including a business's own
-- owner, can delete a business via the client in Phase 1.

-- ---------- business_settings ----------
drop policy if exists "settings: owner/admin read" on business_settings;
create policy "settings: owner/admin read"
on business_settings for select
using (
  exists (
    select 1 from business_members bm
    where bm.business_id = business_settings.business_id
      and bm.profile_id = auth.uid()
      and bm.role in ('owner','administrator')
      and bm.status = 'active'
  )
);

drop policy if exists "settings: owner/admin update" on business_settings;
create policy "settings: owner/admin update"
on business_settings for update
using (
  exists (
    select 1 from business_members bm
    where bm.business_id = business_settings.business_id
      and bm.profile_id = auth.uid()
      and bm.role in ('owner','administrator')
      and bm.status = 'active'
  )
);
-- No insert policy: settings rows are created only via create_business().

-- ============================================
-- 6. GRANTS
-- ============================================
-- PRODUCTION FIX #2: missing table grants.
--
-- With Supabase's "Automatically expose new tables" setting off,
-- newly created tables are NOT automatically granted base read/write
-- privileges to the `authenticated` API role. This is a separate layer
-- from RLS: a query needs BOTH a passing GRANT (can it touch the table
-- at all) AND a passing RLS policy (which rows, specifically) to
-- succeed. Without this grant, every client query fails with
-- "permission denied for table ..." regardless of how correct the RLS
-- policies are.
--
-- These grants only unlock the tables themselves — the RLS policies
-- above still fully control which rows are visible or editable within
-- them. This does not weaken security; it's the other half of it.

grant select, insert, update, delete on profiles to authenticated;
grant select, insert, update, delete on businesses to authenticated;
grant select, insert, update, delete on business_settings to authenticated;
grant select, insert, update, delete on business_members to authenticated;

-- ============================================
-- END PHASE 1 MIGRATION
-- ============================================
