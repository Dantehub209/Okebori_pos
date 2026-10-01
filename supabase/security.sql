-- Access rules (Row Level Security) for Okebori. Run in the Supabase SQL editor.
--
-- BEFORE RUNNING: save your current rules so you can compare or restore them.
-- Run this on its own and download the result as CSV:
--     select * from pg_policies where schemaname = 'public';
--
-- What this does:
--   * Removes every existing rule on the Okebori tables and replaces them with the set below.
--   * Only signed-in staff with an active account can read anything.
--   * Cashiers can book parcels, take payments, issue receipts and update parcel status,
--     always as themselves. They cannot change or delete payments or receipts, or edit
--     branches, prices, categories, roles or staff.
--   * Super Admins can manage branches, prices, categories, roles and staff.
--   * Staff marked inactive lose access straight away.
--   * The public (not signed in) can read nothing except app_version.
--
-- Safe to run again.

-- Helpers. "security definer" lets them read users/roles without tripping these same rules.
create or replace function public.current_staff_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select r.name
  from public.users u
  join public.roles r on r.id = u.role_id
  where u.id = auth.uid()
    and lower(coalesce(u.status, 'active')) = 'active'
$$;

create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$ select public.current_staff_role() is not null $$;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$ select coalesce(public.current_staff_role() = 'Super Admin', false) $$;

revoke all on function public.current_staff_role(), public.is_staff(), public.is_super_admin() from public, anon;
grant execute on function public.current_staff_role(), public.is_staff(), public.is_super_admin() to authenticated;

-- Remove every existing rule on these tables, then switch RLS on.
do $$
declare
  t text;
  p record;
begin
  foreach t in array array[
    'businesses', 'roles', 'branches', 'users', 'customers', 'parcel_categories',
    'pricing_rules', 'parcels', 'payments', 'receipts', 'parcel_status_history'
  ] loop
    for p in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
      execute format('drop policy %I on public.%I', p.policyname, t);
    end loop;
    execute format('alter table public.%I enable row level security', t);
    -- Any staff member can read
    execute format('create policy "Staff can read" on public.%I for select to authenticated using (public.is_staff())', t);
  end loop;
end $$;

-- Reference data: only Super Admins change it
do $$
declare
  t text;
begin
  foreach t in array array['businesses', 'roles', 'branches', 'parcel_categories', 'pricing_rules', 'users'] loop
    execute format('create policy "Super admins can add" on public.%I for insert to authenticated with check (public.is_super_admin())', t);
    execute format('create policy "Super admins can edit" on public.%I for update to authenticated using (public.is_super_admin()) with check (public.is_super_admin())', t);
    execute format('create policy "Super admins can delete" on public.%I for delete to authenticated using (public.is_super_admin())', t);
  end loop;
end $$;

-- Customers: staff add and correct them while booking
create policy "Staff can add customers" on public.customers
  for insert to authenticated with check (public.is_staff());
create policy "Staff can edit customers" on public.customers
  for update to authenticated using (public.is_staff()) with check (public.is_staff());

-- Parcels: staff book as themselves and update status along the way
create policy "Staff can book parcels as themselves" on public.parcels
  for insert to authenticated with check (public.is_staff() and booked_by = auth.uid());
create policy "Staff can update parcels" on public.parcels
  for update to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "Super admins can delete parcels" on public.parcels
  for delete to authenticated using (public.is_super_admin());

-- Money: recorded once by the person taking it; only Super Admins can correct
create policy "Staff can record payments as themselves" on public.payments
  for insert to authenticated with check (public.is_staff() and received_by = auth.uid());
create policy "Super admins can correct payments" on public.payments
  for update to authenticated using (public.is_super_admin()) with check (public.is_super_admin());
create policy "Super admins can delete payments" on public.payments
  for delete to authenticated using (public.is_super_admin());

create policy "Staff can issue receipts as themselves" on public.receipts
  for insert to authenticated with check (public.is_staff() and issued_by = auth.uid());
create policy "Super admins can correct receipts" on public.receipts
  for update to authenticated using (public.is_super_admin()) with check (public.is_super_admin());
create policy "Super admins can delete receipts" on public.receipts
  for delete to authenticated using (public.is_super_admin());

-- Tracking history: added as yourself, never edited
create policy "Staff can add tracking as themselves" on public.parcel_status_history
  for insert to authenticated with check (public.is_staff() and user_id = auth.uid());
