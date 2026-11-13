-- ==============================================================================
-- MIRROR DIGITAL: SUPABASE MIGRATION - PART 09
-- File: 09_maintenance_and_cron.sql
-- Description: Scheduled maintenance, trash retention, account deletion, and pg_cron config.
-- ==============================================================================

-- 1. Trashed Materials 30-Day Retention Purge Routine
CREATE OR REPLACE FUNCTION public.purge_trashed_materials()
RETURNS INT AS $$
DECLARE
    deleted_count INT := 0;
BEGIN
    DELETE FROM public.resources
    WHERE status = 'trashed'
      AND deleted_at IS NOT NULL
      AND deleted_at < (NOW() - INTERVAL '30 days');
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Privilege Hardening: Revoke client execution; grant strictly to backend executor (postgres, service_role)
REVOKE EXECUTE ON FUNCTION public.purge_trashed_materials() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.purge_trashed_materials() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_trashed_materials() TO postgres, service_role;

-- 2. Expired Account Deletion & Anonymization Processor
-- Strictly adheres to 30-day grace period, protects DSpace academic materials,
-- purges private chat messages/conversations and notifications, invalidates sessions,
-- anonymizes user contributions and user profile, and updates compliance audit logs.
CREATE OR REPLACE FUNCTION public.process_expired_account_deletions()
RETURNS INT AS $$
DECLARE
    rec RECORD;
    processed_count INT := 0;
BEGIN
    FOR rec IN 
        SELECT id, firebase_uid, email 
        FROM public.users
        WHERE deletion_status IN ('pending', 'pending_deletion')
          AND deletion_scheduled_at IS NOT NULL
          AND deletion_scheduled_at <= NOW()
    LOOP
        -- 1. PROTECT DSPACE ACADEMIC MATERIALS AND ANONYMIZE USER CONTRIBUTIONS
        -- University exam papers, past papers, and curriculum materials (is_imported_dspace = TRUE)
        -- MUST NEVER be deleted, altered, or unlinked.
        -- User-uploaded materials are preserved for the academic community under 'Anonymous Contributor'.
        UPDATE public.resources SET
            uploaded_by = 'Anonymous Contributor',
            uploader_id = NULL,
            uploader_firebase_uid = NULL,
            uploader_role = 'Contributor',
            is_anonymous = TRUE,
            updated_at = NOW()
        WHERE (uploader_id = rec.id OR (rec.firebase_uid IS NOT NULL AND uploader_firebase_uid = rec.firebase_uid))
          AND is_imported_dspace = FALSE;

        -- 2. ANONYMIZE USER COMMENTS
        -- Preserve public academic discussion threads while stripping personal identifiers
        UPDATE public.comments SET
            author_name = 'Anonymous User',
            author_profile_image = NULL,
            author_id = NULL,
            author_firebase_uid = NULL,
            updated_at = NOW()
        WHERE author_id = rec.id OR (rec.firebase_uid IS NOT NULL AND author_firebase_uid = rec.firebase_uid);

        -- 3. PURGE PRIVATE NOTIFICATIONS
        DELETE FROM public.notifications 
        WHERE target_user_id = rec.id OR (rec.firebase_uid IS NOT NULL AND target_firebase_uid = rec.firebase_uid);

        -- 4. PURGE PRIVATE SUPPORT CHAT MESSAGES & CONVERSATIONS
        -- Delete all personal messages where user was sender or conversation owner
        DELETE FROM public.messages 
        WHERE conversation_id = rec.id OR sender_id = rec.id 
           OR (rec.firebase_uid IS NOT NULL AND sender_firebase_uid = rec.firebase_uid);
           
        -- Delete conversation container
        DELETE FROM public.conversations WHERE id = rec.id;

        -- 5. INVALIDATE AND REMOVE DEVICE SESSIONS
        DELETE FROM public.user_sessions WHERE user_id = rec.id;

        -- 6. SCRUB AND ANONYMIZE USER PROFILE
        UPDATE public.users SET
            email = 'deleted_' || substr(rec.id::text, 1, 8) || '@deleted.local',
            username = 'deleted_' || substr(rec.id::text, 1, 8),
            display_name = 'Deleted User',
            phone = NULL,
            photo_url = NULL,
            institution = 'Anonymized',
            university_location = NULL,
            program = NULL,
            program_code = NULL,
            active_device_id = NULL,
            session_id = NULL,
            deletion_status = 'anonymized',
            is_anonymized = TRUE,
            anonymized_at = NOW(),
            disabled = TRUE,
            updated_at = NOW()
        WHERE id = rec.id;

        -- 7. UPDATE COMPLIANCE AUDIT RECORD
        UPDATE public.account_deletion_audits SET
            status = 'purged',
            updated_at = NOW()
        WHERE (user_id = rec.id OR (rec.firebase_uid IS NOT NULL AND uid = rec.firebase_uid))
          AND status = 'scheduled';

        processed_count := processed_count + 1;
    END LOOP;

    RETURN processed_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Privilege Hardening: Revoke client execution; grant strictly to backend executor (postgres, service_role)
REVOKE EXECUTE ON FUNCTION public.process_expired_account_deletions() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.process_expired_account_deletions() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_expired_account_deletions() TO postgres, service_role;

-- 3. Account Restoration Function (Allows user to cancel deletion during 30-day grace period)
-- Verifies caller ownership (auth.uid() = p_user_id), admin role, or trusted service_role execution.
CREATE OR REPLACE FUNCTION public.restore_user_account(p_user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_status VARCHAR(50);
    v_scheduled TIMESTAMPTZ;
    v_firebase_uid VARCHAR(64);
    caller_uid UUID;
    is_caller_admin BOOLEAN := FALSE;
BEGIN
    caller_uid := auth.uid();

    -- 1. Authorization Verification:
    -- Ordinary authenticated callers can ONLY restore their own personal account.
    -- Administrators and trusted backend processes (auth.uid() IS NULL) may restore on behalf of users.
    IF caller_uid IS NOT NULL THEN
        is_caller_admin := public.is_admin();
        IF caller_uid != p_user_id AND NOT is_caller_admin THEN
            RAISE EXCEPTION 'Permission denied: you can only restore your own account.';
        END IF;
    END IF;

    -- 2. Fetch target user state
    SELECT deletion_status, deletion_scheduled_at, firebase_uid
    INTO v_status, v_scheduled, v_firebase_uid
    FROM public.users
    WHERE id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User profile not found.';
    END IF;

    -- 3. Verify account is actually in pending deletion status
    IF v_status NOT IN ('pending', 'pending_deletion') THEN
        RAISE EXCEPTION 'Account is not pending deletion (current status: %).', v_status;
    END IF;

    -- 4. Verify 30-day grace period has not expired
    IF v_scheduled IS NOT NULL AND v_scheduled <= NOW() THEN
        RAISE EXCEPTION 'Grace period has expired. Account cannot be restored.';
    END IF;

    -- 5. Restore user profile
    UPDATE public.users SET
        deletion_status = 'active',
        deletion_requested_at = NULL,
        deletion_scheduled_at = NULL,
        deletion_reason = NULL,
        deletion_survey = NULL,
        restored_at = NOW(),
        updated_at = NOW()
    WHERE id = p_user_id;

    -- 6. Update compliance audit record
    UPDATE public.account_deletion_audits SET
        status = 'restored',
        restored_at = NOW(),
        updated_at = NOW()
    WHERE (user_id = p_user_id OR (v_firebase_uid IS NOT NULL AND uid = v_firebase_uid))
      AND status = 'scheduled';

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Privilege Hardening: Authenticated users and service_role can call restoration; anonymous cannot
REVOKE EXECUTE ON FUNCTION public.restore_user_account(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.restore_user_account(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.restore_user_account(UUID) TO authenticated, service_role;

-- 4. pg_cron Scheduled Tasks Configuration (Supabase Cloud)
-- NOTE: Requires pg_cron extension to be enabled in Supabase Dashboard (Database -> Extensions)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        -- ACTIVE SCHEDULE 1: Materials Trash 30-day retention purge (Daily at 03:00 UTC)
        PERFORM cron.schedule(
            'scheduled-materials-trash-retention',
            '0 3 * * *',
            'SELECT public.purge_trashed_materials();'
        );

        -- ACTIVE SCHEDULE 2: Expired Account Deletion Processor (Daily at 02:00 UTC)
        PERFORM cron.schedule(
            'scheduled-account-deletion-processor',
            '0 2 * * *',
            'SELECT public.process_expired_account_deletions();'
        );

        -- ==============================================================================
        -- MANDATORY PAUSE NOTICE:
        -- The four Explore news schedulers below are INTENTIONALLY PAUSED per project mandate.
        -- They must NOT be scheduled in production until explicitly authorized by the user:
        -- 1. scheduledExploreDiscovery
        -- 2. scheduledExploreQueueDrainer
        -- 3. scheduledWorkerHealthCheck
        -- 4. scheduledNewsCapacityCheck
        -- ==============================================================================
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron configuration skipped or extension not yet enabled.';
END $$;
