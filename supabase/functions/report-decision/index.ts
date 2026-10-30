// Resolves a user report (moderation). Requires the moderation permission; the action is audited.
import { rpcFunction } from "../_shared/rpc.ts";
import { str, uuid } from "../_shared/http.ts";

Deno.serve(rpcFunction("resolve_report", (body) => {
  const id = uuid(body, "report_id");
  if (id instanceof Response) return id;
  const action = str(body, "action", { max: 40 });
  if (action instanceof Response) return action;
  const note = str(body, "note", { max: 1000, optional: true });
  if (note instanceof Response) return note;
  return { p_report_id: id, p_action: action, p_note: note };
}));
