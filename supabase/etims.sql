-- Run in the Supabase SQL editor AFTER book_parcel.sql and mpesa.sql (safe to run again).
--
-- KRA eTIMS invoices (OSCU). Every completed payment creates an invoice; cancelling a paid
-- parcel creates a credit note. Invoices are never edited or deleted.
--
-- Modes (etims_config.mode, changed by Super Admins in the web admin):
--   off         no invoices are created
--   simulation  invoices are "signed" right here with pretend KRA numbers, clearly marked
--               SIMULATION, so the whole flow can be tested without KRA
--   sandbox     invoices are queued and sent to KRA's test system by the etims-sync function
--   production  invoices are queued and sent to KRA for real
-- Each mode has its own invoice number sequence, as KRA expects per device.

create table if not exists public.etims_config (
  id int primary key default 1 check (id = 1),
  mode text not null default 'off' check (mode in ('off', 'simulation', 'sandbox', 'production')),
  kra_pin text,          -- the business's PIN (sandbox: the test PIN KRA gives you)
  branch_code text not null default '00',
  device_serial text,
  updated_at timestamptz not null default now()
);
insert into public.etims_config (id) values (1) on conflict (id) do nothing;

create table if not exists public.etims_counters (
  mode text primary key,
  last_number bigint not null default 0
);

create table if not exists public.etims_invoices (
  id uuid primary key default gen_random_uuid(),
  mode text not null,
  invoice_type text not null check (invoice_type in ('SALE', 'CREDIT_NOTE')),
  invoice_number bigint not null,
  original_invoice_id uuid references public.etims_invoices (id),
  parcel_id uuid not null,
  payment_id uuid,
  customer_kra_pin text,
  customer_name text,
  taxable_amount numeric not null,
  vat_rate numeric not null,
  vat_amount numeric not null,
  total_amount numeric not null,
  status text not null default 'queued' check (status in ('queued', 'signed', 'failed')),
  attempts int not null default 0,
  last_error text,
  kra_receipt_number text,
  kra_signature text,
  kra_internal_data text,
  kra_sdc_id text,
  qr_text text,
  kra_response jsonb,
  created_at timestamptz not null default now(),
  signed_at timestamptz,
  unique (mode, invoice_number)
);
create index if not exists etims_invoices_parcel_idx on public.etims_invoices (parcel_id);
create index if not exists etims_invoices_status_idx on public.etims_invoices (status) where status <> 'signed';

-- Staff can read; nobody edits through the app. Only the triggers below and the server
-- (service role) write.
alter table public.etims_config enable row level security;
alter table public.etims_counters enable row level security;
alter table public.etims_invoices enable row level security;
drop policy if exists "Staff can read eTIMS invoices" on public.etims_invoices;
create policy "Staff can read eTIMS invoices" on public.etims_invoices
  for select to authenticated using (public.is_staff());
drop policy if exists "Staff can read eTIMS settings" on public.etims_config;
create policy "Staff can read eTIMS settings" on public.etims_config
  for select to authenticated using (public.is_staff());
revoke insert, update, delete on public.etims_invoices, public.etims_config, public.etims_counters from anon, authenticated;
grant select on public.etims_invoices, public.etims_config to authenticated;

-- Signed invoices are final: KRA has them. Corrections go through credit notes.
create or replace function public.etims_protect_signed()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    if old.status = 'signed' then
      raise exception 'Signed eTIMS invoices cannot be deleted. Issue a credit note instead.';
    end if;
    return old;
  end if;
  if old.status = 'signed' then
    raise exception 'Signed eTIMS invoices cannot be changed. Issue a credit note instead.';
  end if;
  return new;
end;
$$;
drop trigger if exists etims_protect_signed on public.etims_invoices;
create trigger etims_protect_signed
  before update or delete on public.etims_invoices
  for each row execute function public.etims_protect_signed();

-- Pretend KRA, for simulation mode only. Real signing happens in the etims-sync function.
create or replace function public.etims_sign_simulated(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv public.etims_invoices%rowtype;
  v_cfg public.etims_config%rowtype;
  v_sig text;
begin
  select * into v_inv from public.etims_invoices where id = p_invoice_id for update;
  select * into v_cfg from public.etims_config where id = 1;
  v_sig := upper(substr(md5(v_inv.id::text || v_inv.invoice_number || v_inv.total_amount), 1, 16));
  update public.etims_invoices set
    status = 'signed',
    kra_receipt_number = 'SIM-' || lpad(v_inv.invoice_number::text, 8, '0'),
    kra_signature = substr(v_sig, 1, 4) || '-' || substr(v_sig, 5, 4) || '-' || substr(v_sig, 9, 4) || '-' || substr(v_sig, 13, 4),
    kra_internal_data = upper(md5(v_sig)),
    kra_sdc_id = 'SIMULATION',
    qr_text = 'SIMULATION|' || coalesce(v_cfg.kra_pin, 'P000000000X') || '|' || v_cfg.branch_code || '|' || v_sig,
    signed_at = now()
  where id = p_invoice_id;
end;
$$;

-- Creates an invoice (or credit note) for a parcel, numbered within the current mode.
create or replace function public.etims_create_invoice(
  p_parcel_id uuid,
  p_payment_id uuid,
  p_type text,
  p_original_invoice_id uuid
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cfg public.etims_config%rowtype;
  v_parcel public.parcels%rowtype;
  v_customer text;
  v_total numeric;
  v_vat numeric;
  v_number bigint;
  v_id uuid;
begin
  select * into v_cfg from public.etims_config where id = 1;
  if v_cfg.mode is null or v_cfg.mode = 'off' then
    return null;
  end if;

  select * into v_parcel from public.parcels where id = p_parcel_id;
  select name into v_customer from public.customers where id = v_parcel.sender_id;
  v_total := v_parcel.shipping_charge;
  v_vat := coalesce(v_parcel.vat_amount, 0);

  insert into public.etims_counters (mode, last_number) values (v_cfg.mode, 1)
  on conflict (mode) do update set last_number = public.etims_counters.last_number + 1
  returning last_number into v_number;

  insert into public.etims_invoices (mode, invoice_type, invoice_number, original_invoice_id, parcel_id, payment_id,
                                     customer_kra_pin, customer_name, taxable_amount, vat_rate, vat_amount, total_amount)
  values (v_cfg.mode, p_type, v_number, p_original_invoice_id, p_parcel_id, p_payment_id,
          v_parcel.customer_kra_pin, v_customer, v_total - v_vat, coalesce(v_parcel.vat_rate, 0), v_vat, v_total)
  returning id into v_id;

  if v_cfg.mode = 'simulation' then
    perform public.etims_sign_simulated(v_id);
  end if;
  return v_id;
end;
$$;

-- Every completed payment gets an invoice (cash, card and confirmed M-Pesa alike).
create or replace function public.etims_on_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'COMPLETED' and not exists (
    select 1 from public.etims_invoices where parcel_id = new.parcel_id and invoice_type = 'SALE'
  ) then
    perform public.etims_create_invoice(new.parcel_id, new.id, 'SALE', null);
  end if;
  return new;
end;
$$;
drop trigger if exists etims_on_payment on public.payments;
create trigger etims_on_payment
  after insert on public.payments
  for each row execute function public.etims_on_payment();

-- Cancelling a paid parcel reverses its invoice with a credit note.
create or replace function public.etims_on_parcel_cancel()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sale public.etims_invoices%rowtype;
begin
  if new.status = 'CANCELLED' and old.status is distinct from 'CANCELLED' then
    select * into v_sale from public.etims_invoices
     where parcel_id = new.id and invoice_type = 'SALE'
     order by created_at desc limit 1;
    if v_sale.id is not null and not exists (
      select 1 from public.etims_invoices where original_invoice_id = v_sale.id
    ) then
      perform public.etims_create_invoice(new.id, v_sale.payment_id, 'CREDIT_NOTE', v_sale.id);
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists etims_on_parcel_cancel on public.parcels;
create trigger etims_on_parcel_cancel
  after update of status on public.parcels
  for each row execute function public.etims_on_parcel_cancel();

-- Super Admins switch modes from the web admin
create or replace function public.etims_set_mode(p_mode text, p_kra_pin text default null, p_device_serial text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Only Super Admins can change eTIMS settings.';
  end if;
  if p_mode not in ('off', 'simulation', 'sandbox', 'production') then
    raise exception 'Unknown eTIMS mode %', p_mode;
  end if;
  update public.etims_config
     set mode = p_mode,
         kra_pin = coalesce(nullif(upper(trim(p_kra_pin)), ''), kra_pin),
         device_serial = coalesce(nullif(trim(p_device_serial), ''), device_serial),
         updated_at = now()
   where id = 1;
end;
$$;

revoke all on function public.etims_sign_simulated(uuid) from public, anon, authenticated;
revoke all on function public.etims_create_invoice(uuid, uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.etims_set_mode(text, text, text) from public, anon;
grant execute on function public.etims_set_mode(text, text, text) to authenticated;
grant execute on function public.etims_sign_simulated(uuid), public.etims_create_invoice(uuid, uuid, text, uuid) to service_role;
