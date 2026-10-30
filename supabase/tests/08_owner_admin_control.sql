-- 08_owner_admin_control: validates Part 7 migration (owner + admin control center)
\set ON_ERROR_STOP on
\pset tuples_only on

DO $$
DECLARE c int;
BEGIN
  -- 15 new granular permissions present
  SELECT count(*) INTO c FROM permissions WHERE key IN (
    'users.warn','users.restrict','users.sessions_revoke','users.audit_read',
    'community.manage','channels.feature','reports.manage','reports.escalate',
    'announcements.manage','notifications.manage','security.read','security.manage',
    'settings.manage','audit.read','owner.manage'
  );
  IF c < 15 THEN RAISE EXCEPTION 'Missing Part 7 permissions: found % expected 15', c; END IF;
  RAISE NOTICE 'Part7 permissions OK %', c;

  SELECT count(*) INTO c FROM platform_settings WHERE setting_key IN (
    'registration_enabled','registration_require_email_otp','maintenance_mode','maintenance_announcement',
    'stories_enabled','channels_enabled','communities_enabled','discovery_enabled','allow_public_discovery',
    'verification_selfie_required','verification_review_sla_hours',
    'partner_min_followers','partner_review_sla_hours','premium_price_monthly',
    'max_message_length','allowed_message_types','message_edit_window_seconds','message_delete_window_seconds',
    'session_timeout_seconds','login_max_attempts','rate_limit_messages_per_minute','account_lockout_duration'
  );
  IF c < 20 THEN RAISE EXCEPTION 'Missing Part 7 platform_settings %', c; END IF;
  RAISE NOTICE 'Part7 settings OK %', c;

  SELECT count(*) INTO c FROM information_schema.tables WHERE table_name IN ('user_warnings','user_restrictions','session_revocations','announcements');
  IF c != 4 THEN RAISE EXCEPTION 'Missing Part7 tables %', c; END IF;

  PERFORM owner_dashboard_stats();
  PERFORM owner_dashboard_timeseries(7);
  PERFORM owner_system_health();
  PERFORM security_overview();
  RAISE NOTICE 'Part7 stats functions OK';
END $$;

SELECT 'ok' AS result;
