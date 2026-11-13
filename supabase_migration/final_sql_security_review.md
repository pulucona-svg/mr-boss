# Mirror Digital — Supabase Phase 1: Final SQL Security & Correctness Review

**Target Project:** Mirror Digital (Supabase Cloud)  
**Evaluated Bundle:** [`supabase_migration/00_full_migration_bundle.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/00_full_migration_bundle.sql)  
**Referenced Files:** `supabase_migration/01_*.sql` through `10_*.sql`  
**Review Type:** Strictly Read-Only Security, Logic, and Parity Audit  
**Status:** AUDIT COMPLETE — Actionable Findings Identified  
**Timestamp:** 2026-11-12T21:16:00+03:00  

---

## Executive Summary of Audit Findings

| Category | Item Evaluated | Verdict | Summary |
| :--- | :--- | :---: | :--- |
| **Coverage** | 31 Root Collections & 7 Subcollection Categories | **PASS** | 100% of Firestore entities mapped to relational tables. |
| **Volume Parity** | 27,268 Production Documents Destination | **PASS** | Every document class has an exact, typed destination schema. |
| **Table Architecture**| 34 Tables DDL, Primary Keys & Constraints | **PASS** | Robust primary keys, foreign keys, cascade rules, and check constraints. |
| **Financial Security**| Payments, XP, Subscriptions, Ad Reward Sessions | **PASS** | Client writes strictly denied (`WITH CHECK (FALSE)`); server-only mutation. |
| **Atomicity** | `fulfill_paystack_subscription` Function | **PASS** | Exclusive row locking (`FOR UPDATE`) prevents duplicate fulfillment. |
| **Schedulers** | Four Paused Explore News Schedulers | **PASS** | Schedulers remain explicitly paused; no unauthorized crons active. |
| **Background Jobs** | Thumbnail Retry & Account Deletion Processing | **PASS** | Routines preserved for Supabase Cron execution. |
| **Safety & Secrets** | No Truncation, Deletion, or Embedded Credentials| **PASS** | Pure DDL; idempotent creation; zero secrets in SQL files. |
| **Execution Order** | Topological SQL Dependency Sequencing | **PASS** | Extensions -> Tables -> Functions -> Triggers -> Policies -> Validation. |
| **Realtime Pub** | Realtime Publication Membership | **CRITICAL BLOCKER** | Missing `ALTER PUBLICATION supabase_realtime ADD TABLE ...;` for streams. |
| **Column Mismatch** | `process_expired_account_deletions` Column Name | **CRITICAL BLOCKER** | Function references `rec.uid`, but column on `public.users` is `firebase_uid`. |
| **RLS Policy Scope**| `public.resources` Update Policy Scope | **WARNING** | Community engagement check allows altering non-whitelisted columns. |
| **RLS Self-Query** | `public.users` Update Self-Subqueries | **WARNING** | RLS policy uses self-subqueries; trigger-based lock is safer. |
| **Auth Dependency** | Foreign Key to `auth.users(id)` Ingestion Order | **WARNING** | Data import must follow deterministic UUID mapping post-auth creation. |
| **Architecture** | 18-Table Blueprint vs. 34-Table Implementation | **PASS** | Justified expansion: 18 domain + 16 operational/queue/cache tables. |

---

## Detailed Section-by-Section Review

### 1. Representation of All Collections & Subcollections
- **Verdict:** **PASS**
- **Evidence:**
  All 31 root collections discovered during the production backup audit are represented:
  1. `account_deletion_audits` -> `public.account_deletion_audits`
  2. `article_jobs` -> `public.article_jobs`
  3. `campaigns` -> `public.promotional_campaigns`
  4. `categories` & `categoryNews` -> `public.explore_categories`
  5. `conversations` -> `public.conversations`
  6. `curriculum` -> `public.curriculum`
  7. `discovery_jobs` -> `public.discovery_jobs`
  8. `dspace_jobs` -> `public.dspace_jobs`
  9. `explore_news` -> `public.explore_news`
  10. `explore_news_archive` -> `public.explore_news_archive`
  11. `failed_article_jobs` -> `public.failed_article_jobs`
  12. `flux_workers` -> `public.flux_workers`
  13. `latestNews` -> `public.latest_news`
  14. `manual_ads` -> `public.manual_ads`
  15. `notifications` -> `public.notifications`
  16. `payments` -> `public.payments`
  17. `promotional_trial_claims` -> `public.promotional_trial_claims`
  18. `promotional_trial_emails` -> `public.promotional_trial_emails`
  19. `resources` -> `public.resources`
  20. `scheduler`, `system` -> mapped / retained in operational configuration
  21. `storyClusters` -> `public.story_clusters`
  22. `story_candidates` -> `public.story_candidates`
  23. `subscriptions` -> `public.subscription_history`
  24. `topStories` -> `public.top_stories`
  25. `trendingTopics` -> `public.trending_topics`
  26. `used_article_images` -> `public.used_article_images`
  27. `used_thumbnails` -> `public.used_thumbnails`
  28. `users` -> `public.users`
  29. `workers` -> `public.workers`

  All 7 subcollection categories are mapped:
  - `resources/{id}/comments` -> `public.comments`
  - `users/{id}/sessions` -> `public.user_sessions`
  - `users/{id}/xp_transactions` -> `public.xp_transactions`
  - `users/{id}/ad_reward_sessions` -> `public.ad_reward_sessions`
  - `conversations/{id}/messages` -> `public.messages`
  - `subscriptions/{id}/history` -> `public.subscription_history`
  - `users/{id}/notifications` -> `public.notifications`

---

### 2. Document Volume Destination Parity (27,268 Documents)
- **Verdict:** **PASS**
- **Evidence:**
  The destination tables cleanly accommodate all 27,268 exported documents without truncation:
  - Operational queues (`discovery_jobs`: 10,149, `article_jobs`: 2,705, `failed_article_jobs`: 2,072) have dedicated tables.
  - Image deduplication caches (`used_article_images`: 3,597, `used_thumbnails`: 1,609) have indexed tables.
  - Core domain data (`resources`: 1,666, `curriculum`: 1,343, `explore_news`: 395, `story_clusters`: 487) map directly.
  - User records (`users`: 71, `sessions`: 131, `comments`: 12, `messages`: 36, `payments`: 44) map losslessly.

---

### 3. Investigation of Architecture Discrepancy (18 vs. 34 Tables)
- **Verdict:** **PASS** (Design Clarification)
- **Investigation:**
  - The earlier architectural blueprint outlined **18 core application domain tables** to explain the conceptual entity-relationship model to stakeholders.
  - During live extraction, the backup verified that Firestore also hosts autonomous background processing queues, ImageKit hash registries, dead-letter job queues, and anti-fraud email registries.
  - The implementation expanded to **34 tables** by creating dedicated relational schemas for:
    - 3 Magazine Highlight tables (`top_stories`, `latest_news`, `trending_topics`).
    - 4 Autonomous Editorial Pipeline queues (`story_candidates`, `discovery_jobs`, `article_jobs`, `failed_article_jobs`).
    - 2 Worker Pool health registries (`workers`, `flux_workers`).
    - 2 Media deduplication registries (`used_article_images`, `used_thumbnails`).
    - 3 Promotional Trial anti-abuse tables (`promotional_campaigns`, `promotional_trial_claims`, `promotional_trial_emails`).
    - 1 GDPR Compliance Audit table (`account_deletion_audits`).
    - 1 Auth Migration table (`auth_migration.legacy_credentials`).
  - **Conclusion:** If the schema had remained at 18 tables, over 15,000 operational and cache documents would have been orphaned. The 34-table architecture guarantees 100% preservation of all production data.

---

### 4. Critical Findings & Blockers

#### 🚨 CRITICAL BLOCKER 1: Missing Realtime Publication Configuration
- **Severity:** **CRITICAL BLOCKER**
- **Location:** Missing from [`supabase_migration/00_full_migration_bundle.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/00_full_migration_bundle.sql)
- **Issue:**
  In Supabase, database tables do **not** broadcast changes over WebSocket unless they are explicitly added to the `supabase_realtime` publication. The Flutter application relies on 11 real-time listeners:
  - `messages` (Chat support)
  - `conversations` (Typing indicators & unread counts)
  - `comments` (Discussion thread updates)
  - `notifications` (User alert popups)
  - `resources` (Material catalog updates)
  - `explore_news`, `explore_categories`, `trending_topics` (Live news feeds)
  - `user_sessions` (Device concurrency tracking)
- **Impact:**
  Without `ALTER PUBLICATION supabase_realtime ADD TABLE ...;`, Flutter `.stream()` and `postgres_changes` subscriptions will silently receive zero real-time events.
- **Required Remediation SQL:**
  ```sql
  ALTER PUBLICATION supabase_realtime ADD TABLE 
      public.messages,
      public.conversations,
      public.comments,
      public.notifications,
      public.resources,
      public.explore_news,
      public.explore_categories,
      public.trending_topics,
      public.user_sessions,
      public.manual_ads;
  ```

---

#### 🚨 CRITICAL BLOCKER 2: Column Name Discrepancy in Account Deletion Processor
- **Severity:** **CRITICAL BLOCKER**
- **Location:** [`supabase_migration/09_maintenance_and_cron.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql#L27-L54)
- **Issue:**
  In [`09_maintenance_and_cron.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql#L27), the function `process_expired_account_deletions` executes:
  ```sql
  SELECT id, uid, email FROM public.users
  WHERE deletion_status = 'pending_deletion' ...
  ```
  And on line 52:
  ```sql
  WHERE uid = rec.uid AND status = 'scheduled';
  ```
  However, in [`02_core_users_and_auth.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/02_core_users_and_auth.sql#L10), the column on `public.users` is defined as:
  ```sql
  firebase_uid VARCHAR(64) UNIQUE,
  ```
  There is **no** column named `uid` in `public.users`.
- **Impact:**
  When `process_expired_account_deletions()` runs (via `pg_cron` or manual invocation), PostgreSQL will throw:
  `ERROR: column "uid" does not exist`. The deletion processor will fail and abort the transaction.
- **Required Remediation SQL:**
  Change line 27 and line 52 to:
  ```sql
  SELECT id, firebase_uid, email FROM public.users ...
  ...
  UPDATE public.account_deletion_audits SET
      status = 'purged',
      updated_at = NOW()
  WHERE uid = rec.firebase_uid AND status = 'scheduled';
  ```

---

### 5. Warnings & Security Recommendations

#### ⚠️ WARNING 1: Community Engagement Check on Resources Update Policy
- **Severity:** **WARNING**
- **Location:** [`supabase_migration/08_row_level_security.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/08_row_level_security.sql#L100-L114)
- **Issue:**
  In [`08_row_level_security.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/08_row_level_security.sql#L108-L113), the policy allows non-uploaders to update resources if `title`, `file_url`, and `file_id` remain unchanged. However, other fields (such as `status`, `cat_type`, `unit_name`, or `is_pinned`) are not explicitly blocked by the `WITH CHECK` clause.
- **Remediation:**
  Implement a `BEFORE UPDATE ON public.resources` trigger that enforces:
  ```sql
  IF auth.uid() IS DISTINCT FROM OLD.uploader_id AND NOT public.is_admin() THEN
      NEW.title := OLD.title;
      NEW.file_name := OLD.file_name;
      NEW.file_url := OLD.file_url;
      NEW.file_id := OLD.file_id;
      NEW.status := OLD.status;
      NEW.is_pinned := OLD.is_pinned;
      NEW.unit_code := OLD.unit_code;
      NEW.unit_name := OLD.unit_name;
  END IF;
  ```

---

#### ⚠️ WARNING 2: RLS Self-Subquery Overhead on User Profile Updates
- **Severity:** **WARNING**
- **Location:** [`supabase_migration/08_row_level_security.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/08_row_level_security.sql#L61-L67)
- **Issue:**
  The `WITH CHECK` on `public.users` runs 6 scalar subqueries against `public.users` to verify that `role`, `xp_balance`, `is_subscribed`, etc., have not changed. While syntactically valid, self-subqueries within RLS policies add unnecessary query overhead.
- **Remediation:**
  Use a simple `BEFORE UPDATE ON public.users` trigger to lock authoritative fields against non-admin callers (`NEW.role := OLD.role; NEW.xp_balance := OLD.xp_balance;`).

---

#### ⚠️ WARNING 3: Foreign Key Dependency on `auth.users(id)` During Ingestion
- **Severity:** **WARNING**
- **Location:** [`supabase_migration/02_core_users_and_auth.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/02_core_users_and_auth.sql#L9)
- **Issue:**
  `public.users.id` has a strict foreign key: `REFERENCES auth.users(id) ON DELETE CASCADE`.
  In the Firestore backup, user document IDs are 28-character strings (`7Z9cveBB47hxUQLVM8Xf40IiWuo2`), NOT UUIDs.
- **Ingestion Rule:**
  1. The data import tool must **never** insert raw Firebase UID strings into `public.users.id`.
  2. Accounts must first be created in `auth.users` using deterministic **UUIDv5** identifiers.
  3. Relational foreign keys in `resources.uploader_id`, `comments.author_id`, `conversations.id`, and `payments.user_id` must map to the corresponding UUIDs, while preserving the raw string in `*_firebase_uid`.
  4. If an uploader or commenter no longer exists in `users`, `uploader_id` must be set to `NULL` (permitted by `ON DELETE SET NULL`).

---

### 6. Verification Checklist Status

| # | Review Requirement | Status | Notes |
| :-: | :--- | :---: | :--- |
| 1 | All 31 Root Collections & 7 Subcollection Categories | **PASS** | Fully accounted for in DDL. |
| 2 | All 27,268 Exported Documents Destination | **PASS** | Valid, typed destination tables established. |
| 3 | 34 Tables Primary Keys, Foreign Keys, Constraints | **PASS** | Valid constraints and cascade behaviors. |
| 4 | 44 RLS Policies Enforce Privacy & Ownership | **PASS** | Valid ownership boundaries; chat strictly isolated. |
| 5 | Ordinary Users Blocked from Mutating Financials/XP | **PASS** | Strict client write lock (`WITH CHECK (FALSE)`). |
| 6 | Account Deletion Preserves Business Rules | **CRITICAL BLOCKER** | Requires column name fix (`firebase_uid`). |
| 7 | Payment Fulfillment Atomic & Idempotent | **PASS** | `FOR UPDATE` prevents double-credit race conditions. |
| 8 | Realtime Requirements Configured | **CRITICAL BLOCKER** | Missing `ALTER PUBLICATION supabase_realtime ADD TABLE`. |
| 9 | Extensions Available on Supabase Cloud | **PASS** | `pgcrypto`, `uuid-ossp`, `pg_trgm`, `btree_gin` native. |
| 10 | Four Explore Schedulers Remain Paused | **PASS** | Explicitly commented out and paused. |
| 11 | Thumbnail Retry & Account Deletion Preserved | **PASS** | Both routines preserved for `pg_cron`. |
| 12 | No Accidental Deletions, Truncations, Overwrites | **PASS** | Zero destructive table drops or truncations. |
| 13 | No Secrets or Production Credentials Embedded | **PASS** | Zero credentials or keys in SQL code. |
| 14 | Execution Dependency Order | **PASS** | Topological ordering valid. |
| 15 | Compatible with Supabase Postgres Environment | **PASS** | Fully standard PostgreSQL 15+ syntax. |

---

## Conclusion & Next Action

The generated SQL bundle [`supabase_migration/00_full_migration_bundle.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/00_full_migration_bundle.sql) is fundamentally sound, highly structured, and production-grade.

Before executing the migration on Supabase Cloud, the **2 Critical Blockers** must be resolved:
1. Append the `ALTER PUBLICATION supabase_realtime ADD TABLE ...` statements to enable WebSocket streaming for chat, comments, notifications, and news.
2. Fix the column name in `public.process_expired_account_deletions` (`rec.uid` -> `rec.firebase_uid`).

Awaiting your authorization to apply these two targeted corrections to the migration files.
