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
