-- ==============================================================================
-- MIRROR DIGITAL: SUPABASE MIGRATION - PART 02
-- File: 02_core_users_and_auth.sql
-- Description: Core users table, session management, and auth bridge.
-- ==============================================================================

-- 1. Main Public Users Table (Extends Supabase auth.users)
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    firebase_uid VARCHAR(64) UNIQUE,
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(100),
    display_name VARCHAR(150),
    phone VARCHAR(50),
    photo_url TEXT,
    institution VARCHAR(150) DEFAULT 'Laikipia University',
    university_location VARCHAR(100),
    program VARCHAR(150),
    program_code VARCHAR(50),
    year VARCHAR(20),
    semester VARCHAR(20),
    role VARCHAR(20) DEFAULT 'student' CHECK (role IN ('student', 'lecturer', 'admin', 'moderator')),
    is_virtual_uploader BOOLEAN DEFAULT FALSE,
    onboarding_complete BOOLEAN DEFAULT FALSE,
    email_verified BOOLEAN DEFAULT FALSE,
    active_device_id VARCHAR(100),
    session_id VARCHAR(100),
    
    -- Subscriptions & Wallet
    is_subscribed BOOLEAN DEFAULT FALSE,
    subscription_plan VARCHAR(50),
    subscription_expiry TIMESTAMPTZ,
    xp_balance INT DEFAULT 0 CHECK (xp_balance >= 0),
    ad_reward_count_video_today INT DEFAULT 0,
    ad_reward_count_interstitial_today INT DEFAULT 0,
    ad_reward_date_nairobi DATE,
    last_ad_reward_at TIMESTAMPTZ,
    
    -- Terms & Compliance
    terms_version_accepted VARCHAR(20),
    terms_accepted_at TIMESTAMPTZ,
    privacy_policy_version_accepted VARCHAR(20),
    privacy_policy_accepted_at TIMESTAMPTZ,
    
    -- Account Lifecycle
    deletion_status VARCHAR(50) DEFAULT 'active' CHECK (deletion_status IN ('active', 'pending', 'pending_deletion', 'deleted', 'anonymized')),
    deletion_requested_at TIMESTAMPTZ,
    deletion_scheduled_at TIMESTAMPTZ,
    deletion_reason TEXT,
    deletion_survey JSONB,
    restored_at TIMESTAMPTZ,
    is_anonymized BOOLEAN DEFAULT FALSE,
    anonymized_at TIMESTAMPTZ,
    disabled BOOLEAN DEFAULT FALSE,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_login TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for Fast Lookups
CREATE INDEX IF NOT EXISTS idx_users_firebase_uid ON public.users(firebase_uid);
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
CREATE INDEX IF NOT EXISTS idx_users_role ON public.users(role);
CREATE INDEX IF NOT EXISTS idx_users_deletion_status ON public.users(deletion_status, deletion_scheduled_at);
CREATE INDEX IF NOT EXISTS idx_users_subscription ON public.users(is_subscribed, subscription_expiry);

-- Auto-update updated_at timestamp
CREATE OR REPLACE TRIGGER trg_users_updated_at
BEFORE UPDATE ON public.users
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 2. User Multi-device Sessions Table
CREATE TABLE IF NOT EXISTS public.user_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    session_id VARCHAR(100) NOT NULL,
    device_id VARCHAR(100) NOT NULL,
    platform VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,
    last_active TIMESTAMPTZ DEFAULT NOW(),
    last_login TIMESTAMPTZ DEFAULT NOW(),
    invalidated_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_sessions_lookup ON public.user_sessions(user_id, session_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_device ON public.user_sessions(device_id);

-- 3. Automatic Profile Creation Trigger on Supabase Auth Signup
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.users (
        id,
        email,
        display_name,
        photo_url,
        email_verified,
        created_at,
        updated_at
    ) VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
        NEW.raw_user_meta_data->>'avatar_url',
        COALESCE(NEW.email_confirmed_at IS NOT NULL, FALSE),
        NOW(),
        NOW()
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Connect trigger to auth.users (runs automatically when a new user signs up)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();

-- 4. Secure Legacy Authentication Migration Table (Restricted schema)
-- Stores Firebase Scrypt password hashes for lazy verification on first login
CREATE TABLE IF NOT EXISTS auth_migration.legacy_credentials (
    user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    firebase_uid VARCHAR(64) NOT NULL,
    password_hash_base64 TEXT NOT NULL,
    salt_base64 TEXT NOT NULL,
    migrated_to_bcrypt BOOLEAN DEFAULT FALSE,
    migrated_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable Row Level Security (Enforces strict default-deny for all non-privileged roles)
ALTER TABLE auth_migration.legacy_credentials ENABLE ROW LEVEL SECURITY;

-- Privilege Hardening: Strip all permissions from client roles; grant minimal DML strictly to service_role
REVOKE ALL ON TABLE auth_migration.legacy_credentials FROM PUBLIC;
REVOKE ALL ON TABLE auth_migration.legacy_credentials FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE auth_migration.legacy_credentials TO service_role;

-- 5. Secure Single-Author Attribution Profile RPC
-- Replaces bulk enumerable views with a strictly parameterized, content-linked lookup.
-- Returns ONLY explicitly approved non-sensitive public identity fields (username, display_name, photo, institution, program).
-- Requires caller authentication; enforces legitimate visibility (author of active, approved, public, non-anonymous resource or active comment, self, or admin).
-- Excludes anonymized and permanently deleted accounts.
CREATE OR REPLACE FUNCTION public.get_author_profile(p_user_id UUID)
RETURNS TABLE (
    id UUID,
    username VARCHAR(100),
    display_name VARCHAR(150),
    photo_url TEXT,
    institution VARCHAR(150),
    program VARCHAR(150)
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    caller_uid UUID;
    is_caller_admin BOOLEAN := FALSE;
    is_visible BOOLEAN := FALSE;
BEGIN
    caller_uid := auth.uid();

    -- 1. Authentication Check: Reject unauthenticated execution
    IF caller_uid IS NULL THEN
        IF current_user != 'service_role' AND current_user != 'postgres' THEN
            RAISE EXCEPTION 'Authentication required.';
        END IF;
    END IF;

    -- 2. Caller Identity Verification:
    -- A user can always view their own profile attribution card
    IF caller_uid IS NOT NULL AND caller_uid = p_user_id THEN
        is_visible := TRUE;
    END IF;

    -- Administrators can view profile attribution
    IF NOT is_visible AND caller_uid IS NOT NULL THEN
        is_caller_admin := public.is_admin();
        IF is_caller_admin THEN
            is_visible := TRUE;
        END IF;
    END IF;

    -- Trusted backend processes (service_role / postgres):
    IF caller_uid IS NULL THEN
        is_visible := TRUE;
    END IF;

    -- 3. Content-Linked Legitimate Visibility Check:
    -- Profile is visible if target user is an uploader of an active, approved, public, non-anonymous resource
    -- OR an author of an active unmoderated comment on an active, approved, public resource.
    IF NOT is_visible THEN
        IF EXISTS (
            SELECT 1 FROM public.resources r
            WHERE r.uploader_id = p_user_id
              AND r.status = 'active'
              AND r.approved_by_admin = TRUE
              AND r.visibility = 'public'
              AND r.is_anonymous = FALSE
        ) OR EXISTS (
            SELECT 1 FROM public.comments c
            JOIN public.resources r ON c.resource_id = r.id
            WHERE c.author_id = p_user_id
              AND c.is_moderated = FALSE
              AND r.status = 'active'
              AND r.approved_by_admin = TRUE
              AND r.visibility = 'public'
        ) THEN
            is_visible := TRUE;
        END IF;
    END IF;

    -- If not legitimately visible, return empty set (prevents directory enumeration)
    IF NOT is_visible THEN
        RETURN;
    END IF;

    -- 4. Return strictly approved non-sensitive public identity fields
    -- Excludes anonymized, permanently deleted, or disabled accounts
    RETURN QUERY
    SELECT 
        u.id,
        u.username,
        u.display_name,
        u.photo_url,
        u.institution,
        u.program
    FROM public.users u
    WHERE u.id = p_user_id
      AND u.deletion_status NOT IN ('deleted', 'anonymized')
      AND u.is_anonymized = FALSE
      AND u.disabled = FALSE;
END;
$$;

-- Privilege Hardening: Revoke from PUBLIC and anon; grant strictly to authenticated and service_role
REVOKE EXECUTE ON FUNCTION public.get_author_profile(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_author_profile(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_author_profile(UUID) TO authenticated, service_role;
