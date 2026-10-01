-- Run in the Supabase SQL editor (safe to run again).
--
-- Lets Super Admins delete parcels and customers from the web admin.
-- Deleting a parcel also deletes its payments, receipts, tracking history and items,
-- so it disappears from reports too. Prefer "Cancel" for real parcels; use delete for
-- test data and mistakes.

create or replace function public.delete_parcel(p_parcel_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.users u join public.roles r on r.id = u.role_id
    where u.id = auth.uid() and r.name = 'Super Admin' and lower(coalesce(u.status, 'active')) = 'active'
  ) then
    raise exception 'Only Super Admins can delete parcels.';
  end if;

  if not exists (select 1 from public.parcels where id::text = p_parcel_id) then
    raise exception 'Parcel not found.';
  end if;

  -- Children first: receipts point at payments; payments, history and items point at the parcel
  delete from public.receipts
   where parcel_id::text = p_parcel_id
      or payment_id in (select id from public.payments where parcel_id::text = p_parcel_id);
  delete from public.payments where parcel_id::text = p_parcel_id;
  delete from public.parcel_status_history where parcel_id::text = p_parcel_id;
  if to_regclass('public.parcel_items') is not null then
    execute 'delete from public.parcel_items where parcel_id::text = $1' using p_parcel_id;
  end if;
  delete from public.parcels where id::text = p_parcel_id;
end;
$$;

-- Deletes a customer. If they have parcels (as sender or receiver), it refuses unless
-- p_with_parcels is true, in which case those parcels are deleted as well.
create or replace function public.delete_customer(p_customer_id text, p_with_parcels boolean default false)
returns integer -- number of parcels deleted with them
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parcel record;
  v_count integer := 0;
begin
  if not exists (
    select 1 from public.users u join public.roles r on r.id = u.role_id
    where u.id = auth.uid() and r.name = 'Super Admin' and lower(coalesce(u.status, 'active')) = 'active'
  ) then
    raise exception 'Only Super Admins can delete customers.';
  end if;

  select count(*) into v_count from public.parcels
   where sender_id::text = p_customer_id or receiver_id::text = p_customer_id;
  if v_count > 0 and not p_with_parcels then
    raise exception 'This customer has % parcel(s). Delete them too, or keep the customer.', v_count;
  end if;

  for v_parcel in
    select id from public.parcels where sender_id::text = p_customer_id or receiver_id::text = p_customer_id
  loop
    perform public.delete_parcel(v_parcel.id::text);
  end loop;

  delete from public.customers where id::text = p_customer_id;
  return v_count;
end;
$$;

revoke all on function public.delete_parcel(text), public.delete_customer(text, boolean) from public, anon;
grant execute on function public.delete_parcel(text), public.delete_customer(text, boolean) to authenticated;
