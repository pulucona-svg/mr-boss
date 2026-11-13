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
