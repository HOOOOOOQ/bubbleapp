// Admin management — Owner/Super Admin only, enforced in DB. Covers new Part 7 RPCs.
// Body: { op: string, user_id, ... }
import { json, preflight, readJsonObject, str, uuid } from "../_shared/http.ts";
import { requireUser } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  const body = await readJsonObject(req);
  if (body instanceof Response) return body;
  const auth = await requireUser(req);
  if (auth instanceof Response) return auth;

  const userId = body.user_id ? uuid(body, "user_id") : null;
  if (userId instanceof Response) return userId as unknown as Response;

  let rpc: string;
  let args: Record<string, unknown> = {};
  const op = str(body, "op", { max: 40 });
  if (op instanceof Response) return op;
  switch (op) {
    case "create": {
      const uid = uuid(body, "user_id"); if (uid instanceof Response) return uid;
      const role = str(body, "role_key", { max: 40 }); if (role instanceof Response) return role;
      const perms = Array.isArray(body.permissions) ? body.permissions.filter((p) => typeof p === "string") : [];
      rpc = "admin_create_admin"; args = { p_user_id: uid, p_role_key: role, p_permissions: perms }; break;
    }
    case "set_permission": {
      const uid = uuid(body, "user_id"); if (uid instanceof Response) return uid;
      const perm = str(body, "permission", { max: 60 }); if (perm instanceof Response) return perm;
      const mode = str(body, "mode", { max: 10 }); if (mode instanceof Response) return mode;
      rpc = "admin_set_permission"; args = { p_user_id: uid, p_permission: perm, p_mode: mode }; break;
    }
    case "set_status": {
      const uid = uuid(body, "user_id"); if (uid instanceof Response) return uid;
      const status = str(body, "status", { max: 20 }); if (status instanceof Response) return status;
      const reason = str(body, "reason", { max: 500, optional: true }); if (reason instanceof Response) return reason;
      rpc = "admin_set_admin_status"; args = { p_user_id: uid, p_status: status, p_reason: reason }; break;
    }
    case "warn": {
      const uid = uuid(body, "user_id"); if (uid instanceof Response) return uid;
      const reason = str(body, "reason", { max: 500 }); if (reason instanceof Response) return reason;
      rpc = "admin_issue_warning"; args = { p_user_id: uid, p_reason: reason }; break;
    }
    case "restrict": {
      const uid = uuid(body, "user_id"); if (uid instanceof Response) return uid;
      const feature = str(body, "feature", { max: 60 }); if (feature instanceof Response) return feature;
      const reason = str(body, "reason", { max: 500, optional: true }); if (reason instanceof Response) return reason;
      rpc = "admin_restrict_feature"; args = { p_user_id: uid, p_feature: feature, p_reason: reason }; break;
    }
    case "revoke_sessions": {
      const uid = uuid(body, "user_id"); if (uid instanceof Response) return uid;
      const reason = str(body, "reason", { max: 500, optional: true }); if (reason instanceof Response) return reason;
      rpc = "admin_revoke_sessions"; args = { p_user_id: uid, p_reason: reason }; break;
    }
    case "lift_restriction": {
      const rid = uuid(body, "restriction_id"); if (rid instanceof Response) return rid;
      rpc = "admin_lift_restriction"; args = { p_restriction_id: rid }; break;
    }
    case "emergency_suspend": {
      const uid = uuid(body, "user_id"); if (uid instanceof Response) return uid;
      const reason = str(body, "reason", { max: 500 }); if (reason instanceof Response) return reason;
      rpc = "admin_emergency_suspend"; args = { p_user_id: uid, p_reason: reason }; break;
    }
    case "maintenance": {
      const enabled = body.enabled === true;
      const ann = str(body, "announcement", { max: 2000, optional: true }); if (ann instanceof Response) return ann;
      rpc = "owner_set_maintenance"; args = { p_enabled: enabled, p_announcement: ann ?? null }; break;
    }
    case "assign_report": {
      const rid = uuid(body, "report_id"); if (rid instanceof Response) return rid;
      const aid = uuid(body, "assignee_id"); if (aid instanceof Response) return aid;
      rpc = "moderation_assign"; args = { p_report_id: rid, p_assignee: aid }; break;
    }
    case "escalate_report": {
      const rid = uuid(body, "report_id"); if (rid instanceof Response) return rid;
      const note = str(body, "note", { max: 2000, optional: true }); if (note instanceof Response) return note;
      rpc = "moderation_escalate"; args = { p_report_id: rid, p_note: note ?? null }; break;
    }
    case "platform_setting": {
      const key = str(body, "key", { max: 80 }); if (key instanceof Response) return key;
      rpc = "set_platform_setting"; args = { p_key: key, p_value: body.value ?? null }; break;
    }
    default:
      return json({ error: "Unknown op" }, 400);
  }
  const { data, error } = await auth.client.rpc(rpc, args);
  if (error) return json({ error: error.message }, error.code === "42501" ? 403 : 422);
  return json({ ok: true, result: data ?? null });
});
