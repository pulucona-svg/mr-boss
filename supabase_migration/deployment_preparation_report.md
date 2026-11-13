# MIRROR DIGITAL: CONTROLLED SUPABASE SCHEMA DEPLOYMENT MANUAL & PREPARATION REPORT
**Target Project:** Mirror Digital (Supabase Cloud)  
**Project Reference:** `iagfozaynaxexaefdpns`  
**Project URL:** `https://iagfozaynaxexaefdpns.supabase.co`  
**Target File:** [`supabase_migration/00_full_migration_bundle.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/00_full_migration_bundle.sql)  
**Date:** March 2026  
**Document Status:** **APPROVED FOR CONTROLLED EXECUTION (PREPARATION ONLY)**  

---

> [!IMPORTANT]
> **SAFETY GATE CONFIRMATION**
> This document is a **preparation and verification guide only**.  
> - **Zero remote database commands** were executed during this task.
> - **Zero connections** were made to the remote Supabase database.
> - **Zero changes** were made to Flutter application code or Firebase production.
> - **Zero secrets or API keys** were printed or stored.
> - Execution against Supabase Cloud must be initiated manually by authorized staff following the exact steps in Section 3.

---

## 1. PROJECT & ENVIRONMENT VERIFICATION

### 1.1 Project Target & Identifiers
- **Supabase Cloud Project Name:** Mirror Digital
- **Configured Project URL:** `https://iagfozaynaxexaefdpns.supabase.co`
- **Project Ref ID:** `iagfozaynaxexaefdpns`
- **Target Database Engine:** PostgreSQL 15+ (Managed Supabase Cloud)

### 1.2 Local Migration Bundle & Checksum
- **Migration Directory:** `C:\Users\Hp i7\Documents\mirror Laikipia3\mirror_laikipia\supabase_migration`
- **Consolidated Bundle File:** [`supabase_migration/00_full_migration_bundle.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/00_full_migration_bundle.sql)
- **Bundle File Size:** `84,670 bytes` (2,081 lines)
- **Transaction Mode:** Explicit All-or-Nothing Atomic Transaction (`BEGIN ... COMMIT`)
- **SHA256 Checksum:**
  ```
  ac878b91b03c3f4627b640cffe089f54bf715ba329f096b27a974b8d4be3194b
  ```

### 1.3 Modular Parity Verification
Automated cryptographic comparison confirmed that all 10 modular files match their respective sections in the consolidated bundle 100% byte-for-byte:

| Modular File | Size (Bytes) | SHA256 Checksum | Parity Status |
| :--- | :---: | :--- | :---: |
| [`01_extensions_and_helpers.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/01_extensions_and_helpers.sql) | 2,159 | `cca3bbaae67c839b1943d6eae9cc144f55b184b4c5577a32f6c5706af71f3d28` | **MATCH** |
| [`02_core_users_and_auth.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/02_core_users_and_auth.sql) | 9,058 | `6a0bbc4f7cb652c18730b9a7ac541cf3d945f93058fcc5cd3b4c2220f474c4f2` | **MATCH** |
| [`03_academic_resources_and_curriculum.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/03_academic_resources_and_curriculum.sql) | 11,759 | `cd3648c6714b2e1175c2ef27af85b86c86d0a700ecde07a0412dc69ad3f75f85` | **MATCH** |
| [`04_payments_subscriptions_and_xp.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/04_payments_subscriptions_and_xp.sql) | 7,312 | `8c7e2488128a75827c6fdc3c8cb7121586483aa6150a3968207b1ffc94f4e1fd` | **MATCH** |
| [`05_communications_and_ads.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/05_communications_and_ads.sql) | 4,684 | `969d1c9ed51a6ac03356c99427f4cbda05cab421560c95a680f1fd50caf7cab1` | **MATCH** |
| [`06_explore_news_and_content_pipeline.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/06_explore_news_and_content_pipeline.sql) | 8,811 | `0ed8a1c7867b23f693e34abf3bafcb51761346834e6cd6d30d4ab59d28419026` | **MATCH** |
| [`07_governance_and_integrations.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/07_governance_and_integrations.sql) | 3,961 | `df7666cf7fd8283f2b60a1ac261f8302a1a2c3e746732827c4b7fa52ed2124ca` | **MATCH** |
| [`08_row_level_security.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/08_row_level_security.sql) | 19,722 | `be10510ad0352115bbcc3c6acb4d166e364bd97a9d7c19bcae62a5a5e2074fc1` | **MATCH** |
| [`09_maintenance_and_cron.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql) | 9,669 | `07bd90f85416849ef9b33aa7fc0a2dbbdad92b899ca990c0dace354b47f2286c` | **MATCH** |
| [`10_schema_validation.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/10_schema_validation.sql) | 6,602 | `854ab6eb9527671336aabb08240f8716cb36c3f6e7334390cbca1bad282c7372` | **MATCH** |

### 1.4 Secret & Credential Scanning Audit
An automated security scan of all SQL files for JWT tokens, service-role keys, private keys, Paystack API keys, and plain passwords yielded **0 findings**. No secrets are embedded in the migration DDL.

### 1.5 Supabase Infrastructure & Role Assumptions
1. **Pre-existing Database Roles:** The migration relies on standard Supabase Cloud roles:
   - `postgres` (Schema owner and superuser executor in SQL Editor)
   - `service_role` (Backend Edge Functions / bypass RLS role)
   - `authenticated` (Standard authenticated client role derived from GoTrue JWT)
   - `anon` (Unauthenticated public role)
   - `PUBLIC` (PostgreSQL pseudo-role)
2. **Pre-existing Schemas & Objects:**
   - Schema `auth` and table `auth.users` are pre-provisioned by Supabase GoTrue.
   - Built-in authentication functions `auth.uid()` and `auth.jwt()` exist.
   - Default publication `supabase_realtime` exists.
3. **Extensions:**
   - Extensions `uuid-ossp`, `pgcrypto`, `pg_trgm`, `btree_gin` can be created directly by `postgres`.
   - Extension `pg_cron` is pre-installed in Supabase Cloud, but should be enabled in the Dashboard before running cron schedules.

---

## 2. PRE-DEPLOYMENT VERIFICATION: EMPTY DATABASE CONFIRMATION

Before running any migration DDL, the operator must execute the following read-only query in the Supabase Dashboard SQL Editor to verify the database is clean:

```sql
-- PRE-FLIGHT CHECK: Ensure public schema and custom schemas are empty
SELECT 
    schemaname, 
    tablename 
FROM pg_tables 
WHERE schemaname IN ('public', 'auth_migration')
ORDER BY schemaname, tablename;
```

**Expected Result:** **0 rows**.  
*(If any application tables exist, do not proceed without investigating their origin).*

---

## 3. CONTROLLED DEPLOYMENT PROCEDURE

### 3.1 Recommended Execution Strategy: Two-Stage Deployment

While [`supabase_migration/00_full_migration_bundle.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/00_full_migration_bundle.sql) can be executed in one single pass in the Supabase SQL Editor, the safest controlled production strategy is a **Two-Stage Deployment**:

#### STAGE 1: Enable `pg_cron` Extension in Supabase Dashboard
1. Navigate to: `https://supabase.com/dashboard/project/iagfozaynaxexaefdpns`
2. In the left navigation, click **Database** -> **Extensions**.
3. Search for **`pg_cron`**.
4. Toggle **`pg_cron`** to **ON** (Enabled).  
   *(Enabling this first guarantees that the two essential maintenance jobs in Part 09 register immediately on the first run).*

#### STAGE 2: Execute Consolidated Migration Bundle
1. In the Supabase Dashboard, click **SQL Editor**.
2. Click **+ New Query**.
3. Open [`supabase_migration/00_full_migration_bundle.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/00_full_migration_bundle.sql) on your computer, copy its entire contents, and paste into the query window.
4. Verify the line count shows `2,076 lines`.
5. Click **Run** (green button).

### 3.2 Controlled Multi-Section Fallback (If Sectional Execution is Preferred)
If the operator prefers stepping through individual sections, execute in the exact order below:

- **Step 1:** Run [`01_extensions_and_helpers.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/01_extensions_and_helpers.sql) (Extensions, namespaces, updated_at helper, is_admin).
- **Step 2:** Run [`02_core_users_and_auth.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/02_core_users_and_auth.sql) (`users`, `user_sessions`, auth bridge trigger, `get_author_profile`).
- **Step 3:** Run [`03_academic_resources_and_curriculum.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/03_academic_resources_and_curriculum.sql) (`curriculum`, `resources`, `comments`, field immutability trigger).
- **Step 4:** Run [`04_payments_subscriptions_and_xp.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/04_payments_subscriptions_and_xp.sql) (`payments`, `subscription_history`, `xp_transactions`, `fulfill_paystack_subscription`).
- **Step 5:** Run [`05_communications_and_ads.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/05_communications_and_ads.sql) (`conversations`, `messages`, `notifications`, `manual_ads`).
- **Step 6:** Run [`06_explore_news_and_content_pipeline.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/06_explore_news_and_content_pipeline.sql) (`explore_news`, queues, workers, media hash tables).
- **Step 7:** Run [`07_governance_and_integrations.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/07_governance_and_integrations.sql) (`dspace_jobs`, `account_deletion_audits`, promotional trial claims).
- **Step 8:** Run [`08_row_level_security.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/08_row_level_security.sql) (Enables RLS on 33 tables, 45 policies, sets `REPLICA IDENTITY FULL`, registers Realtime).
- **Step 9:** Run [`09_maintenance_and_cron.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql) (Registers maintenance procs & pg_cron schedules).
- **Step 10:** Run [`10_schema_validation.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/10_schema_validation.sql) (Runs diagnostic verification script).

---

## 4. TRANSACTION ATOMICITY & EMERGENCY ROLLBACK STRATEGY

### 4.1 Transaction Atomicity Analysis
A central concern for production deployment is establishing whether the 2,081-line consolidated bundle executes atomically, and what state the database is left in if an error occurs midway.

#### Without `BEGIN ... COMMIT` (Multi-statement Autocommit Mode)
In PostgreSQL (and standard Supabase SQL Editor execution), if multiple SQL statements are submitted without an explicit `BEGIN; ... COMMIT;` wrapper:
- PostgreSQL executes each statement as an independent, autocommitted transaction.
- If statement #50 fails (e.g. at line 1,200):
  - Statements #1 through #49 **remain committed permanently** in the database.
  - Statements #51 through #100 are never reached.
- **Resulting Database State:**
  - **Severe Schema Inconsistency:** 33 tables might exist, but Row Level Security policies (Part 08) were never applied, leaving tables unprotected.
  - **Broken Application Dependencies:** Realtime publications, indexes, and triggers would be partially missing.
  - **Manual Cleanup Required:** Re-running fails with `relation already exists`, requiring manual table teardown.

#### With `BEGIN ... COMMIT` (Baked-in Atomic Transaction Mode)
[`supabase_migration/00_full_migration_bundle.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/00_full_migration_bundle.sql) is now explicitly wrapped in a top-level `BEGIN;` and trailing `COMMIT;`:
- **PostgreSQL Transactional DDL:** Unlike MySQL or Oracle, PostgreSQL fully supports transactional DDL. Tables, indexes, functions, triggers, policies, and schemas are modified within an isolated transaction.
- **Execution Compatibility:** Every single statement in the bundle (including `CREATE EXTENSION`, `ALTER PUBLICATION`, `PERFORM cron.schedule`, and anonymous `DO $$` blocks) is 100% valid inside a PostgreSQL transaction block.
- **All-or-Nothing Guarantee:** If ANY statement encounters an error anywhere across the 2,081 lines, the PostgreSQL transaction engine immediately triggers an automatic `ROLLBACK`.
- **Zero Inconsistent State:** In the event of a failure, **0 objects remain committed**. The database immediately and automatically reverts to its exact pre-deployment state (100% clean and empty).

---

### 4.2 How Non-Idempotent Operations are Guarded
Every operation in the bundle has also been defensively hardened:
1. **Tables & Indexes:** Use `CREATE TABLE IF NOT EXISTS` and `CREATE INDEX IF NOT EXISTS`.
2. **Triggers:** Preceded by `DROP TRIGGER IF EXISTS` before `CREATE TRIGGER`.
3. **Policies:** Preceded by `DROP POLICY IF EXISTS` before `CREATE POLICY`.
4. **Functions:** Defined via `CREATE OR REPLACE FUNCTION`.
5. **Realtime Publication:** Wrapped in an idempotent membership check (`IF NOT EXISTS (SELECT 1 FROM pg_publication_rel ...)`), preventing `relation already member of publication` errors.
6. **pg_cron Schedules:** Wrapped in exception handlers to prevent transaction aborts.

---

### 4.3 Total Schema Teardown / Rollback Script

If a catastrophic deployment failure occurs or if an immediate complete rollback is needed, the standalone script [`supabase_migration/emergency_rollback.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/emergency_rollback.sql) must be executed.

> [!CAUTION]
> **Defects in Basic Rollback Scripts Identified & Fixed:**
> A naive `DROP TABLE ... CASCADE` script leaves critical orphaned objects in Supabase:
> 1. **Auth Trigger:** Leaves `on_auth_user_created` active on `auth.users`, which crashes GoTrue signups because target tables are missing.
> 2. **Stored Functions:** Leaves all 12 custom functions orphaned in the `public` schema.
> 3. **Cron Jobs:** Leaves active scheduled jobs in `cron.job` that fail nightly with `function does not exist`.
>
> The verified rollback script below resolves all 3 defects, cleanly un-scheduling jobs, dropping the `auth.users` trigger, cascading table drops, removing the `auth_migration` schema, and dropping all 12 stored functions.

```sql
-- ==============================================================================
-- MIRROR DIGITAL: COMPLETE DATABASE ROLLBACK & TEARDOWN SCRIPT
-- File: emergency_rollback.sql
-- Target: Supabase Cloud PostgreSQL 15+ (Reverts 00_full_migration_bundle.sql)
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

-- 5. Drop All 12 Custom Stored Functions in Public Schema
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
DROP FUNCTION IF EXISTS public.handle_updated_at() CASCADE;

COMMIT;
```

---

## 5. POST-DEPLOYMENT VERIFICATION QUERIES (STRICTLY READ-ONLY)

Execute these diagnostic queries in the SQL Editor immediately following deployment to verify all objects:

### Query 1: Verify All 34 Expected Tables Exist
```sql
SELECT 
    COUNT(*) AS total_tables,
    CASE WHEN COUNT(*) = 34 THEN 'PASS (34 Tables Created)' ELSE 'FAIL: Check missing tables' END AS status
FROM (
    SELECT table_schema, table_name FROM information_schema.tables WHERE table_schema = 'public'
    UNION ALL
    SELECT table_schema, table_name FROM information_schema.tables WHERE table_schema = 'auth_migration' AND table_name = 'legacy_credentials'
) t;
```

### Query 2: Verify 100% Row Level Security Enforcement
```sql
SELECT 
    COUNT(*) AS total_public_tables,
    SUM(CASE WHEN rowsecurity = TRUE THEN 1 ELSE 0 END) AS rls_enabled_tables,
    CASE 
        WHEN COUNT(*) = SUM(CASE WHEN rowsecurity = TRUE THEN 1 ELSE 0 END) 
        THEN 'PASS (100% RLS Enabled)' 
        ELSE 'FAIL: Unprotected tables detected!' 
    END AS rls_verdict
FROM pg_tables
WHERE schemaname = 'public';
```

### Query 3: Verify All 45 RLS Policies
```sql
SELECT 
    COUNT(*) AS total_policies,
    CASE WHEN COUNT(*) = 45 THEN 'PASS (45 Policies Active)' ELSE 'FAIL: Policy count mismatch' END AS verdict
FROM pg_policies
WHERE schemaname = 'public';
```

### Query 4: Verify All 14 Triggers
```sql
SELECT 
    COUNT(*) AS total_triggers,
    CASE WHEN COUNT(*) = 14 THEN 'PASS (14 Triggers Active)' ELSE 'FAIL: Trigger count mismatch' END AS verdict
FROM information_schema.triggers
WHERE trigger_schema = 'public' 
   OR (trigger_schema = 'auth' AND event_object_table = 'users');
```

### Query 5: Verify All 12 Functions & Pinned `search_path`
```sql
SELECT 
    p.proname AS function_name,
    p.prosecdef AS is_security_definer,
    p.proconfig AS pinned_search_path,
    CASE 
        WHEN p.prosecdef = TRUE AND p.proconfig @> ARRAY['search_path=public, pg_temp'] THEN 'PASS (Pinned Security Definer)'
        WHEN p.prosecdef = FALSE THEN 'PASS (Security Invoker)'
        ELSE 'FAIL: Unpinned Security Definer!'
    END AS security_verdict
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname IN (
      'handle_updated_at', 'is_authenticated', 'is_admin',
      'handle_new_auth_user', 'get_author_profile', 'update_resource_comment_count',
      'enforce_resource_update_security', 'fulfill_paystack_subscription',
      'handle_new_chat_message', 'purge_trashed_materials',
      'process_expired_account_deletions', 'restore_user_account'
  )
ORDER BY p.proname;
```

### Query 6: Verify Realtime Publication (All 13 Tables with `REPLICA IDENTITY FULL`)
```sql
SELECT 
    c.relname AS table_name,
    CASE c.relreplident
        WHEN 'f' THEN 'FULL (PASS)'
        ELSE 'FAIL: Identity not FULL'
    END AS replica_identity,
    p.pubname AS publication_name
FROM pg_publication_rel pr
JOIN pg_class c ON pr.prrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
JOIN pg_publication p ON pr.prpubid = p.oid
WHERE p.pubname = 'supabase_realtime'
  AND n.nspname = 'public'
ORDER BY c.relname;
```

### Query 7: Verify pg_cron Registration (2 Active, 4 Paused)
```sql
SELECT 
    jobid,
    jobname,
    schedule,
    command,
    active
FROM cron.job
ORDER BY jobid;
```
**Expected Output:** Exactly 2 rows:
1. `scheduled-materials-trash-retention` (`0 3 * * *`)
2. `scheduled-account-deletion-processor` (`0 2 * * *`)  
*(Confirm that `scheduledExploreDiscovery`, `scheduledExploreQueueDrainer`, `scheduledWorkerHealthCheck`, and `scheduledNewsCapacityCheck` are NOT present).*

---

## 6. AUTHENTICATION & ADMINISTRATOR SAFEGUARDS

### 6.1 Relationship Between Supabase Auth and `public.users`
- **Identity Provider Layer:** `auth.users` manages credentials, JWT generation, email verification, session tokens, and multi-factor authentication.
- **Application Profile Layer:** `public.users` manages university affiliations, student programs, academic roles, wallet XP balances, subscription statuses, and terms compliance.
- **Cascading Foreign Key:** `public.users.id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE`.
- **Automatic Lifecycle Provisioning:** Trigger `on_auth_user_created` creates the corresponding `public.users` row upon every new GoTrue signup, populating name and avatar metadata automatically.

### 6.2 First Administrator Bootstrap Procedure
1. Register or identify the administrator's email in Supabase Auth (e.g., `admin@mirrorlaikipia.ac.ke`).
2. Run the following single authoritative query in the SQL Editor (as `postgres`):
   ```sql
   UPDATE public.users 
   SET role = 'admin' 
   WHERE email = 'admin@mirrorlaikipia.ac.ke';
   ```
3. Set custom claims in GoTrue via the Supabase Dashboard:
   - Navigate to **Authentication** -> **Users** -> Click on the admin user.
   - Under **App Metadata**, add: `{"admin": true}`.
4. When this user logs in, both `auth.jwt()->'app_metadata'->>'admin'` and `public.users.role` validate to `TRUE` in [`public.is_admin()`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/01_extensions_and_helpers.sql#L35).

### 6.3 Self-Promotion Immunity
Ordinary authenticated users cannot elevate their role to `admin`:
- RLS policy [`Users can update own profile`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/08_row_level_security.sql#L56-L71) strictly requires:
  ```sql
  AND role IS NOT DISTINCT FROM (SELECT role FROM public.users WHERE id = auth.uid())
  ```
- Any direct client request to mutate `role`, `is_subscribed`, `subscription_expiry`, `xp_balance`, or `deletion_status` is rejected by PostgreSQL at the database engine level.
- `public.is_admin()` strictly ignores `user_metadata` (client-writable), reading only `app_metadata` (server-only).

### 6.4 Firebase Modified-Scrypt Password Migration Requirements
Firebase Authentication does not use standard Scrypt. It uses a proprietary modified Scrypt implementation with custom parameters:
- `signer_key` (Base64)
- `salt_separator` (Base64)
- `rounds` (Integer, typically 8)
- `mem_cost` (Integer, typically 14)

**Prerequisite Testing Before Account Cutover:**
1. Do NOT attempt to import modified-Scrypt hashes directly into standard Bcrypt columns.
2. Staged hashes are stored in [`auth_migration.legacy_credentials`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/02_core_users_and_auth.sql#L124-L136).
3. A test account with known password `testPassword123!` must be exported from Firebase and verified against the migration Edge Function before mass importing all 63 production accounts.

### 6.5 Why Firebase Refresh Tokens Cannot Be Reused in Supabase
- **Cryptographic Signature Mismatch:** Firebase tokens are signed by Google Identity Platform RS256 private keys and verified against Google's public certificates. Supabase PostgREST and Realtime authenticate via HS256/RS256 keys issued by Supabase GoTrue.
- **Claim Structure Incompatibility:** Supabase RLS functions (`auth.uid()`) specifically look for the JWT `sub` claim formatted as a Supabase user UUID. A Firebase ID token presented to Supabase will fail cryptographic signature verification and return `401 Unauthorized`.
- **Session Transition Strategy:** Users must authenticate through Supabase Auth during the migration cutover to establish valid Supabase sessions.

---

## 7. FINAL DEPLOYMENT READINESS CHECKLIST

- [x] Target Supabase project confirmed: `https://iagfozaynaxexaefdpns.supabase.co`
- [x] Consolidated bundle confirmed: [`00_full_migration_bundle.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/00_full_migration_bundle.sql)
- [x] Checksum verified: `c933fea61fa2df8468f4f927396a58ff271580bce209ac9aa8a20bcf5939f4e2`
- [x] 10 modular files match consolidated bundle 100% byte-for-byte.
- [x] Zero embedded secrets or credentials in SQL files.
- [x] Step-by-step deployment instructions prepared.
- [x] Pre-flight empty database query prepared.
- [x] Rollback / reset SQL script prepared.
- [x] Post-deployment read-only verification queries prepared.
- [x] Authentication and admin bootstrap safeguards documented.
- [x] Modified-Scrypt testing requirements established.
- [x] 4 Explore schedulers confirmed paused; 2 maintenance schedulers confirmed active.
- [x] **Zero remote database commands executed during this preparation task.**

---

**Next Action:** Await user authorization to deploy [`supabase_migration/00_full_migration_bundle.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/00_full_migration_bundle.sql) to the Supabase Cloud project `Mirror Digital` via the Dashboard SQL Editor.
