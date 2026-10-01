// Creates a staff login and their users row without signing the admin out.
// Only active Super Admins may call it. Deploy: see README "Add staff function".
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "Use POST" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Who is calling?
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: caller, error: callerError } = await admin.auth.getUser(token);
  if (callerError || !caller.user) return reply(401, { error: "Please sign in again." });

  const { data: callerRow } = await admin
    .from("users")
    .select("status, business_id, role_id")
    .eq("id", caller.user.id)
    .maybeSingle();
  const { data: roleRow } = callerRow?.role_id
    ? await admin.from("roles").select("name").eq("id", callerRow.role_id).maybeSingle()
    : { data: null };
  const callerRole = roleRow?.name;
  const callerActive = (callerRow?.status ?? "active").toLowerCase() === "active";
  if (callerRole !== "Super Admin" || !callerActive) {
    return reply(403, { error: "Only Super Admins can add staff." });
  }

  let input: Record<string, string>;
  try {
    input = await req.json();
  } catch {
    return reply(400, { error: "Invalid request." });
  }
  const name = (input.name ?? "").trim();
  const email = (input.email ?? "").trim().toLowerCase();
  const phone = (input.phone ?? "").trim();
  const password = input.password ?? "";
  const roleId = input.role_id;
  const branchId = input.branch_id;
  if (!name || !email || password.length < 6 || !roleId || !branchId) {
    return reply(400, { error: "Name, email, role, branch and a password of 6+ characters are required." });
  }

  // Create the login, already confirmed so they can sign in straight away
  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { name },
  });
  if (createError || !created.user) {
    return reply(400, { error: createError?.message ?? "Could not create the login." });
  }

  const { error: rowError } = await admin.from("users").insert({
    id: created.user.id,
    business_id: callerRow?.business_id,
    branch_id: branchId,
    role_id: roleId,
    name,
    email,
    phone,
    status: "active",
  });
  if (rowError) {
    // Don't leave a login with no staff record behind
    await admin.auth.admin.deleteUser(created.user.id);
    return reply(400, { error: rowError.message });
  }

  return reply(200, { id: created.user.id });
});
