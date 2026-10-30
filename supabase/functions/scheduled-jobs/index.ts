// Runs time-based database jobs. Invoke every minute from a scheduler (Supabase cron, pg_cron via
// pg_net, or an external scheduler) with header x-job-secret = JOB_SECRET.
//   - expire_stale_calls(): ends ringing calls that were not answered
//   - dispatch_due_channel_posts(): publishes scheduled official-channel posts
//   - dispatch_due_scheduled_messages(): sends user-scheduled messages
import { json, preflight, safeEqual } from "../_shared/http.ts";
import { requiredEnv, serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const secret = req.headers.get("x-job-secret") ?? "";
  if (!safeEqual(secret, requiredEnv("JOB_SECRET"))) return json({ error: "Forbidden" }, 403);

  const admin = serviceClient();
  const [calls, posts, messages, signals, stories] = await Promise.all([
    admin.rpc("expire_stale_calls"),
    admin.rpc("dispatch_due_channel_posts"),
    admin.rpc("dispatch_due_scheduled_messages", { p_limit: 100 }),
    admin.rpc("cleanup_expired_call_signals"),
    admin.rpc("cleanup_expired_stories"),
  ]);
  const errors = [calls.error, posts.error, messages.error, signals.error, stories.error].filter(Boolean).map((e) => e!.message);
  if (errors.length) return json({ ok: false, errors }, 500);
  return json({
    ok: true,
    expired_calls: calls.data ?? 0,
    published_posts: posts.data ?? 0,
    sent_scheduled_messages: messages.data ?? 0,
    cleaned_signals: signals.data ?? 0,
    cleaned_stories: stories.data ?? 0,
  });
});
