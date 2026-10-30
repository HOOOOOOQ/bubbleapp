// Permanently deletes the caller's account. Requires an explicit confirmation string. Owners must
// transfer the Owner role first (the Owner role is never removed silently).
import { json, preflight, readJsonObject } from "../_shared/http.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  const body = await readJsonObject(req);
  if (body instanceof Response) return body;
  if (body.confirm !== "DELETE MY ACCOUNT") return json({ error: "Confirmation text does not match" }, 400);
  const auth = await requireUser(req);
  if (auth instanceof Response) return auth;

  const admin = serviceClient();
  const { data: owner } = await admin
    .from("user_roles").select("id").eq("user_id", auth.userId).eq("role_key", "owner")
    .is("revoked_at", null).maybeSingle();
  if (owner) return json({ error: "Transfer the Owner role before deleting this account" }, 409);

  const { error } = await admin.auth.admin.deleteUser(auth.userId);
  if (error) return json({ error: "Account could not be deleted. Try again later." }, 500);
  return json({ ok: true });
});
