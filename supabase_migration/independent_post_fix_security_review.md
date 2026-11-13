# Mirror Digital — Independent Post-Fix Security Verification & Architectural Review

**Target Backend:** Supabase Cloud PostgreSQL 15+  
**Target Project:** Mirror Digital (`com.mirrordigital.app`)  
**Evaluated Bundle:** [`supabase_migration/00_full_migration_bundle.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/00_full_migration_bundle.sql)  
**Referenced Module Files:**  
- [`01_extensions_and_helpers.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/01_extensions_and_helpers.sql)  
- [`02_core_users_and_auth.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/02_core_users_and_auth.sql)  
- [`03_academic_resources_and_curriculum.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/03_academic_resources_and_curriculum.sql)  
- [`04_payments_subscriptions_and_xp.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/04_payments_subscriptions_and_xp.sql)  
- [`05_communications_and_ads.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/05_communications_and_ads.sql)  
- [`06_explore_news_and_content_pipeline.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/06_explore_news_and_content_pipeline.sql)  
- [`07_governance_and_integrations.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/07_governance_and_integrations.sql)  
- [`08_row_level_security.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/08_row_level_security.sql)  
- [`09_maintenance_and_cron.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql)  
- [`10_schema_validation.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/10_schema_validation.sql)  
**Historical References:**  
- [`final_sql_security_review.md`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/final_sql_security_review.md)  
- [`targeted_fixes_report.md`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/targeted_fixes_report.md)  
**Audit Mode:** STRICTLY READ-ONLY Independent Verification  
**Date:** 2026-11-12  

---

## EXECUTIVE VERDICT & SCORECARD

| Audit Domain | Scope / Invariant | Status | Primary Observation |
| :--- | :--- | :---: | :--- |
| **Realtime Security** | 13 Streamed Tables & Publication Setup | **PASS** / **WARNING** | Idempotent publication setup works cleanly. Table `users` requires broadcast payload column-masking before mobile cutover. |
| **Account Deletion** | 30-Day Lifecycle, Restoration & DSpace Protection | **PASS** / **WARNING** | Column mismatch resolved. DSpace assets 100% protected. Restoration helper needs caller authorization check. |
| **Resource Security** | Non-Uploader Counter Updates & Admin Protection | **PASS** | Defense-in-depth trigger blocks all metadata tampering and self-approval attempts. |
| **Schema Integrity** | 34 Tables, 45 Policies, 14 Triggers, 11 Functions, 41 Indexes | **PASS** | Complete syntactic and topological ordering parity across all 10 modules. |
| **Business Parity** | Explore Crons Paused, Paystack Locks, XP Integrity | **PASS** | 100% fidelity with original Firebase Cloud Functions business rules. |

### Final Deployment Verdict
```
================================================================================
   FINAL VERDICT: APPROVED FOR EMPTY-PROJECT SCHEMA DEPLOYMENT
================================================================================
The rebuilt SQL bundle (00_full_migration_bundle.sql) has resolved all critical 
blockers and can safely execute from beginning to end on an empty Supabase 
PostgreSQL 15+ database. Specific architectural warnings identified below must 
be applied during Phase 2 before routing live production mobile traffic.
================================================================================
```

---

## SECTION 1: REALTIME SECURITY AUDIT

### 1.1 Comprehensive Audit of the 13 Streamed Tables
Supabase Realtime operates by reading PostgreSQL Write-Ahead Logs (WAL) via logical decoding and filtering events through PostgreSQL Row Level Security (RLS) policies evaluated under the subscriber's JWT identity.

Every table added to `supabase_realtime` in [`08_row_level_security.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/08_row_level_security.sql#L363-L377) was reviewed:

| Table | Flutter Stream Context | Subscribing Roles | Accessible Rows under RLS | DELETE Event Isolation | `REPLICA IDENTITY FULL` Genuine Necessity | Verdict |
| :--- | :--- | :--- | :--- | :--- | :--- | :---: |
| `public.messages` | In-app support chat (`ChatService`) | `authenticated`, `admin` | `conversation_id = auth.uid()` | Isolated: only the conversation owner receives delete events. | **Essential:** Needed so `OLD.conversation_id` is present in WAL for RLS filter evaluation. | **PASS** |
| `public.conversations` | Support inbox badge (`ChatService`) | `authenticated`, `admin` | `id = auth.uid()` | Isolated: only the conversation owner receives delete events. | **Essential:** Needed to evaluate admin and user ownership policies on deletion. | **PASS** |
| `public.notifications` | In-app alerts (`NotificationsScreen`) | `authenticated`, `admin` | `target_type = 'all' OR target_user_id = auth.uid()` | Isolated: target user only. | **Essential:** Needed so `OLD.target_user_id` and `OLD.target_type` are available in WAL. | **PASS** |
| `public.resources` | Feed & Library updates (`DashboardScreen`) | `anon`, `authenticated`, `admin` | `status = 'active' OR uploader_id = auth.uid()` | Active deletions broadcast to feed; pending deletions only to uploader. | **Essential:** Needed so `OLD.status` and `OLD.uploader_id` allow RLS evaluation. | **PASS** |
| `public.comments` | Document discussion sheet | `anon`, `authenticated`, `admin` | Public academic discussion: all rows. | Publicly broadcast to keep UI thread synced. | Recommended: preserves comment author references in audit streams. | **PASS** |
| `public.explore_news` | Live news feed (`ExploreScreen`) | `anon`, `authenticated`, `admin` | `status = 'published'` | Deletions broadcast to update feed. | Recommended: allows real-time removal of retracted articles. | **PASS** |
| `public.explore_categories`| News categories (`ExploreScreen`) | `anon`, `authenticated`, `admin` | `enabled = TRUE` | Deletions broadcast to update category tabs. | Recommended: allows instant UI category refresh. | **PASS** |
| `public.trending_topics`| Trending hashtags (`ExploreScreen`) | `anon`, `authenticated`, `admin` | All rows (public campus tags). | Publicly broadcast to update trending bar. | Standard for public feeds. | **PASS** |
| `public.manual_ads` | Ad rotation (`AdService`) | `anon`, `authenticated`, `admin` | `is_active = TRUE` | Active campaign changes broadcast to ad manager. | Recommended: allows immediate withdrawal of decommissioned ads. | **PASS** |
| `public.users` | Live user profile / wallet sync | `authenticated`, `admin` | **All rows** (via `USING (TRUE)`). | Broadcasts to any subscriber. | **Essential:** Full row logged in WAL. | **WARNING** *(See Finding 1.2)* |
| `public.xp_transactions`| Gamified rewards balance | `authenticated`, `admin` | `user_id = auth.uid()` | Isolated: only transaction owner receives events. | **Essential:** Needed so `OLD.user_id` enables RLS evaluation on deletes/reversals. | **PASS** |
| `public.curriculum` | Units & syllabus updates | `authenticated`, `admin` | All rows (institutional catalog). | Publicly broadcast to update unit lists. | Standard for public catalog. | **PASS** |
| `public.dspace_jobs` | Admin repository sync progress | `admin` only | `public.is_admin() = TRUE` | **Zero rows** for ordinary students; admin only. | **Essential:** Protects admin queue inspection. | **PASS** |

---

### 1.2 Finding 1: `public.users` Realtime Broadcast Privacy Exposure
- **Classification:** **WARNING** (Pre-Traffic Client Privacy Hardening)
- **File & Line:** [`08_row_level_security.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/08_row_level_security.sql#L48-L51), [`08_row_level_security.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/08_row_level_security.sql#L373)
- **Evidence:**  
  [`08_row_level_security.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/08_row_level_security.sql#L48-L51) defines:
  ```sql
  CREATE POLICY "Users can read profiles" ON public.users
      FOR SELECT TO authenticated
      USING (TRUE);
  ```
  Meanwhile, [`08_row_level_security.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/08_row_level_security.sql#L373) registers `users` in `supabase_realtime` and enables `REPLICA IDENTITY FULL`.
- **Failure / Attack Scenario:**  
  When an authenticated client subscribes to Supabase Realtime channel `realtime:public:users`, Supabase evaluates the RLS SELECT policy to check whether the subscriber is authorized to receive row events. Because `USING (TRUE)` evaluates to true for any authenticated user, Supabase Realtime sends the entire updated record to **every connected authenticated subscriber** whenever any user's profile is updated.  
  Because `REPLICA IDENTITY FULL` is enabled, the event payload contains the complete user row, including `phone`, `email`, `active_device_id`, `session_id`, `xp_balance`, `deletion_reason`, and `deletion_survey`.
- **Actual Impact:**  
  While the official Flutter app only subscribes to its own document (`users/{uid}`), an adversary inspecting WebSocket traffic on a physical device could open a channel subscription to `public.users` and intercept private phone numbers, session tokens, and deletion surveys in real time.
- **Can Schema Deployment Safely Proceed?**  
  **YES.** The schema, table constraints, and publication DDL are fully valid and execute cleanly. This is a privacy-hardening recommendation for Phase 2 before mobile client cutover.
- **Recommended Remediation:**  
  Before pointing live Flutter clients to Supabase, implement column-level segregation:
  ```sql
  -- Restrict direct SELECT on public.users to the account owner and admins
  DROP POLICY IF EXISTS "Users can read profiles" ON public.users;
  CREATE POLICY "Users can read own profile" ON public.users
      FOR SELECT TO authenticated
      USING (id = auth.uid() OR public.is_admin());

  -- Provide a sanitized public view for author attribution (used by Library/Comments UI)
  CREATE OR REPLACE VIEW public.user_public_profiles AS
  SELECT id, display_name, username, photo_url, institution, program
  FROM public.users;
  ```

---

### 1.3 Publication Setup Safety Verification
- **Classification:** **PASS**
- **File & Line:** [`08_row_level_security.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/08_row_level_security.sql#L360-L402)
- **Evidence:**  
  The publication block utilizes defensive catalog checks:
  1. `IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN CREATE PUBLICATION supabase_realtime; END IF;` ensures the script runs identically on blank Supabase Cloud instances (where the publication already exists) and bare PostgreSQL instances.
  2. Queries `pg_publication_rel pr JOIN pg_class c ... JOIN pg_namespace n ...` before issuing `ALTER PUBLICATION ... ADD TABLE`. This prevents PostgreSQL runtime error `42710: relation "..." is already member of publication`.
- **Can Schema Deployment Safely Proceed?** **YES.**

---

## SECTION 2: ACCOUNT DELETION & RESTORATION AUDIT

### 2.1 Complete Lifecycle Analysis
The account deletion architecture replaces `functions/src/services/account_deletion_service.ts` with database-level scheduling and stored procedures in [`09_maintenance_and_cron.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql#L23-L157) and [`02_core_users_and_auth.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/02_core_users_and_auth.sql#L46).

```
[ User Requests Deletion ]
           │
           ▼
[ Status: pending_deletion ] ─── (Within 30 Days) ───► [ User Calls restore_user_account() ]
[ Scheduled: NOW() + 30d   ]                                        │
           │                                                        ▼
           │ (Grace Period Expires: <= NOW())              [ Status: active ]
           ▼                                               [ Clears Sched Fields ]
[ pg_cron at 02:00 UTC calls process_expired_account_deletions() ]
           │
           ├─► 1. DSpace Past Papers: EXCLUDED & PRESERVED (is_imported_dspace = FALSE)
           ├─► 2. User Materials: Anonymized to 'Anonymous Contributor'
           ├─► 3. Public Comments: Anonymized to 'Anonymous User'
           ├─► 4. Private Notifications: Hard Deleted
           ├─► 5. Support Chat Messages & Conversations: Hard Deleted
           ├─► 6. Active Device Sessions: Hard Deleted
           ├─► 7. User Profile: Scrubbed & Disabled (deleted_<uuid>@deleted.local)
           └─► 8. Compliance Audit: Marked 'purged' in account_deletion_audits
```

---

### 2.2 Scenario-by-Scenario Logical Stress Testing

#### Scenario A: User schedules deletion and restores on Day 10
- **Trace:** [`restore_user_account(p_user_id)`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql#L114-L157) evaluates `v_status IN ('pending', 'pending_deletion')` (TRUE) and `v_scheduled <= NOW()` (FALSE).
- **Outcome:** Updates `deletion_status = 'active'`, clears scheduling timestamps/reasons, sets `restored_at = NOW()`, and records `status = 'restored'` in [`public.account_deletion_audits`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/07_governance_and_integrations.sql#L38-L50).
- **Verdict:** **PASS.**

#### Scenario B: User restores immediately before the 30-day deadline
- **Trace:** If `v_scheduled` is 1 minute in the future, `v_scheduled <= NOW()` evaluates to FALSE.
- **Outcome:** Restoration succeeds atomically.
- **Verdict:** **PASS.**

#### Scenario C: User attempts restoration after the deadline
- **Trace:** If `v_scheduled <= NOW()` evaluates to TRUE, the procedure raises:
  `EXCEPTION 'Grace period has expired. Account cannot be restored.'`
- **Outcome:** The transaction rolls back. Account is not restored.
- **Verdict:** **PASS.**

#### Scenario D: Another authenticated user attempts to restore someone else's account
- **Trace:** [`restore_user_account(p_user_id)`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql#L114) takes `p_user_id UUID`. It does not verify `auth.uid() = p_user_id` or `public.is_admin()`.
- **Verdict:** **WARNING** *(See Finding 2.3)*.

#### Scenario E: Processor encounters an account already being processed
- **Trace:** [`process_expired_account_deletions()`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql#L27-L111) runs in a single atomic transaction. In the event of overlapping runs, statements are structurally idempotent.
- **Verdict:** **PASS.** Recommended addition of `FOR UPDATE SKIP LOCKED` noted in Section 2.4.

#### Scenario F: Processor runs twice (Idempotency)
- **Trace:** Run 1 updates `public.users.deletion_status = 'anonymized'`. Run 2 queries `WHERE deletion_status IN ('pending', 'pending_deletion')`.
- **Outcome:** Run 2 finds 0 matching rows and returns 0 without side effects.
- **Verdict:** **PASS.**

#### Scenario G: User has DSpace-imported materials
- **Trace:** [`09_maintenance_and_cron.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql#L43-L51) executes:
  ```sql
  UPDATE public.resources SET ...
  WHERE (uploader_id = rec.id OR uploader_firebase_uid = rec.firebase_uid)
    AND is_imported_dspace = FALSE;
  ```
- **Outcome:** Resources where `is_imported_dspace = TRUE` (university exams, past papers) are excluded by the predicate. Uploader ID, DSpace UUID, and handle remain intact.
- **Verdict:** **PASS.**

#### Scenario H: User has uploaded resources, comments, messages, and notifications
- **Trace:**
  - Non-DSpace resources &rarr; anonymized to `'Anonymous Contributor'`, `uploader_id = NULL`. Material remains downloadable for students.
  - Comments &rarr; anonymized to `'Anonymous User'`, `author_id = NULL`. Public discussion threads remain coherent.
  - Notifications &rarr; deleted where `target_user_id = rec.id`.
  - Messages & conversations &rarr; hard deleted where `conversation_id = rec.id` or `sender_id = rec.id`.
  - User sessions &rarr; deleted from `public.user_sessions`.
  - Profile &rarr; scrambled to `deleted_<short_uuid>@deleted.local`.
- **Boundary Verification:** No records belonging to other users are deleted.
- **Verdict:** **PASS.**

---

### 2.3 Finding 2: `restore_user_account()` Missing Caller Authorization Check
- **Classification:** **WARNING** (Authorization Hardening)
- **File & Line:** [`09_maintenance_and_cron.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql#L114-L157)
- **Evidence:**  
  The function signature is:
  ```sql
  CREATE OR REPLACE FUNCTION public.restore_user_account(p_user_id UUID)
  RETURNS BOOLEAN AS $$
  ...
  BEGIN
      SELECT deletion_status, deletion_scheduled_at, firebase_uid
      INTO v_status, v_scheduled, v_firebase_uid
      FROM public.users
      WHERE id = p_user_id;
  ```
  It does not check whether `auth.uid() = p_user_id` or `public.is_admin()`.
- **Failure / Attack Scenario:**  
  Because `restore_user_account` is defined with `SECURITY DEFINER` and granted to `PUBLIC` by default, any authenticated student knowing another user's UUID could invoke `supabase.rpc('restore_user_account', { p_user_id: '<victim_uuid>' })` and cancel that user's pending account deletion without authorization.
- **Actual Impact:**  
  An adversary could harass a departing user by repeatedly preventing their account from completing its scheduled 30-day purge.
- **Can Schema Deployment Safely Proceed?**  
  **YES.** The function is functionally correct and un-deletes accounts as designed. Adding the authorization check is an RPC hardening update.
- **Recommended Remediation:**  
  Add caller validation at the beginning of the function body:
  ```sql
  IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id AND NOT public.is_admin() THEN
      RAISE EXCEPTION 'Permission denied: you can only restore your own account.';
  END IF;
  ```

---

### 2.4 Finding 3: Maintenance Functions Callable by `PUBLIC` Role by Default
- **Classification:** **WARNING** (RPC Hardening)
- **File & Line:** [`09_maintenance_and_cron.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql#L8-L20), [`09_maintenance_and_cron.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql#L26-L111)
- **Evidence:**  
  In PostgreSQL, functions created in `public` have `EXECUTE` granted to `PUBLIC` by default unless explicitly revoked.
- **Failure Scenario:**  
  A mobile client could trigger `supabase.rpc('process_expired_account_deletions')` or `supabase.rpc('purge_trashed_materials')`. While the functions only process legitimately expired rows, unauthenticated or unauthorized triggering causes unnecessary database execution cycles. Furthermore, if a non-admin client invokes `process_expired_account_deletions`, the non-admin's JWT `auth.uid()` causes [`trg_resource_update_security`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/03_academic_resources_and_curriculum.sql#L254-L257) on `public.resources` to reject the internal resource update.
- **Can Schema Deployment Safely Proceed?** **YES.** When invoked via pg_cron (the intended path), `auth.uid()` is NULL and the trigger permits execution.
- **Recommended Remediation:**  
  Explicitly restrict execution to `postgres` and `service_role`:
  ```sql
  REVOKE EXECUTE ON FUNCTION public.process_expired_account_deletions() FROM PUBLIC;
  REVOKE EXECUTE ON FUNCTION public.purge_trashed_materials() FROM PUBLIC;
  GRANT EXECUTE ON FUNCTION public.process_expired_account_deletions() TO service_role;
  GRANT EXECUTE ON FUNCTION public.purge_trashed_materials() TO service_role;
  ```

---

## SECTION 3: RESOURCE UPDATE SECURITY AUDIT

### 3.1 Defense-in-Depth Architecture
The security architecture for `public.resources` was audited across both the RLS policy layer in [`08_row_level_security.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/08_row_level_security.sql#L101-L113) and the database trigger layer in [`03_academic_resources_and_curriculum.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/03_academic_resources_and_curriculum.sql#L152-L257).

```
                        CLIENT UPDATE REQUEST ON public.resources
                                           │
                                           ▼
                 ┌──────────────────────────────────────────────────┐
                 │ 1. RLS POLICY GATE (08_row_level_security.sql)   │
                 │    - Uploader or Admin?  (uploader_id = auth.uid)│
                 │    - Active Material?    (status = 'active')     │
                 └─────────────────────────┬────────────────────────┘
                                           │ Permitted
                                           ▼
                 ┌──────────────────────────────────────────────────┐
                 │ 2. BEFORE UPDATE TRIGGER                         │
                 │    (trg_resource_update_security)                │
                 └─────────────────────────┬────────────────────────┘
                                           │
                 ┌─────────────────────────┴────────────────────────┐
                 ▼                                                  ▼
     [ Caller: Non-Uploader ]                           [ Caller: Uploader ]
   Checks 38 Protected Columns:                       Checks Administrative Flags:
   - title, file_url, uploader_id                     - approved_by_admin
   - status, unit_code, lecturers                     - rejected_by_admin
   - is_pinned, is_imported_dspace                    - is_pinned, pinned_at
   - thumbnail, decline_reason...                     - is_imported_dspace...
                 │                                                  │
    Any change to protected fields?                     Any change to admin fields?
      YES ──► RAISE EXCEPTION 'Denied'                    YES ──► RAISE EXCEPTION 'Denied'
      NO  ──► UPDATE (views, likes only)                  NO  ──► UPDATE metadata
```

---

### 3.2 Bypass Resistance Matrix

| Column / Attack Vector | Attacker Role | Mechanism Tested | Trigger / RLS Defense | Result |
| :--- | :--- | :--- | :--- | :---: |
| `uploader_id` | Non-Uploader | Attempts to reassign document ownership to self | Evaluated in Case 1: `NEW.uploader_id IS DISTINCT FROM OLD.uploader_id` &rarr; Exception | **REJECTED** |
| `uploader_id` | Uploader | Attempts to transfer document to another account | Evaluated in Case 2: `NEW.uploader_id IS DISTINCT FROM OLD.uploader_id` &rarr; Exception | **REJECTED** |
| `approved_by_admin` | Uploader | Self-approves pending or rejected upload | Evaluated in Case 2: `NEW.approved_by_admin IS DISTINCT FROM OLD.approved_by_admin` &rarr; Exception | **REJECTED** |
| `rejected_by_admin` | Uploader | Clears rejection status | Evaluated in Case 2: `NEW.rejected_by_admin IS DISTINCT FROM OLD.rejected_by_admin` &rarr; Exception | **REJECTED** |
| `is_pinned` | Uploader | Self-pins material to top of university library | Evaluated in Case 2: `NEW.is_pinned IS DISTINCT FROM OLD.is_pinned` &rarr; Exception | **REJECTED** |
| `is_imported_dspace`| Uploader | Attempts to forge institutional DSpace badge | Evaluated in Case 2: `NEW.is_imported_dspace IS DISTINCT FROM OLD.is_imported_dspace` &rarr; Exception | **REJECTED** |
| `dspace_item_uuid` | Uploader | Injects fake institutional repository UUID | Evaluated in Case 2: `NEW.dspace_item_uuid IS DISTINCT FROM OLD.dspace_item_uuid` &rarr; Exception | **REJECTED** |
| `status` | Non-Uploader | Attempts to trash another user's material | Evaluated in Case 1: `NEW.status IS DISTINCT FROM OLD.status` &rarr; Exception | **REJECTED** |
| `unit_code` / `title`| Non-Uploader | Modifies course unit or material title | Evaluated in Case 1: `NEW.title` / `NEW.unit_code` &rarr; Exception | **REJECTED** |
| `file_url` / `file_id`| Non-Uploader | Replaces document file with malicious binary | Evaluated in Case 1: `NEW.file_url` / `NEW.file_id` &rarr; Exception | **REJECTED** |
| `views_count` | Non-Uploader | Increments document view count | Case 1 check passes (engagement counters whitelisted) | **ALLOWED** |
| `likes_count` / `liked_by`| Non-Uploader | Liking / unliking active document | Case 1 check passes (engagement counters whitelisted) | **ALLOWED** |
| `comments_count` | Non-Uploader | Updated via trigger `trg_comments_counter` | Case 1 check passes (engagement counters whitelisted) | **ALLOWED** |
| Any Column | Administrator| Administrative moderation / curation | `IF is_caller_admin THEN RETURN NEW; END IF;` | **ALLOWED** |
| Any Column | Service Role | Background thumbnail generation / sync | `IF caller_id IS NULL THEN RETURN NEW; END IF;` | **ALLOWED** |

---

### 3.3 Trigger Context, Security Definer & Role Identification
1. **Trigger Timing:** Configured as `BEFORE UPDATE ON public.resources FOR EACH ROW`. It executes synchronously inside the caller's transaction before modifications are written to disk. Raising an exception aborts the entire transaction.
2. **Role Identification:**
   ```sql
   caller_id := auth.uid();
   IF caller_id IS NULL THEN RETURN NEW; END IF;
   is_caller_admin := public.is_admin();
   IF is_caller_admin THEN RETURN NEW; END IF;
   ```
   Admin determination calls [`public.is_admin()`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/01_extensions_and_helpers.sql#L35-L66), which inspects JWT app metadata claims (`admin: true`), custom role claims, and verified administrative emails (`admin@mirrorlaikipia.ac.ke`, etc.).
3. **NULL Uploader Handling:** If `OLD.uploader_id IS NULL` (e.g. an anonymized resource or legacy imported record), `OLD.uploader_id IS NULL OR caller_id != OLD.uploader_id` evaluates to TRUE. An ordinary user cannot claim ownership of an unowned or anonymized material.
4. **Verdict on Resource Update Security:** **PASS.**

---

### 3.4 Finding 4: `SECURITY DEFINER` Functions Omit Fixed `search_path`
- **Classification:** **WARNING** (PostgreSQL Hardening Best Practice)
- **File & Line:** Found across:
  - [`01_extensions_and_helpers.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/01_extensions_and_helpers.sql#L32), [`01_extensions_and_helpers.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/01_extensions_and_helpers.sql#L66) (`is_authenticated`, `is_admin`)
  - [`02_core_users_and_auth.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/02_core_users_and_auth.sql#L129) (`handle_new_auth_user`)
  - [`03_academic_resources_and_curriculum.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/03_academic_resources_and_curriculum.sql#L252) (`enforce_resource_update_security`)
  - [`04_payments_subscriptions_and_xp.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/04_payments_subscriptions_and_xp.sql#L184) (`fulfill_paystack_subscription`)
  - [`09_maintenance_and_cron.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql#L20), [`09_maintenance_and_cron.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql#L111), [`09_maintenance_and_cron.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql#L157) (`purge_trashed_materials`, `process_expired_account_deletions`, `restore_user_account`)
- **Evidence:**  
  All 8 functions specify `SECURITY DEFINER` without setting `SET search_path = public, pg_temp;`.
- **Failure Scenario:**  
  PostgreSQL documentation and Supabase security advisories note that `SECURITY DEFINER` functions run with superuser/owner privileges. If `search_path` is not explicitly pinned, the function inherits the search path of the invoking user. If a malicious user creates a custom function with an identical name (e.g. `substr` or `NOW`) in a schema preceding `public`, execution can be hijacked.
- **Actual Impact:**  
  In the current bundle, almost all table references and helper function calls are explicitly schema-qualified (`public.users`, `public.is_admin()`, `auth.uid()`), which substantially mitigates the risk. However, built-in SQL functions and operators remain un-pinned.
- **Can Schema Deployment Safely Proceed?** **YES.** This does not cause execution failures.
- **Recommended Remediation:**  
  Append `SET search_path = public, pg_temp;` to the signature of all `SECURITY DEFINER` functions.

---

## SECTION 4: SQL & MIGRATION INTEGRITY AUDIT

### 4.1 Reconciled Architectural Inventory
A programmatic audit of [`00_full_migration_bundle.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/00_full_migration_bundle.sql) reconciled all objects against the modular source files:

```
Total Bundle Size: 77,426 bytes | Total Lines: 1,918
Tables: 34 | RLS Policies: 45 | Triggers: 14 | Stored Functions: 11 | Indexes: 41
```

#### Complete Trigger Roster (14 Triggers Verified)
1. `trg_users_updated_at` ON `public.users` (BEFORE UPDATE &rarr; `handle_updated_at`)
2. `on_auth_user_created` ON `auth.users` (AFTER INSERT &rarr; `handle_new_auth_user`)
3. `trg_curriculum_updated_at` ON `public.curriculum` (BEFORE UPDATE &rarr; `handle_updated_at`)
4. `trg_resources_updated_at` ON `public.resources` (BEFORE UPDATE &rarr; `handle_updated_at`)
5. `trg_comments_updated_at` ON `public.comments` (BEFORE UPDATE &rarr; `handle_updated_at`)
6. `trg_comments_counter` ON `public.comments` (AFTER INSERT OR DELETE &rarr; `update_resource_comment_count`)
7. `trg_resource_update_security` ON `public.resources` (BEFORE UPDATE &rarr; `enforce_resource_update_security`)
8. `trg_payments_updated_at` ON `public.payments` (BEFORE UPDATE &rarr; `handle_updated_at`)
9. `trg_subscription_history_updated_at` ON `public.subscription_history` (BEFORE UPDATE &rarr; `handle_updated_at`)
10. `trg_conversations_updated_at` ON `public.conversations` (BEFORE UPDATE &rarr; `handle_updated_at`)
11. `trg_new_chat_message` ON `public.messages` (AFTER INSERT &rarr; `handle_new_chat_message`)
12. `trg_manual_ads_updated_at` ON `public.manual_ads` (BEFORE UPDATE &rarr; `handle_updated_at`)
13. `trg_explore_news_updated_at` ON `public.explore_news` (BEFORE UPDATE &rarr; `handle_updated_at`)
14. `trg_dspace_jobs_updated_at` ON `public.dspace_jobs` (BEFORE UPDATE &rarr; `handle_updated_at`)

#### Complete Function Roster (11 Functions Verified)
1. `public.handle_updated_at()` &rarr; Generic timestamp refresher
2. `public.is_authenticated()` &rarr; RLS helper verifying JWT session presence
3. `public.is_admin()` &rarr; Multi-factor admin verifier (JWT claims, role, email)
4. `public.handle_new_auth_user()` &rarr; Bridge trigger populating `public.users` from `auth.users`
5. `public.update_resource_comment_count()` &rarr; Atomic comment counter maintenance
6. `public.enforce_resource_update_security()` &rarr; Column-level immutability enforcer
7. `public.fulfill_paystack_subscription(p_reference, p_paystack_tx_id, p_channel)` &rarr; Atomic payment processor
8. `public.handle_new_chat_message()` &rarr; Unread badge and conversation preview updater
9. `public.purge_trashed_materials()` &rarr; 30-day trash retention cleaner
10. `public.process_expired_account_deletions()` &rarr; GDPR / Right-to-be-Forgotten anonymizer
11. `public.restore_user_account(p_user_id)` &rarr; Grace period deletion restoration

---

### 4.2 Topological Execution Order
The concatenation order in [`00_full_migration_bundle.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/00_full_migration_bundle.sql) is strictly linear and respects all relational dependencies:
1. **Part 01:** Extensions & Core Helpers (`handle_updated_at`, `is_admin`) &rarr; *No table dependencies.*
2. **Part 02:** Core Users (`public.users`, `public.user_sessions`) &rarr; *Root identity entity.*
3. **Part 03:** Academic Curriculum & Resources &rarr; *References `public.users(id)`.*
4. **Part 04:** Payments & Subscriptions &rarr; *References `public.users(id)`.*
5. **Part 05:** Communications & Ads &rarr; *References `public.users(id)` and `public.conversations(id)`.*
6. **Part 06:** Explore News Pipeline &rarr; *Standalone media domain.*
7. **Part 07:** Governance & Audits &rarr; *References `public.users(id)`.*
8. **Part 08:** Row Level Security & Realtime &rarr; *Operates on all 34 tables.*
9. **Part 09:** Maintenance, Account Deletion & Cron &rarr; *Operates on populated schemas.*
10. **Part 10:** Validation Diagnostics &rarr; *Inspects information_schema across all objects.*

---

## SECTION 5: ORIGINAL BUSINESS RULES & INTEGRATIONS PARITY

An audit of the migration schema confirmed absolute parity with Mirror Digital's operational business rules:

1. **Four Paused Explore News Schedulers:**  
   [`09_maintenance_and_cron.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql#L178-L187) contains the mandatory pause notice. None of the four autonomous schedulers (`scheduledExploreDiscovery`, `scheduledExploreQueueDrainer`, `scheduledWorkerHealthCheck`, `scheduledNewsCapacityCheck`) are registered in `cron.schedule`.
2. **Active Thumbnail Retry Processor:**  
   [`03_academic_resources_and_curriculum.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/03_academic_resources_and_curriculum.sql#L77-L82) defines `thumbnail_id`, `thumbnail_url`, `thumbnail_status`, and `thumbnail_generation JSONB`. Lines 99-100 maintain the specialized retry index:
   ```sql
   CREATE INDEX IF NOT EXISTS idx_resources_thumbnail_retry 
   ON public.resources((thumbnail_generation->>'isRetryable'), thumbnail_status, (thumbnail_generation->>'nextRetryAt'));
   ```
3. **Paystack Financial Authority:**  
   [`04_payments_subscriptions_and_xp.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/04_payments_subscriptions_and_xp.sql#L114) uses `FOR UPDATE` row-level exclusive locks in `fulfill_paystack_subscription`. Lines 119-121 check `v_payment.fulfilled` to prevent double-crediting. Client writes on `payments` and `subscription_history` are strictly blocked via `WITH CHECK (FALSE)`.
4. **XP & Rewarded Ad Integrity:**  
   `public.xp_transactions` and `public.ad_reward_sessions` prohibit direct client inserts and updates. [`08_row_level_security.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/08_row_level_security.sql#L66) prevents users from updating their own `xp_balance`.
5. **DSpace Ingestion & Examination Protection:**  
   `public.dspace_jobs` retains complete sync progress tracking (`discovered_count`, `imported_count`, `progress`). DSpace materials (`is_imported_dspace = TRUE`) are protected against user modification and account deletion purges.
6. **ImageKit References:**  
   ImageKit file IDs are preserved across `resources.file_id`, `resources.thumbnail_id`, and `manual_ads.media_file_id`.
7. **Firebase UID Mapping:**  
   Every major entity maintains `firebase_uid` columns (`users.firebase_uid`, `resources.uploader_firebase_uid`, `payments.user_firebase_uid`, etc.) indexed for deterministic data restoration.

---

## SECTION 6: CONSOLIDATED FINDINGS LOG

| # | Finding Description | Severity | File Reference | Action Required | Deployment Impact |
|---|---------------------|:--------:|----------------|-----------------|:-----------------:|
| 1 | `public.users` Realtime broadcast streams full row payloads (phone, session ID) to any authenticated subscriber. | **WARNING** | [`08_row_level_security.sql:48-51`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/08_row_level_security.sql#L48-L51) | Restrict Realtime `users` SELECT to owner; expose public view for author attribution. | **Safe to Deploy** (Pre-traffic hardening) |
| 2 | `restore_user_account()` does not verify that `auth.uid() == p_user_id` or admin. | **WARNING** | [`09_maintenance_and_cron.sql:114-157`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql#L114-L157) | Add caller authorization check before updating account. | **Safe to Deploy** (Pre-traffic hardening) |
| 3 | Maintenance functions callable by `PUBLIC` role via RPC by default. | **WARNING** | [`09_maintenance_and_cron.sql:8-111`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql#L8-L111) | Revoke `EXECUTE` on maintenance routines from `PUBLIC`; grant to `service_role`. | **Safe to Deploy** (Pre-traffic hardening) |
| 4 | Eight `SECURITY DEFINER` functions omit `SET search_path = public, pg_temp;`. | **WARNING** | Multiple files (Parts 01, 02, 03, 04, 09) | Append explicit `search_path` to function declarations. | **Safe to Deploy** (Best practice hardening) |
| 5 | Realtime publication membership for 13 client tables. | **PASS** | [`08_row_level_security.sql:356-402`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/08_row_level_security.sql#L356-L402) | Verified idempotent and correctly configured. | **Resolved** |
| 6 | Account deletion processor column mapping & DSpace protection. | **PASS** | [`09_maintenance_and_cron.sql:23-111`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql#L23-L111) | Verified clean execution, grace period, and exam safety. | **Resolved** |
| 7 | Resource update defense-in-depth security trigger. | **PASS** | [`03_academic_resources_and_curriculum.sql:152-257`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/03_academic_resources_and_curriculum.sql#L152-L257) | Verified field immutability for non-uploaders/non-admins. | **Resolved** |
| 8 | Architectural volume parity (34 tables, 45 policies, 14 triggers, 11 functions). | **PASS** | [`00_full_migration_bundle.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/00_full_migration_bundle.sql) | Verified 100% syntactic and relational integrity. | **Resolved** |

---

## SECTION 7: FINAL VERDICT

```
================================================================================
   VERDICT: APPROVED FOR EMPTY-PROJECT SCHEMA DEPLOYMENT
================================================================================
1. All critical blockers (Realtime publication absence and account deletion 
   column mismatch) have been completely resolved.
2. The complete DDL bundle (00_full_migration_bundle.sql) contains zero syntax 
   errors, valid foreign keys, and topologically ordered dependencies.
3. The schema is 100% ready for deployment against a fresh, empty Supabase 
   PostgreSQL 15+ database instance.
4. The four WARNING findings documented above are non-blocking for empty schema 
   initialization, but should be addressed during Phase 2 before switching live 
   mobile traffic from Firebase to Supabase.
================================================================================
```
