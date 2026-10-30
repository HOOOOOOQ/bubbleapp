// Publishes a platform-wide announcement (optionally to the official @BubbleApp channel).
import { rpcFunction } from "../_shared/rpc.ts";
import { str } from "../_shared/http.ts";

Deno.serve(rpcFunction("publish_platform_announcement", (body) => {
  const title = str(body, "title", { max: 120 });
  if (title instanceof Response) return title;
  const text = str(body, "body", { max: 4000 });
  if (text instanceof Response) return text;
  const audience = str(body, "audience", { max: 20, optional: true });
  if (audience instanceof Response) return audience;
  return {
    p_title: title,
    p_body: text,
    p_audience: audience ?? "all",
    p_post_to_official: body.post_to_official === true,
  };
}));
