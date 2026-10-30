// Sets a platform setting. Protected keys require owner.manage (checked in the database).
import { rpcFunction } from "../_shared/rpc.ts";
import { str } from "../_shared/http.ts";

Deno.serve(rpcFunction("set_platform_setting", (body) => {
  const key = str(body, "key", { max: 80 });
  if (key instanceof Response) return key;
  if (!("value" in body)) return new Response(JSON.stringify({ error: "value is required" }), { status: 400, headers: { "Content-Type": "application/json" } });
  return { p_key: key, p_value: body.value };
}));
