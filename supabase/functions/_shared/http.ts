// Shared HTTP helpers for BubbleApp Edge Functions.

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-job-secret, x-webhook-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function preflight(req: Request): Response | null {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  return null;
}

// Requires POST and returns the parsed JSON object, or a Response describing the failure.
export async function readJsonObject(req: Request): Promise<Record<string, unknown> | Response> {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Request body must be JSON" }, 400);
  }
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return json({ error: "Request body must be a JSON object" }, 400);
  }
  return body as Record<string, unknown>;
}

export function str(body: Record<string, unknown>, key: string, opts: { max?: number; optional: true }): string | null | Response;
export function str(body: Record<string, unknown>, key: string, opts?: { max?: number; optional?: false }): string | Response;
export function str(body: Record<string, unknown>, key: string, opts: { max?: number; optional?: boolean } = {}): string | null | Response {
  const v = body[key];
  if (v === undefined || v === null || v === "") {
    if (opts.optional) return null;
    return json({ error: `${key} is required` }, 400);
  }
  if (typeof v !== "string") return json({ error: `${key} must be a string` }, 400);
  const trimmed = v.trim();
  if (opts.max && trimmed.length > opts.max) return json({ error: `${key} is too long` }, 400);
  return trimmed;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function uuid(body: Record<string, unknown>, key: string): string | Response {
  const v = body[key];
  if (typeof v !== "string" || !UUID.test(v)) return json({ error: `${key} must be a UUID` }, 400);
  return v;
}

// Constant-time comparison for shared secrets.
export function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
