// Edits a staff member: name, phone, role, branch, active status, and their
// login email/password. Deactivating also blocks their login straight away.
// Only active Super Admins may call it. Deploy like create-staff (README).
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

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Only active Super Admins
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: caller, error: callerError } = await admin.auth.getUser(token);
  if (callerError || !caller.user) return reply(401, { error: "Please sign in again." });
  const { data: callerRow } = await admin.from("users").select("status, role_id").eq("id", caller.user.id).maybeSingle();
  const { data: callerRole } = callerRow?.role_id
    ? await admin.from("roles").select("name").eq("id", callerRow.role_id).maybeSingle()
    : { data: null };
  const callerActive = (callerRow?.status ?? "active").toLowerCase() === "active";
  if (callerRole?.name !== "Super Admin" || !callerActive) {
    return reply(403, { error: "Only Super Admins can edit staff." });
  }

  let input: Record<string, string | null>;
  try {
    input = await req.json();
  } catch {
    return reply(400, { error: "Invalid request." });
  }
  const id = input.id ?? "";
  const name = (input.name ?? "").trim();
  const email = (input.email ?? "").trim().toLowerCase();
  const phone = (input.phone ?? "").trim();
  const password = input.password ?? "";
  const roleId = input.role_id;
  const branchId = input.branch_id;
  const status = input.status === "inactive" ? "inactive" : "active";
  if (!id || !name || !email || !roleId || !branchId) {
    return reply(400, { error: "Name, email, role and branch are required." });
  }
  if (password && password.length < 6) return reply(400, { error: "New password must be at least 6 characters." });

  // Don't let an admin lock themselves out
  if (id === caller.user.id) {
    if (status !== "active") return reply(400, { error: "You can't deactivate your own account." });
    if (roleId !== callerRow?.role_id) return reply(400, { error: "You can't change your own role." });
  }

  const { data: existing, error: findError } = await admin.auth.admin.getUserById(id);
  if (findError || !existing.user) return reply(404, { error: "Staff login not found." });

  // Login details. A long ban blocks sign-in for deactivated staff; "none" lifts it.
  const authChanges: Record<string, unknown> = { ban_duration: status === "active" ? "none" : "876000h" };
  if (email !== (existing.user.email ?? "").toLowerCase()) {
    authChanges.email = email;
    authChanges.email_confirm = true;
  }
  if (password) authChanges.password = password;
  const { error: authError } = await admin.auth.admin.updateUserById(id, authChanges);
  if (authError) return reply(400, { error: authError.message });

  const { error: rowError } = await admin
    .from("users")
    .update({ name, email, phone, role_id: roleId, branch_id: branchId, status })
    .eq("id", id);
  if (rowError) return reply(400, { error: rowError.message });

  return reply(200, { id });
});
