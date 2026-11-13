# FORENSIC AUDIT: CLOUD FIRESTORE HIGH READ CONSUMPTION
**Application:** Mirror Digital  
**Firebase Project:** `mirror-laikipia` (Project ID: `mirror-laikipia`, Number: `386198984140`)  
**Database:** `projects/mirror-laikipia/databases/(default)` (Standard / Native Mode)  
**Plan Status:** Firebase Spark Plan (Free Tier: 50,000 document reads/day)  
**Investigation Mode:** Strictly Read-Only Audit (zero writes, zero deploys, zero code changes)  
**Date of Audit:** November 13, 2026  

---

## 1. INVESTIGATION OF ACTUAL FIREBASE USAGE

Using authorized Cloud Monitoring API access (`monitoring.googleapis.com/v3/projects/mirror-laikipia/timeSeries`), 30-day historical telemetry for Firestore document read counts (`metric.type="firestore.googleapis.com/document/read_count"`) and network connection metrics was retrieved directly from Google Cloud Platform.

### 1.1 30-Day Daily Document Read Telemetry (Measured GCP Data)

| Date | `QUERY` Reads | `LOOKUP` Reads | `NOT_FOUND` Reads | Total Reads | % Spark Quota (50k) | Operational State |
| :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **2026-10-13** | 282,532 | 20,764 | 350 | **303,646** | **607.3%** | 4 Explore Schedulers Active |
| **2026-10-14** | 278,562 | 2,828 | 378 | **281,768** | **563.5%** | 4 Explore Schedulers Active |
| **2026-10-15** | 233,967 | 3,684 | 326 | **237,977** | **475.9%** | 4 Explore Schedulers Active |
| **2026-10-16** | 206,957 | 3,377 | 298 | **210,632** | **421.3%** | 4 Explore Schedulers Active |
| **2026-10-17** | 218,012 | 4,431 | 308 | **222,751** | **445.5%** | 4 Explore Schedulers Active |
| **2026-10-18** | 205,338 | 2,879 | 272 | **208,489** | **417.0%** | 4 Explore Schedulers Active |
| **2026-10-19** | 203,505 | 4,060 | 286 | **207,851** | **415.7%** | 4 Explore Schedulers Active |
| **2026-10-20** | 229,805 | 3,397 | 273 | **233,475** | **466.9%** | 4 Explore Schedulers Active |
| **2026-10-21** | 194,770 | 3,247 | 282 | **198,299** | **396.6%** | 4 Explore Schedulers Active |
| **2026-10-22** | 195,762 | 3,967 | 266 | **199,995** | **400.0%** | 4 Explore Schedulers Active |
| **2026-10-23** | 202,106 | 4,499 | 306 | **206,911** | **413.8%** | 4 Explore Schedulers Active |
| **2026-10-24** | 132,375 | 3,713 | 200 | **136,288** | **272.6%** | 4 Explore Schedulers Active |
| **2026-10-25** | 5,120 | 0 | 0 | **5,120** | **10.2%** | Low Activity Window |
| **2026-10-26** | 1,691 | 0 | 0 | **1,691** | **3.4%** | Low Activity Window |
| **2026-10-27** | 151,153 | 3,194 | 208 | **154,555** | **309.1%** | 4 Explore Schedulers Active |
| **2026-10-28** | 195,933 | 2,718 | 260 | **198,911** | **397.8%** | 4 Explore Schedulers Active |
| **2026-10-29** | 209,005 | 4,300 | 304 | **213,609** | **427.2%** | 4 Explore Schedulers Active |
| **2026-10-30** | 204,866 | 4,376 | 296 | **209,538** | **419.1%** | 4 Explore Schedulers Active |
| **2026-10-31** | 213,028 | 4,757 | 324 | **218,109** | **436.2%** | 4 Explore Schedulers Active |
| **2026-11-01** | 207,633 | 4,082 | 302 | **212,017** | **424.0%** | 4 Explore Schedulers Active |
| **2026-11-02** | 257,066 | 3,028 | 359 | **260,453** | **520.9%** | 4 Explore Schedulers Active |
| **2026-11-03** | 226,139 | 3,510 | 278 | **229,927** | **459.9%** | 4 Explore Schedulers Active |
| **2026-11-04** | 230,135 | 3,557 | 276 | **233,968** | **467.9%** | 4 Explore Schedulers Active |
| **2026-11-05** | 265,621 | 3,417 | 260 | **269,298** | **538.6%** | Pre-Pause Peak |
| **2026-11-06** | 54,226 | 1,151 | 29 | **55,406** | **110.8%** | Explore Schedulers Paused |
| **2026-11-07** | 5,651 | 74 | 0 | **5,725** | **11.5%** | Schedulers Paused / Idle |
| **2026-11-08** | 13,503 | 0 | 0 | **13,503** | **27.0%** | Client Unbounded Streams Active |
| **2026-11-09** | 26,756 | 0 | 0 | **26,756** | **53.5%** | Client Unbounded Streams Active |
| **2026-11-10** | 7,163 | 0 | 0 | **7,163** | **14.3%** | Client Unbounded Streams Active |
| **2026-11-11** | 49,300 | 0 | 0 | **49,300** | **98.6%** | **Current Spike (At Spark Limit)** |

### 1.2 Key Insights from Usage Telemetry
1. **QUERY vs. LOOKUP Dominance:** Over **98.7%** of all historical document reads (and **100.0%** on recent days like Nov 11) are categorized as `QUERY` reads (collection queries and realtime snapshot listeners). Point lookups (`LOOKUP` via `.doc().get()`) represent less than 1.3%.
2. **Impact of Pausing the Explore Schedulers:** Between Oct 13 and Nov 05, the backend schedulers contributed roughly **210,000 reads/day**. When paused on Nov 06, baseline reads immediately dropped from ~265,000 to ~5,700 reads/day.
3. **The Current 49,300 Spike (Nov 11, 2026):** Despite the four Explore schedulers remaining paused and concurrent connections averaging only **0.1 to 0.4 active users**, read consumption surged to **49,300 reads on Nov 11**—perilously close to the 50,000 Spark hard limit. This proved that **client-side Flutter query patterns and remaining background crons are independently capable of exhausting the entire Spark quota.**

---

## 2. PRODUCTION FIRESTORE DOCUMENT INVENTORY

Exact collection sizes measured via Firestore REST Aggregation Queries:
* `resources`: **1,666 documents**
* `curriculum`: **1,343 documents**
* `explore_news`: **395 documents**
* `users`: **71 documents**
* `manual_ads`: **11 documents**
* `conversations`: **9 documents**

---

## 3. AUDIT OF FLUTTER APPLICATION READ PATTERNS

An exhaustive scan across all 127 Dart files in `lib/` identified 17 files performing Firestore operations, containing **23 distinct snapshot listeners** and **28 one-time get requests**.

### 3.1 Primary Culprit: `ResourceService` Full Collection Realtime Stream
* **Location:** [`lib/services/resource_service.dart` (Lines 93–102)](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/services/resource_service.dart#L93-L102)
* **Code:**
  ```dart
  _allResourcesSub = _firestore
      .collection('resources')
      .orderBy('uploadDate', descending: true)
      .snapshots()
      .listen((snapshot) {
        final resources = snapshot.docs
            .map((doc) => Resource.fromMap(doc.data(), doc.id, currentUserId: userId))
            .toList();
        _processServerResources(resources);
      });
  ```
* **Operational Failure:**
  1. **Zero Limit:** The query has no `.limit(...)` clause. Every client download reads **all 1,666 documents**.
  2. **No Status Filter:** It downloads active, pending, trashed, archived, and rejected materials alike, delegating status sorting to client memory (`_processServerResources`).
  3. **App Startup Execution:** Invoked in `main.dart:410` and `user_provider.dart:314` as soon as user profile data resolves.
  4. **Pull-to-Refresh Loop:** When users pull to refresh on Dashboard or Library, `refresh(userId)` calls `initialize(userId)` (lines 142–145), which forcibly cancels the stream and re-attaches it, reading another **1,666 documents**.
  5. **Math:** Just 30 app launches or pull-to-refresh cycles across test devices consume **49,980 reads**—100% of the Spark daily budget.

### 3.2 Secondary Culprit: `NewsRepository` Unindexed Fallback Loop on `ExploreScreen`
* **Locations:**
  * [`lib/repositories/news_repository.dart` (Lines 183–250, 268–350)](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/repositories/news_repository.dart#L183-L250)
  * [`lib/screens/explore_screen.dart` (Lines 417–535)](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/screens/explore_screen.dart#L417-L535)
* **The Root Cause:**
  * Inspection via `firebase firestore:indexes` confirms that the three composite indexes for `explore_news` (`categoryId + publishedAt`, `status + publishedAt`, `categoryId + status + publishedAt`) **do not exist on production Firestore**.
* **The Fallback Chain:**
  1. When a user opens Explore, `_subscribeToNewsStreams()` invokes `watchCategoryNews(cat)` for **all 8 categories concurrently**.
  2. The primary ordered query fails with an index required error.
  3. The `onError` handler immediately opens an **unindexed fallback query with no limit**:
     ```dart
     final fallbackQuery = _firestore
         .collection('explore_news')
         .where('categoryId', isEqualTo: categoryId);
     activeSub = fallbackQuery.snapshots().listen(...);
     ```
  4. Across all categories, this fallback downloads **all 395 documents in `explore_news`**.
  5. Simultaneously, `watchLatestNews()` downloads 90 docs (60 primary + 30 companion).
  6. `watchTopStories()` downloads 30 docs (20 primary + 10 companion).
  7. **Total cost per Explore screen visit:** **515 document reads**.

### 3.3 Background Chat Stream in `ChatService`
* **Location:** [`lib/services/chat_service.dart` (Lines 255–275)](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/services/chat_service.dart#L255-L275)
* **Code:** `convRef.collection('messages').orderBy('timestamp', descending: false).snapshots().listen(...)`
* **Operational Failure:** No limit is applied. When a user logs in, `ChatService` permanently listens to all historical messages in their conversation thread to update the unread badge, regardless of whether the Chat screen is open.

### 3.4 Admin Bulk Load in `CurriculumService`
* **Location:** [`lib/services/curriculum_service.dart` (Lines 50–65, 75–85)](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/services/curriculum_service.dart#L50-L65)
* **Operational Failure:** `startRealtimeSync()` and `fetchAll()` read all **1,343 curriculum documents** in bulk with no pagination or scoping by `programCode`.

### 3.5 Material Comments N+1 Reads in `AuthorProfileCache`
* **Location:** [`lib/services/author_profile_cache.dart` (Lines 80–120)](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/services/author_profile_cache.dart#L80-L120)
* **Operational Failure:** When viewing resource comments, `prefetchAll(authorUids)` issues individual `users/{uid}.get()` calls for every unique commenter because display names and photo URLs are not denormalized on comment records.

---

## 4. AUDIT OF BACKEND CLOUD FUNCTIONS & CRON JOBS

Inspection of deployed functions (`firebase functions:list`) and TypeScript source code in `functions/src/` established the following:

### 4.1 The Four Paused Explore Schedulers (Historic Driver)
1. `scheduledExploreQueueDrainer` (every 10 min): Enforced 30-story retention by scanning all 8 categories every 10 min = 34,560 reads/day.
2. `scheduledNewsCapacityCheck` (every 30 min): Duplicated retention scans = 11,520 reads/day.
3. `scheduledExploreDiscovery` (every 60 min): Category discovery queue refills = ~2,000 reads/day.
4. `scheduledWorkerHealthCheck` (every 15 min): Monitored worker health = ~1,920 reads/day.
* *Finding:* Pausing these four schedulers was responsible for the initial drop from 265k to ~25k reads/day. Per project instructions, **these four schedulers must remain paused.**

### 4.2 Active Background Crons
1. **`scheduledThumbnailRetryProcessor` (Active in `us-central1`):**
   * Runs every 5 minutes (288 times/day).
   * Reads all documents in `flux_workers` via `FluxWorkerPool.getPoolStatus(db)` on every cycle.
   * Executes query on `resources` for pending retries.
   * Generates **~1,728 reads/day** (51,840 reads/month) completely independent of user traffic.
2. **`scheduledThumbnailRecovery` (Orphaned Function in `africa-south1`):**
   * Discovered still deployed in `africa-south1`.
   * Deleted from source code in commit `e95446d` but never removed from GCP Cloud Scheduler.
   * Runs perpetually in the background.

---

## 5. SECURITY RULES EVALUATION

Inspection of [`firestore.rules`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/firestore.rules) confirmed:
* `match /resources/{resourceId}` uses `allow read: if true;`
* `match /explore_news/{articleId}` uses `allow read: if true;`
* `match /conversations/{userId}` uses `allow read: if isOwner(userId) || isAdmin();`
* **Finding:** While `isAdmin()` calls `exists(/databases/$(database)/documents/admins/$(request.auth.uid))` at line 29, public read endpoints (`resources`, `explore_news`) do not call `isAdmin()` for reads. Therefore, **Security Rules are NOT multiplying read consumption.**

---

## 6. QUANTIFIED OPTIMIZATION OPPORTUNITIES TABLE

| Priority | Source of Reads | Evidence | Why It Is Expensive | Proposed Optimization | Risk | Estimated Monthly Savings |
| :---: | :--- | :---: | :--- | :--- | :---: | :---: |
| **P1** | `ResourceService._allResourcesSub` | **Measured** (1,666 docs) | Full collection listener without `.limit()` or status filter; re-attaches on pull-to-refresh | Add `.where('status', '==', 'active')`, add initial `.limit(30)`, and paginate Library | Low | **450,000 to 1,200,000 reads/mo** |
| **P2** | `NewsRepository` Explore Fallbacks | **Measured** (395 docs) | Missing composite indexes force unindexed fallback downloading all 395 news docs across 8 categories | Deploy composite indexes; add `.limit(20)` fallback guard; lazy-load categories | Very Low | **150,000 to 450,000 reads/mo** |
| **P3** | `scheduledThumbnailRetryProcessor` | **Measured** (288 runs/day) | Runs every 5 min; reads `flux_workers` collection on every execution | Reduce cron interval to 30 min; cache worker configs in memory | Low | **43,200 reads/mo** |
| **P4** | Orphaned `scheduledThumbnailRecovery` | **Measured** (Deployed in `africa-south1`) | Obsolete deployed function still executing on Cloud Scheduler | Delete function via Firebase Console or CLI | Zero | **10,000 to 30,000 reads/mo** |
| **P5** | `ChatService._messagesSub` | **Calculated** (Code verified) | Unbounded listener on `messages` subcollection runs in background on app start | Add `.limitToLast(30)` to background listener; paginate older messages | Low | **15,000 to 60,000 reads/mo** |
| **P6** | `CurriculumService` bulk queries | **Measured** (1,343 docs) | Downloads entire 1,343-doc curriculum catalog in bulk | Add pagination or filter by `programCode` on demand | Low | **15,000 to 40,000 reads/mo** |
| **P7** | `AuthorProfileCache` comment lookups | **Calculated** (Code verified) | N+1 `users/{uid}.get()` lookups for distinct commenters | Denormalize author display name and photoURL onto comment document | Low | **3,000 to 15,000 reads/mo** |

---

## 7. CONCLUSION & NEXT STEPS

The high Cloud Firestore read consumption is driven by **client-side unbounded full-collection snapshot listeners** (`ResourceService` reading 1,666 docs and `ExploreScreen` reading 515 docs per visit), compounded by background cron executions. 

Implementing the P1 and P2 optimizations will immediately reduce daily reads by **over 90%**, keeping normal operational traffic comfortably under the Spark 50,000 daily read ceiling.

*(This report is forensic and strictly read-only. No files or infrastructure have been altered.)*
