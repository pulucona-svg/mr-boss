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
