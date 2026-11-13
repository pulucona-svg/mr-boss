-- ==============================================================================
-- MIRROR DIGITAL: COMPLETE SUPABASE MIGRATION BUNDLE (ALL-IN-ONE)
-- Generated: 2026-11-12T21:29:13.191Z
-- Target Backend: Supabase Cloud PostgreSQL 15+
-- Execution Mode: ATOMIC TRANSACTION (All-or-Nothing via BEGIN ... COMMIT)
-- ==============================================================================

BEGIN;


-- >>> FILE: 01_extensions_and_helpers.sql <<<

-- ==============================================================================
-- MIRROR DIGITAL: SUPABASE MIGRATION - PART 01
-- File: 01_extensions_and_helpers.sql
-- Description: Core extensions, helper functions, and shared trigger utilities.
-- ==============================================================================

-- 1. Essential PostgreSQL Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "btree_gin";

-- 2. Schema Namespaces
CREATE SCHEMA IF NOT EXISTS auth_migration;

-- Schema Security Hardening: Revoke client access; grant strictly USAGE to service_role
REVOKE ALL ON SCHEMA auth_migration FROM PUBLIC;
REVOKE ALL ON SCHEMA auth_migration FROM anon, authenticated;
GRANT USAGE ON SCHEMA auth_migration TO service_role;

-- 3. Common Trigger Function: Update 'updated_at' column automatically
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. Security & Role Helper Functions for RLS Policies
-- Checks if current caller is authenticated via Supabase JWT
CREATE OR REPLACE FUNCTION public.is_authenticated()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN auth.uid() IS NOT NULL;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp;

-- Checks if caller is an authorized administrator
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
DECLARE
    caller_uid UUID;
    caller_email TEXT;
    is_admin_user BOOLEAN := FALSE;
BEGIN
    caller_uid := auth.uid();
    IF caller_uid IS NULL THEN
        RETURN FALSE;
    END IF;

    -- 1. Check custom claim from JWT if available
    IF (auth.jwt()->>'role' = 'admin') OR (auth.jwt()->'app_metadata'->>'admin' = 'true') THEN
        RETURN TRUE;
    END IF;

    -- 2. Query public.users for explicit admin role or known authoritative emails
    SELECT (role = 'admin' OR email IN (
        'pulucona@mail.com',
        'pulucona@gmail.com',
        'culucona@gmail.com',
        'admin@mirrorlaikipia.ac.ke',
        'admin@mirror.com',
        'testadmin@mirror.com'
    )) INTO is_admin_user
    FROM public.users
    WHERE id = caller_uid;

    RETURN COALESCE(is_admin_user, FALSE);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp;

-- 5. Full-Text Search Array Flattener Helper
-- Converts TEXT[] arrays to string with IMMUTABLE volatility for expression indexes.
-- Built-in array_to_string is STABLE in pg_proc; this wrapper strictly operates on text[]
-- ensuring deterministic, locale-independent output acceptable in index expressions.
CREATE OR REPLACE FUNCTION public.immutable_array_to_string(arr TEXT[], sep TEXT DEFAULT ' ')
RETURNS TEXT AS $$
BEGIN
    RETURN COALESCE(array_to_string(arr, sep), '');
END;
$$ LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION public.immutable_array_to_string(TEXT[], TEXT) TO authenticated, anon, service_role;


-- >>> FILE: 02_core_users_and_auth.sql <<<

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


-- >>> FILE: 03_academic_resources_and_curriculum.sql <<<

-- ==============================================================================
-- MIRROR DIGITAL: SUPABASE MIGRATION - PART 03
-- File: 03_academic_resources_and_curriculum.sql
-- Description: Curriculum catalog, academic documents, and material comments.
-- ==============================================================================

-- 1. Curriculum Catalog Table (Programs, Units, Lecturers)
CREATE TABLE IF NOT EXISTS public.curriculum (
    id VARCHAR(64) PRIMARY KEY,
    program_name VARCHAR(150) NOT NULL,
    program_code VARCHAR(50) NOT NULL,
    unit_name VARCHAR(255) NOT NULL,
    unit_code VARCHAR(50) NOT NULL,
    lecturer_name VARCHAR(150),
    year_of_study VARCHAR(20),
    semester VARCHAR(20),
    is_active BOOLEAN DEFAULT TRUE,
    updated_by VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_curriculum_lookup ON public.curriculum(program_code, unit_code);
CREATE INDEX IF NOT EXISTS idx_curriculum_active ON public.curriculum(is_active);

CREATE OR REPLACE TRIGGER trg_curriculum_updated_at
BEFORE UPDATE ON public.curriculum
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 2. Academic Resources & Materials Catalog Table
CREATE TABLE IF NOT EXISTS public.resources (
    id VARCHAR(64) PRIMARY KEY, -- Preserves Firestore ID (e.g. HTKdYhSTiPPhijBubEBF)
    title VARCHAR(255) NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    type VARCHAR(50),
    material_type VARCHAR(50),
    material_format VARCHAR(50),
    file_url TEXT NOT NULL,
    file_id VARCHAR(100) NOT NULL, -- ImageKit fileId
    unit_name VARCHAR(255),
    unit_code VARCHAR(50),
    year VARCHAR(50),
    upload_year VARCHAR(20),
    publication_year VARCHAR(20),
    year_of_study VARCHAR(20),
    semester VARCHAR(20),
    cat_type VARCHAR(50),
    lecturers TEXT[] DEFAULT '{}',
    uploaded_by VARCHAR(150),
    uploader_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    uploader_firebase_uid VARCHAR(64),
    uploader_role VARCHAR(50),
    target_programs TEXT[] DEFAULT '{}',
    program_codes TEXT[] DEFAULT '{}',
    visibility VARCHAR(50) DEFAULT 'public' CHECK (visibility IN ('public', 'unlisted', 'private')),
    status VARCHAR(50) DEFAULT 'active' CHECK (status IN ('active', 'trashed', 'archived', 'pending_approval', 'rejected')),
    is_anonymous BOOLEAN DEFAULT FALSE,
    is_pinned BOOLEAN DEFAULT FALSE,
    pinned_at TIMESTAMPTZ,
    approved_by_admin BOOLEAN DEFAULT TRUE,
    rejected_by_admin BOOLEAN DEFAULT FALSE,
    updated_by_admin BOOLEAN DEFAULT FALSE,
    decline_reason TEXT,
    decline_date TIMESTAMPTZ,
    
    -- DSpace Examination Repository Tracking
    is_imported_dspace BOOLEAN DEFAULT FALSE,
    dspace_item_uuid VARCHAR(100),
    dspace_handle VARCHAR(100),
    
    -- Engagement & Metrics
    views_count INT DEFAULT 0 CHECK (views_count >= 0),
    likes_count INT DEFAULT 0 CHECK (likes_count >= 0),
    comments_count INT DEFAULT 0 CHECK (comments_count >= 0),
    liked_by UUID[] DEFAULT '{}',
    
    -- Thumbnail & AI Generation
    thumbnail_id VARCHAR(100),
    thumbnail_url TEXT,
    thumbnail_status VARCHAR(50) DEFAULT 'none',
    thumbnail_generation JSONB DEFAULT '{}'::jsonb,
    
    upload_date TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    archived_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Full-Text Search GIN Index across Title, Unit Name, Unit Code, and Lecturers
CREATE INDEX IF NOT EXISTS idx_resources_fts ON public.resources 
USING gin(to_tsvector('english'::regconfig, title || ' ' || COALESCE(unit_name, '') || ' ' || COALESCE(unit_code, '') || ' ' || public.immutable_array_to_string(lecturers, ' ')));

-- Composite Indexes for High-Frequency Queries
CREATE INDEX IF NOT EXISTS idx_resources_status_upload ON public.resources(status, upload_date DESC);
CREATE INDEX IF NOT EXISTS idx_resources_uploader ON public.resources(uploader_id);
CREATE INDEX IF NOT EXISTS idx_resources_unit_code ON public.resources(unit_code);
CREATE INDEX IF NOT EXISTS idx_resources_pinned ON public.resources(is_pinned, pinned_at DESC);
CREATE INDEX IF NOT EXISTS idx_resources_thumbnail_retry ON public.resources((thumbnail_generation->>'isRetryable'), thumbnail_status, (thumbnail_generation->>'nextRetryAt'));

CREATE OR REPLACE TRIGGER trg_resources_updated_at
BEFORE UPDATE ON public.resources
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 3. Comments & Nested Reactions Table
CREATE TABLE IF NOT EXISTS public.comments (
    id VARCHAR(64) PRIMARY KEY,
    resource_id VARCHAR(64) NOT NULL REFERENCES public.resources(id) ON DELETE CASCADE,
    author_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    author_firebase_uid VARCHAR(64),
    author_name VARCHAR(150),
    author_profile_image TEXT,
    parent_id VARCHAR(64) REFERENCES public.comments(id) ON DELETE CASCADE,
    text TEXT NOT NULL,
    likes_count INT DEFAULT 0 CHECK (likes_count >= 0),
    liked_by UUID[] DEFAULT '{}',
    reactions JSONB DEFAULT '{}'::jsonb,
    is_moderated BOOLEAN DEFAULT FALSE,
    moderated_at TIMESTAMPTZ,
    moderated_by UUID REFERENCES public.users(id),
    moderation_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_comments_resource_created ON public.comments(resource_id, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_comments_parent ON public.comments(parent_id);
CREATE INDEX IF NOT EXISTS idx_comments_author ON public.comments(author_id);

CREATE OR REPLACE TRIGGER trg_comments_updated_at
BEFORE UPDATE ON public.comments
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 4. Automatic Comments Counter Trigger on Resources
CREATE OR REPLACE FUNCTION public.update_resource_comment_count()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        UPDATE public.resources SET comments_count = comments_count + 1 WHERE id = NEW.resource_id;
    ELSIF (TG_OP = 'DELETE') THEN
        UPDATE public.resources SET comments_count = GREATEST(0, comments_count - 1) WHERE id = OLD.resource_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_comments_counter ON public.comments;
CREATE TRIGGER trg_comments_counter
AFTER INSERT OR DELETE ON public.comments
FOR EACH ROW EXECUTE FUNCTION public.update_resource_comment_count();

-- 5. Resource Update Security & Field Immutability Trigger
CREATE OR REPLACE FUNCTION public.enforce_resource_update_security()
RETURNS TRIGGER AS $$
DECLARE
    caller_id UUID;
    is_caller_admin BOOLEAN;
BEGIN
    caller_id := auth.uid();

    -- Service role / background processes without JWT session are permitted
    IF caller_id IS NULL THEN
        RETURN NEW;
    END IF;

    is_caller_admin := public.is_admin();

    -- System administrators have full update authority across all fields
    IF is_caller_admin THEN
        RETURN NEW;
    END IF;

    -- CASE 1: Non-uploader (Community Member)
    -- Non-uploaders are ONLY permitted to update engagement counters:
    -- views_count, likes_count, liked_by, comments_count, and updated_at.
    IF OLD.uploader_id IS NULL OR caller_id != OLD.uploader_id THEN
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.title IS DISTINCT FROM OLD.title
           OR NEW.file_name IS DISTINCT FROM OLD.file_name
           OR NEW.type IS DISTINCT FROM OLD.type
           OR NEW.material_type IS DISTINCT FROM OLD.material_type
           OR NEW.material_format IS DISTINCT FROM OLD.material_format
           OR NEW.file_url IS DISTINCT FROM OLD.file_url
           OR NEW.file_id IS DISTINCT FROM OLD.file_id
           OR NEW.unit_name IS DISTINCT FROM OLD.unit_name
           OR NEW.unit_code IS DISTINCT FROM OLD.unit_code
           OR NEW.year IS DISTINCT FROM OLD.year
           OR NEW.upload_year IS DISTINCT FROM OLD.upload_year
           OR NEW.publication_year IS DISTINCT FROM OLD.publication_year
           OR NEW.year_of_study IS DISTINCT FROM OLD.year_of_study
           OR NEW.semester IS DISTINCT FROM OLD.semester
           OR NEW.cat_type IS DISTINCT FROM OLD.cat_type
           OR NEW.lecturers IS DISTINCT FROM OLD.lecturers
           OR NEW.uploaded_by IS DISTINCT FROM OLD.uploaded_by
           OR NEW.uploader_id IS DISTINCT FROM OLD.uploader_id
           OR NEW.uploader_firebase_uid IS DISTINCT FROM OLD.uploader_firebase_uid
           OR NEW.uploader_role IS DISTINCT FROM OLD.uploader_role
           OR NEW.target_programs IS DISTINCT FROM OLD.target_programs
           OR NEW.program_codes IS DISTINCT FROM OLD.program_codes
           OR NEW.visibility IS DISTINCT FROM OLD.visibility
           OR NEW.status IS DISTINCT FROM OLD.status
           OR NEW.is_anonymous IS DISTINCT FROM OLD.is_anonymous
           OR NEW.is_pinned IS DISTINCT FROM OLD.is_pinned
           OR NEW.pinned_at IS DISTINCT FROM OLD.pinned_at
           OR NEW.approved_by_admin IS DISTINCT FROM OLD.approved_by_admin
           OR NEW.rejected_by_admin IS DISTINCT FROM OLD.rejected_by_admin
           OR NEW.updated_by_admin IS DISTINCT FROM OLD.updated_by_admin
           OR NEW.decline_reason IS DISTINCT FROM OLD.decline_reason
           OR NEW.decline_date IS DISTINCT FROM OLD.decline_date
           OR NEW.is_imported_dspace IS DISTINCT FROM OLD.is_imported_dspace
           OR NEW.dspace_item_uuid IS DISTINCT FROM OLD.dspace_item_uuid
           OR NEW.dspace_handle IS DISTINCT FROM OLD.dspace_handle
           OR NEW.thumbnail_id IS DISTINCT FROM OLD.thumbnail_id
           OR NEW.thumbnail_url IS DISTINCT FROM OLD.thumbnail_url
           OR NEW.thumbnail_status IS DISTINCT FROM OLD.thumbnail_status
           OR NEW.thumbnail_generation IS DISTINCT FROM OLD.thumbnail_generation
           OR NEW.upload_date IS DISTINCT FROM OLD.upload_date
           OR NEW.deleted_at IS DISTINCT FROM OLD.deleted_at
           OR NEW.archived_at IS DISTINCT FROM OLD.archived_at
           OR NEW.created_at IS DISTINCT FROM OLD.created_at
        THEN
            RAISE EXCEPTION 'Permission denied: non-uploaders can only update engagement counters (views, likes, comments).';
        END IF;

        RETURN NEW;
    END IF;

    -- CASE 2: Original Uploader (Non-admin)
    -- Uploaders can update their own content metadata (title, unit, lecturers, etc.)
    -- but CANNOT modify administrative approval flags, pinned status, or DSpace identifiers.
    IF caller_id = OLD.uploader_id THEN
        IF NEW.approved_by_admin IS DISTINCT FROM OLD.approved_by_admin
           OR NEW.rejected_by_admin IS DISTINCT FROM OLD.rejected_by_admin
           OR NEW.updated_by_admin IS DISTINCT FROM OLD.updated_by_admin
           OR NEW.decline_reason IS DISTINCT FROM OLD.decline_reason
           OR NEW.decline_date IS DISTINCT FROM OLD.decline_date
           OR NEW.is_pinned IS DISTINCT FROM OLD.is_pinned
           OR NEW.pinned_at IS DISTINCT FROM OLD.pinned_at
           OR NEW.is_imported_dspace IS DISTINCT FROM OLD.is_imported_dspace
           OR NEW.dspace_item_uuid IS DISTINCT FROM OLD.dspace_item_uuid
           OR NEW.dspace_handle IS DISTINCT FROM OLD.dspace_handle
           OR NEW.uploader_id IS DISTINCT FROM OLD.uploader_id
        THEN
            RAISE EXCEPTION 'Permission denied: uploaders cannot modify administrative flags, pinned state, or DSpace metadata.';
        END IF;

        RETURN NEW;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS trg_resource_update_security ON public.resources;
CREATE TRIGGER trg_resource_update_security
BEFORE UPDATE ON public.resources
FOR EACH ROW EXECUTE FUNCTION public.enforce_resource_update_security();


-- >>> FILE: 04_payments_subscriptions_and_xp.sql <<<

-- ==============================================================================
-- MIRROR DIGITAL: SUPABASE MIGRATION - PART 04
-- File: 04_payments_subscriptions_and_xp.sql
-- Description: Paystack payments, subscription history, XP ledger, and ad reward sessions.
-- ==============================================================================

-- 1. Paystack Payments Log Table
CREATE TABLE IF NOT EXISTS public.payments (
    reference VARCHAR(100) PRIMARY KEY, -- Paystack transaction reference (PAY_...)
    user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    user_firebase_uid VARCHAR(64),
    user_email VARCHAR(255),
    phone_number VARCHAR(50),
    package_id VARCHAR(50) NOT NULL,
    package_name VARCHAR(100) NOT NULL,
    expected_amount_kes NUMERIC(10, 2) NOT NULL,
    expected_amount_subunits INT NOT NULL,
    currency VARCHAR(10) DEFAULT 'KES',
    duration_days INT,
    payment_method VARCHAR(50),
    paystack_transaction_id BIGINT,
    paystack_status VARCHAR(50),
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'success', 'failed')),
    fulfilled BOOLEAN DEFAULT FALSE,
    fulfilled_at TIMESTAMPTZ,
    fulfillment_source VARCHAR(50),
    subscription_id VARCHAR(100),
    error_message TEXT,
    failure_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payments_user ON public.payments(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_status_fulfilled ON public.payments(status, fulfilled);

CREATE OR REPLACE TRIGGER trg_payments_updated_at
BEFORE UPDATE ON public.payments
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 2. User Subscription Validity & History Table
CREATE TABLE IF NOT EXISTS public.subscription_history (
    id VARCHAR(100) PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    user_firebase_uid VARCHAR(64),
    package_title VARCHAR(100),
    amount NUMERIC(10, 2),
    transaction_code VARCHAR(100),
    payment_channel VARCHAR(50),
    operator_receipt_number VARCHAR(100),
    paystack_reference VARCHAR(100),
    paystack_transaction_id BIGINT,
    purchase_date TIMESTAMPTZ DEFAULT NOW(),
    activation_date TIMESTAMPTZ DEFAULT NOW(),
    expiry_date TIMESTAMPTZ NOT NULL,
    status VARCHAR(50) DEFAULT 'active' CHECK (status IN ('active', 'expired', 'cancelled')),
    download_count INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_subscription_history_user ON public.subscription_history(user_id, expiry_date DESC);
CREATE INDEX IF NOT EXISTS idx_subscription_history_status ON public.subscription_history(status);

CREATE OR REPLACE TRIGGER trg_subscription_history_updated_at
BEFORE UPDATE ON public.subscription_history
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 3. Authoritative XP Balance Transactions Ledger Table
CREATE TABLE IF NOT EXISTS public.xp_transactions (
    id VARCHAR(100) PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    user_firebase_uid VARCHAR(64),
    type VARCHAR(50) NOT NULL CHECK (type IN ('ad_reward', 'donation', 'purchase', 'bonus', 'penalty', 'download_spend')),
    title VARCHAR(150),
    description TEXT,
    xp_amount INT NOT NULL,
    ad_unit_id VARCHAR(100),
    status VARCHAR(50) DEFAULT 'completed',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_xp_transactions_user ON public.xp_transactions(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_xp_transactions_type ON public.xp_transactions(type);

-- 4. Temporary Ad Reward Sessions Table (Prevents replay attacks & fraud)
CREATE TABLE IF NOT EXISTS public.ad_reward_sessions (
    id VARCHAR(100) PRIMARY KEY, -- Session UUID
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    user_firebase_uid VARCHAR(64),
    reward_type VARCHAR(50) NOT NULL CHECK (reward_type IN ('video', 'interstitial')),
    ad_unit_id VARCHAR(100) NOT NULL,
    expected_xp INT NOT NULL,
    consumed BOOLEAN DEFAULT FALSE,
    consumed_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ad_reward_sessions_lookup ON public.ad_reward_sessions(user_id, consumed, expires_at);

-- 5. Stored Procedure: Atomic Subscription Fulfillment
CREATE OR REPLACE FUNCTION public.fulfill_paystack_subscription(
    p_reference VARCHAR,
    p_paystack_tx_id BIGINT,
    p_channel VARCHAR
)
RETURNS JSONB AS $$
DECLARE
    v_payment RECORD;
    v_new_expiry TIMESTAMPTZ;
    v_current_expiry TIMESTAMPTZ;
BEGIN
    SELECT * INTO v_payment FROM public.payments WHERE reference = p_reference FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Payment record not found');
    END IF;

    IF v_payment.fulfilled THEN
        RETURN jsonb_build_object('success', true, 'message', 'Already fulfilled');
    END IF;

    -- Fetch current user subscription expiry
    SELECT subscription_expiry INTO v_current_expiry FROM public.users WHERE id = v_payment.user_id;

    -- Calculate extended expiry date
    IF v_current_expiry IS NOT NULL AND v_current_expiry > NOW() THEN
        v_new_expiry := v_current_expiry + (v_payment.duration_days || ' days')::INTERVAL;
    ELSE
        v_new_expiry := NOW() + (v_payment.duration_days || ' days')::INTERVAL;
    END IF;

    -- 1. Update user profile
    UPDATE public.users SET
        is_subscribed = TRUE,
        subscription_plan = v_payment.package_id,
        subscription_expiry = v_new_expiry,
        updated_at = NOW()
    WHERE id = v_payment.user_id;

    -- 2. Insert subscription history record
    INSERT INTO public.subscription_history (
        id,
        user_id,
        user_firebase_uid,
        package_title,
        amount,
        transaction_code,
        payment_channel,
        paystack_reference,
        paystack_transaction_id,
        purchase_date,
        activation_date,
        expiry_date,
        status
    ) VALUES (
        gen_random_uuid()::TEXT,
        v_payment.user_id,
        v_payment.user_firebase_uid,
        v_payment.package_name,
        v_payment.expected_amount_kes,
        p_reference,
        p_channel,
        p_reference,
        p_paystack_tx_id,
        NOW(),
        NOW(),
        v_new_expiry,
        'active'
    );

    -- 3. Mark payment fulfilled
    UPDATE public.payments SET
        status = 'success',
        fulfilled = TRUE,
        fulfilled_at = NOW(),
        paystack_transaction_id = p_paystack_tx_id,
        paystack_status = 'success',
        updated_at = NOW()
    WHERE reference = p_reference;

    RETURN jsonb_build_object('success', true, 'expiry', v_new_expiry);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Deny client direct execution of payment fulfillment RPC
REVOKE EXECUTE ON FUNCTION public.fulfill_paystack_subscription(VARCHAR, BIGINT, VARCHAR) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fulfill_paystack_subscription(VARCHAR, BIGINT, VARCHAR) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fulfill_paystack_subscription(VARCHAR, BIGINT, VARCHAR) TO postgres, service_role;


-- >>> FILE: 05_communications_and_ads.sql <<<

-- ==============================================================================
-- MIRROR DIGITAL: SUPABASE MIGRATION - PART 05
-- File: 05_communications_and_ads.sql
-- Description: In-app support conversations, private messages, notifications, and manual ads.
-- ==============================================================================

-- 1. Support Conversations Table (1-to-1 between User and Admin)
CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    firebase_uid VARCHAR(64) UNIQUE,
    user_name VARCHAR(150),
    user_photo_url TEXT,
    last_message_text TEXT,
    last_message_timestamp TIMESTAMPTZ,
    user_unread_count INT DEFAULT 0 CHECK (user_unread_count >= 0),
    admin_unread_count INT DEFAULT 0 CHECK (admin_unread_count >= 0),
    is_user_typing BOOLEAN DEFAULT FALSE,
    is_admin_typing BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_conversations_last_msg ON public.conversations(last_message_timestamp DESC);

CREATE OR REPLACE TRIGGER trg_conversations_updated_at
BEFORE UPDATE ON public.conversations
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 2. Support Chat Messages Table
CREATE TABLE IF NOT EXISTS public.messages (
    id VARCHAR(64) PRIMARY KEY,
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    sender_firebase_uid VARCHAR(64),
    sender_role VARCHAR(50) NOT NULL CHECK (sender_role IN ('user', 'admin')),
    text TEXT,
    image_url TEXT,
    reply_to_id VARCHAR(64) REFERENCES public.messages(id) ON DELETE SET NULL,
    reply_text TEXT,
    reply_is_image BOOLEAN DEFAULT FALSE,
    is_deleted BOOLEAN DEFAULT FALSE,
    deleted_for UUID[] DEFAULT '{}',
    status VARCHAR(50) DEFAULT 'sent' CHECK (status IN ('sending', 'sent', 'delivered', 'read')),
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation ON public.messages(conversation_id, created_at ASC);

-- 3. Automatic Conversation Update Trigger on Message Sent
CREATE OR REPLACE FUNCTION public.handle_new_chat_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.conversations SET
        last_message_text = COALESCE(NEW.text, '[Image]'),
        last_message_timestamp = NEW.created_at,
        user_unread_count = CASE WHEN NEW.sender_role = 'admin' THEN user_unread_count + 1 ELSE user_unread_count END,
        admin_unread_count = CASE WHEN NEW.sender_role = 'user' THEN admin_unread_count + 1 ELSE admin_unread_count END,
        updated_at = NOW()
    WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_new_chat_message ON public.messages;
CREATE TRIGGER trg_new_chat_message
AFTER INSERT ON public.messages
FOR EACH ROW EXECUTE FUNCTION public.handle_new_chat_message();

-- 4. Global & Targeted Notifications Table
CREATE TABLE IF NOT EXISTS public.notifications (
    id VARCHAR(64) PRIMARY KEY,
    target_type VARCHAR(50) DEFAULT 'all' CHECK (target_type IN ('all', 'user', 'role')),
    target_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    target_firebase_uid VARCHAR(64),
    sender_type VARCHAR(50) DEFAULT 'system',
    sender_name VARCHAR(100),
    created_by UUID REFERENCES public.users(id),
    type VARCHAR(50) DEFAULT 'general',
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_target ON public.notifications(target_type, target_user_id, created_at DESC);

-- 5. Manual Advertisements Table (Banners, Interstitials, Offline Ads)
CREATE TABLE IF NOT EXISTS public.manual_ads (
    id VARCHAR(64) PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    subtitle VARCHAR(255),
    url TEXT,
    image_url TEXT,
    contact_url TEXT,
    color BIGINT,
    color_value BIGINT,
    is_asset BOOLEAN DEFAULT FALSE,
    type VARCHAR(50) DEFAULT 'banner' CHECK (type IN ('banner', 'interstitial', 'native', 'video')),
    placement VARCHAR(50) DEFAULT 'all',
    media_file_id VARCHAR(100),
    is_active BOOLEAN DEFAULT TRUE,
    migrated_from_asset BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_manual_ads_active ON public.manual_ads(is_active, placement);

CREATE OR REPLACE TRIGGER trg_manual_ads_updated_at
BEFORE UPDATE ON public.manual_ads
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();


-- >>> FILE: 06_explore_news_and_content_pipeline.sql <<<

-- ==============================================================================
-- MIRROR DIGITAL: SUPABASE MIGRATION - PART 06
-- File: 06_explore_news_and_content_pipeline.sql
-- Description: Explore news magazine articles, categories, clustering, and worker queues.
-- ==============================================================================

-- 1. Explore News Categories Table
CREATE TABLE IF NOT EXISTS public.explore_categories (
    id VARCHAR(64) PRIMARY KEY, -- Category ID (e.g. tech, campus, sports)
    name VARCHAR(100) NOT NULL,
    display_order INT DEFAULT 0,
    retention_limit INT DEFAULT 40,
    hourly_discovery_count INT DEFAULT 5,
    target_articles INT DEFAULT 30,
    enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Story Clusters Table
CREATE TABLE IF NOT EXISTS public.story_clusters (
    id VARCHAR(64) PRIMARY KEY,
    cluster_id VARCHAR(100) UNIQUE NOT NULL,
    topic_title VARCHAR(255),
    main_article_id VARCHAR(100),
    main_article_title VARCHAR(255),
    related_article_ids TEXT[] DEFAULT '{}',
    cluster_size INT DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_story_clusters_cluster_id ON public.story_clusters(cluster_id);

-- 3. Published Explore News Magazine Articles Table
CREATE TABLE IF NOT EXISTS public.explore_news (
    id VARCHAR(64) PRIMARY KEY,
    article_id VARCHAR(100) UNIQUE,
    category_id VARCHAR(64) REFERENCES public.explore_categories(id) ON DELETE SET NULL,
    category VARCHAR(100),
    cluster_id VARCHAR(100),
    topic_query VARCHAR(255),
    title VARCHAR(255) NOT NULL,
    summary TEXT,
    editorial_summary TEXT,
    content TEXT,
    cover_image TEXT,
    thumbnail_url TEXT,
    image_urls TEXT[] DEFAULT '{}',
    images JSONB DEFAULT '[]'::jsonb,
    image_count INT DEFAULT 0,
    image_sources TEXT[] DEFAULT '{}',
    image_search_completed BOOLEAN DEFAULT FALSE,
    image_search_attempts INT DEFAULT 0,
    source VARCHAR(150),
    source_url TEXT,
    original_source_url TEXT,
    source_published_at VARCHAR(100),
    provider VARCHAR(100),
    assigned_worker VARCHAR(100),
    discovery_worker VARCHAR(100),
    discovery_provider VARCHAR(100),
    candidate_id VARCHAR(100),
    status VARCHAR(50) DEFAULT 'published' CHECK (status IN ('published', 'draft', 'archived', 'deactivated')),
    published_at TIMESTAMPTZ DEFAULT NOW(),
    discovered_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_explore_news_cat_published ON public.explore_news(category_id, published_at DESC);
CREATE INDEX IF NOT EXISTS idx_explore_news_status ON public.explore_news(status, published_at DESC);
CREATE INDEX IF NOT EXISTS idx_explore_news_fts ON public.explore_news USING gin(to_tsvector('english'::regconfig, title || ' ' || COALESCE(summary, '')));

CREATE OR REPLACE TRIGGER trg_explore_news_updated_at
BEFORE UPDATE ON public.explore_news
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 4. Explore News Archive Table (For Rotation Retention)
CREATE TABLE IF NOT EXISTS public.explore_news_archive (
    id VARCHAR(64) PRIMARY KEY,
    article_id VARCHAR(100),
    archive_reason VARCHAR(100),
    archived_at TIMESTAMPTZ DEFAULT NOW(),
    data JSONB NOT NULL
);

-- 5. Magazine Highlight Caches: Top Stories, Latest News, Trending Topics
CREATE TABLE IF NOT EXISTS public.top_stories (
    id VARCHAR(64) PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    category VARCHAR(100),
    source VARCHAR(100),
    top_story_rank INT DEFAULT 1,
    importance_score NUMERIC(5, 2),
    freshness_score NUMERIC(5, 2),
    viewer_document_url TEXT,
    thumbnail_url TEXT,
    published_at TIMESTAMPTZ,
    data JSONB
);

CREATE TABLE IF NOT EXISTS public.latest_news (
    id VARCHAR(64) PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    category VARCHAR(100),
    source VARCHAR(100),
    trending_rank INT,
    importance_score NUMERIC(5, 2),
    freshness_score NUMERIC(5, 2),
    viewer_document_url TEXT,
    thumbnail_url TEXT,
    published_at TIMESTAMPTZ,
    data JSONB
);

CREATE TABLE IF NOT EXISTS public.trending_topics (
    id VARCHAR(64) PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    cluster_size INT DEFAULT 1,
    importance_score NUMERIC(5, 2),
    icon_name VARCHAR(50),
    gradient_colors TEXT[] DEFAULT '{}',
    image_urls TEXT[] DEFAULT '{}',
    details JSONB
);

-- 6. Operational Queue Tables (Autonomous Scrapers & Article Processors)
CREATE TABLE IF NOT EXISTS public.story_candidates (
    id VARCHAR(64) PRIMARY KEY,
    candidate_id VARCHAR(100) UNIQUE,
    title VARCHAR(255) NOT NULL,
    category_id VARCHAR(64),
    category VARCHAR(100),
    source VARCHAR(150),
    source_url TEXT,
    summary TEXT,
    canonical_identity VARCHAR(255),
    fingerprint VARCHAR(255),
    discovery_worker VARCHAR(100),
    discovery_provider VARCHAR(100),
    status VARCHAR(50) DEFAULT 'pending',
    discovered_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.discovery_jobs (
    id VARCHAR(64) PRIMARY KEY,
    mode VARCHAR(50),
    category_id VARCHAR(64),
    category VARCHAR(100),
    target INT DEFAULT 10,
    accepted INT DEFAULT 0,
    attempts INT DEFAULT 0,
    worker_id VARCHAR(100),
    provider VARCHAR(100),
    status VARCHAR(50) DEFAULT 'pending',
    last_error TEXT,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    retry_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.article_jobs (
    id VARCHAR(64) PRIMARY KEY,
    candidate_id VARCHAR(100),
    article_id VARCHAR(100),
    title VARCHAR(255),
    category_id VARCHAR(64),
    category VARCHAR(100),
    source VARCHAR(150),
    source_url TEXT,
    summary TEXT,
    status VARCHAR(50) DEFAULT 'pending',
    attempts INT DEFAULT 0,
    assigned_worker VARCHAR(100),
    assigned_provider VARCHAR(100),
    last_error TEXT,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    retry_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.failed_article_jobs (
    id VARCHAR(64) PRIMARY KEY,
    candidate_id VARCHAR(100),
    title VARCHAR(255),
    category_id VARCHAR(64),
    category VARCHAR(100),
    source VARCHAR(150),
    source_url TEXT,
    attempts INT DEFAULT 0,
    last_error TEXT,
    status VARCHAR(50) DEFAULT 'failed',
    failed_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. Media Hashing & Duplicate Registry Tables
CREATE TABLE IF NOT EXISTS public.used_article_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    image_hash VARCHAR(128) UNIQUE NOT NULL,
    imagekit_url TEXT NOT NULL,
    original_url TEXT,
    article_title VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_used_article_images_hash ON public.used_article_images(image_hash);

CREATE TABLE IF NOT EXISTS public.used_thumbnails (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    image_hash VARCHAR(128) UNIQUE NOT NULL,
    imagekit_url TEXT NOT NULL,
    imagekit_file_id VARCHAR(100),
    title VARCHAR(255),
    unit_name VARCHAR(255),
    provider VARCHAR(100),
    model_used VARCHAR(100),
    worker_id VARCHAR(100),
    source_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_used_thumbnails_hash ON public.used_thumbnails(image_hash);

-- 8. AI Worker Pool State Tables
CREATE TABLE IF NOT EXISTS public.workers (
    id VARCHAR(64) PRIMARY KEY,
    worker_id VARCHAR(100) UNIQUE NOT NULL,
    status VARCHAR(50) DEFAULT 'idle',
    busy BOOLEAN DEFAULT FALSE,
    enabled BOOLEAN DEFAULT TRUE,
    average_latency NUMERIC(10, 2),
    requests_this_minute INT DEFAULT 0,
    failure_rate NUMERIC(5, 2),
    success_rate NUMERIC(5, 2),
    failure_count INT DEFAULT 0,
    last_error TEXT,
    last_heartbeat TIMESTAMPTZ,
    last_used TIMESTAMPTZ,
    cooldown_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.flux_workers (
    id VARCHAR(64) PRIMARY KEY,
    worker_id VARCHAR(100) UNIQUE NOT NULL,
    status VARCHAR(50) DEFAULT 'idle',
    failure_count INT DEFAULT 0,
    last_error TEXT,
    last_used_at TIMESTAMPTZ,
    last_successful_generation_at TIMESTAMPTZ,
    daily_quota_paused_until TIMESTAMPTZ,
    daily_quota_failure_streak INT DEFAULT 0,
    cooldown_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);


-- >>> FILE: 07_governance_and_integrations.sql <<<

-- ==============================================================================
-- MIRROR DIGITAL: SUPABASE MIGRATION - PART 07
-- File: 07_governance_and_integrations.sql
-- Description: DSpace ingestion jobs, GDPR account deletion audits, and promotional campaigns.
-- ==============================================================================

-- 1. DSpace Institutional Examination Repository Ingestion Jobs Table
CREATE TABLE IF NOT EXISTS public.dspace_jobs (
    id VARCHAR(64) PRIMARY KEY,
    action VARCHAR(50) NOT NULL,
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled')),
    total_items INT DEFAULT 0,
    discovered_count INT DEFAULT 0,
    imported_count INT DEFAULT 0,
    failed_count INT DEFAULT 0,
    skipped_count INT DEFAULT 0,
    pending_count INT DEFAULT 0,
    progress NUMERIC(5, 2) DEFAULT 0,
    message TEXT,
    error TEXT,
    discovered_items JSONB DEFAULT '[]'::jsonb,
    summary JSONB,
    created_by UUID REFERENCES public.users(id),
    created_by_name VARCHAR(150),
    claimed_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_dspace_jobs_status ON public.dspace_jobs(status, created_at DESC);

CREATE OR REPLACE TRIGGER trg_dspace_jobs_updated_at
BEFORE UPDATE ON public.dspace_jobs
FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 2. Account Deletion Compliance & Audit Log Table (GDPR / Right to be Forgotten)
CREATE TABLE IF NOT EXISTS public.account_deletion_audits (
    id VARCHAR(64) PRIMARY KEY,
    uid VARCHAR(64) NOT NULL,
    user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    reason TEXT,
    survey JSONB,
    status VARCHAR(50) DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'cancelled', 'purged', 'restored')),
    requested_at TIMESTAMPTZ NOT NULL,
    scheduled_purge_at TIMESTAMPTZ NOT NULL,
    restored_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_account_deletion_uid ON public.account_deletion_audits(uid);
CREATE INDEX IF NOT EXISTS idx_account_deletion_status ON public.account_deletion_audits(status, scheduled_purge_at);

-- 3. Promotional Campaigns Table
CREATE TABLE IF NOT EXISTS public.promotional_campaigns (
    id VARCHAR(64) PRIMARY KEY,
    campaign_id VARCHAR(100) UNIQUE NOT NULL,
    stage1 JSONB,
    stage2 JSONB,
    stage3 JSONB,
    total_claims INT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Promotional Trial Claims Table (User-level Claim Tracking)
CREATE TABLE IF NOT EXISTS public.promotional_trial_claims (
    id VARCHAR(64) PRIMARY KEY, -- User ID or compound claim ID
    uid VARCHAR(64) NOT NULL,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    email_hash VARCHAR(128) NOT NULL,
    stage INT DEFAULT 1,
    stage_title VARCHAR(100),
    subscription_id VARCHAR(100),
    status VARCHAR(50) DEFAULT 'active',
    claimed_at TIMESTAMPTZ DEFAULT NOW(),
    expiry_date TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_promotional_trial_uid ON public.promotional_trial_claims(uid);
CREATE INDEX IF NOT EXISTS idx_promotional_trial_email_hash ON public.promotional_trial_claims(email_hash);

-- 5. Promotional Trial Emails Table (Device/Email Anti-Abuse Registry)
CREATE TABLE IF NOT EXISTS public.promotional_trial_emails (
    email_hash VARCHAR(128) PRIMARY KEY,
    uid VARCHAR(64) NOT NULL,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    stage INT DEFAULT 1,
    subscription_id VARCHAR(100),
    claimed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_promotional_trial_emails_uid ON public.promotional_trial_emails(uid);


-- >>> FILE: 08_row_level_security.sql <<<

-- ==============================================================================
-- MIRROR DIGITAL: SUPABASE MIGRATION - PART 08
-- File: 08_row_level_security.sql
-- Description: Complete Row Level Security (RLS) policies replicating firestore.rules.
-- ==============================================================================

-- ==============================================================================
-- 1. ENABLE ROW LEVEL SECURITY ON ALL PUBLIC APPLICATION TABLES
-- ==============================================================================
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.resources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.xp_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ad_reward_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.curriculum ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.manual_ads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.explore_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.explore_news ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.explore_news_archive ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.top_stories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.latest_news ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trending_topics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.story_clusters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.story_candidates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discovery_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.article_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.failed_article_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.used_article_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.used_thumbnails ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.flux_workers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dspace_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_deletion_audits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promotional_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promotional_trial_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promotional_trial_emails ENABLE ROW LEVEL SECURITY;

-- ==============================================================================
-- 2. USERS & USER SESSIONS POLICIES
-- ==============================================================================
-- Read: Users can only read their own private profile; administrators can read all profiles.
-- Public author/commenter attribution is strictly served via parameterized public.get_author_profile(UUID) RPC.
DROP POLICY IF EXISTS "Users can read profiles" ON public.users;
DROP POLICY IF EXISTS "Users can read own profile" ON public.users;
CREATE POLICY "Users can read own profile" ON public.users
    FOR SELECT TO authenticated
    USING (id = auth.uid() OR public.is_admin());

-- Update: Users can update their own non-restricted profile fields. Admins can update all fields.
DROP POLICY IF EXISTS "Users can update own profile" ON public.users;
CREATE POLICY "Users can update own profile" ON public.users
    FOR UPDATE TO authenticated
    USING (id = auth.uid() OR public.is_admin())
    WITH CHECK (
        public.is_admin() OR (
            id = auth.uid()
            -- Authoritative fields MUST NOT be altered by users directly
            AND role IS NOT DISTINCT FROM (SELECT role FROM public.users WHERE id = auth.uid())
            AND is_subscribed IS NOT DISTINCT FROM (SELECT is_subscribed FROM public.users WHERE id = auth.uid())
            AND subscription_plan IS NOT DISTINCT FROM (SELECT subscription_plan FROM public.users WHERE id = auth.uid())
            AND subscription_expiry IS NOT DISTINCT FROM (SELECT subscription_expiry FROM public.users WHERE id = auth.uid())
            AND xp_balance IS NOT DISTINCT FROM (SELECT xp_balance FROM public.users WHERE id = auth.uid())
            AND deletion_status IS NOT DISTINCT FROM (SELECT deletion_status FROM public.users WHERE id = auth.uid())
        )
    );

-- Delete: Administrators only
DROP POLICY IF EXISTS "Admins can delete users" ON public.users;
CREATE POLICY "Admins can delete users" ON public.users
    FOR DELETE TO authenticated
    USING (public.is_admin());

-- User Sessions: Owner or Admin
DROP POLICY IF EXISTS "Users can manage own sessions" ON public.user_sessions;
CREATE POLICY "Users can manage own sessions" ON public.user_sessions
    FOR ALL TO authenticated
    USING (user_id = auth.uid() OR public.is_admin())
    WITH CHECK (user_id = auth.uid() OR public.is_admin());

-- ==============================================================================
-- 3. ACADEMIC RESOURCES & COMMENTS POLICIES
-- ==============================================================================
-- Resources: Public can view active materials; uploaders can view their own trashed/pending
DROP POLICY IF EXISTS "Public can view active resources" ON public.resources;
CREATE POLICY "Public can view active resources" ON public.resources
    FOR SELECT TO public
    USING (status = 'active' OR uploader_id = auth.uid() OR public.is_admin());

-- Resources Insert: Authenticated users can upload materials
DROP POLICY IF EXISTS "Authenticated users can upload resources" ON public.resources;
CREATE POLICY "Authenticated users can upload resources" ON public.resources
    FOR INSERT TO authenticated
    WITH CHECK (uploader_id = auth.uid() OR public.is_admin());

-- Resources Update 1: Uploader or Admin can update resource
DROP POLICY IF EXISTS "Update resources permissions" ON public.resources;
DROP POLICY IF EXISTS "Uploaders and admins can update resource" ON public.resources;
CREATE POLICY "Uploaders and admins can update resource" ON public.resources
    FOR UPDATE TO authenticated
    USING (uploader_id = auth.uid() OR public.is_admin())
    WITH CHECK (uploader_id = auth.uid() OR public.is_admin());

-- Resources Update 2: Community members can update engagement metrics on active materials
-- (Enforced at field-level via public.enforce_resource_update_security trigger)
DROP POLICY IF EXISTS "Community can update resource engagement" ON public.resources;
CREATE POLICY "Community can update resource engagement" ON public.resources
    FOR UPDATE TO authenticated
    USING (status = 'active')
    WITH CHECK (status = 'active');

-- Resources Delete: Uploader or Admin
DROP POLICY IF EXISTS "Uploader or admin can delete resources" ON public.resources;
CREATE POLICY "Uploader or admin can delete resources" ON public.resources
    FOR DELETE TO authenticated
    USING (uploader_id = auth.uid() OR public.is_admin());

-- Comments: Public read
DROP POLICY IF EXISTS "Public can read comments" ON public.comments;
CREATE POLICY "Public can read comments" ON public.comments
    FOR SELECT TO public
    USING (TRUE);

-- Comments Insert: Authenticated users can comment
DROP POLICY IF EXISTS "Authenticated users can comment" ON public.comments;
CREATE POLICY "Authenticated users can comment" ON public.comments
    FOR INSERT TO authenticated
    WITH CHECK (author_id = auth.uid() AND is_moderated = FALSE);

-- Comments Update: Author (if unmoderated), Admin, or liking user
DROP POLICY IF EXISTS "Update comments permissions" ON public.comments;
CREATE POLICY "Update comments permissions" ON public.comments
    FOR UPDATE TO authenticated
    USING ((author_id = auth.uid() AND is_moderated = FALSE) OR public.is_admin() OR public.is_authenticated())
    WITH CHECK (
        public.is_admin()
        OR (author_id = auth.uid() AND is_moderated = FALSE)
        OR (
            public.is_authenticated()
            AND text = (SELECT text FROM public.comments WHERE id = comments.id)
            AND author_id = (SELECT author_id FROM public.comments WHERE id = comments.id)
        )
    );

-- Comments Delete: Author or Admin
DROP POLICY IF EXISTS "Author or admin can delete comments" ON public.comments;
CREATE POLICY "Author or admin can delete comments" ON public.comments
    FOR DELETE TO authenticated
    USING (author_id = auth.uid() OR public.is_admin());

-- ==============================================================================
-- 4. CONVERSATIONS & PRIVATE CHAT MESSAGES POLICIES
-- ==============================================================================
-- Conversations: Owner or Admin only (strict isolation between users)
DROP POLICY IF EXISTS "User or admin conversation access" ON public.conversations;
CREATE POLICY "User or admin conversation access" ON public.conversations
    FOR ALL TO authenticated
    USING (id = auth.uid() OR public.is_admin())
    WITH CHECK (id = auth.uid() OR public.is_admin());

-- Messages: Conversation owner or Admin only
DROP POLICY IF EXISTS "User or admin message access" ON public.messages;
CREATE POLICY "User or admin message access" ON public.messages
    FOR ALL TO authenticated
    USING (conversation_id = auth.uid() OR public.is_admin())
    WITH CHECK (conversation_id = auth.uid() OR public.is_admin());

-- ==============================================================================
-- 5. NOTIFICATIONS & CURRICULUM POLICIES
-- ==============================================================================
-- Notifications: Broadcast ('all') or targeted to specific user; admins read/write all
DROP POLICY IF EXISTS "Read notifications policy" ON public.notifications;
CREATE POLICY "Read notifications policy" ON public.notifications
    FOR SELECT TO authenticated
    USING (target_type = 'all' OR target_user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS "Admin manage notifications" ON public.notifications;
CREATE POLICY "Admin manage notifications" ON public.notifications
    FOR ALL TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- Curriculum: Read by authenticated; written by Admin
DROP POLICY IF EXISTS "Authenticated can read curriculum" ON public.curriculum;
CREATE POLICY "Authenticated can read curriculum" ON public.curriculum
    FOR SELECT TO authenticated
    USING (TRUE);

DROP POLICY IF EXISTS "Admin manage curriculum" ON public.curriculum;
CREATE POLICY "Admin manage curriculum" ON public.curriculum
    FOR ALL TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- ==============================================================================
-- 6. AUTHORITATIVE FINANCIAL & WALLET POLICIES (STRICT SERVER CONTROL)
-- ==============================================================================
-- Payments: Users can view own payment receipts; only service_role (Edge Functions) can insert/update
DROP POLICY IF EXISTS "Users can view own payments" ON public.payments;
CREATE POLICY "Users can view own payments" ON public.payments
    FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR public.is_admin());

-- Deny direct client insert/update on payments
DROP POLICY IF EXISTS "Deny client write on payments" ON public.payments;
CREATE POLICY "Deny client write on payments" ON public.payments
    FOR INSERT TO authenticated
    WITH CHECK (FALSE);

DROP POLICY IF EXISTS "Deny client update on payments" ON public.payments;
CREATE POLICY "Deny client update on payments" ON public.payments
    FOR UPDATE TO authenticated
    USING (FALSE);

-- Subscription History: Read by user/admin; write forbidden from client
DROP POLICY IF EXISTS "Users view own subscription history" ON public.subscription_history;
CREATE POLICY "Users view own subscription history" ON public.subscription_history
    FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS "Deny client write on subscriptions" ON public.subscription_history;
CREATE POLICY "Deny client write on subscriptions" ON public.subscription_history
    FOR INSERT TO authenticated
    WITH CHECK (FALSE);

-- XP Transactions: Read by user/admin; write forbidden from client
DROP POLICY IF EXISTS "Users view own xp transactions" ON public.xp_transactions;
CREATE POLICY "Users view own xp transactions" ON public.xp_transactions
    FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS "Deny client write on xp transactions" ON public.xp_transactions;
CREATE POLICY "Deny client write on xp transactions" ON public.xp_transactions
    FOR INSERT TO authenticated
    WITH CHECK (FALSE);

-- Ad Reward Sessions: Read by user/admin; write forbidden from client
DROP POLICY IF EXISTS "Users view own ad reward sessions" ON public.ad_reward_sessions;
CREATE POLICY "Users view own ad reward sessions" ON public.ad_reward_sessions
    FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS "Deny client write on ad reward sessions" ON public.ad_reward_sessions;
CREATE POLICY "Deny client write on ad reward sessions" ON public.ad_reward_sessions
    FOR INSERT TO authenticated
    WITH CHECK (FALSE);

-- ==============================================================================
-- 7. EXPLORE NEWS & ADVERTISING POLICIES
-- ==============================================================================
-- Manual Ads: Public read active ads; admin write
DROP POLICY IF EXISTS "Public view active manual ads" ON public.manual_ads;
CREATE POLICY "Public view active manual ads" ON public.manual_ads
    FOR SELECT TO public
    USING (is_active = TRUE OR public.is_admin());

DROP POLICY IF EXISTS "Admin manage manual ads" ON public.manual_ads;
CREATE POLICY "Admin manage manual ads" ON public.manual_ads
    FOR ALL TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- Explore News & Categories: Public read; admin write
DROP POLICY IF EXISTS "Public view explore categories" ON public.explore_categories;
CREATE POLICY "Public view explore categories" ON public.explore_categories
    FOR SELECT TO public
    USING (enabled = TRUE OR public.is_admin());

DROP POLICY IF EXISTS "Public view explore news" ON public.explore_news;
CREATE POLICY "Public view explore news" ON public.explore_news
    FOR SELECT TO public
    USING (status = 'published' OR public.is_admin());

DROP POLICY IF EXISTS "Public view top stories" ON public.top_stories;
CREATE POLICY "Public view top stories" ON public.top_stories
    FOR SELECT TO public
    USING (TRUE);

DROP POLICY IF EXISTS "Public view latest news" ON public.latest_news;
CREATE POLICY "Public view latest news" ON public.latest_news
    FOR SELECT TO public
    USING (TRUE);

DROP POLICY IF EXISTS "Public view trending topics" ON public.trending_topics;
CREATE POLICY "Public view trending topics" ON public.trending_topics
    FOR SELECT TO public
    USING (TRUE);

DROP POLICY IF EXISTS "Public view story clusters" ON public.story_clusters;
CREATE POLICY "Public view story clusters" ON public.story_clusters
    FOR SELECT TO public
    USING (TRUE);

-- Operational Queues & Workers: Admin only
DROP POLICY IF EXISTS "Admin only discovery jobs" ON public.discovery_jobs;
CREATE POLICY "Admin only discovery jobs" ON public.discovery_jobs
    FOR ALL TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Admin only article jobs" ON public.article_jobs;
CREATE POLICY "Admin only article jobs" ON public.article_jobs
    FOR ALL TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Admin only workers" ON public.workers;
CREATE POLICY "Admin only workers" ON public.workers
    FOR ALL TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- ==============================================================================
-- 8. COMPLIANCE & INTEGRATION POLICIES
-- ==============================================================================
-- DSpace Jobs: Admin only
DROP POLICY IF EXISTS "Admin only dspace jobs" ON public.dspace_jobs;
CREATE POLICY "Admin only dspace jobs" ON public.dspace_jobs
    FOR ALL TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- Account Deletion Audits: Admin only
DROP POLICY IF EXISTS "Admin only account deletion audits" ON public.account_deletion_audits;
CREATE POLICY "Admin only account deletion audits" ON public.account_deletion_audits
    FOR ALL TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- Promotional Campaigns & Claims: Read authenticated; write server/admin only
DROP POLICY IF EXISTS "Read promotional campaigns" ON public.promotional_campaigns;
CREATE POLICY "Read promotional campaigns" ON public.promotional_campaigns
    FOR SELECT TO authenticated
    USING (is_active = TRUE OR public.is_admin());

DROP POLICY IF EXISTS "Users view own trial claims" ON public.promotional_trial_claims;
CREATE POLICY "Users view own trial claims" ON public.promotional_trial_claims
    FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS "Deny client write on trial claims" ON public.promotional_trial_claims;
CREATE POLICY "Deny client write on trial claims" ON public.promotional_trial_claims
    FOR INSERT TO authenticated
    WITH CHECK (FALSE);

DROP POLICY IF EXISTS "Admin only promotional trial emails" ON public.promotional_trial_emails;
CREATE POLICY "Admin only promotional trial emails" ON public.promotional_trial_emails
    FOR ALL TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- ==============================================================================
-- 9. SUPABASE REALTIME CONFIGURATION & PUBLICATION
-- ==============================================================================
-- Configures Supabase Realtime publication ('supabase_realtime') for client-streamed tables.
-- Sets REPLICA IDENTITY FULL on each table to enable RLS filtering on UPDATE and DELETE.
DO $$
DECLARE
    tbl_name text;
    realtime_tables text[] := ARRAY[
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
BEGIN
    -- Ensure the default Supabase Realtime publication exists
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;

    FOREACH tbl_name IN ARRAY realtime_tables LOOP
        -- Set REPLICA IDENTITY FULL so RLS filters evaluate accurately on UPDATE / DELETE
        EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL;', tbl_name);

        -- Add table to publication idempotently (prevents duplicate membership error)
        IF NOT EXISTS (
            SELECT 1 
            FROM pg_publication_tables 
            WHERE pubname = 'supabase_realtime'
              AND schemaname = 'public'
              AND tablename = tbl_name
        ) THEN
            EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I;', tbl_name);
        END IF;
    END LOOP;
END $$;


-- >>> FILE: 09_maintenance_and_cron.sql <<<

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


-- >>> FILE: 10_schema_validation.sql <<<

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


COMMIT;
