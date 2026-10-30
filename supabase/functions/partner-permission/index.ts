// Grants or revokes ONE partner permission for a partner. Requires partners.manage.
import { rpcFunction } from "../_shared/rpc.ts";
import { uuid, str } from "../_shared/http.ts";

Deno.serve(rpcFunction("set_partner_permission", (body) => {
  const userId = uuid(body, "user_id");
  if (userId instanceof Response) return userId;
  const permission = str(body, "permission", { max: 60 });
  if (permission instanceof Response) return permission;
  if (typeof body.granted !== "boolean") return new Response(JSON.stringify({ error: "granted must be a boolean" }), { status: 400, headers: { "Content-Type": "application/json" } });
  return { p_user_id: userId, p_permission: permission, p_granted: body.granted };
}));
