import { corsHeaders, json, preflight } from '../_shared/http.ts';
import { requiredEnv } from '../_shared/supabase.ts';
import { createClient } from 'npm:@supabase/supabase-js@2';

// Returns time-limited TURN/STUN config for authenticated caller.
// Secrets must be set in Supabase Dashboard: TURN_URL, TURN_USERNAME, TURN_CREDENTIAL
// Optional: TURN_URLS (comma-separated), STUN_URLS, TURN_TTL_SECONDS.
// Never expose service_role; we validate membership via RLS when call_id supplied.

const DEFAULT_STUN = ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'];

function supabaseFromAuthHeader(req: Request) {
  const url = requiredEnv('SUPABASE_URL');
  const anonKey = requiredEnv('SUPABASE_ANON_KEY');
  const auth = req.headers.get('authorization') ?? '';
  return createClient(url, anonKey, { global: { headers: { Authorization: auth } } });
}

Deno.serve(async (req: Request) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== 'POST' && req.method !== 'GET') return json({ error: 'Method not allowed' }, 405);

  const authHeader = req.headers.get('authorization');
  if (!authHeader || !authHeader.toLowerCase().startsWith('bearer ')) return json({ error: 'Missing authorization' }, 401);

  const supabase = supabaseFromAuthHeader(req);

  // Verify JWT by fetching user — fails if invalid/expired
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) return json({ error: 'Invalid token' }, 401);

  // Optional verification: if call_id provided, ensure caller is participant (RLS)
  let callId: string | null = null;
  if (req.method === 'POST') {
    try { const b = await req.clone().json(); callId = (b as Record<string, unknown>).call_id as string ?? (b as Record<string, unknown>).callId as string ?? null; } catch { /* ignore */ }
  } else {
    callId = new URL(req.url).searchParams.get('call_id');
  }

  if (callId) {
    const { data, error } = await supabase.from('calls').select('id').eq('id', callId).maybeSingle();
    if (error) return json({ error: error.message }, 400);
    if (!data) return json({ error: 'Call not found or not a participant' }, 404);
  }

  const turnUrl = Deno.env.get('TURN_URL');
  const turnUrlsEnv = Deno.env.get('TURN_URLS');
  const stunUrlsEnv = Deno.env.get('STUN_URLS');
  const username = Deno.env.get('TURN_USERNAME');
  const credential = Deno.env.get('TURN_CREDENTIAL');
  const ttl = parseInt(Deno.env.get('TURN_TTL_SECONDS') ?? '86400', 10);

  const stunUrls: string[] = stunUrlsEnv ? stunUrlsEnv.split(',').map((s: string) => s.trim()).filter(Boolean) : DEFAULT_STUN;
  const iceServers: Array<Record<string, unknown>> = stunUrls.map((url: string) => ({ urls: url }));

  if (turnUrl && username && credential) {
    const turnUrls: string[] = turnUrlsEnv ? turnUrlsEnv.split(',').map((s: string) => s.trim()).filter(Boolean) : [turnUrl];
    for (const url of turnUrls) {
      iceServers.push({ urls: url, username, credential });
    }
  } else if (turnUrl) {
    iceServers.push({ urls: turnUrl });
  }

  return json({
    iceServers,
    ttlSeconds: ttl,
    turnConfigured: Boolean(turnUrl && username && credential),
    note: !turnUrl ? 'TURN not configured — set TURN_URL, TURN_USERNAME, TURN_CREDENTIAL for NAT traversal. See supabase/README.md.' : undefined,
  }, 200);
});
