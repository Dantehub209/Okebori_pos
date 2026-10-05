// Safaricom calls this when the customer finishes (or cancels) an M-Pesa prompt.
// It is the ONLY way an M-Pesa payment gets recorded.
//
// Deploy with "Enforce JWT verification" turned OFF (Safaricom cannot sign in);
// instead the URL must carry ?token=MPESA_CALLBACK_TOKEN, which mpesa-pay adds.
// Before trusting a "paid" message it asks Safaricom directly to confirm, and the
// database then checks the amount and that the receipt number is new.
import { createClient } from "npm:@supabase/supabase-js@2";

const accepted = () =>
  new Response(JSON.stringify({ ResultCode: 0, ResultDesc: "Accepted" }), {
    headers: { "Content-Type": "application/json" },
  });

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value.trim();
}

const darajaBase = () =>
  env("MPESA_ENV") === "production" ? "https://api.safaricom.co.ke" : "https://sandbox.safaricom.co.ke";

function timestamp(): string {
  const t = new Date(Date.now() + 3 * 60 * 60 * 1000);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${t.getUTCFullYear()}${p(t.getUTCMonth() + 1)}${p(t.getUTCDate())}${p(t.getUTCHours())}${p(t.getUTCMinutes())}${p(t.getUTCSeconds())}`;
}

/** Same length and same characters, compared without leaking timing. */
function sameSecret(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** Ask Safaricom whether this prompt really was paid. */
async function confirmedPaid(checkoutRequestId: string): Promise<boolean> {
  const basic = btoa(`${env("MPESA_CONSUMER_KEY")}:${env("MPESA_CONSUMER_SECRET")}`);
  const tokenRes = await fetch(`${darajaBase()}/oauth/v1/generate?grant_type=client_credentials`, {
    headers: { Authorization: `Basic ${basic}` },
  });
  const { access_token } = await tokenRes.json();
  const ts = timestamp();
  const res = await fetch(`${darajaBase()}/mpesa/stkpushquery/v1/query`, {
    method: "POST",
    headers: { Authorization: `Bearer ${access_token}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      BusinessShortCode: env("MPESA_SHORTCODE"),
      Password: btoa(`${env("MPESA_SHORTCODE")}${env("MPESA_PASSKEY")}${ts}`),
      Timestamp: ts,
      CheckoutRequestID: checkoutRequestId,
    }),
  });
  const data = await res.json().catch(() => ({}));
  return String(data.ResultCode) === "0";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  const token = new URL(req.url).searchParams.get("token") ?? "";
  if (!sameSecret(token, env("MPESA_CALLBACK_TOKEN"))) {
    console.warn("M-Pesa callback with a wrong token was rejected");
    return new Response("Forbidden", { status: 403 });
  }

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try {
    body = await req.json();
  } catch {
    return accepted();
  }
  const cb = body?.Body?.stkCallback;
  const checkoutRequestId: string | undefined = cb?.CheckoutRequestID;
  if (!checkoutRequestId) return accepted();

  // Keep Safaricom's exact message for reconciliation, whatever happens next
  await admin
    .from("mpesa_requests")
    .update({ callback_payload: body, updated_at: new Date().toISOString() })
    .eq("checkout_request_id", checkoutRequestId);

  const resultCode = String(cb.ResultCode);
  if (resultCode !== "0") {
    await admin.rpc("fail_mpesa_request", {
      p_checkout_request_id: checkoutRequestId,
      p_result_code: resultCode,
      p_result_desc: cb.ResultDesc ?? "Not paid",
    });
    return accepted();
  }

  const items: { Name: string; Value?: string | number }[] = cb.CallbackMetadata?.Item ?? [];
  const get = (name: string) => items.find((i) => i.Name === name)?.Value;
  const receipt = String(get("MpesaReceiptNumber") ?? "");
  const amount = Number(get("Amount"));
  const phone = String(get("PhoneNumber") ?? "");

  try {
    if (!(await confirmedPaid(checkoutRequestId))) {
      console.warn(`Callback said paid but Safaricom did not confirm ${checkoutRequestId}; left pending`);
      return accepted();
    }
  } catch (e) {
    // Safaricom unreachable: the request stays pending with the payload saved for follow-up
    console.error(`Could not confirm ${checkoutRequestId} with Safaricom`, e);
    return accepted();
  }

  const { data, error } = await admin.rpc("complete_mpesa_payment", {
    p_checkout_request_id: checkoutRequestId,
    p_mpesa_receipt: receipt,
    p_amount: amount,
    p_phone: phone,
  });
  if (error) console.error(`Could not record ${checkoutRequestId}: ${error.message}`);
  else console.log(`M-Pesa ${checkoutRequestId}: ${JSON.stringify(data)}`);
  return accepted();
});
