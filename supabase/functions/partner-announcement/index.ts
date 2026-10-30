// Publishes an announcement to partners. Requires the partner announcement permission.
import { rpcFunction } from "../_shared/rpc.ts";
import { str } from "../_shared/http.ts";

Deno.serve(rpcFunction("publish_partner_announcement", (body) => {
  const title = str(body, "title", { max: 120 });
  if (title instanceof Response) return title;
  const text = str(body, "body", { max: 4000 });
  if (text instanceof Response) return text;
  const category = str(body, "category", { max: 40, optional: true });
  if (category instanceof Response) return category;
  return { p_title: title, p_body: text, p_category: category };
}));
