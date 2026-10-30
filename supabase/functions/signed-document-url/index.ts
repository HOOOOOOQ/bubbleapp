// Issues a short-lived signed URL for a verification document. The bucket is private. The storage
// policy decides access: the applicant, or a reviewer with users.verify / channels.verify.
import { json, preflight, readJsonObject, str } from "../_shared/http.ts";
import { requireUser } from "../_shared/supabase.ts";

const LIFETIME_SECONDS = 300;

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  const body = await readJsonObject(req);
  if (body instanceof Response) return body;
  const auth = await requireUser(req);
  if (auth instanceof Response) return auth;
  const path = str(body, "path", { max: 300 });
  if (path instanceof Response) return path;
  if (path.includes("..") || path.startsWith("/")) return json({ error: "Invalid path" }, 400);

  // Storage RLS applies to the caller's client, so the signed URL is only issued when allowed.
  const { data, error } = await auth.client.storage
    .from("verification-documents")
    .createSignedUrl(path, LIFETIME_SECONDS);
  if (error || !data) return json({ error: "Document not available" }, 404);
  return json({ ok: true, url: data.signedUrl, expires_in: LIFETIME_SECONDS });
});
