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
