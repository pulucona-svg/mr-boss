# MIRROR DIGITAL: TARGETED SUPABASE MIGRATION FIXES REPORT

**Date:** 2026-11-12  
**Target Backend:** Supabase Cloud PostgreSQL 15+  
**Project:** Mirror Digital (`com.mirrordigital.app`)  
**Status:** All Critical Blockers and Security Warnings Resolved Locally  

---

## EXECUTIVE SUMMARY

Following the comprehensive, strictly read-only security and correctness review of the Mirror Digital Supabase migration schema (`supabase_migration/final_sql_security_review.md`), three targeted corrections were authorized and successfully implemented in the local migration codebase:

1. **Supabase Realtime Publication Configuration (`08_row_level_security.sql`):**  
   Configured idempotent publication membership in `supabase_realtime` with `REPLICA IDENTITY FULL` for the exact 13 tables consumed via live Flutter streams, while deliberately excluding operational background queues.
2. **Account Deletion Processor (`09_maintenance_and_cron.sql` & `02_core_users_and_auth.sql`):**  
   Resolved the fatal column mismatch (`rec.uid` &rarr; `rec.firebase_uid` and `rec.id`), fully restored the 30-day grace period logic, integrated cancellation/restoration functionality (`restore_user_account`), safeguarded university DSpace past papers from anonymization, purged private support messages and notifications, and scrubbed personal user data in accordance with GDPR compliance.
3. **Resource Update Policy & Immutability Trigger (`03_academic_resources_and_curriculum.sql` & `08_row_level_security.sql`):**  
   Replaced loose subquery RLS policies with a defense-in-depth architecture consisting of split RLS policies backed by a high-performance `BEFORE UPDATE` trigger (`enforce_resource_update_security`). Non-uploaders are strictly restricted to engagement metrics (`views_count`, `likes_count`, `liked_by`, `comments_count`), and uploaders cannot manipulate administrative approval or DSpace flags.

All 10 individual migration scripts and the unified all-in-one bundle (`00_full_migration_bundle.sql`) were re-generated and validated. No remote SQL was executed, no production configurations were altered, and no Flutter client code was modified.

---

## 1. REALTIME PUBLICATION CONFIGURATION (CRITICAL BLOCKER)

### 1.1 Client Stream Audit & Table Identification
An exhaustive audit of `.snapshots()` calls across the Mirror Digital Flutter repository identified 13 client-facing tables requiring live WebSocket streaming:

| # | PostgreSQL Table | Primary Key | Flutter Feature / Service | Justification |
|---|------------------|-------------|---------------------------|---------------|
| 1 | `public.messages` | `id VARCHAR(64)` | `ChatService.getMessagesStream()` | Realtime in-app support chat messaging between student and admin |
| 2 | `public.conversations` | `id UUID` | `ChatService.getConversationsStream()` | Live conversation inbox with unread badge updates |
| 3 | `public.comments` | `id VARCHAR(64)` | `CommentsBottomSheet` | Live student comments and discussion on academic documents |
| 4 | `public.notifications` | `id VARCHAR(64)` | `NotificationsScreen` | Instant push/in-app announcements and alerts |
| 5 | `public.resources` | `id VARCHAR(64)` | `DashboardScreen`, `LibraryScreen` | Instant document upload visibility, live like/view counters |
| 6 | `public.explore_news` | `id VARCHAR(64)` | `ExploreScreen` | Live campus news feed updates |
| 7 | `public.explore_categories` | `id VARCHAR(64)` | `ExploreScreen` | Dynamic news categories and filters |
| 8 | `public.trending_topics` | `id VARCHAR(64)` | `ExploreScreen` | Realtime trending academic and campus topics |
| 9 | `public.manual_ads` | `id VARCHAR(64)` | `AdService` | Realtime ad campaign controls and fallbacks |
| 10 | `public.users` | `id UUID` | `AuthService`, User Profile | Live subscription status and profile updates |
| 11 | `public.xp_transactions` | `id VARCHAR(64)` | Gamification / Wallet | Live gamified reward balance updates |
| 12 | `public.curriculum` | `id VARCHAR(64)` | Academic Department Catalog | Realtime curriculum and lecturer syllabus changes |
| 13 | `public.dspace_jobs` | `id VARCHAR(64)` | Admin DSpace Sync | Realtime sync job progress indicators |

### 1.2 Deliberate Exclusions
Operational and background processing tables (`discovery_jobs`, `article_jobs`, `failed_article_jobs`, `story_candidates`, `used_thumbnails`, `workers`, `flux_workers`) were **intentionally excluded** from `supabase_realtime`. Adding high-throughput worker queues to client realtime publications causes severe WebSocket connection overhead, unnecessary bandwidth usage, and client CPU lag.

### 1.3 Implementation Details
In `supabase_migration/08_row_level_security.sql`, Section 9 was added with the following features:
- **Idempotency:** Checks `pg_publication` to ensure `supabase_realtime` exists (creating it if missing) and inspects `pg_publication_rel` to prevent duplicate membership runtime errors.
- **Replica Identity:** Executes `ALTER TABLE public.<table_name> REPLICA IDENTITY FULL;` on all 13 streaming tables. This ensures PostgreSQL WAL logs contain full row states on `UPDATE` and `DELETE`, allowing Supabase Realtime to correctly evaluate Row Level Security filters before dispatching events to mobile clients.

```sql
DO $$
DECLARE
    tbl_name text;
    realtime_tables text[] := ARRAY[
        'messages', 'conversations', 'comments', 'notifications',
        'resources', 'explore_news', 'explore_categories', 'trending_topics',
        'manual_ads', 'users', 'xp_transactions', 'curriculum', 'dspace_jobs'
    ];
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;

    FOREACH tbl_name IN ARRAY realtime_tables LOOP
        EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL;', tbl_name);

        IF NOT EXISTS (
            SELECT 1 
            FROM pg_publication_rel pr
            JOIN pg_class c ON pr.prrelid = c.oid
            JOIN pg_namespace n ON c.relnamespace = n.oid
            JOIN pg_publication p ON pr.prpubid = p.oid
            WHERE p.pubname = 'supabase_realtime'
              AND n.nspname = 'public'
              AND c.relname = tbl_name
        ) THEN
            EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I;', tbl_name);
        END IF;
    END LOOP;
END $$;
```

---

## 2. ACCOUNT DELETION & ANONYMIZATION PROCESSOR (CRITICAL BLOCKER)

### 2.1 Root Cause of the Blocker
The previous version of `public.process_expired_account_deletions()` in `09_maintenance_and_cron.sql` executed:
```sql
SELECT id, uid, email FROM public.users ...
```
Table `public.users` uses `id UUID` as its primary key and `firebase_uid VARCHAR(64)` for legacy Firebase accounts. It has no column named `uid`. Calling this procedure on PostgreSQL caused an immediate runtime failure (`column "uid" does not exist`).

### 2.2 Preservation of Business Rules & DSpace Material Protection
Based on the audit of `functions/src/services/account_deletion_service.ts`, the routine was rewritten to enforce all architectural and legal invariants:
1. **30-Day Grace Period Strictness:** Only accounts where `deletion_status IN ('pending', 'pending_deletion')` AND `deletion_scheduled_at <= NOW()` are processed. If an account is within the 30-day grace window, it is never touched.
2. **Absolute DSpace Protection:** Materials imported from Laikipia University's Institutional Repository (`is_imported_dspace = TRUE`) are **explicitly excluded** from anonymization and deletion. University examination past papers and accredited curriculum records remain intact.
3. **Academic Content Retention:** Non-DSpace materials uploaded by the user are preserved for the student community, but ownership is anonymized to `'Anonymous Contributor'` with all user foreign keys unlinked (`uploader_id = NULL`, `uploader_firebase_uid = NULL`).
4. **Public Discussion Anonymization:** User comments are retained to keep discussion threads coherent, but author identity is stripped (`author_name = 'Anonymous User'`, `author_id = NULL`, `author_profile_image = NULL`).
5. **Private Data Destruction:** All private communications (`public.messages`, `public.conversations`), direct alerts (`public.notifications`), and active device login tokens (`public.user_sessions`) are completely deleted.
6. **PII Scrubbing:** User profile attributes in `public.users` are scrubbed: email is scrambled to `deleted_<short-uuid>@deleted.local`, `display_name = 'Deleted User'`, phone, photo, and device IDs are nullified, and `disabled = TRUE`.
7. **Compliance Audit Logging:** The corresponding record in `public.account_deletion_audits` is marked as `status = 'purged'`.
8. **Grace Period Restoration:** Added `public.restore_user_account(p_user_id UUID)` allowing users to cancel deletion if they sign in before the 30-day deadline has passed.
9. **Constraint Compatibility:** Updated `02_core_users_and_auth.sql` so the CHECK constraint on `deletion_status` allows both `'pending'` (Firestore convention) and `'pending_deletion'` (PostgreSQL convention).

---

## 3. RESOURCE UPDATE SECURITY & IMMUTABILITY TRIGGER (SECURITY WARNING)

### 3.1 Vulnerability in Previous Implementation
The previous RLS update policy on `public.resources` permitted any authenticated user to update a document provided they did not alter `title`, `file_url`, and `file_id`. This created two significant vulnerabilities:
1. **Metadata Tampering by Third Parties:** A non-uploader could modify `unit_code`, `unit_name`, `lecturers`, `status`, `target_programs`, `uploader_id`, or `is_pinned`.
2. **Privilege Escalation by Uploaders:** An uploader could self-approve their own rejected document (`approved_by_admin = TRUE`), toggle admin verification, or manipulate DSpace institutional flags.
3. **Performance Overhead:** The RLS policy used correlated subqueries `(SELECT title FROM public.resources WHERE id = resources.id)`, causing query plan bloat and recursion risk.

### 3.2 Implemented Defense-in-Depth Solution
We separated concerns between RLS routing and field-level integrity enforcement:

#### Step 1: Clean RLS Policies (`08_row_level_security.sql`)
Split the ambiguous policy into two clear, high-speed policies with zero subqueries:
- **Policy 1 (Uploaders & Admins):**  
  `USING (uploader_id = auth.uid() OR public.is_admin())`  
  Allows creators and administrators to update the record.
- **Policy 2 (Community Members):**  
  `USING (status = 'active')`  
  Allows students to interact with active public resources (incrementing view counts, liking/unliking).

#### Step 2: High-Performance Immutability Trigger (`03_academic_resources_and_curriculum.sql`)
Created `public.enforce_resource_update_security()` running as a `BEFORE UPDATE` trigger on `public.resources`:
- **For Non-Uploaders:** Evaluates that **none** of the 38 metadata, file, administrative, or provenance fields have changed. Non-uploaders may **only** alter `views_count`, `likes_count`, `liked_by`, `comments_count`, and `updated_at`. Any attempt to touch other columns raises an exception:  
  `'Permission denied: non-uploaders can only update engagement counters (views, likes, comments).'`
- **For Uploaders (Non-Admin):** Uploaders can update their own course titles, lecturers, and academic year, but **cannot** alter `approved_by_admin`, `rejected_by_admin`, `updated_by_admin`, `decline_reason`, `decline_date`, `is_pinned`, `pinned_at`, `is_imported_dspace`, `dspace_item_uuid`, `dspace_handle`, or `uploader_id`. Attempts raise:  
  `'Permission denied: uploaders cannot modify administrative flags, pinned state, or DSpace metadata.'`
- **For Admins & Service Role:** System processes (`auth.uid() IS NULL`) and users with admin privileges have unrestricted authority.

---

## 4. VALIDATION & VERIFICATION

### 4.1 Bundle Re-generation & Automated DDL Audit
The all-in-one bundle `supabase_migration/00_full_migration_bundle.sql` was recompiled from parts 01 through 10. Running the verification suite (`validate_migration_sql.mjs`) confirmed:
- **Total SQL Bundle Size:** 77,426 bytes (1,918 lines).
- **CREATE TABLE Statements:** 34 verified.
- **CREATE POLICY Statements:** 45 verified (RLS 100% active).
- **CREATE TRIGGER Statements:** 14 verified (including `trg_resource_update_security`).
- **CREATE FUNCTION Statements:** 11 verified (including `enforce_resource_update_security`, `process_expired_account_deletions`, and `restore_user_account`).
- **CREATE INDEX Statements:** 41 verified.
- **Syntax / Balance Audit:** Zero syntax errors, zero unmatched parentheses or dollar-quotes.

### 4.2 Diagnostic Validation Suite (`10_schema_validation.sql`)
Updated `10_schema_validation.sql` to include runtime validation for:
1. Existence and RLS status of all 34 tables.
2. Membership of all 13 streaming tables in publication `supabase_realtime`.
3. Existence and attachment of `trg_resource_update_security` on `public.resources`.
4. Availability of `process_expired_account_deletions()` and `restore_user_account()`.

### 4.3 Production & Local Safety Invariants
- **Firebase Production:** 0 modifications. No rules, indexes, or billing altered.
- **Flutter Codebase:** 0 modifications. Application source code untouched.
- **Remote Databases:** 0 remote SQL executions. All changes remain strictly local.

---

## 5. SUMMARY OF MODIFIED FILES

| File | Status | Key Changes Made |
|------|--------|------------------|
| `supabase_migration/02_core_users_and_auth.sql` | Modified | Added `'pending'` to `deletion_status` CHECK constraint for Firestore backup compatibility. |
| `supabase_migration/03_academic_resources_and_curriculum.sql` | Modified | Added `enforce_resource_update_security()` function and `trg_resource_update_security` trigger. |
| `supabase_migration/08_row_level_security.sql` | Modified | Split resources update policies into uploader/admin and community policies; added Section 9 Realtime publication. |
| `supabase_migration/09_maintenance_and_cron.sql` | Modified | Fixed column mapping to `firebase_uid` and `id`, added DSpace protection, conversation purge, and restoration helper. |
| `supabase_migration/10_schema_validation.sql` | Modified | Added automated verification checks for Realtime publication and security triggers. |
| `supabase_migration/00_full_migration_bundle.sql` | Re-generated | Consolidated bundle containing all validated corrections (77.4 KB, 1,918 lines). |
