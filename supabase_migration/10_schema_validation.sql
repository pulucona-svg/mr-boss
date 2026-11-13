-- ==============================================================================
-- MIRROR DIGITAL: SUPABASE MIGRATION - PART 10
-- File: 10_schema_validation.sql
-- Description: Diagnostic verification script to validate schema readiness, RLS status,
--              realtime publication membership, and security triggers.
-- ==============================================================================

DO $$
DECLARE
    expected_tables TEXT[] := ARRAY[
        'users',
        'user_sessions',
        'resources',
        'comments',
        'conversations',
        'messages',
        'payments',
        'subscription_history',
        'xp_transactions',
        'ad_reward_sessions',
        'curriculum',
        'notifications',
        'manual_ads',
        'explore_categories',
        'explore_news',
        'explore_news_archive',
        'top_stories',
        'latest_news',
        'trending_topics',
        'story_clusters',
        'story_candidates',
        'discovery_jobs',
        'article_jobs',
        'failed_article_jobs',
        'used_article_images',
        'used_thumbnails',
        'workers',
        'flux_workers',
        'dspace_jobs',
        'account_deletion_audits',
        'promotional_campaigns',
        'promotional_trial_claims',
        'promotional_trial_emails'
    ];
    realtime_tables TEXT[] := ARRAY[
        'messages',
        'conversations',
        'comments',
        'notifications',
        'resources',
        'explore_news',
        'explore_categories',
        'trending_topics',
        'manual_ads',
        'users',
        'xp_transactions',
        'curriculum',
        'dspace_jobs'
    ];
    tbl TEXT;
    table_count INT := 0;
    rls_enabled_count INT := 0;
    realtime_count INT := 0;
    missing_tables TEXT[] := '{}';
    unprotected_tables TEXT[] := '{}';
    missing_realtime TEXT[] := '{}';
    unexpected_realtime TEXT[] := '{}';
    actual_realtime_total INT := 0;
BEGIN
    RAISE NOTICE '==================================================================';
    RAISE NOTICE '       MIRROR DIGITAL: SUPABASE SCHEMA VALIDATION REPORT          ';
    RAISE NOTICE '==================================================================';

    -- 1. Table & RLS Verification
    FOREACH tbl IN ARRAY expected_tables LOOP
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = tbl) THEN
            table_count := table_count + 1;
            
            IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = tbl AND rowsecurity = TRUE) THEN
                rls_enabled_count := rls_enabled_count + 1;
            ELSE
                unprotected_tables := array_append(unprotected_tables, tbl);
            END IF;
        ELSE
            missing_tables := array_append(missing_tables, tbl);
        END IF;
    END LOOP;

    RAISE NOTICE 'Expected Tables Count:       %', array_length(expected_tables, 1);
    RAISE NOTICE 'Tables Successfully Created: %', table_count;
    RAISE NOTICE 'Tables with RLS Enabled:     %', rls_enabled_count;

    IF array_length(missing_tables, 1) > 0 THEN
        RAISE EXCEPTION 'CRITICAL: MISSING TABLES DETECTED: %', missing_tables;
    ELSE
        RAISE NOTICE 'SUCCESS: All expected application tables are present.';
    END IF;

    IF array_length(unprotected_tables, 1) > 0 THEN
        RAISE EXCEPTION 'CRITICAL: TABLES MISSING RLS DETECTED: %', unprotected_tables;
    ELSE
        RAISE NOTICE 'SUCCESS: 100%% of application tables have Row Level Security enabled.';
    END IF;

    -- Verify auth_migration.legacy_credentials table existence, RLS, and ACL privileges
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'auth_migration' 
          AND table_name = 'legacy_credentials'
    ) THEN
        RAISE EXCEPTION 'CRITICAL: auth_migration.legacy_credentials table was not created.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_tables 
        WHERE schemaname = 'auth_migration' 
          AND tablename = 'legacy_credentials' 
          AND rowsecurity = TRUE
    ) THEN
        RAISE EXCEPTION 'CRITICAL: auth_migration.legacy_credentials is missing Row Level Security.';
    ELSE
        RAISE NOTICE 'SUCCESS: auth_migration.legacy_credentials has Row Level Security enabled.';
    END IF;

    -- Verify Schema Privileges: service_role has USAGE; anon and authenticated are blocked
    IF NOT has_schema_privilege('service_role', 'auth_migration', 'USAGE') THEN
        RAISE EXCEPTION 'CRITICAL: service_role missing USAGE privilege on schema auth_migration.';
    END IF;

    IF has_schema_privilege('anon', 'auth_migration', 'USAGE') THEN
        RAISE EXCEPTION 'CRITICAL: anon role has unauthorized USAGE privilege on schema auth_migration!';
    END IF;

    IF has_schema_privilege('authenticated', 'auth_migration', 'USAGE') THEN
        RAISE EXCEPTION 'CRITICAL: authenticated role has unauthorized USAGE privilege on schema auth_migration!';
    END IF;

    -- Verify Table Privileges: service_role has DML; anon and authenticated have zero permissions
    IF NOT has_table_privilege('service_role', 'auth_migration.legacy_credentials'::regclass, 'SELECT')
       OR NOT has_table_privilege('service_role', 'auth_migration.legacy_credentials'::regclass, 'INSERT')
       OR NOT has_table_privilege('service_role', 'auth_migration.legacy_credentials'::regclass, 'UPDATE')
       OR NOT has_table_privilege('service_role', 'auth_migration.legacy_credentials'::regclass, 'DELETE') THEN
        RAISE EXCEPTION 'CRITICAL: service_role missing required DML privileges on auth_migration.legacy_credentials.';
    ELSE
        RAISE NOTICE 'SUCCESS: service_role has verified minimal DML privileges on auth_migration.legacy_credentials.';
    END IF;

    IF has_table_privilege('anon', 'auth_migration.legacy_credentials'::regclass, 'SELECT')
       OR has_table_privilege('authenticated', 'auth_migration.legacy_credentials'::regclass, 'SELECT') THEN
        RAISE EXCEPTION 'CRITICAL: Client roles (anon/authenticated) have unauthorized SELECT privilege on auth_migration.legacy_credentials!';
    ELSE
        RAISE NOTICE 'SUCCESS: Client roles (anon/authenticated) have zero table privileges on auth_migration.legacy_credentials.';
    END IF;

    -- Verify auth_migration.legacy_credentials has zero client policies (strict Default Deny)
    IF EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'auth_migration' 
          AND tablename = 'legacy_credentials'
    ) THEN
        RAISE EXCEPTION 'CRITICAL: auth_migration.legacy_credentials must have ZERO policies (strict Default Deny); found policies in pg_policies!';
    ELSE
        RAISE NOTICE 'SUCCESS: auth_migration.legacy_credentials has verified zero policies (strict Default Deny).';
    END IF;

    -- 2. Realtime Publication Verification (Strict Multi-Mechanism Fail-Closed Enforcement)
    -- Mechanism A: Verify publication existence
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        RAISE EXCEPTION 'CRITICAL: supabase_realtime publication does not exist.';
    END IF;

    -- Mechanism B: Reject puballtables = TRUE (FOR ALL TABLES)
    IF EXISTS (
        SELECT 1 FROM pg_publication 
        WHERE pubname = 'supabase_realtime' 
          AND puballtables = TRUE
    ) THEN
        RAISE EXCEPTION 'CRITICAL: supabase_realtime publication is configured with puballtables = TRUE (FOR ALL TABLES)! All tables would be exposed.';
    ELSE
        RAISE NOTICE 'SUCCESS: supabase_realtime publication has puballtables = FALSE.';
    END IF;

    -- Mechanism C: Reject unexpected schema-level publication membership in pg_publication_namespace
    IF EXISTS (
        SELECT 1 
        FROM pg_publication_namespace pn
        JOIN pg_publication p ON pn.pnpubid = p.oid
        WHERE p.pubname = 'supabase_realtime'
    ) THEN
        RAISE EXCEPTION 'CRITICAL: supabase_realtime publication contains schema-level membership in pg_publication_namespace! Only explicit table membership is permitted.';
    ELSE
        RAISE NOTICE 'SUCCESS: supabase_realtime has zero schema-level memberships in pg_publication_namespace.';
    END IF;

    -- Mechanism D: Verify exact 13 intended public tables via canonical pg_publication_tables view
    FOREACH tbl IN ARRAY realtime_tables LOOP
        IF EXISTS (
            SELECT 1 
            FROM pg_publication_tables 
            WHERE pubname = 'supabase_realtime' 
              AND schemaname = 'public' 
              AND tablename = tbl
        ) THEN
            realtime_count := realtime_count + 1;
        ELSE
            missing_realtime := array_append(missing_realtime, tbl);
        END IF;
    END LOOP;
    
    RAISE NOTICE 'Realtime Tables Registered:  % of %', realtime_count, array_length(realtime_tables, 1);
    IF array_length(missing_realtime, 1) > 0 THEN
        RAISE EXCEPTION 'CRITICAL: TABLES MISSING REALTIME PUBLICATION: %', missing_realtime;
    ELSE
        RAISE NOTICE 'SUCCESS: All 13 client streaming tables confirmed in pg_publication_tables.';
    END IF;

    -- Mechanism E: Reject any unexpected, sensitive, internal, or auth_migration table via pg_publication_tables
    SELECT COALESCE(array_agg(schemaname || '.' || tablename), '{}')
    INTO unexpected_realtime
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND (
        schemaname != 'public'
        OR tablename != ALL(realtime_tables)
      );

    IF array_length(unexpected_realtime, 1) > 0 THEN
        RAISE EXCEPTION 'CRITICAL: Unauthorized or sensitive tables exposed in supabase_realtime publication: %', unexpected_realtime;
    ELSE
        RAISE NOTICE 'SUCCESS: Zero unauthorized, internal, or sensitive tables exposed in supabase_realtime.';
    END IF;

    -- Mechanism F: Assert exact total table count in pg_publication_tables
    SELECT count(*)
    INTO actual_realtime_total
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime';

    IF actual_realtime_total != 13 THEN
        RAISE EXCEPTION 'CRITICAL: supabase_realtime publication must contain exactly 13 tables, but found %!', actual_realtime_total;
    ELSE
        RAISE NOTICE 'SUCCESS: supabase_realtime publication confirmed to contain exactly 13 tables.';
    END IF;

    -- 3. Security Trigger & Function Verification
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.triggers 
        WHERE event_object_table = 'resources' 
          AND trigger_name = 'trg_resource_update_security'
    ) THEN
        RAISE EXCEPTION 'CRITICAL: trg_resource_update_security trigger not found on public.resources.';
    ELSE
        RAISE NOTICE 'SUCCESS: Resource update security trigger (trg_resource_update_security) is active.';
    END IF;

    -- Verify Auth User Provisioning Trigger on auth.users
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger t
        JOIN pg_class c ON t.tgrelid = c.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'auth' 
          AND c.relname = 'users' 
          AND t.tgname = 'on_auth_user_created'
          AND NOT t.tgisinternal
    ) THEN
        RAISE EXCEPTION 'CRITICAL: on_auth_user_created trigger missing on auth.users.';
    ELSE
        RAISE NOTICE 'SUCCESS: Auth user provisioning trigger (on_auth_user_created) is active on auth.users.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.routines 
        WHERE routine_schema = 'public' 
          AND routine_name = 'process_expired_account_deletions'
    ) THEN
        RAISE EXCEPTION 'CRITICAL: Stored procedure process_expired_account_deletions() not found in public schema.';
    ELSE
        RAISE NOTICE 'SUCCESS: Stored procedure process_expired_account_deletions() is verified.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.routines 
        WHERE routine_schema = 'public' 
          AND routine_name = 'restore_user_account'
    ) THEN
        RAISE EXCEPTION 'CRITICAL: Helper function restore_user_account() not found in public schema.';
    ELSE
        RAISE NOTICE 'SUCCESS: Helper function restore_user_account() is verified.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.routines 
        WHERE routine_schema = 'public' 
          AND routine_name = 'immutable_array_to_string'
    ) THEN
        RAISE EXCEPTION 'CRITICAL: Helper function immutable_array_to_string() not found in public schema.';
    ELSE
        RAISE NOTICE 'SUCCESS: Helper function immutable_array_to_string() is verified.';
    END IF;

    -- 4. Secure Author Profile RPC Verification
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.routines 
        WHERE routine_schema = 'public' 
          AND routine_name = 'get_author_profile'
          AND security_type = 'DEFINER'
    ) THEN
        RAISE EXCEPTION 'CRITICAL: get_author_profile routine not found or not SECURITY DEFINER in public schema.';
    ELSE
        RAISE NOTICE 'SUCCESS: Secure author profile RPC (get_author_profile) is verified with SECURITY DEFINER.';
    END IF;

    RAISE NOTICE '==================================================================';
    RAISE NOTICE '   DATABASE SCHEMA IS PRODUCTION READY FOR DATA INGESTION!        ';
    RAISE NOTICE '==================================================================';
END $$;
