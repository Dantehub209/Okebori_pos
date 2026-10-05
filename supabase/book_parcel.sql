-- Run in the Supabase SQL editor (safe to run again).
--
-- quote_parcel works out the price on the server from the pricing rules and the
-- branches' GPS, the same way the app shows it. book_parcel always charges this
-- server price: the amount sent by the phone is only used to catch a stale screen.
--
-- book_parcel saves a booking in one step: customers, parcel, payment and receipt.
-- If anything fails (e.g. the network drops), nothing is saved.
-- With p_payment_method = 'MPESA_PROMPT' it saves the parcel as AWAITING_PAYMENT with
-- no payment yet; the mpesa-pay / mpesa-callback functions complete it (see mpesa.sql).
--
-- It runs with the caller's own permissions (security invoker), so the access
-- rules in security.sql still apply.

create or replace function public.quote_parcel(
  p_origin_branch_id text,
  p_destination_branch_id text,
  p_weight_kg numeric
) returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_from record;
  v_to record;
  v_rules record;
  v_base numeric := 150;
  v_base_kg numeric := 5;
  v_per_kg numeric := 50;
  v_per_km numeric := 30;
  v_km double precision;
  v_extra_kg numeric;
  v_total numeric;
begin
  select id, name, latitude, longitude into v_from from public.branches where id::text = p_origin_branch_id;
  select id, name, latitude, longitude into v_to from public.branches where id::text = p_destination_branch_id;
  if v_from.id is null or v_to.id is null then
    raise exception 'Choose valid branches.';
  end if;
  if v_from.id = v_to.id then
    raise exception 'Destination must be a different branch.';
  end if;
  if v_from.latitude is null or v_from.longitude is null or (v_from.latitude = 0 and v_from.longitude = 0) then
    raise exception '% has no GPS location.', v_from.name;
  end if;
  if v_to.latitude is null or v_to.longitude is null or (v_to.latitude = 0 and v_to.longitude = 0) then
    raise exception '% has no GPS location.', v_to.name;
  end if;
  if p_weight_kg is null or p_weight_kg <= 0 then
    raise exception 'Weight must be greater than zero.';
  end if;

  -- Same rules row the app reads (first business); built-in defaults otherwise
  select * into v_rules from public.pricing_rules
   where business_id = (select id from public.businesses limit 1)
   limit 1;
  if found then
    v_base := v_rules.base_price;
    v_base_kg := v_rules.base_weight_kg;
    v_per_kg := v_rules.price_per_extra_kg;
    v_per_km := v_rules.fuel_cost_per_km;
  end if;

  -- Haversine, identical to distanceBetween() in lib/services/pricing.dart
  v_km := 12742 * asin(sqrt(
            0.5 - cos(radians(v_to.latitude - v_from.latitude)) / 2
            + cos(radians(v_from.latitude)) * cos(radians(v_to.latitude))
              * (1 - cos(radians(v_to.longitude - v_from.longitude))) / 2));
  v_extra_kg := greatest(0, p_weight_kg - v_base_kg);
  -- Whole shillings, rounded up (M-Pesa only accepts whole amounts)
  v_total := ceil(round(v_base + v_extra_kg * v_per_kg + v_km::numeric * v_per_km, 2));

  return jsonb_build_object(
    'base_rate', v_base,
    'extra_weight_kg', v_extra_kg,
    'weight_charge', v_extra_kg * v_per_kg,
    'distance_km', round(v_km::numeric, 2),
    'distance_charge', round(v_km::numeric * v_per_km, 2),
    'total', v_total
  );
end;
$$;

create or replace function public.book_parcel(
  p_origin_branch_id text,
  p_destination_branch_id text,
  p_category_id text,
  p_weight_kg numeric,
  p_distance_km numeric,
  p_shipping_charge numeric,
  p_sender_name text,
  p_sender_phone text,
  p_receiver_name text,
  p_receiver_phone text,
  p_payment_method text,
  p_mpesa_code text default null
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user public.users%rowtype;
  v_business_id text;
  v_sender_id text;
  v_receiver_id text;
  v_quote jsonb;
  v_charge numeric;
  v_awaiting boolean := p_payment_method = 'MPESA_PROMPT';
  v_parcel public.parcels%rowtype;
  v_payment public.payments%rowtype;
  v_receipt public.receipts%rowtype;
begin
  select * into v_user from public.users where id = auth.uid();
  if not found then
    raise exception 'This account is not an active staff account';
  end if;
  if p_payment_method not in ('CASH', 'MPESA', 'CARD', 'MPESA_PROMPT') then
    raise exception 'Unknown payment method %', p_payment_method;
  end if;
  if p_payment_method = 'MPESA' and coalesce(trim(p_mpesa_code), '') = '' then
    raise exception 'M-Pesa transaction code is required';
  end if;

  -- The server decides the price
  v_quote := public.quote_parcel(p_origin_branch_id, p_destination_branch_id, p_weight_kg);
  v_charge := (v_quote->>'total')::numeric;
  if p_shipping_charge is not null and abs(p_shipping_charge - v_charge) > 1 then
    raise exception 'The price has changed to KSh %. Check the total and try again.', v_charge;
  end if;

  v_business_id := coalesce(v_user.business_id::text, (select id::text from public.businesses limit 1));

  -- Reuse customers with the same phone number instead of creating duplicates
  select id::text into v_sender_id from public.customers where phone = trim(p_sender_phone) order by id limit 1;
  if v_sender_id is null then
    insert into public.customers (business_id, name, phone)
    select r.business_id, r.name, r.phone
    from jsonb_populate_record(null::public.customers, jsonb_build_object(
      'business_id', v_business_id, 'name', trim(p_sender_name), 'phone', trim(p_sender_phone))) r
    returning id::text into v_sender_id;
  end if;

  select id::text into v_receiver_id from public.customers where phone = trim(p_receiver_phone) order by id limit 1;
  if v_receiver_id is null then
    insert into public.customers (business_id, name, phone)
    select r.business_id, r.name, r.phone
    from jsonb_populate_record(null::public.customers, jsonb_build_object(
      'business_id', v_business_id, 'name', trim(p_receiver_name), 'phone', trim(p_receiver_phone))) r
    returning id::text into v_receiver_id;
  end if;

  -- jsonb_populate_record converts each value to the column's real type
  insert into public.parcels (business_id, sender_id, receiver_id, origin_branch_id, destination_branch_id,
                              category_id, weight_kg, declared_value, is_fragile, shipping_charge, distance_km,
                              status, booked_by)
  select r.business_id, r.sender_id, r.receiver_id, r.origin_branch_id, r.destination_branch_id,
         r.category_id, r.weight_kg, r.declared_value, r.is_fragile, r.shipping_charge, r.distance_km,
         r.status, r.booked_by
  from jsonb_populate_record(null::public.parcels, jsonb_build_object(
    'business_id', v_business_id,
    'sender_id', v_sender_id,
    'receiver_id', v_receiver_id,
    'origin_branch_id', p_origin_branch_id,
    'destination_branch_id', p_destination_branch_id,
    'category_id', p_category_id,
    'weight_kg', p_weight_kg,
    'declared_value', 0,
    'is_fragile', false,
    'shipping_charge', v_charge,
    'distance_km', (v_quote->>'distance_km')::numeric,
    'status', case when v_awaiting then 'AWAITING_PAYMENT' else 'BOOKED' end,
    'booked_by', auth.uid())) r
  returning * into v_parcel;

  -- M-Pesa prompt: payment and receipt are added only when Safaricom confirms
  if v_awaiting then
    return jsonb_build_object(
      'parcel_id', v_parcel.id,
      'booking_number', v_parcel.booking_number,
      'amount', v_charge
    );
  end if;

  insert into public.payments (parcel_id, business_id, branch_id, amount, payment_method,
                               mpesa_transaction_code, status, received_by, paid_at)
  select r.parcel_id, r.business_id, r.branch_id, r.amount, r.payment_method,
         r.mpesa_transaction_code, r.status, r.received_by, r.paid_at
  from jsonb_populate_record(null::public.payments, jsonb_build_object(
    'parcel_id', v_parcel.id,
    'business_id', v_business_id,
    'branch_id', v_user.branch_id,
    'amount', v_charge,
    'payment_method', p_payment_method,
    'mpesa_transaction_code', case when p_payment_method = 'MPESA' then upper(trim(p_mpesa_code)) end,
    'status', 'COMPLETED',
    'received_by', auth.uid(),
    'paid_at', now())) r
  returning * into v_payment;

  -- receipt_number is generated by the existing database trigger/default
  insert into public.receipts (business_id, branch_id, parcel_id, payment_id, issued_by, issued_at)
  select r.business_id, r.branch_id, r.parcel_id, r.payment_id, r.issued_by, r.issued_at
  from jsonb_populate_record(null::public.receipts, jsonb_build_object(
    'business_id', v_business_id,
    'branch_id', v_user.branch_id,
    'parcel_id', v_parcel.id,
    'payment_id', v_payment.id,
    'issued_by', auth.uid(),
    'issued_at', now())) r
  returning * into v_receipt;

  return jsonb_build_object(
    'parcel_id', v_parcel.id,
    'booking_number', v_parcel.booking_number,
    'receipt_number', v_receipt.receipt_number,
    'amount', v_charge
  );
end;
$$;

revoke all on function public.book_parcel from public, anon;
grant execute on function public.book_parcel to authenticated;
revoke all on function public.quote_parcel from public, anon;
grant execute on function public.quote_parcel to authenticated;
