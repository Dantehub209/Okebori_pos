-- Run in the Supabase SQL editor (safe to run again).
--
-- Who may move a parcel to each status, checked by the database itself:
--   * Sending branch staff:      Received, Dispatched, In transit, and Cancel (only before dispatch)
--   * Destination branch staff:  Arrived, Ready for collection, Picked / Delivered
--   * Super Admins:              anything, including fixing finished or cancelled parcels
-- "Staff" means anyone assigned to that branch (cashier or manager).

create or replace function public.enforce_parcel_branch_rules()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_branch text;
begin
  if new.status is not distinct from old.status then
    return new; -- not a status change
  end if;
  if auth.uid() is null then
    return new; -- run from the SQL editor or a server function
  end if;

  select r.name, u.branch_id::text into v_role, v_branch
  from public.users u
  left join public.roles r on r.id = u.role_id
  where u.id = auth.uid();

  if v_role = 'Super Admin' then
    return new;
  end if;

  if old.status in ('PICKED', 'DELIVERED', 'CANCELLED') then
    raise exception 'This parcel is already %. Only a Super Admin can change it.', lower(old.status);
  end if;

  if new.status in ('ARRIVED', 'READY_FOR_COLLECTION', 'PICKED', 'DELIVERED') then
    if v_branch is distinct from old.destination_branch_id::text then
      raise exception 'Only staff at the destination branch can mark this parcel %.', lower(replace(new.status, '_', ' '));
    end if;
  elsif new.status in ('RECEIVED', 'DISPATCHED', 'IN_TRANSIT', 'CANCELLED') then
    if v_branch is distinct from old.origin_branch_id::text then
      raise exception 'Only staff at the sending branch can mark this parcel %.', lower(replace(new.status, '_', ' '));
    end if;
    if new.status = 'CANCELLED' and old.status not in ('BOOKED', 'RECEIVED') then
      raise exception 'This parcel has already left. Only a Super Admin can cancel it now.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists parcel_branch_rules on public.parcels;
create trigger parcel_branch_rules
  before update on public.parcels
  for each row execute function public.enforce_parcel_branch_rules();
