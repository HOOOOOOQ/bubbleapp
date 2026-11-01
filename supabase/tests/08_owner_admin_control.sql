-- 08_owner_admin_control: validates Part 7 migration (owner + admin control center)
\set ON_ERROR_STOP on
\pset tuples_only on

DO $$
DECLARE c int;
BEGIN
  -- 15 new granular permissions present
  SELECT count(*) INTO c FROM permissions WHERE key IN (
    'users.warn','users.restrict','users.sessions.revoke','community.manage',
    'channels.feature','community.feature','posts.feature','notifications.manage',
    'security.read','security.manage','audit.manage','platform.announce',
    'platform.content.manage','verification.manage','partners.manage.full'
  );
  IF c < 15 THEN RAISE EXCEPTION 'Missing Part 7 permissions: found % expected 15', c; END IF;
  RAISE NOTICE 'Part7 permissions OK %', c;

  SELECT count(*) INTO c FROM platform_settings WHERE setting_key IN (
    'registration_restrictions','email_verification_required','account_creation_limits',
    'allowed_attachment_sizes','supported_attachment_types','message_retention_days',
    'stories_enabled','channels_enabled','communities_enabled','discovery_enabled',
    'public_profiles_enabled','verification_enabled','verification_review_config',
    'partner_requirements','partner_benefits_config',
    'session_policy','login_restrictions','rate_limits','account_protection_enabled',
    'maintenance_mode','maintenance_announcement'
  );
  IF c < 20 THEN RAISE EXCEPTION 'Missing Part 7 platform_settings %', c; END IF;
  RAISE NOTICE 'Part7 settings OK %', c;

  SELECT count(*) INTO c FROM information_schema.tables WHERE table_name IN ('user_warnings','user_restrictions','session_revocations','announcements');
  IF c != 4 THEN RAISE EXCEPTION 'Missing Part7 tables %', c; END IF;

  -- These functions are permission-gated, so this suite asserts they exist with the
  -- expected signatures instead of executing them without an owner session.
  IF to_regprocedure('public.owner_dashboard_stats()') IS NULL THEN
    RAISE EXCEPTION 'Missing owner_dashboard_stats()';
  END IF;
  IF to_regprocedure('public.owner_dashboard_timeseries(integer)') IS NULL THEN
    RAISE EXCEPTION 'Missing owner_dashboard_timeseries(int)';
  END IF;
  IF to_regprocedure('public.owner_system_health()') IS NULL THEN
    RAISE EXCEPTION 'Missing owner_system_health()';
  END IF;
  IF to_regprocedure('public.security_overview()') IS NULL THEN
    RAISE EXCEPTION 'Missing security_overview()';
  END IF;
  IF to_regprocedure('public.admin_list_users(text, text, text, integer, integer)') IS NULL THEN
    RAISE EXCEPTION 'Missing enhanced admin_list_users with p_filter';
  END IF;
  RAISE NOTICE 'Part7 stats functions OK';
END $$;

SELECT 'ok' AS result;
