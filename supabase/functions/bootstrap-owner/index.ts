// One-time Owner bootstrap. The caller must be signed in with a verified email.
// The token is issued by the operator with issue_owner_bootstrap_token() in a trusted
// database session; only its hash is stored. The database redeems it atomically and
// closes the path once any Owner exists.
import { rpcFunction } from "../_shared/rpc.ts";
import { str } from "../_shared/http.ts";

Deno.serve(rpcFunction("redeem_owner_bootstrap", (body) => {
  const token = str(body, "token", { max: 256 });
  if (token instanceof Response) return token;
  return { p_token: token };
}));
