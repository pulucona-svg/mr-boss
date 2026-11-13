# MIRROR DIGITAL — FIRESTORE READ CONSUMPTION OPTIMIZATION PLAN
**Target Project:** `mirror-laikipia` (Project ID: `mirror-laikipia`)  
**Objective:** Eliminate Excessive Document Reads and Maintain Operations Within Free/Low-Cost Boundaries  
**Status:** STAGED IMPLEMENTATION STRATEGY (INVESTIGATION & PROPOSAL ONLY — NOT YET IMPLEMENTED)  

---

## 1. STRATEGIC OVERVIEW & SAFETY CONSTRAINTS

This plan outlines a phased, non-destructive remediation roadmap to reduce Firestore document reads by **90% to 95%** while strictly preserving existing business rules, user experience, and realtime capabilities:

* **Realtime Integrity:** Notifications, chat updates, live comments, and administrative monitoring remain fully realtime.
* **Feature Preservation:** Thumbnail retry pipelines, DSpace sync, Paystack subscriptions, and Explore news feeds remain intact.
* **Strict Safety Boundaries:** No changes are applied during this investigation turn. Implementation will occur only in controlled, staged sequences upon explicit user authorization.

---

## 2. PHASED OPTIMIZATION ROADMAP

### PHASE 1: IMMEDIATE HIGH-IMPACT WINS (Zero-Risk & Non-Breaking)

#### Step 1.1: Deploy Missing Composite Indexes for `explore_news`
* **Target:** Production Firestore
* **Problem:** `firestore.indexes.json` contains composite index definitions for `explore_news` (`categoryId + publishedAt`, `status + publishedAt`, `categoryId + status + publishedAt`), but they were never deployed to production. This forces `news_repository.dart` into an unindexed fallback that downloads **all 395 documents** across 8 categories on every Explore screen visit.
* **Remediation:** Deploy indexes using `firebase deploy --only firestore:indexes`.
* **Fallback Safety in Flutter:** Add `.limit(20)` to `fallbackQuery` in `_createCategoryNewsStream` so that even if an index is building or fails, it never downloads unbounded collection slices.
* **Estimated Savings:** **~10,000 to 25,000 reads/day** when users browse Explore.
* **Risk:** **Very Low.** Composite indexes improve query performance and do not alter document schemas or data.

#### Step 1.2: Bound and Paginate `ResourceService._allResourcesSub`
* **Target:** [`lib/services/resource_service.dart`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/services/resource_service.dart#L93-L102)
* **Problem:** Downloads all **1,666 documents** in `resources` with zero limit and zero status filter on app launch and pull-to-refresh.
* **Remediation:**
  1. Add `.where('status', isEqualTo: 'active')` so rejected, trashed, and archived materials are not downloaded by normal students.
  2. Add an initial `.limit(30)` for the dashboard view.
  3. Implement cursor-based pagination (`startAfterDocument`) for the Library browsing view when the user scrolls near the bottom.
  4. In `refresh()`, update only changed documents rather than cancelling and re-attaching the entire collection stream.
* **Estimated Savings:** **~20,000 to 45,000 reads/day** (from 1,666 docs per app open down to 30 docs).
* **Risk:** **Low to Medium.** Requires connecting infinite-scroll pagination in `library_screen.dart`.

#### Step 1.3: Delete Orphaned Deployed Function `scheduledThumbnailRecovery`
* **Target:** Google Cloud Platform / Firebase Console (Region: `africa-south1`)
* **Problem:** `scheduledThumbnailRecovery` is an obsolete function in `africa-south1` removed from git source code in commit `e95446d`, but still running in GCP Cloud Scheduler.
* **Remediation:** Delete the orphaned function from Firebase Console or via `firebase functions:delete scheduledThumbnailRecovery --region africa-south1`.
* **Estimated Savings:** **~5,000 to 15,000 reads/month**.
* **Risk:** **Zero.** Function is superseded by `scheduledThumbnailRetryProcessor` in `us-central1`.

---

### PHASE 2: APPLICATION ARCHITECTURE & STREAM EFFICIENCY

#### Step 2.1: Lazy-Load Explore Category Streams
* **Target:** [`lib/screens/explore_screen.dart`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/screens/explore_screen.dart#L515-L535)
* **Problem:** `_subscribeCategoryNewsStreams()` subscribes to all 8 categories simultaneously as soon as the screen opens, even though the user is viewing only one category tab at a time.
* **Remediation:** Subscribe *only* to the currently active category (`uiState.exploreCategory`). When the user taps a different category pill, cancel the previous category listener and subscribe to the new one (with in-memory caching of already-fetched lists).
* **Estimated Savings:** **~1,500 to 5,000 reads/day**.
* **Risk:** **Low.** Category selection state is already centralized in Riverpod `uiStateProvider`.

#### Step 2.2: Add `.limit(30)` to Background Chat Listener
* **Target:** [`lib/services/chat_service.dart`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/services/chat_service.dart#L255-L275)
* **Problem:** Listens to `conversations/{userId}/messages` with no limit, downloading the entire chat history on app startup.
* **Remediation:** Limit the background listener to `.limitToLast(30)`. When the user opens `admin_chat_detail_screen.dart` and scrolls up, load older messages on demand.
* **Estimated Savings:** **~500 to 2,000 reads/day** for active chat users.
* **Risk:** **Low.** Users typically only need recent messages upon launching the app.

#### Step 2.3: Optimize `scheduledThumbnailRetryProcessor` Cron
* **Target:** [`functions/src/index.ts`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/functions/src/index.ts#L433-L445)
* **Problem:** Runs every 5 minutes (288 times/day), querying `flux_workers` and `resources` even when no retries are pending.
* **Remediation:**
  1. Change schedule from `"every 5 minutes"` to `"every 30 minutes"` (48 times/day), reducing executions by 83.3%.
  2. Cache `flux_workers` configuration in memory with a 15-minute TTL to eliminate the collection get on every run.
* **Estimated Savings:** **~1,440 reads/day** (~43,200 reads/month).
* **Risk:** **Low.** Thumbnail retry backoff is exponential; checking every 30 minutes remains fully responsive for background image generation.

---

### PHASE 3: DATA MODEL DENORMALIZATION & STRATEGIC MIGRATION

#### Step 3.1: Denormalize Author Profiles onto Comments
* **Target:** [`lib/services/comment_service.dart`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/services/comment_service.dart) & [`lib/widgets/comment_modal.dart`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/widgets/comment_modal.dart)
* **Problem:** When opening comments on a resource, `AuthorProfileCache` issues N+1 `users/{uid}.get()` calls for every commenter.
* **Remediation:** Store `authorName` and `authorPhotoUrl` directly inside each comment document upon creation. Update them via Cloud Function only when a user changes their profile picture or username.
* **Estimated Savings:** **~200 to 1,000 reads/day**.
* **Risk:** **Low.** Standard Firestore document denormalization pattern.

#### Step 3.2: Complete Permanent Supabase Migration (Phase 1 & Phase 2)
* **Target:** Supabase Cloud PostgreSQL
* **The Long-Term Solution:**
  * Supabase PostgreSQL does not charge per row read; read queries are covered by compute resources with **zero per-document read pricing**.
  * By migrating client read queries (`resources`, `explore_news`, `curriculum`, `manual_ads`) to Supabase PostgREST endpoints, the application permanently escapes Firebase Spark read caps.
* **Estimated Savings:** **100% elimination of Firestore read costs and quota pressure.**

---

## 3. IMPLEMENTATION SAFETY GATES & ROLLBACK READINESS

1. **Gate 1: Verification in Isolated Branches:** All Flutter client modifications must pass regression tests (`test/android_document_opening_regression_test.dart`, `test/explore_ordering_and_safety_test.dart`).
2. **Gate 2: Non-Destructive Deployments:** Index deployments in Firestore are non-destructive and run in the background without affecting existing data.
3. **Gate 3: Rollback Path:** If any pagination or limit change produces UI issues, reverting client files restores previous behavior without database data modifications.

*(No files have been modified or deployed during this strictly read-only turn.)*
