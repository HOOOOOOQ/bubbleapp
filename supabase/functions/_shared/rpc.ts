// Generic "forward to a database RPC as the caller" handler.
// The database function performs the permission check and writes the audit record.

import { json, preflight, readJsonObject } from "./http.ts";
import { requireUser } from "./supabase.ts";

export function rpcFunction(
  rpcName: string,
  build: (body: Record<string, unknown>) => Record<string, unknown> | Response,
): (req: Request) => Promise<Response> {
  return async (req: Request) => {
    const pre = preflight(req);
    if (pre) return pre;
    const body = await readJsonObject(req);
    if (body instanceof Response) return body;
    const auth = await requireUser(req);
    if (auth instanceof Response) return auth;
    const args = build(body);
    if (args instanceof Response) return args;
    const { data, error } = await auth.client.rpc(rpcName, args);
    if (error) {
      // Messages raised by the database are designed for users. SQLSTATE 42501 = not permitted,
      // P0002 = not found, anything else = rejected input or state.
      const status = error.code === "42501" ? 403 : error.code === "P0002" ? 404 : 422;
      return json({ error: error.message }, status);
    }
    return json({ ok: true, result: data ?? null });
  };
}
