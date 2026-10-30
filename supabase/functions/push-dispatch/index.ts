// Sends FCM (HTTP v1) push messages for notifications that have not been pushed yet.
// Triggered by a Supabase Database Webhook on INSERT into public.notifications, which sends
// header x-webhook-secret = PUSH_WEBHOOK_SECRET. Preferences were already applied when the
// notification row was created (notify_user), so this function only delivers rows that exist.
//
// Required secrets (see supabase/README.md):
//   FCM_PROJECT_ID, FCM_CLIENT_EMAIL, FCM_PRIVATE_KEY (service account), PUSH_WEBHOOK_SECRET.
import { json, preflight, safeEqual } from "../_shared/http.ts";
import { requiredEnv, serviceClient } from "../_shared/supabase.ts";

const enc = new TextEncoder();

function b64url(bytes: ArrayBuffer | Uint8Array): string {
  const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let s = "";
  for (const b of u8) s += String.fromCharCode(b);
  return btoa(s).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
}

// OAuth2 access token from the service account (JWT bearer grant, RS256).
async function googleAccessToken(): Promise<string> {
  const email = requiredEnv("FCM_CLIENT_EMAIL");
  const pem = requiredEnv("FCM_PRIVATE_KEY").replace(/\\n/g, "\n");
  const der = Uint8Array.from(atob(pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "")), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(enc.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = b64url(enc.encode(JSON.stringify({
    iss: email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })));
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, enc.encode(`${header}.${claims}`));
  const assertion = `${header}.${claims}.${b64url(signature)}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!res.ok) throw new Error(`Google token request failed (${res.status})`);
  return (await res.json()).access_token as string;
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!safeEqual(req.headers.get("x-webhook-secret") ?? "", requiredEnv("PUSH_WEBHOOK_SECRET"))) {
    return json({ error: "Forbidden" }, 403);
  }
  const payload = await req.json().catch(() => null);
  const notificationId: unknown = payload?.record?.id ?? payload?.notification_id;
  if (typeof notificationId !== "string") return json({ error: "notification id missing" }, 400);

  const admin = serviceClient();
  const { data: note } = await admin
    .from("notifications").select("id, user_id, kind, title, body, data, push_sent_at, push_attempts")
    .eq("id", notificationId).maybeSingle();
  if (!note) return json({ error: "Notification not found" }, 404);
  if (note.push_sent_at) return json({ ok: true, skipped: "already sent" });

  const { data: devices } = await admin
    .from("devices").select("id, fcm_token").eq("user_id", note.user_id).not("fcm_token", "is", null);

  let sent = 0;
  let failed = 0;
  if (devices && devices.length) {
    const token = await googleAccessToken();
    const url = `https://fcm.googleapis.com/v1/projects/${requiredEnv("FCM_PROJECT_ID")}/messages:send`;
    for (const d of devices) {
      const res = await fetch(url, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token: d.fcm_token,
            notification: { title: note.title, body: note.body },
            data: { kind: note.kind, notification_id: note.id, ...Object.fromEntries(
              Object.entries(note.data ?? {}).map(([k, v]) => [k, String(v)])) },
            android: { priority: "HIGH" },
          },
        }),
      });
      if (res.ok) {
        sent++;
      } else {
        failed++;
        // Remove tokens FCM reports as no longer registered.
        const body = await res.text();
        if (body.includes("UNREGISTERED") || body.includes("INVALID_ARGUMENT")) {
          await admin.from("devices").delete().eq("id", d.id);
        }
      }
    }
  }
  await admin.from("notifications").update({
    push_sent_at: new Date().toISOString(),
    push_attempts: (note.push_attempts ?? 0) + 1,
    push_error: failed ? `${failed} device(s) failed` : null,
  }).eq("id", note.id);
  return json({ ok: true, sent, failed });
});
