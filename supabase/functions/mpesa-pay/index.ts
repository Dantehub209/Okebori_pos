// Sends an M-Pesa Express (STK push) prompt for a parcel that is AWAITING_PAYMENT,
// and checks on it while the cashier waits. The amount always comes from the
// parcel's server-calculated price, never from the phone.
//
// Secrets (Supabase > Edge Functions > Secrets):
//   MPESA_ENV               sandbox | production
//   MPESA_CONSUMER_KEY      from the Daraja app
//   MPESA_CONSUMER_SECRET   from the Daraja app
//   MPESA_SHORTCODE         Paybill / store number (sandbox: 174379)
//   MPESA_PASSKEY           Lipa na M-Pesa passkey
//   MPESA_CALLBACK_TOKEN    long random text; must match mpesa-callback
//   MPESA_TRANSACTION_TYPE  optional: CustomerPayBillOnline (default) or CustomerBuyGoodsOnline
//   MPESA_PARTY_B           optional: till number when using Buy Goods (defaults to the shortcode)
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`M-Pesa is not set up yet (missing ${name}).`);
  return value.trim();
}

const darajaBase = () =>
  env("MPESA_ENV") === "production" ? "https://api.safaricom.co.ke" : "https://sandbox.safaricom.co.ke";

/** 0712345678, 712345678, +254712345678 -> 254712345678 (Safaricom and Airtel style numbers). */
function normalizePhone(input: string): string | null {
  let d = (input ?? "").replace(/\D/g, "");
  if (d.startsWith("0")) d = "254" + d.slice(1);
  else if (d.length === 9 && (d.startsWith("7") || d.startsWith("1"))) d = "254" + d;
  return /^254(7|1)\d{8}$/.test(d) ? d : null;
}

/** YYYYMMDDHHmmss in Kenya time, as Daraja expects. */
function timestamp(): string {
  const t = new Date(Date.now() + 3 * 60 * 60 * 1000);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${t.getUTCFullYear()}${p(t.getUTCMonth() + 1)}${p(t.getUTCDate())}${p(t.getUTCHours())}${p(t.getUTCMinutes())}${p(t.getUTCSeconds())}`;
}

async function accessToken(): Promise<string> {
  const basic = btoa(`${env("MPESA_CONSUMER_KEY")}:${env("MPESA_CONSUMER_SECRET")}`);
  const res = await fetch(`${darajaBase()}/oauth/v1/generate?grant_type=client_credentials`, {
    headers: { Authorization: `Basic ${basic}` },
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || !data.access_token) throw new Error("Could not log in to M-Pesa. Check the Daraja keys.");
  return data.access_token;
}

function password(ts: string): string {
  return btoa(`${env("MPESA_SHORTCODE")}${env("MPESA_PASSKEY")}${ts}`);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "Use POST" });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Only active staff
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: caller, error: callerError } = await admin.auth.getUser(jwt);
  if (callerError || !caller.user) return reply(401, { error: "Please sign in again." });
  const { data: staff } = await admin.from("users").select("status, branch_id, role_id").eq("id", caller.user.id).maybeSingle();
  if (!staff || (staff.status ?? "active").toLowerCase() !== "active") {
    return reply(403, { error: "This account is not an active staff account." });
  }

  let input: Record<string, string>;
  try {
    input = await req.json();
  } catch {
    return reply(400, { error: "Invalid request." });
  }

  try {
    if (input.action === "check") return await check(admin, input.checkout_request_id);
    return await send(admin, caller.user.id, staff, input.parcel_id, input.phone);
  } catch (e) {
    return reply(400, { error: e instanceof Error ? e.message : String(e) });
  }
});

// deno-lint-ignore no-explicit-any
type Admin = any;

async function send(admin: Admin, userId: string, staff: { branch_id: string | null; role_id: string | null }, parcelId: string, rawPhone: string) {
  const phone = normalizePhone(rawPhone);
  if (!phone) return reply(400, { error: "Enter a valid Safaricom number, e.g. 0712 345 678." });

  const { data: parcel } = await admin
    .from("parcels")
    .select("id, status, shipping_charge, booking_number, origin_branch_id")
    .eq("id", parcelId)
    .maybeSingle();
  if (!parcel) return reply(404, { error: "Parcel not found." });
  if (parcel.status !== "AWAITING_PAYMENT") return reply(400, { error: "This parcel is not waiting for payment." });

  // Only the sending branch (or a Super Admin) collects payment
  const { data: role } = staff.role_id
    ? await admin.from("roles").select("name").eq("id", staff.role_id).maybeSingle()
    : { data: null };
  if (role?.name !== "Super Admin" && String(staff.branch_id) !== String(parcel.origin_branch_id)) {
    return reply(403, { error: "Only the sending branch can collect payment for this parcel." });
  }

  const { error: limitError } = await admin.rpc("mpesa_check_can_send", { p_parcel_id: parcel.id, p_phone: phone });
  if (limitError) return reply(429, { error: limitError.message });

  const amount = Math.ceil(Number(parcel.shipping_charge));
  if (!(amount > 0)) return reply(400, { error: "This parcel has no price." });

  const ts = timestamp();
  const shortcode = env("MPESA_SHORTCODE");
  const callbackUrl = `${Deno.env.get("SUPABASE_URL")}/functions/v1/mpesa-callback?token=${encodeURIComponent(env("MPESA_CALLBACK_TOKEN"))}`;
  const res = await fetch(`${darajaBase()}/mpesa/stkpush/v1/processrequest`, {
    method: "POST",
    headers: { Authorization: `Bearer ${await accessToken()}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      BusinessShortCode: shortcode,
      Password: password(ts),
      Timestamp: ts,
      TransactionType: Deno.env.get("MPESA_TRANSACTION_TYPE")?.trim() || "CustomerPayBillOnline",
      Amount: amount,
      PartyA: phone,
      PartyB: Deno.env.get("MPESA_PARTY_B")?.trim() || shortcode,
      PhoneNumber: phone,
      CallBackURL: callbackUrl,
      AccountReference: String(parcel.booking_number ?? "Okebori").slice(0, 12),
      TransactionDesc: "Parcel",
    }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || data.ResponseCode !== "0" || !data.CheckoutRequestID) {
    return reply(502, { error: `M-Pesa did not accept the request: ${data.errorMessage ?? data.ResponseDescription ?? res.status}` });
  }

  const { error: saveError } = await admin.from("mpesa_requests").insert({
    parcel_id: parcel.id,
    checkout_request_id: data.CheckoutRequestID,
    merchant_request_id: data.MerchantRequestID,
    phone,
    amount,
    requested_by: userId,
  });
  if (saveError) return reply(500, { error: `Prompt sent but not recorded: ${saveError.message}` });

  return reply(200, { checkout_request_id: data.CheckoutRequestID, amount, phone, status: "pending" });
}

/** Called by the app every few seconds while waiting. Also asks Safaricom directly,
 *  so a cancelled or timed-out prompt is noticed even if the callback is slow. */
async function check(admin: Admin, checkoutRequestId: string) {
  const { data: request } = await admin
    .from("mpesa_requests")
    .select("parcel_id, status, result_desc, created_at")
    .eq("checkout_request_id", checkoutRequestId)
    .maybeSingle();
  if (!request) return reply(404, { error: "Payment request not found." });

  if (request.status === "success") {
    const { data: receipt } = await admin
      .from("receipts")
      .select("receipt_number")
      .eq("parcel_id", request.parcel_id)
      .order("issued_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    return reply(200, { status: "success", receipt_number: receipt?.receipt_number ?? null });
  }
  if (request.status !== "pending") return reply(200, { status: request.status, result_desc: request.result_desc });

  // Give the customer time to see the prompt before asking Safaricom
  if (Date.now() - new Date(request.created_at).getTime() < 20_000) return reply(200, { status: "pending" });

  const ts = timestamp();
  const res = await fetch(`${darajaBase()}/mpesa/stkpushquery/v1/query`, {
    method: "POST",
    headers: { Authorization: `Bearer ${await accessToken()}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      BusinessShortCode: env("MPESA_SHORTCODE"),
      Password: password(ts),
      Timestamp: ts,
      CheckoutRequestID: checkoutRequestId,
    }),
  });
  const data = await res.json().catch(() => ({}));
  const code = data.ResultCode === undefined ? null : String(data.ResultCode);
  // Still being processed, or paid but the callback (which carries the receipt) hasn't arrived yet
  if (code === null || code === "0") return reply(200, { status: "pending" });

  await admin.rpc("fail_mpesa_request", {
    p_checkout_request_id: checkoutRequestId,
    p_result_code: code,
    p_result_desc: data.ResultDesc ?? "Not paid",
  });
  return reply(200, { status: code === "1032" ? "cancelled" : "failed", result_desc: data.ResultDesc ?? "Not paid" });
}
