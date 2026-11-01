# Part 8 — Business & Partner Ecosystem

This part extends the existing BubbleApp schema (migrations 0001–0015) with the business
workspace and the partner programme. **Nothing is simulated**: every number on screen is
computed from rows the platform really stores, and every privileged action is re-checked by
the database.

## What ships

| Area | Database (migration 0016) | Flutter |
| --- | --- | --- |
| Business permissions | `business_permissions`, `business_role_permissions`, `business_member_permissions`, `has_business_permission`, `business_permissions_for` | `BusinessMembership.can`, `BusinessProfile.can` |
| Profile | `businesses` columns (professional details, visibility, response note), `business_update_profile`, `business_public_profile`, `business_setup_progress` | `/business/:id/workspace`, `/business/:id/edit`, `/businesses/:id` |
| Team | `business_team_invites`, invite/accept/revoke, role change, per-member permission override, removal | `/business/:id/team` |
| Catalog | `business_catalog_items` (status, gallery, variants, stock, external URL, counters) + `business_catalog_save/list/public/detail/set_status/delete/share/categories` | `/business/:id/catalog`, editor |
| Inquiries | `business_inquiries`, `business_customers`, `business_customer_labels`, `business_label_list/save/delete`, real `conversations` of kind `business`, message trigger | `/business/:id/inbox`, inquiry detail |
| Customers | customer list/detail/update, labels, follow-up status, internal notes (never exposed to customers) | `/business/:id/customers` |
| Analytics | `business_events`, `business_followers`, `business_analytics(days)` | `/business/:id/analytics` |
| Verification | `business_verification_state` reuses `verification_applications`, `verification_history`, `verification_documents` | `/business/:id/verification` |
| Partner program | `partner_profiles`, `partner_benefits`, `partner_resources`, `partner_support_requests`, `partner_activity`, directory + benefits RPCs, application lifecycle | `/partners/workspace`, `/partners/profile`, `/partners/resources`, `/partners/support`, `/partners/directory`, `/partners/application` |
| Storage | `business-media` (permission-aware), `partner-media` (public, own folder), `partner-documents` (private, 10 MB, images + PDF) | URLs saved through the normal update RPCs |
| Notifications | preference-aware `notify_user(... p_dedupe_key)` with a unique dedupe key | shown through the existing notification centre |

## Permission model

Business access is **scoped to each business** and independent of platform RBAC.

* Roles: `owner`, `admin`, `manager`, `support`, `operator`, `catalog`, `analyst`.
* 13 permission keys; `business.delete` is `owner_only` and can never be delegated.
* Per-member overrides (`business_member_permissions`) win over the role default, in both
  directions. An owner can withhold `inquiries.manage` from one support agent without
  changing the role.
* Every write goes through a `SECURITY DEFINER` RPC that checks the permission, the tenant
  and the caller's account status, then writes an audit row.
* The client's `permissions` array is only used to hide controls. RLS and the RPCs reject
  unauthorised calls even if the UI is bypassed.

Platform roles are untouched: business members never gain `has_permission('users.read')` or
any owner/admin capability. Partner status grants partner-scoped benefits only.

## Real data, no fabricated metrics

* `profile_view` and `catalog_view` are recorded by `business_record_event`, de-duplicated
  per actor/day, and increment the real `view_count`/`viewers` counters.
* `business_analytics` aggregates inventory, customers, followings, post engagement and
  response times from the actual tables. It returns
  `unavailable: [{metric, reason}]` for anything the platform does not collect — currently
  paid ad reach and checkout revenue. The UI lists those instead of inventing numbers.
* Response statistics are marked unavailable until at least one inquiry has been answered.
* Followers come from `business_followers` with a trigger-maintained counter.

## Partner lifecycle

`draft → pending → reviewing → additional_info_required → approved` with `rejected`,
`withdrawn`, `suspended`, `terminated` as terminal/administrative states. Approval is a
reviewer RPC (`review_partner_application`, gated by `partners.approve`/`partners.manage`)
that creates the partner profile, grants the trusted `partner` role server-side and records
the decision in `partner_application_events` + audit logs. Applicants can never set their
own status, category, featured placement or badge; `partner_profile_update` rejects those
keys.

Benefits (badge, directory listing, announcements, resources, support channel, featured
eligibility) are toggled by BubbleApp through `admin_set_partner_benefit`. Early access and
revenue sharing are explicitly reported as `not_implemented` by `partner_my_benefits()` and
in the UI.

## Security properties verified by tests

* Cross-tenant isolation: business B cannot read or mutate business A's profile, catalog,
  analytics, team, inquiries, customers or labels — including via direct table access.
* Removed members lose conversation access, catalog access and customer rows immediately.
* Customers cannot enumerate the customer list or read internal notes/labels.
* Pending/rejected applicants get no badge and no public partner profile; a hidden partner
  disappears from the directory and from `partner_public_profile`.
* `businesses` no longer grants `business_email`, `business_phone` or `address` to clients;
  private contact data is returned only to members or when visibility allows it.
* Directory partner rows are selectable only when `partner_status = 'active'` **and** the
  partner is listed or has the badge enabled.

## Bugs found and fixed while testing

1. `expire_stale_calls()` returned the row count of its last `UPDATE`, hiding expired calls
   from the scheduler.
2. `business_setup_progress()` concatenated text into a `text[]` with `||`, which PostgreSQL
   parsed as an array literal.
3. Inquiry creation notified the owner directly and again through the message trigger.
   Notifications are now produced only by the trigger, once per member per message.
4. A `business_inquiry_set_status` system message re-opened the inquiry through the message
   trigger. System events no longer change inquiry status.

## Configuration

The app needs only build-time dart-defines (never committed):

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon key>
```

Server-side secrets (Edge Functions) are documented in `supabase/README.md`. The new
buckets (`business-media`, `partner-media`, `partner-documents`) are created by migration
0016 together with their policies; no manual dashboard step is required.

## Verification status

* **SQL:** fresh database, migrations 0001–0016 + suites 02–09 → **509 assertions, 0
  failures** (`scripts/test_db.sh`).
* **Dart:** the Flutter/Dart SDK and pub.dev are unreachable from this environment, so
  `dart analyze`, `dart format` and `flutter test` were **not** executed. `app/test/business_partner_test.dart`
  covers the Part 8 models (permissions, visibility, catalog draft parameter mapping,
  analytics, inquiries, partner benefits/directory/application) and is ready to run wherever
  the SDK is available. `test/owner_admin_test.dart` was repaired to match the current
  `AccessSnapshot`/`OwnerStats` API.

## Not implemented (and why)

| Item | Status |
| --- | --- |
| Partner revenue share and payouts | No payment provider is configured; `partner_my_benefits` reports `not_implemented` |
| Partner early-access feature flags | No feature-flag service; reported as `not_implemented` |
| Paid advertising reach | No ads system; analytics marks the metric `unavailable` |
| Checkout revenue | No payment/checkout integration; analytics marks the metric `unavailable` |
| Business document uploads UI | The storage bucket and RPC exist; the Flutter picker flow is not wired in this part |
