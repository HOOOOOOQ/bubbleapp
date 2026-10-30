// Admin account management. Owner/Super Admin only, enforced in the database.
// Body: { op: "create" | "set_permission" | "set_status", ... }
import { json, preflight, readJsonObject, str, uuid } from "../_shared/http.ts";
import { requireUser } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  const body = await readJsonObject(req);
  if (body instanceof Response) return body;
  const auth = await requireUser(req);
  if (auth instanceof Response) return auth;

  const userId = uuid(body, "user_id");
  if (userId instanceof Response) return userId;

  let rpc: string;
  let args: Record<string, unknown>;
  switch (body.op) {
    case "create": {
      const role = str(body, "role_key", { max: 40 });
      if (role instanceof Response) return role;
      const perms = Array.isArray(body.permissions) ? body.permissions.filter((p) => typeof p === "string") : [];
      rpc = "admin_create_admin";
      args = { p_user_id: userId, p_role_key: role, p_permissions: perms };
      break;
    }
    case "set_permission": {
      const perm = str(body, "permission", { max: 60 });
      if (perm instanceof Response) return perm;
      const mode = str(body, "mode", { max: 10 });
      if (mode instanceof Response) return mode;
      rpc = "admin_set_permission";
      args = { p_user_id: userId, p_permission: perm, p_mode: mode };
      break;
    }
    case "set_status": {
      const status = str(body, "status", { max: 20 });
      if (status instanceof Response) return status;
      const reason = str(body, "reason", { max: 500, optional: true });
      if (reason instanceof Response) return reason;
      rpc = "admin_set_admin_status";
      args = { p_user_id: userId, p_status: status, p_reason: reason };
      break;
    }
    default:
      return json({ error: "Unknown op" }, 400);
  }
  const { data, error } = await auth.client.rpc(rpc, args);
  if (error) return json({ error: error.message }, error.code === "42501" ? 403 : 422);
  return json({ ok: true, result: data ?? null });
});
