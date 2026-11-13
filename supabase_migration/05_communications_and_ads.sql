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
