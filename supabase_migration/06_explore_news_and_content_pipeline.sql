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
