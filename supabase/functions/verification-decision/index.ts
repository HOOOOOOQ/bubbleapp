// Verification decisions (approve, reject, suspend, revoke, restore). The database checks the
// reviewer's permission (users.verify / channels.verify), updates the badge state, and writes
// verification_history and the audit log in the same transaction.
import { rpcFunction } from "../_shared/rpc.ts";
import { str, uuid } from "../_shared/http.ts";

Deno.serve(rpcFunction("review_verification_application", (body) => {
  const id = uuid(body, "application_id");
  if (id instanceof Response) return id;
  const action = str(body, "action", { max: 20 });
  if (action instanceof Response) return action;
  const note = str(body, "note", { max: 1000, optional: true });
  if (note instanceof Response) return note;
  return { p_application_id: id, p_action: action, p_note: note };
}));
