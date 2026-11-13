# MIRROR DIGITAL — FINAL POST-HARDENING POSTGRESQL SECURITY GATE

**Target Bundle:** [`supabase_migration/00_full_migration_bundle.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/00_full_migration_bundle.sql)  
**Evaluation Target:** Supabase Cloud PostgreSQL 15+  
**Project:** Mirror Digital (`com.mirrordigital.app`)  
**Audit Scope:** Independent, Strictly Read-Only PostgreSQL Security Gate Review  
**Timestamp:** 2026-11-12T21:55:00+03:00  

---

## EXECUTIVE GATE SUMMARY

This independent gate review evaluated the complete, rebuilt migration bundle ([`00_full_migration_bundle.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/00_full_migration_bundle.sql)) against production PostgreSQL security standards, Supabase Realtime internals, and Row Level Security (RLS) enforcement.

While the pre-deployment hardening successfully resolved the `search_path` vulnerabilities across all eight `SECURITY DEFINER` functions, hardened `restore_user_account()` caller checks, and locked down maintenance function privileges, an architectural investigation of the newly introduced [`public.user_public_profiles`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/02_core_users_and_auth.sql#L138-L160) view identified an **unacceptable RLS bypass and data enumeration vulnerability**.

```
================================================================================
   FINAL GATE VERDICT: B. NOT APPROVED — REMAINING BLOCKERS
================================================================================
CRITICAL BLOCKER IDENTIFIED:
The view `public.user_public_profiles` is defined without `security_invoker = true`
and grants unconditional `SELECT` to role `anon`. Because standard PostgreSQL views 
evaluate under the owner's privileges (`postgres`), the view creates an unrestricted 
RLS bypass on `public.users`, allowing unauthenticated scrapers on the public internet 
to bulk-enumerate all registered students, their university programs, roles, 
account deletion statuses, and internal Firebase Auth UIDs.

Deployment cannot proceed until this critical architectural defect is resolved.
================================================================================
```

---

## SECTION 1: CRITICAL AUDIT — SANITIZED PUBLIC VIEW (`public.user_public_profiles`)

### 1.1 Technical Architecture of the View
In [`supabase_migration/02_core_users_and_auth.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/02_core_users_and_auth.sql#L141-L160), the view is defined as:
```sql
CREATE OR REPLACE VIEW public.user_public_profiles AS
SELECT 
    id,
    firebase_uid,
    username,
    display_name,
    photo_url,
    institution,
    university_location,
    program,
    program_code,
    role,
    is_virtual_uploader,
    is_anonymized,
    deletion_status,
    created_at
FROM public.users;

GRANT SELECT ON public.user_public_profiles TO authenticated, anon;
```

---

### 1.2 Point-by-Point Security Verification

#### 1. Does the view use `security_invoker = true`?
- **Finding:** **NO.**
- **File & Line:** [`02_core_users_and_auth.sql:141-157`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/02_core_users_and_auth.sql#L141-L157)
- **Evidence:** The DDL is a bare `CREATE OR REPLACE VIEW ... AS SELECT ...`. It lacks `WITH (security_invoker = true)`.
- **PostgreSQL Mechanics:** In PostgreSQL 15+, a view created without `security_invoker = true` defaults to `security_invoker = false`.

#### 2. Is underlying `public.users` RLS enforced for the querying user?
- **Finding:** **NO.**
- **PostgreSQL Mechanics:** When `security_invoker = false`, PostgreSQL evaluates permissions and RLS on the underlying base table (`public.users`) using the identity and privileges of the **view owner** (`postgres`), not the client executing the query. Because `postgres` is a superuser that bypasses RLS, the querying user's RLS policy (`USING (id = auth.uid() OR public.is_admin())`) is **completely ignored**.

#### 3. Does view ownership create an RLS bypass?
- **Finding:** **YES. Direct RLS Bypass.**
- **Evidence:** By querying through the view, any user—even an unauthenticated visitor—effectively runs with superuser privileges with respect to row visibility on `public.users`.

#### 4. Do `anon` and `authenticated` have appropriate SELECT privileges?
- **Finding:** **INAPPROPRIATE PRIVILEGE ASSIGNMENT.**
- **File & Line:** [`02_core_users_and_auth.sql:160`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/02_core_users_and_auth.sql#L160)
- **Evidence:** `GRANT SELECT ON public.user_public_profiles TO authenticated, anon;`
- **Security Implications:** In the original Firebase project and throughout the PostgreSQL RLS architecture, `anon` was strictly prohibited from reading user account data (`public.users` RLS specifies `FOR SELECT TO authenticated`). Granting `anon` access to this view exposes the user directory to public unauthenticated requests over Supabase PostgREST (`https://<project-ref>.supabase.co/rest/v1/user_public_profiles`).

#### 5. Can unauthorized users enumerate private profiles?
- **Finding:** **YES. Complete User Directory Enumeration.**
- **Attack Scenario:** An anonymous web scraper or malicious student sends an unauthenticated HTTP GET request:
  ```http
  GET /rest/v1/user_public_profiles?select=* HTTP/1.1
  Host: <project-ref>.supabase.co
  apikey: <anon_public_key>
  ```
  PostgREST executes the query against the view. Because the view is owned by `postgres` and has no `security_invoker`, PostgreSQL returns **every single registered user row in the database** (all 71 production student profiles).

#### 6. Are `firebase_uid`, `deletion_status`, `is_anonymized`, and `role` genuinely appropriate public fields?
- **Finding:** **NO. Sensitive Metadata Exposure.**
- **Field Breakdown:**
  * `firebase_uid`: Confidential internal authentication mapping identifier from Firebase Authentication. Exposing all Firebase UIDs publicly facilitates credential-stuffing and cross-system correlation attacks.
  * `deletion_status`: Discloses whether a student has requested account deletion (`pending`, `pending_deletion`). GDPR and privacy regulations require that a user's intent to delete their account remain confidential.
  * `role`: Publicly identifies which accounts hold administrative and moderation privileges (`role = 'admin'`), exposing administrators to targeted spear-phishing and brute-force targeting.
  * `created_at`: Exposes exact registration dates and usage patterns.

#### 7. Does the view expose private information through joins, expressions, or functions?
- **Finding:** It does not use joins or expressions, but directly projects sensitive administrative and compliance columns.

#### 8. Can Flutter use the view without requiring unsafe access to `public.users`?
- **Finding:** **FLAWED PARADOX.**
  * If the view retains `security_invoker = false`, it creates the critical enumeration vulnerability described above.
  * If the view is altered to `WITH (security_invoker = true)`, PostgreSQL enforces `public.users` RLS (`id = auth.uid() OR public.is_admin()`). Under this RLS policy, User A querying User B's profile will receive **0 rows**, breaking author attribution in Flutter!

---

### 1.3 Classification of Finding 1
```
================================================================================
   FINDING 1: CRITICAL BLOCKER
   File: supabase_migration/02_core_users_and_auth.sql (Lines 141-160)
   Severity: CRITICAL BLOCKER
   Impact: Mass User Directory Enumeration & RLS Bypass to 'anon' and 'authenticated'
================================================================================
```

#### Remediation Recommendation (For Authorization Prior to Deployment):
To safely provide document author attribution without creating an enumerable view or an RLS bypass:
1. **Drop the enumerable view:** `DROP VIEW IF EXISTS public.user_public_profiles;`
2. **Denormalization Parity:** Recognize that `public.resources` already stores `uploaded_by` and `uploader_role`, and `public.comments` already stores `author_name` and `author_profile_image`.
3. **Targeted Parameterized RPC:** If dynamic author profile lookup is required, replace the bulk view with a strictly parameterized, single-user RPC function that rejects bulk querying and requires authentication:
   ```sql
   CREATE OR REPLACE FUNCTION public.get_author_profile(p_user_id UUID)
   RETURNS TABLE (
       id UUID,
       username VARCHAR,
       display_name VARCHAR,
       photo_url TEXT,
       institution VARCHAR,
       program VARCHAR
   )
   LANGUAGE sql
   STABLE
   SECURITY DEFINER
   SET search_path = public, pg_temp
   AS $$
       SELECT id, username, display_name, photo_url, institution, program
       FROM public.users
       WHERE id = p_user_id
         AND deletion_status NOT IN ('deleted', 'anonymized');
   $$;

   REVOKE EXECUTE ON FUNCTION public.get_author_profile(UUID) FROM PUBLIC, anon;
   GRANT EXECUTE ON FUNCTION public.get_author_profile(UUID) TO authenticated;
   ```
   This prevents any client from dumping the user directory while allowing author card lookups by document `uploader_id`.

---

## SECTION 2: SECURITY DEFINER FUNCTIONS AUDIT

All eight `SECURITY DEFINER` functions in [`00_full_migration_bundle.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/00_full_migration_bundle.sql) were independently audited:

| # | Function Signature | Module & Lines | `SET search_path` | Dynamic SQL | `auth.uid() IS NULL` Handling | Caller Authorization | Verdict |
|---|--------------------|----------------|:-----------------:|:-----------:|:-----------------------------:|:--------------------:|:-------:|
| 1 | `public.is_authenticated()` | `01:27-32` | `public, pg_temp` | None | Safely returns `FALSE` | JWT presence check | **PASS** |
| 2 | `public.is_admin()` | `01:35-66` | `public, pg_temp` | None | Safely returns `FALSE` | JWT claims + verified emails | **PASS** |
| 3 | `public.handle_new_auth_user()` | `02:91-114` | `public, pg_temp` | None | Trigger context (`NEW.id`) | Supabase Auth internal | **PASS** |
| 4 | `public.enforce_resource_update_security()` | `03:153-252` | `public, pg_temp` | None | Safely permits background tasks (`RETURN NEW`) | Field-level immutability | **PASS** |
| 5 | `public.fulfill_paystack_subscription(...)` | `04:103-184` | `public, pg_temp` | None | Operates on reference | `service_role` only | **PASS** |
| 6 | `public.purge_trashed_materials()` | `09:8-20` | `public, pg_temp` | None | Standalone maintenance | `postgres`, `service_role` | **PASS** |
| 7 | `public.process_expired_account_deletions()`| `09:31-116` | `public, pg_temp` | None | Batch cron routine | `postgres`, `service_role` | **PASS** |
| 8 | `public.restore_user_account(UUID)` | `09:125-187` | `public, pg_temp` | None | Allows `service_role` | `auth.uid() = p_user_id` or admin | **PASS** |

### Detailed Function Inspections:
1. **`restore_user_account(p_user_id UUID)`:**
   - Lines 134-144 in [`09_maintenance_and_cron.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql#L134-L144):
     ```sql
     IF caller_uid IS NOT NULL THEN
         is_caller_admin := public.is_admin();
         IF caller_uid != p_user_id AND NOT is_caller_admin THEN
             RAISE EXCEPTION 'Permission denied: you can only restore your own account.';
         END IF;
     END IF;
     ```
   - Caller ownership is verified. An ordinary user attempting to restore another account is rejected with an exception.
   - Status verification (`v_status IN ('pending', 'pending_deletion')`) ensures permanently deleted or active accounts cannot be restored.
   - Expiration verification (`v_scheduled <= NOW()`) prevents restoration after the 30-day grace period.
2. **`fulfill_paystack_subscription(p_reference, p_paystack_tx_id, p_channel)`:**
   - Uses `SELECT ... FOR UPDATE` row lock on `public.payments`.
   - Checks `v_payment.fulfilled` to prevent replay attacks and duplicate subscription extensions.
   - Execution revoked from `PUBLIC`, `anon`, and `authenticated`; granted strictly to `postgres` and `service_role`.

---

## SECTION 3: PRIVILEGE AUDIT

The exact permissions for sensitive database functions were audited from [`00_full_migration_bundle.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/00_full_migration_bundle.sql):

```sql
-- Lines 691-693: fulfill_paystack_subscription
REVOKE EXECUTE ON FUNCTION public.fulfill_paystack_subscription(VARCHAR, BIGINT, VARCHAR) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fulfill_paystack_subscription(VARCHAR, BIGINT, VARCHAR) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fulfill_paystack_subscription(VARCHAR, BIGINT, VARCHAR) TO postgres, service_role;

-- Lines 1614-1616: purge_trashed_materials
REVOKE EXECUTE ON FUNCTION public.purge_trashed_materials() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.purge_trashed_materials() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_trashed_materials() TO postgres, service_role;

-- Lines 1710-1712: process_expired_account_deletions
REVOKE EXECUTE ON FUNCTION public.process_expired_account_deletions() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.process_expired_account_deletions() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_expired_account_deletions() TO postgres, service_role;

-- Lines 1781-1783: restore_user_account
REVOKE EXECUTE ON FUNCTION public.restore_user_account(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.restore_user_account(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.restore_user_account(UUID) TO authenticated, service_role;
```

### Role-by-Role Privilege Matrix:
| Target Routine | `anon` | `authenticated` | `service_role` | `postgres` (Cron Worker) |
| :--- | :---: | :---: | :---: | :---: |
| `fulfill_paystack_subscription` | **DENIED** | **DENIED** | **GRANTED** (Webhook) | **GRANTED** |
| `purge_trashed_materials` | **DENIED** | **DENIED** | **GRANTED** | **GRANTED** (03:00 UTC Daily) |
| `process_expired_account_deletions`| **DENIED** | **DENIED** | **GRANTED** | **GRANTED** (02:00 UTC Daily) |
| `restore_user_account` | **DENIED** | **GRANTED** (Self-only) | **GRANTED** | **GRANTED** |

**Supabase Cron Verification:** In Supabase Cloud, `pg_cron` jobs run as database superuser `postgres`. Because `postgres` is explicitly granted `EXECUTE`, scheduled jobs will execute without permission errors.

---

## SECTION 4: REALTIME & ROW LEVEL SECURITY AUDIT

All 13 tables in publication `supabase_realtime` were audited against their respective RLS policies:

1. **`public.users`:**
   - Policy: `USING (id = auth.uid() OR public.is_admin())`.
   - Realtime Result: Subscribers receive events **only** for their own user record. Cross-user payload leakage (phone, device ID, session ID) is completely eliminated.
2. **`public.messages` & `public.conversations`:**
   - Isolated to `auth.uid() = conversation_id` or `public.is_admin()`.
3. **`public.notifications`:**
   - Isolated to `target_user_id = auth.uid()` or broadcast `target_type = 'all'`.
4. **`public.xp_transactions`:**
   - Isolated to `user_id = auth.uid()`.
5. **`public.resources`:**
   - Public can view `status = 'active'`; uploaders can view own pending/trashed materials.
6. **`public.dspace_jobs`:**
   - Restricted to `public.is_admin()`. Non-admins receive zero events.
7. **`REPLICA IDENTITY FULL`:**
   - Confirmed configured on all 13 tables, ensuring WAL retains complete row states for UPDATE/DELETE event filtering.

---

## SECTION 5: FULL MIGRATION INTEGRITY & INVENTORY

The bundle was reconciled against the 10 modular migration files:
- **Tables (34 Verified):** All domain entities, job queues, worker registries, and caches present.
- **Views (1 Present):** `public.user_public_profiles` (Flagged as Critical Blocker in Section 1).
- **RLS Policies (45 Verified):** 100% of tables have Row Level Security enabled.
- **Triggers (14 Verified):** Timestamps, comment counters, resource security, chat previews.
- **Functions (11 Verified):** 8 `SECURITY DEFINER` (all hardened with `search_path`), 3 trigger helpers.
- **Indexes (41 Verified):** FTS GIN indexes, compound indexes, thumbnail retry index.
- **Business Rule Invariants:**
  * Four Explore news schedulers remain strictly paused.
  * Active thumbnail retry pipeline and trash retention purge remain configured.
  * Account deletion processor preserves DSpace materials (`is_imported_dspace = FALSE`).
  * Paystack duplicate payment protection (`FOR UPDATE` + `fulfilled` check) is intact.

---

## SECTION 6: CONSOLIDATED FINDINGS TABLE

| # | Finding Description | Severity | File Reference | Safe to Deploy? |
|---|---------------------|:--------:|----------------|:---------------:|
| 1 | `public.user_public_profiles` view lacks `security_invoker = true`, creating an RLS bypass that exposes the entire user directory (including Firebase UIDs, roles, and deletion requests) to role `anon`. | **CRITICAL BLOCKER** | [`02_core_users_and_auth.sql:141-160`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/02_core_users_and_auth.sql#L141-L160) | **NO** |
| 2 | All eight `SECURITY DEFINER` functions have `SET search_path = public, pg_temp;`. | **PASS** | Modules 01, 02, 03, 04, 09 | Yes |
| 3 | Caller ownership checks in `restore_user_account()` prevent third-party deletion cancellations. | **PASS** | [`09_maintenance_and_cron.sql:125-187`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql#L125-L187) | Yes |
| 4 | Sensitive maintenance procedures revoked from `PUBLIC`, `anon`, and `authenticated`; granted to `postgres` and `service_role`. | **PASS** | [`09_maintenance_and_cron.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql) & [`04_payments_subscriptions_and_xp.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/04_payments_subscriptions_and_xp.sql) | Yes |
| 5 | Realtime publication configuration on 13 streaming tables preserves RLS isolation and eliminates cross-user payload leakage. | **PASS** | [`08_row_level_security.sql:356-402`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/08_row_level_security.sql#L356-L402) | Yes |
| 6 | Preservation of paused Explore schedulers, thumbnail retry pipeline, and DSpace institutional records. | **PASS** | [`09_maintenance_and_cron.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/09_maintenance_and_cron.sql) & [`03_academic_resources_and_curriculum.sql`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/supabase_migration/03_academic_resources_and_curriculum.sql) | Yes |

---

## SECTION 7: FINAL GATE VERDICT

```
================================================================================
   VERDICT: B. NOT APPROVED — REMAINING BLOCKERS
================================================================================
CRITICAL REASON:
Finding 1 represents a high-severity security vulnerability where `public.user_public_profiles` 
bypasses Row Level Security under `postgres` view ownership and grants public read access 
to `anon`. Any unauthenticated user can dump the entire Mirror Digital user catalog, 
disclosing Firebase Auth UIDs, university academic programs, account deletion statuses, 
and administrative roles.

PER THE PROJECT MANDATE:
No local files have been modified. Schema deployment to Supabase must remain ON HOLD 
until this critical blocker is formally addressed.
================================================================================
```
