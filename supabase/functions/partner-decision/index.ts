// Partner application decisions. Partner status never grants admin rights; partner permissions are
// set separately (see partner-permission).
import { rpcFunction } from "../_shared/rpc.ts";
import { str, uuid } from "../_shared/http.ts";

Deno.serve(rpcFunction("review_partner_application", (body) => {
  const id = uuid(body, "application_id");
  if (id instanceof Response) return id;
  const action = str(body, "action", { max: 20 });
  if (action instanceof Response) return action;
  const category = str(body, "category", { max: 40, optional: true });
  if (category instanceof Response) return category;
  const note = str(body, "note", { max: 1000, optional: true });
  if (note instanceof Response) return note;
  return { p_application_id: id, p_action: action, p_category: category, p_note: note };
}));
