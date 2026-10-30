// Supabase clients for Edge Functions.
//
// userClient(req): acts AS THE CALLER (anon key + caller's JWT). Every RPC and query runs
//   under the caller's identity, so the database RLS and RBAC checks are the authority.
//   Use this for all user-initiated actions.
// serviceClient(): service-role key. Bypasses RLS. Use ONLY for scheduled jobs, webhooks,
//   and account deletion, and never to decide a permission on the caller's behalf.

import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";
import { json } from "./http.ts";

export function requiredEnv(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing environment variable ${name}. See supabase/README.md.`);
  return v;
}

export function userClient(req: Request): SupabaseClient {
  // Supabase injects SUPABASE_URL and SUPABASE_ANON_KEY (or SUPABASE_PUBLISHABLE_KEY) into functions.
  const key = Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? requiredEnv("SUPABASE_ANON_KEY");
  return createClient(requiredEnv("SUPABASE_URL"), key, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export function serviceClient(): SupabaseClient {
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
  return createClient(requiredEnv("SUPABASE_URL"), key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

// Verifies the caller's JWT with Supabase Auth. Returns the user id or a 401 Response.
export async function requireUser(req: Request): Promise<{ userId: string; client: SupabaseClient } | Response> {
  if (!req.headers.get("Authorization")) return json({ error: "Sign in required" }, 401);
  const client = userClient(req);
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) return json({ error: "Sign in required" }, 401);
  return { userId: data.user.id, client };
}
