#!/usr/bin/env bash
# Applies BubbleApp migrations to a throwaway PostgreSQL database and runs the test suite.
# Usage: DATABASE_URL=postgresql://... scripts/test_db.sh
# The target database must be disposable: it is reset by the stub script.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB_URL="${DATABASE_URL:?set DATABASE_URL to a disposable PostgreSQL database}"
PSQL=(psql "$DB_URL" -v ON_ERROR_STOP=1 -q)

"${PSQL[@]}" -f "$ROOT/supabase/tests/00_supabase_stub.sql"
for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "== migrate $(basename "$f")"
  "${PSQL[@]}" -f "$f"
done
"${PSQL[@]}" -f "$ROOT/supabase/tests/01_helpers.sql"
"${PSQL[@]}" -f "$ROOT/supabase/tests/02_scenarios.sql"
"${PSQL[@]}" -f "$ROOT/supabase/tests/03_scenarios_business_social_ops.sql"
"${PSQL[@]}" -f "$ROOT/supabase/tests/04_scenarios_messaging_calls.sql"
echo "== suite finished"
