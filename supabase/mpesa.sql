-- Run in the Supabase SQL editor AFTER book_parcel.sql (safe to run again).
--
-- M-Pesa Express (STK push). How a payment flows:
--   1. The app books the parcel with payment method MPESA_PROMPT: it is saved as
--      AWAITING_PAYMENT, priced by the server (book_parcel.sql).
--   2. The mpesa-pay function asks Safaricom to send the prompt for that server price
--      and records the request here.
--   3. Safaricom calls mpesa-callback. Only then is the payment recorded, the receipt
--      issued and the parcel set to BOOKED, by complete_mpesa_payment below.
-- Staff can read requests (the app watches for the result) but cannot create or change
-- them; only the server functions can, using the service role.

create table if not exists public.mpesa_requests (
  id uuid primary key default gen_random_uuid(),
  parcel_id uuid not null,
  checkout_request_id text not null unique,
  merchant_request_id text,
  phone text not null,
  amount numeric not null check (amount > 0),
  status text not null default 'pending'
    check (status in ('pending', 'success', 'failed', 'cancelled', 'amount_mismatch')),
  result_code text,
  result_desc text,
  mpesa_receipt text unique,           -- one M-Pesa receipt can pay for one parcel only
  requested_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- Safaricom's exact callback message, kept for reconciliation
alter table public.mpesa_requests add column if not exists callback_payload jsonb;

create index if not exists mpesa_requests_parcel_idx on public.mpesa_requests (parcel_id);
create index if not exists mpesa_requests_phone_idx on public.mpesa_requests (phone, created_at);

alter table public.mpesa_requests enable row level security;
drop policy if exists "Staff can read M-Pesa requests" on public.mpesa_requests;
create policy "Staff can read M-Pesa requests" on public.mpesa_requests
  for select to authenticated using (public.is_staff());
revoke insert, update, delete on public.mpesa_requests from anon, authenticated;
grant select on public.mpesa_requests to authenticated;

-- Throttle prompts so nobody can spam a customer's phone.
-- Raises with a readable message when the limit is hit.
create or replace function public.mpesa_check_can_send(p_parcel_id uuid, p_phone text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.mpesa_requests where parcel_id = p_parcel_id and status = 'success') then
    raise exception 'This parcel is already paid.';
  end if;
  if (select count(*) from public.mpesa_requests
       where parcel_id = p_parcel_id and created_at > now() - interval '2 minutes') >= 3 then
    raise exception 'Too many prompts for this parcel. Wait 2 minutes and try again.';
  end if;
  if (select count(*) from public.mpesa_requests
       where phone = p_phone and created_at > now() - interval '10 minutes') >= 5 then
    raise exception 'Too many prompts to this phone number. Wait 10 minutes and try again.';
  end if;
end;
$$;

-- Called by mpesa-callback after Safaricom confirms (and the server double-checked
-- with Safaricom's status query). Records payment + receipt and books the parcel,
-- all at once. Calling it again for the same request does nothing new.
create or replace function public.complete_mpesa_payment(
  p_checkout_request_id text,
  p_mpesa_receipt text,
  p_amount numeric,
  p_phone text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.mpesa_requests%rowtype;
  v_parcel public.parcels%rowtype;
  v_staff public.users%rowtype;
  v_payment public.payments%rowtype;
  v_receipt public.receipts%rowtype;
begin
  select * into v_req from public.mpesa_requests
   where checkout_request_id = p_checkout_request_id
   for update;
  if not found then
    raise exception 'Unknown M-Pesa request %', p_checkout_request_id;
  end if;

  if v_req.status = 'success' then
    -- Safaricom sent the same confirmation twice: already done
    select * into v_receipt from public.receipts where parcel_id = v_req.parcel_id order by issued_at desc limit 1;
    return jsonb_build_object('status', 'already_completed', 'receipt_number', v_receipt.receipt_number);
  end if;

  if coalesce(trim(p_mpesa_receipt), '') = '' then
    raise exception 'Missing M-Pesa receipt number';
  end if;
  if exists (select 1 from public.mpesa_requests where mpesa_receipt = upper(trim(p_mpesa_receipt))) then
    raise exception 'M-Pesa receipt % was already used', p_mpesa_receipt;
  end if;

  if p_amount is null or p_amount < v_req.amount then
    update public.mpesa_requests
       set status = 'amount_mismatch', result_desc = format('Paid %s, expected %s', p_amount, v_req.amount),
           mpesa_receipt = upper(trim(p_mpesa_receipt)), updated_at = now()
     where id = v_req.id;
    return jsonb_build_object('status', 'amount_mismatch');
  end if;

  select * into v_parcel from public.parcels where id = v_req.parcel_id for update;
  if v_parcel.status <> 'AWAITING_PAYMENT' then
    -- e.g. cancelled while the customer was paying: keep the money on record for a refund
    update public.mpesa_requests
       set status = 'success', mpesa_receipt = upper(trim(p_mpesa_receipt)),
           result_desc = 'Paid, but parcel was ' || lower(v_parcel.status) || '. Needs refund or rebooking.',
           updated_at = now()
     where id = v_req.id;
    return jsonb_build_object('status', 'paid_but_parcel_' || lower(v_parcel.status));
  end if;

  select * into v_staff from public.users where id = v_req.requested_by;

  insert into public.payments (parcel_id, business_id, branch_id, amount, payment_method,
                               mpesa_transaction_code, status, received_by, paid_at)
  select r.parcel_id, r.business_id, r.branch_id, r.amount, r.payment_method,
         r.mpesa_transaction_code, r.status, r.received_by, r.paid_at
  from jsonb_populate_record(null::public.payments, jsonb_build_object(
    'parcel_id', v_parcel.id,
    'business_id', v_parcel.business_id,
    'branch_id', v_staff.branch_id,
    'amount', v_req.amount,
    'payment_method', 'MPESA',
    'mpesa_transaction_code', upper(trim(p_mpesa_receipt)),
    'status', 'COMPLETED',
    'received_by', v_req.requested_by,
    'paid_at', now())) r
  returning * into v_payment;

  insert into public.receipts (business_id, branch_id, parcel_id, payment_id, issued_by, issued_at)
  select r.business_id, r.branch_id, r.parcel_id, r.payment_id, r.issued_by, r.issued_at
  from jsonb_populate_record(null::public.receipts, jsonb_build_object(
    'business_id', v_parcel.business_id,
    'branch_id', v_staff.branch_id,
    'parcel_id', v_parcel.id,
    'payment_id', v_payment.id,
    'issued_by', v_req.requested_by,
    'issued_at', now())) r
  returning * into v_receipt;

  update public.parcels set status = 'BOOKED' where id = v_parcel.id;

  update public.mpesa_requests
     set status = 'success', mpesa_receipt = upper(trim(p_mpesa_receipt)),
         result_code = '0', result_desc = 'Paid', updated_at = now()
   where id = v_req.id;

  return jsonb_build_object('status', 'completed', 'receipt_number', v_receipt.receipt_number);
end;
$$;

-- Called when the customer cancels, times out, has too little money, etc.
create or replace function public.fail_mpesa_request(
  p_checkout_request_id text,
  p_result_code text,
  p_result_desc text
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.mpesa_requests
     set status = case when p_result_code = '1032' then 'cancelled' else 'failed' end,
         result_code = p_result_code, result_desc = p_result_desc, updated_at = now()
   where checkout_request_id = p_checkout_request_id
     and status = 'pending';
end;
$$;

-- Only the server functions (service role) may use these
revoke all on function public.mpesa_check_can_send(uuid, text) from public, anon, authenticated;
revoke all on function public.complete_mpesa_payment(text, text, numeric, text) from public, anon, authenticated;
revoke all on function public.fail_mpesa_request(text, text, text) from public, anon, authenticated;
grant execute on function public.mpesa_check_can_send(uuid, text) to service_role;
grant execute on function public.complete_mpesa_payment(text, text, numeric, text) to service_role;
grant execute on function public.fail_mpesa_request(text, text, text) to service_role;
