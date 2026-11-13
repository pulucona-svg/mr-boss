# MIRROR DIGITAL — CLOUD FIRESTORE READ HOTSPOTS ANALYSIS
**Target Project:** `mirror-laikipia` (Project ID: `mirror-laikipia`, Number: `386198984140`)  
**Application:** Mirror Digital (Flutter + Firebase Cloud Functions + Cloud Firestore)  
**Investigation Scope:** Strictly Read-Only Forensic Audit  
**Date:** November 13, 2026  
**Status:** COMPLETED & EMPIRICALLY VERIFIED AGAINST GOOGLE CLOUD MONITORING METRICS  

---

## 1. EXECUTIVE SUMMARY & FORENSIC METRICS

Historical Cloud Monitoring telemetry for `mirror-laikipia` (`firestore.googleapis.com/document/read_count`) reveals a project operating in two distinct phases:

1. **Pre-Pause Historical Baseline (Oct 13 – Nov 05, 2026):**
   * **Daily Volume:** 200,000 to 282,532 document reads/day.
   * **Monthly Run Rate:** 6.5M to 8.4M reads/month.
   * **Dominant Operation:** Over **98.7%** of reads were `QUERY` operations (collection queries and snapshot listeners); `LOOKUP` (`.doc().get()`) accounted for less than 1.3%.
2. **Post-Pause Baseline (Nov 06 – Nov 12, 2026):**
   * Upon pausing the four Explore backend schedulers, daily reads plummeted from ~265,000 down to 5,600 – 54,000 reads/day.
   * **Current Spike Incident (Nov 11, 2026):** Exactly **49,300 reads** were measured in a single 24-hour period (100% `QUERY` operations), bringing the project to **98.6% of the Spark Free Tier limit (50,000 reads/day)** despite average concurrent connections measuring only **0.1 to 0.4 active users**.

Empirical collection aggregation queries verify the exact document inventory in production:
* `resources`: **1,666 documents**
* `curriculum`: **1,343 documents**
* `explore_news`: **395 documents**
* `users`: **71 documents**
* `manual_ads`: **11 documents**
* `conversations`: **9 documents**

Below is the prioritized, evidence-backed ranking of the read hotspots driving high consumption.

---

## 2. RANKED READ HOTSPOTS

### 🔴 HOTSPOT #1: Unbounded Full Collection Realtime Listener on `/resources`
* **Source Location:** [`lib/services/resource_service.dart` (Lines 93–102)](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/services/resource_service.dart#L93-L102)
* **Code Implementation:**
  ```dart
  _allResourcesSub = _firestore
      .collection('resources')
      .orderBy('uploadDate', descending: true)
      .snapshots()
      .listen((snapshot) { ... });
  ```
* **Cost per Execution:** **1,666 document reads** (every single document in `resources`).
* **Trigger Mechanism:**
  1. Triggered in `ResourceService().initialize(userId)` called on app startup in `main.dart:410`.
  2. Triggered on auth changes in `user_provider.dart:314`.
  3. Triggered on pull-to-refresh (`refresh(userId)`) on Dashboard and Library tabs, which forcibly cancels and re-attaches the listener.
* **Why It Is Catastrophic:**
  * **Zero Server-Side Limits:** There is no `.limit(...)` clause.
  * **Zero Server-Side Status Filtering:** It downloads all materials—including pending, trashed, archived, and rejected materials—and filters them locally in client memory (`_processServerResources()`).
  * **Duplication:** A companion listener (`_userUploadsSub`, line 105) simultaneously listens to `resources` where `uploaderId == userId`, re-reading the user's uploads a second time.
* **Mathematical Impact:**
  * 1 user launching the app 10 times in a day = **16,660 reads**.
  * 3 users launching the app 10 times = **49,980 reads** (100% of Spark quota).
  * 10 daily active users = **16,660 reads/day** to **50,000+ reads/day** from app launches alone.
* **Evidence Classification:** **Measured** (collection count 1,666 docs; listener code verified; Monitoring confirms 100% Query reads).

---

### 🔴 HOTSPOT #2: Explore News Query Explosion & Missing Composite Index Fallback
* **Source Location:**
  * [`lib/repositories/news_repository.dart` (Lines 183–250, 268–350)](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/repositories/news_repository.dart#L183-L250)
  * [`lib/screens/explore_screen.dart` (Lines 417–535)](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/screens/explore_screen.dart#L417-L535)
* **The Underlying Fault:**
  * Live project index inspection (`firebase firestore:indexes`) reveals that the three composite indexes defined in `firestore.indexes.json` for `explore_news` (`categoryId + publishedAt`, `status + publishedAt`, `categoryId + status + publishedAt`) **ARE NOT DEPLOYED** on production Firestore.
* **The Catastrophic Fallback Loop:**
  1. When a user opens `ExploreScreen`, `_subscribeToNewsStreams()` invokes `watchTopStories()`, `watchLatestNews()`, `watchTrendingTopics()`, `watchAllMixedNews()`, and `watchCategoryNews(cat)` for **every category in parallel**.
  2. `watchCategoryNews(cat)` attempts the indexed query `orderBy('publishedAt', descending: true).limit(30)`.
  3. Because the composite index is missing in production, Firestore rejects the query with an index required error.
  4. The code catches this error in `onError` and immediately executes an **unindexed, UNBOUNDED fallback query**:
     ```dart
     final fallbackQuery = _firestore
         .collection('explore_news')
         .where('categoryId', isEqualTo: categoryId);
     activeSub = fallbackQuery.snapshots().listen(...);
     ```
  5. Across all 8 categories, this fallback downloads **all 395 documents in `explore_news`**!
  6. Simultaneously, `watchLatestNews()` subscribes to 60 docs + 30 docs (companion stream) = 90 docs.
  7. `watchTopStories()` subscribes to 20 docs + 10 docs (companion stream) = 30 docs.
* **Cost per Screen Visit:** **515 document reads** on a single visit to Explore.
* **Mathematical Impact:**
  * 10 visits to Explore (or 10 pull-to-refresh actions) = **5,150 reads**.
  * 50 visits across users = **25,750 reads**.
* **Evidence Classification:** **Measured** (missing live indexes verified via CLI; 395 docs measured; code verified).

---

### 🟠 HOTSPOT #3: Perpetual Backend Cloud Schedulers (Historic & Active)
* **Source Location:**
  * [`functions/src/index.ts` (Lines 361–445)](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/functions/src/index.ts#L361-L445)
  * [`functions/src/thumbnail_search_service.ts` (Lines 378–415)](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/functions/src/thumbnail_search_service.ts#L378-L415)
  * [`functions/src/providers/image_generation/flux_worker_pool.ts` (Lines 110–150)](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/functions/src/providers/image_generation/flux_worker_pool.ts#L110-L150)
* **The Four Explore Schedulers (Historically ~200,000+ reads/day):**
  * `scheduledExploreQueueDrainer` (every 10 min): Scanned all categories and executed `enforceRetention` across all articles up to 30 per category = ~240 docs every 10 min = 34,560 reads/day.
  * `scheduledNewsCapacityCheck` (every 30 min): Duplicated retention enforcement scans.
  * `scheduledExploreDiscovery` (every 60 min): Category configuration scans + backlog filling.
  * `scheduledWorkerHealthCheck` (every 15 min): Worker pool status reads.
  * *Confirmed:* Cloud Monitoring metrics verify that pausing these four schedulers reduced consumption from ~265k to ~25k reads/day.
* **Currently Active Schedulers:**
  1. **`scheduledThumbnailRetryProcessor` (Still Active):**
     * Runs every 5 minutes (288 executions/day).
     * Calls `FluxWorkerPool.getPoolStatus(db)` which executes `db.collection("flux_workers").get()` (reads all worker configs).
     * Executes pending retry query on `resources` (counts as at least 1 query read even if empty).
     * Generates **~1,728 reads/day** (51,840 reads/month) in total isolation from user traffic.
  2. **`scheduledThumbnailRecovery` (Orphaned Deployed Cloud Function):**
     * Discovered in `firebase functions:list` running in region `africa-south1`.
     * Removed from source code in commit `e95446d` but never deleted from GCP Cloud Scheduler.
     * Still running perpetually in the background.
* **Evidence Classification:** **Measured** (GCP Monitoring delta confirms scheduler impact; deployed function list confirms active and orphaned functions).

---

### 🟡 HOTSPOT #4: Unbounded Background Chat Messages Listener in `ChatService`
* **Source Location:** [`lib/services/chat_service.dart` (Lines 255–275)](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/services/chat_service.dart#L255-L275)
* **Code Implementation:**
  ```dart
  _messagesSub = convRef
      .collection('messages')
      .orderBy('timestamp', descending: false)
      .snapshots()
      .listen((snapshot) { ... });
  ```
* **Why It Is Wasteful:**
  * `ChatService` is a singleton service that starts listening on `conversations/{userId}/messages` immediately upon user authentication to drive the unread badge.
  * **Zero Limit:** It retrieves all historical messages in the conversation rather than just the latest 20–30 messages or unread count.
  * For active chat users with extensive message threads (e.g. 100–300 messages), every app launch reads the entire conversation thread, even if the user never opens the Chat screen.
* **Evidence Classification:** **Calculated from observed behavior** (code confirmed; conversation collection size measured at 9 docs in current testing).

---

### 🟡 HOTSPOT #5: Bulk Catalog Scans in `CurriculumService`
* **Source Location:** [`lib/services/curriculum_service.dart` (Lines 50–65, 75–85)](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/services/curriculum_service.dart#L50-L65)
* **Code Implementation:**
  ```dart
  _curriculumSub = _firestore.collection('curriculum').snapshots().listen(...);
  // and
  final snap = await _firestore.collection('curriculum').get();
  ```
* **Cost per Execution:** **1,343 document reads** per execution (entire `curriculum` collection).
* **Trigger Mechanism:** Invoked when opening `curriculum_admin_screen.dart` (`startRealtimeSync()`) or calling `fetchAll()`.
* **Why It Is Wasteful:** The entire university curriculum catalog is downloaded in bulk instead of scoping queries by `programCode` or paginating the admin UI.
* **Evidence Classification:** **Measured** (collection count 1,343 docs; code verified).

---

### 🟢 HOTSPOT #6: N+1 Author Profile Reads in `AuthorProfileCache`
* **Source Location:** [`lib/services/author_profile_cache.dart` (Lines 80–120)](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/services/author_profile_cache.dart#L80-L120)
* **Code Implementation:**
  ```dart
  final doc = await _firestore.collection('users').doc(uid).get();
  ```
* **Cost per Execution:** 1 read per distinct commenter on a viewed academic material.
* **Trigger Mechanism:** Triggered by `CommentModal` (`comment_modal.dart:205`) prefetching authors for all comments and nested replies via `AuthorProfileCache().prefetchAll(authorUids)`.
* **Why It Is Wasteful:** When viewing an active material with 20 comments from 20 distinct authors, 20 individual document reads are dispatched to `users/{uid}` instead of denormalizing author display names and avatar URLs directly on the comment document.
* **Evidence Classification:** **Calculated from observed behavior** (code confirmed; in-memory caching mitigates repeated reads within a session).

---

## 3. SUMMARY OF HOTSPOT IMPACT ON SPARK PLAN QUOTA

| Hotspot | Primary Driver | Reads per Event | Frequency / Volume | Daily Read Contribution | % of Spark Quota (50k) |
| :--- | :--- | :---: | :---: | :---: | :---: |
| **#1. ResourceService** | Unbounded `resources` listener | 1,666 docs | 15–30 app opens / pull-to-refresh | **25,000 – 50,000** | **50% – 100%** |
| **#2. NewsRepository** | Explore unindexed fallback query | 515 docs | 10–30 Explore visits / refresh | **5,150 – 15,450** | **10% – 31%** |
| **#3. Thumbnail Retry Cron** | 5-minute background polling | 5–15 docs | 288 executions/day | **~1,728** | **3.5%** |
| **#4. ChatService** | Unbounded message listener | 20–200 docs | Per logged-in active chat user | **500 – 2,000** | **1% – 4%** |
| **#5. CurriculumService** | Admin catalog bulk load | 1,343 docs | On admin screen open | **1,343 – 2,686** | **2.7% – 5.4%** |
| **#6. AuthorProfileCache** | N+1 user lookups on comments | 5–30 docs | Per viewed commented material | **100 – 500** | **< 1%** |

*(No files have been modified, deployed, or committed during this strictly read-only turn.)*
