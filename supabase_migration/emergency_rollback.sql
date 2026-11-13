-- ==============================================================================
-- MIRROR DIGITAL: COMPLETE DATABASE ROLLBACK & TEARDOWN SCRIPT
-- Target Backend: Supabase Cloud PostgreSQL 15+
-- Purpose: Complete reversal of 00_full_migration_bundle.sql to a 100% pristine state.
-- Safety: Fully transactional (BEGIN ... COMMIT) and completely idempotent (IF EXISTS).
-- ==============================================================================

BEGIN;

-- 1. Unschedule Active Maintenance Cron Tasks (Fail-Safe Verification)
DO $$
BEGIN
    -- If pg_cron extension is absent, exit safely without error
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        RAISE NOTICE 'pg_cron extension not installed; skipping cron unschedule.';
        RETURN;
    END IF;

    -- If pg_cron exists and named jobs exist, unschedule them.
    -- Unhandled exceptions will abort the rollback transaction, preventing function drops.
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'scheduled-materials-trash-retention') THEN
        PERFORM cron.unschedule('scheduled-materials-trash-retention');
    END IF;

    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'scheduled-account-deletion-processor') THEN
        PERFORM cron.unschedule('scheduled-account-deletion-processor');
    END IF;

    -- Strict Assertion: Confirm that no scheduled maintenance jobs remain active
    IF EXISTS (
        SELECT 1 FROM cron.job 
        WHERE jobname IN ('scheduled-materials-trash-retention', 'scheduled-account-deletion-processor')
    ) THEN
        RAISE EXCEPTION 'CRITICAL: Rollback halted. One or more maintenance cron jobs could not be unscheduled.';
    END IF;
END $$;

-- 2. Drop Auth Trigger on auth.users (Must be dropped explicitly; not dropped by public table cascades)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- 3. Drop All 33 Public Application Tables in Reverse Dependency Order
-- Note: Dropping tables with CASCADE automatically drops all 41 indexes,
-- all 45 RLS policies, all 13 table-level triggers, and publication memberships.
DROP TABLE IF EXISTS public.promotional_trial_emails CASCADE;
DROP TABLE IF EXISTS public.promotional_trial_claims CASCADE;
DROP TABLE IF EXISTS public.promotional_campaigns CASCADE;
DROP TABLE IF EXISTS public.account_deletion_audits CASCADE;
DROP TABLE IF EXISTS public.dspace_jobs CASCADE;
DROP TABLE IF EXISTS public.flux_workers CASCADE;
DROP TABLE IF EXISTS public.workers CASCADE;
DROP TABLE IF EXISTS public.used_thumbnails CASCADE;
DROP TABLE IF EXISTS public.used_article_images CASCADE;
DROP TABLE IF EXISTS public.failed_article_jobs CASCADE;
DROP TABLE IF EXISTS public.article_jobs CASCADE;
DROP TABLE IF EXISTS public.discovery_jobs CASCADE;
DROP TABLE IF EXISTS public.story_candidates CASCADE;
DROP TABLE IF EXISTS public.trending_topics CASCADE;
DROP TABLE IF EXISTS public.latest_news CASCADE;
DROP TABLE IF EXISTS public.top_stories CASCADE;
DROP TABLE IF EXISTS public.explore_news_archive CASCADE;
DROP TABLE IF EXISTS public.explore_news CASCADE;
DROP TABLE IF EXISTS public.story_clusters CASCADE;
DROP TABLE IF EXISTS public.explore_categories CASCADE;
DROP TABLE IF EXISTS public.manual_ads CASCADE;
DROP TABLE IF EXISTS public.notifications CASCADE;
DROP TABLE IF EXISTS public.messages CASCADE;
DROP TABLE IF EXISTS public.conversations CASCADE;
DROP TABLE IF EXISTS public.ad_reward_sessions CASCADE;
DROP TABLE IF EXISTS public.xp_transactions CASCADE;
DROP TABLE IF EXISTS public.subscription_history CASCADE;
DROP TABLE IF EXISTS public.payments CASCADE;
DROP TABLE IF EXISTS public.comments CASCADE;
DROP TABLE IF EXISTS public.resources CASCADE;
DROP TABLE IF EXISTS public.curriculum CASCADE;
DROP TABLE IF EXISTS public.user_sessions CASCADE;
DROP TABLE IF EXISTS public.users CASCADE;

-- 4. Drop Custom Migration Schema (Legacy Scrypt Passwords)
DROP SCHEMA IF EXISTS auth_migration CASCADE;

-- 5. Drop All 13 Custom Stored Functions in Public Schema
DROP FUNCTION IF EXISTS public.restore_user_account(UUID) CASCADE;
DROP FUNCTION IF EXISTS public.process_expired_account_deletions() CASCADE;
DROP FUNCTION IF EXISTS public.purge_trashed_materials() CASCADE;
DROP FUNCTION IF EXISTS public.handle_new_chat_message() CASCADE;
DROP FUNCTION IF EXISTS public.fulfill_paystack_subscription(VARCHAR, BIGINT, VARCHAR) CASCADE;
DROP FUNCTION IF EXISTS public.enforce_resource_update_security() CASCADE;
DROP FUNCTION IF EXISTS public.update_resource_comment_count() CASCADE;
DROP FUNCTION IF EXISTS public.get_author_profile(UUID) CASCADE;
DROP FUNCTION IF EXISTS public.handle_new_auth_user() CASCADE;
DROP FUNCTION IF EXISTS public.is_admin() CASCADE;
DROP FUNCTION IF EXISTS public.is_authenticated() CASCADE;
DROP FUNCTION IF EXISTS public.immutable_array_to_string(TEXT[], TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.handle_updated_at() CASCADE;

COMMIT;
