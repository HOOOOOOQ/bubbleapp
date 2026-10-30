// Suspends, bans, or restores an account. Requires an admin permission; audited in the database.
import { rpcFunction } from "../_shared/rpc.ts";
import { str, uuid } from "../_shared/http.ts";

Deno.serve(rpcFunction("admin_set_account_status", (body) => {
  const userId = uuid(body, "user_id");
  if (userId instanceof Response) return userId;
  const status = str(body, "status", { max: 20 });
  if (status instanceof Response) return status;
  const reason = str(body, "reason", { max: 500, optional: true });
  if (reason instanceof Response) return reason;
  return { p_user_id: userId, p_status: status, p_reason: reason };
}));
