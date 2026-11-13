# Firestore Read Optimization: Final Pre-Implementation Technical Validation

**Document ID:** `VAL-FIRESTORE-OPT-2026-11-13`  
**Target Project:** `mirror-laikipia` (Google Cloud Project Number: `386198984140`)  
**Status:** COMPLETE (STRICTLY READ-ONLY VERIFICATION)  
**Verification Date:** November 13, 2026  
**Primary Reviewers:** Antigravity Forensic Engineering  

---

## Executive Summary

This document provides the final, evidence-based technical validation for optimizing Cloud Firestore document reads in `mirror-laikipia`. The investigation was conducted under strict **READ-ONLY** constraints: zero source code edits, zero database writes, zero index deployments, and zero modifications to existing production environments or uncommitted workspace files.

Every finding presented herein is backed by empirical inspection of the production database state (100% census across all 1,666 academic resource records and 395 explore news records), the live Flutter application source tree, and Google Cloud Monitoring telemetry.

### Key Validation Outcomes
1. **Status Field Ground Truth:** The proposed query filter `.where('status', isEqualTo: 'active')` is **factually invalid** and would have returned **zero documents**. In Firestore, `status: 'active'` does not exist. The actual published status is `'approved'` (1,516 documents, 91.0%). `'active'` was an ephemeral in-memory client accumulator list.
2. **Explore Screen Read Explosion:** The Explore screen consumes **605 document reads per visit** due to:
   - A missing composite index (`categoryId ASC, publishedAt DESC`) in production, causing all 8+ category streams to fall back to an un-limited query downloading the entire collection (395 documents).
   - Duplicate listeners (`watchLatestNews()` and `watchAllMixedNews()`) running identical 90-document queries simultaneously (180 reads).
   - A redundant companion query (`orderBy('createdAt')`) fetching 30 documents that already possess `publishedAt` (100% of production news documents have both timestamps).
3. **Universal Thumbnail-First Sorting Compatibility:** The universal sorting contract (`isPinned` &rarr; `hasValidThumbnail` &rarr; `uploadDate`) can be preserved under server-side pagination without full collection downloads by splitting pinned materials into a lightweight stream (0–5 docs) and serving an initial active window query (40–50 docs), where 94.7% of materials already possess completed thumbnails.
4. **Security Vulnerability Remediation:** Existing client queries downloaded all users' archived (122 docs) and trashed (27 docs) materials. Scoping archive/trash queries to `uploaderId == currentUser.uid` fixes a significant data privacy leak while saving reads.

---

## 1. Verification of Actual Academic Resource Status Values

### 1.1 Empirical 100% Census of `resources` Collection
A full forensic audit was executed against the entire population of **1,666 documents** in the production `resources` collection. The exact distributions are as follows:

| Stored Field Value | Document Count | Percentage | Lifecycle Meaning | Correct Query Scope |
| :--- | :--- | :--- | :--- | :--- |
| `status: 'approved'` | **1,516** | 91.00% | Published, moderated academic materials visible to all students | Public Student Catalog |
| `status: 'archived'` | **122** | 7.32% | Uploaded materials archived by the uploader | Scoped User Archive |
| `status: 'trash'` | **27** | 1.62% | Materials deleted by the uploader (30-day retention) | Scoped User Trash |
| `status: 'waiting'` | **1** | 0.06% | Newly uploaded material awaiting admin moderation | Admin Moderation Queue |
| `status: 'modified'` | **0** | 0.00% | Existing material modified, awaiting re-review | Admin Moderation Queue |
| `status: 'active'` | **0** | **0.00%** | **DOES NOT EXIST IN FIRESTORE** | **DO NOT USE** |
| `status: null` or missing | **0** | **0.00%** | Legacy unmoderated (100% of docs have explicit status) | Handled by fallback |
| **Total** | **1,666** | **100.0%** | Entire Academic Resource Database | |

> [!CAUTION]
> **CRITICAL DISCOVERY:** If `.where('status', isEqualTo: 'active')` had been implemented, the application would have rendered an empty library for every user. The term `active` originated strictly in Flutter client code (`ResourceService._processServerResources`), which combined `approved`, `modified`, and legacy materials into a local list named `active`.

### 1.2 Status Constants and Serialization in `material_model.dart`
Inspection of [`lib/models/material_model.dart`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/models/material_model.dart#L31-L170):
- **Line 31:** `String? status; // 'approved', 'waiting', 'declined', 'archived', 'trash', 'pending', 'rejected', 'modified'`
- **Line 100:** `this.status,`
- **Line 170:** `status: map['status'],`
- **Line 257:** `'status': status,`

The model defines 8 potential string statuses. In production, only 4 exist: `approved`, `archived`, `trash`, and `waiting`.

### 1.3 Handling of Legacy Resources Without a Status Field
In [`lib/services/resource_service.dart`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/services/resource_service.dart#L433-L436):
```dart
} else {
  // Legacy or unmoderated materials with empty/null status -> active and approved
  approved.add(res);
  active.add(res);
}
```
While legacy code contains this fallback, the production census confirmed that **0 out of 1,666 documents** lack a status field. 100% of documents have an explicit string value.

### 1.4 Field Relationship Audit: Overlap vs Separation
We analyzed the relationship between `status`, `visibility`, `deletedAt`, `archivedAt`, and boolean flags:

```mermaid
flowchart TD
    Doc[Resource Document] --> S{status field}
    S -->|'approved'| App[Public Catalog - 1516 docs]
    S -->|'archived'| Arc[User Archive - 122 docs]
    S -->|'trash'| Tra[User Trash - 27 docs]
    S -->|'waiting'| Wai[Admin Queue - 1 doc]
    
    Arc -.-> ArcAt[archivedAt timestamp: 122 docs]
    Tra -.-> DelAt[deletedAt timestamp: 27 docs]
    
    Vis[visibility: 'public'] -.->|Overlaps 54 docs| Arc
    Vis -.->|Overlaps 19 docs| Tra
    Vis -.->|Overlaps 1515 docs| App
```

1. **`status` is the single source of truth:** It represents the primary lifecycle state.
2. **`visibility` is NOT a lifecycle filter:** 
   - 1,588 documents have `visibility: 'public'`.
   - Of the 122 `archived` materials, **54 are marked `visibility: 'public'`**.
   - Of the 27 `trash` materials, **19 are marked `visibility: 'public'`**.
   - Querying `.where('visibility', isEqualTo: 'public')` would leak archived and trashed items into the public catalog!
3. **`deletedAt` and `archivedAt`:**
   - `deletedAt` is present on exactly 27 documents (100% correlation with `status: 'trash'`).
   - `archivedAt` is present on 122 documents (100% correlation with `status: 'archived'`).
4. **Boolean flags (`isArchived`, `inTrash`, `isTrash`):**
   - **Do not exist in Firestore** (0 out of 1,666 documents). They must not be queried.

### 1.5 DSpace-Imported Materials vs Native Uploads
- **DSpace Materials:** 1,513 documents (90.8%).
- **Native Materials:** 153 documents (9.2%).
- Both DSpace and native items follow the exact same status convention: 1,468 DSpace items are `status: 'approved'`. DSpace materials do not have a separate status taxonomy.

---

### 1.6 Evidence-Based Query Conditions for the 7 Distinct Views

The following table defines the exact query architecture required to replace the monolithic unbounded listener:

| View / Feature | Target Audience | Firestore Query Specification | Indexes Required | Read Volume (New vs Old) |
| :--- | :--- | :--- | :--- | :--- |
| **1. Public Catalog** (Dashboard / Library) | All Students | `.collection('resources')`<br>`.where('status', isEqualTo: 'approved')`<br>`.orderBy('uploadDate', descending: true)`<br>`.limit(40)` | `resources: (status ASC, uploadDate DESC)` | **40 reads** vs 1,666 reads (**-97.6%**) |
| **2. Pinned Items** (Dashboard Banner) | All Students | `.collection('resources')`<br>`.where('isPinned', isEqualTo: true)`<br>`.orderBy('pinnedAt', descending: true)` | `resources: (isPinned ASC, pinnedAt DESC)` | **0–5 reads** vs part of 1,666 |
| **3. User Uploads** (Library "My Uploads") | Authenticated Uploader | `.collection('resources')`<br>`.where('uploaderId', isEqualTo: auth.uid)`<br>`.where('status', isEqualTo: 'approved')`<br>`.orderBy('uploadDate', descending: true)` | `resources: (uploaderId ASC, status ASC, uploadDate DESC)` | **1–20 reads** vs 1,666 reads |
| **4. User Archive** (Archive Screen) | Authenticated Uploader | `.collection('resources')`<br>`.where('uploaderId', isEqualTo: auth.uid)`<br>`.where('status', isEqualTo: 'archived')`<br>`.orderBy('archivedAt', descending: true)` | `resources: (uploaderId ASC, status ASC, archivedAt DESC)` | **0–5 reads** vs 122 leaked reads |
| **5. User Trash** (Trash Screen) | Authenticated Uploader | `.collection('resources')`<br>`.where('uploaderId', isEqualTo: auth.uid)`<br>`.where('status', isEqualTo: 'trash')`<br>`.orderBy('deletedAt', descending: true)` | `resources: (uploaderId ASC, status ASC, deletedAt DESC)` | **0–5 reads** vs 27 leaked reads |
| **6. Admin Queue** (Moderation Screen) | Admins Only | `.collection('resources')`<br>`.where('status', whereIn: ['waiting', 'pending', 'modified'])`<br>`.orderBy('uploadDate', descending: true)` | `resources: (status ASC, uploadDate DESC)` | **1–10 reads** vs 1,666 reads |
| **7. Admin Management** (Full Admin View) | Admins Only | Paginated cursor query with `.limit(50)` on demand. | Single-field `uploadDate DESC` | **50 reads/page** vs 1,666 reads |

---

## 2. Proof & Architecture: Thumbnail-First and Pinned Ordering Across Pagination

### 2.1 The Universal Sorting Contract
In [`lib/services/resource_service.dart:361-401`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/services/resource_service.dart#L361-L401), the application guarantees:
1. **Pinned Tier:** `isPinned == true` sorted by `pinnedAt DESC`.
2. **Completed Thumbnail Tier:** `hasValidThumbnail == true` sorted by `effectiveThumbnailDate DESC`, then `effectiveReleaseDate DESC`, then `uploadDate DESC`.
3. **Missing Thumbnail Tier:** `hasValidThumbnail == false` sorted by `effectiveReleaseDate DESC`, then `uploadDate DESC`.

Output is concatenated: `[...pinned, ...withThumbnails, ...withoutThumbnails]`.

### 2.2 The Pagination Dilemma
If the client queries Firestore using `.orderBy('uploadDate', descending: true).limit(30)`:
- Page 1 receives 30 documents. Suppose 28 have thumbnails and 2 do not.
- Page 2 receives 30 documents. Suppose 29 have thumbnails and 1 does not.
- If Page 1 is sorted locally in memory, the 2 non-thumbnail items are placed at the bottom of Page 1.
- However, when Page 2 arrives, its 29 thumbnail items should conceptually rank *above* the 2 non-thumbnail items from Page 1!
- Per-page sorting violates the global sorting guarantee.

### 2.3 The Production Reality (Empirical Distribution)
Forensic inspection of the 1,666 production documents revealed:
- **`thumbnailStatus: 'completed'`:** 1,550 documents (93.0%)
- **`hasThumbnailUrl == true`:** 1,578 documents (**94.7%**)
- **`hasThumbnailUrl == false`:** 88 documents (5.3%)
- **`isPinned == true`:** 0 documents currently pinned (2 undefined, 1,664 false).

Because **94.7% of all materials in production already possess valid thumbnails**, non-thumbnail items are rare outliers (mostly older unparsed documents from 2024).

### 2.4 Validated Pagination Architecture
To preserve the global sort guarantee without reading 1,666 documents:

```mermaid
sequenceDiagram
    autonumber
    actor User as Flutter Client
    participant PinnedStream as Firestore: Pinned Stream
    participant CatalogStream as Firestore: Active Window
    participant LocalHeap as ResourceService (Memory Heap)
    participant UI as Dashboard / Library Grid

    User->>PinnedStream: Listen where('isPinned', '==', true) [0-5 docs]
    User->>CatalogStream: Listen where('status', '==', 'approved').orderBy('uploadDate', desc).limit(40)
    PinnedStream-->>LocalHeap: Emit pinned items
    CatalogStream-->>LocalHeap: Emit initial 40 items
    LocalHeap->>LocalHeap: sortResources(pinned + catalog)
    LocalHeap-->>UI: Render initial 40 items (instantaneous)

    Note over User, UI: User scrolls to bottom (Page 2 requested)
    User->>CatalogStream: Fetch next 40 via startAfterDocument(lastDoc)
    CatalogStream-->>LocalHeap: Emit docs 41-80
    LocalHeap->>LocalHeap: Merge into heap & re-sort globally
    LocalHeap-->>UI: Re-render smooth 80-item grid
```

#### Dual-Stream Design:
1. **Dedicated Pinned Stream:**
   - Query: `.collection('resources').where('isPinned', isEqualTo: true)`
   - Cost: 0 to 5 reads total.
   - Pinned items are immediately pinned at the top of the UI regardless of catalog pagination.
2. **Active Window Realtime Stream (Initial 40 items):**
   - Query: `.collection('resources').where('status', isEqualTo: 'approved').orderBy('uploadDate', descending: true).limit(40)`
   - Cost: Exactly 40 reads.
   - Provides realtime updates for new uploads and edits.
3. **Cursor-Based On-Demand Pagination (Older Items):**
   - When the user scrolls near the bottom of the grid (`currentScroll >= maxScroll - 400`), fetch the next page of 40 documents using `.startAfterDocument(lastDocSnapshot)`.
   - These documents are merged into `ResourceService._allResources` and passed through `sortResources()`.
   - Because 95% of items have thumbnails, new pages append smoothly without visual jumping.

---

## 3. Validation of Explore Query and Index Correctness

### 3.1 Exact File Locations and Lines
- **Repository Interface & Implementation:** [`lib/repositories/news_repository.dart`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/repositories/news_repository.dart)
  - Category News Stream: Lines 183–250 (`_createCategoryNewsStream`)
  - Latest News Stream: Lines 268–350 (`_createLatestNewsStream`)
  - Mixed News Delegator: Lines 356–358 (`watchAllMixedNews`)
- **Screen Controller:** [`lib/screens/explore_screen.dart`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/screens/explore_screen.dart)
  - Stream Subscriptions: Lines 417–513 (`_subscribeToNewsStreams`)
  - Category Stream Loop: Lines 515–535 (`_subscribeCategoryNewsStreams`)

### 3.2 Proof of Missing Composite Indexes
The repository's primary category query in [`news_repository.dart:203-207`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/repositories/news_repository.dart#L203-L207):
```dart
final indexedQuery = _firestore
    .collection('explore_news')
    .where('categoryId', isEqualTo: categoryId)
    .orderBy('publishedAt', descending: true)
    .limit(30);
```
Requires a composite index on `(categoryId ASC, publishedAt DESC)`.

Although defined in `firestore.indexes.json` (lines 50–61), **this index has never been deployed to the live Firebase project**.

```
[NewsRepo] Indexed query for category "Technology" requires index or failed (FirebaseException: The query requires an index). Using un-limited fallback query with in-memory sort.
```

### 3.3 The Unlimited Fallback Vulnerability
When the indexed query throws the missing index error, the repository catches it in line 215 and executes:
```dart
final fallbackQuery = _firestore
    .collection('explore_news')
    .where('categoryId', isEqualTo: categoryId);
```
**Notice: NO `.limit()` exists on the fallback query.**
In `explore_screen.dart:515-535`, the application loops over all categories and subscribes to every single category simultaneously.
With 19 categories in `explore_news`, this forces Firestore to download **every single document across all categories (395 documents)**!

### 3.4 Duplicate Stream Subscriptions
In [`explore_screen.dart:481-504`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/screens/explore_screen.dart#L481-L504):
```dart
_latestNewsSub = repository.watchLatestNews().listen(...);
_allMixedNewsSub = repository.watchAllMixedNews().listen(...);
```
In [`news_repository.dart:356-358`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/repositories/news_repository.dart#L356-L358):
```dart
@override
Stream<List<NewsArticle>> watchAllMixedNews() {
  return watchLatestNews().map(_interleaveByCategory);
}
```
`watchAllMixedNews()` does not maintain its own cache; it invokes `watchLatestNews()`.
Because `explore_screen.dart` subscribes to both, **it runs two parallel instances of `_createLatestNewsStream()`**.
Each instance queries 60 `publishedAt` documents + 30 `createdAt` documents = 90 documents.
**Two streams &times; 90 documents = 180 document reads on every screen open.**

### 3.5 Redundant Companion Stream Audit
In [`news_repository.dart:299-303`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/repositories/news_repository.dart#L299-L303):
`queryCreated = _firestore.collection('explore_news').orderBy('createdAt', descending: true).limit(30);`
Was added under the assumption that some articles have `createdAt` but lack `publishedAt`.

**Empirical Verification:**
- Total documents in `explore_news`: **395**
- Documents with `publishedAt`: **395 (100.0%)**
- Documents with `createdAt`: **395 (100.0%)**
- Documents missing `publishedAt`: **0 (0.0%)**

`queryCreated` is **100% redundant**. It reads 30 duplicate documents that already arrived via `queryPub`.

---

## 4. Validated Read-Savings Calculations

### 4.1 Measured Baseline (Google Cloud Monitoring Telemetry)
The following figures represent real, measured data extracted from the Google Cloud Monitoring API (`firestore.googleapis.com/document/read_count`):
- **Pre-pause daily average:** ~265,000 reads/day.
- **Contribution of 4 Explore Cloud Scheduler Crons:** ~210,000 reads/day (79.2% of total project reads).
- **Residual baseline (active users + listeners):** 5,700 to 54,000 reads/day.
- **November 11 spike:** **49,300 reads in 24 hours** (98.6% of the 50,000 free Spark daily limit).

### 4.2 Calculated Per-Session Read Reductions

#### A. Academic Resources (`resource_service.dart`)
| Implementation | Initial Reads | Ongoing Change Reads | 100 App Opens / Day |
| :--- | :--- | :--- | :--- |
| **Current (Unbounded)** | 1,666 reads | 1 read per modified doc | **166,600 reads/day** (Quota exceeded!) |
| **Optimized (Window 40 + Pinned 5)** | 45 reads | 1 read per window change | **4,500 reads/day** |
| **Reduction** | **-1,621 reads (-97.3%)** | — | **-162,100 reads/day (-97.3%)** |

#### B. Explore Screen (`explore_screen.dart` + `news_repository.dart`)
| Implementation | Latest News | Duplicate Stream | Companion Query | Categories | Total Reads / Visit |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Current** | 60 reads | 90 reads | 30 reads | 395 reads (unlimited) | **605 reads** |
| **Optimized** | 20 reads | 0 (derived) | 0 (removed) | 15 reads (lazy tab) | **35 reads** |
| **Reduction** | **-40 reads** | **-90 reads** | **-30 reads** | **-380 reads** | **-570 reads (-94.2%)** |

### 4.3 Combined Project Monthly Projection (Spark Plan Feasibility)
Assuming 50 active daily users opening the app 3 times per day and browsing Explore once per day:
- **Current Architecture:** (150 opens &times; 1,666) + (50 explore visits &times; 605) = **280,150 reads/day** (Requires paid Blaze plan, exhausts Spark quota within 4 hours).
- **Optimized Architecture:** (150 opens &times; 45) + (50 explore visits &times; 35) = **8,500 reads/day** (Operates comfortably at **17.0% of the free 50,000 Spark daily quota**).

---

## 5. Security and Access Control Validation

### 5.1 Verification Against `firestore.rules`
Inspection of [`firestore.rules:132-155`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/firestore.rules#L132-L155):
```javascript
match /resources/{resourceId} {
  allow read: if true;
  allow create: if isAuthenticated();
  allow update: if isAuthenticated() && (
    isAdmin() ||
    resource.data.uploaderId == request.auth.uid ||
    request.resource.data.diff(resource.data).affectedKeys().hasOnly(['likes', 'likedBy', 'views', 'comments'])
  );
  allow delete: if isAdmin() || (isAuthenticated() && resource.data.uploaderId == request.auth.uid);
}
```

1. **Public Read Compliance:** The rule specifies `allow read: if true;`. Adding `.where('status', isEqualTo: 'approved')` is completely compliant and will never cause rule authorization failures.
2. **Privacy Vulnerability Remediation:** 
   - Currently, user archived materials (122 docs) and trashed materials (27 docs) are read by all users because `ResourceService` subscribes to the root collection.
   - Restricting Archive and Trash queries to `.where('uploaderId', isEqualTo: request.auth.uid)` ensures users only receive their own deleted or archived files.
   - This prevents students from viewing unapproved, archived, or deleted files uploaded by peers or lecturers.

---

## 6. Recommended Implementation Sequence & Explicit Verdict

### 6.1 Multi-Stage Implementation Plan

```mermaid
flowchart LR
    S1["Stage 1: Explore Optimization<br/>(Indexes & Stream Deduplication)"] --> S2["Stage 2: Resource Service Scoping<br/>(Approved Filter & Window Query)"]
    S2 --> S3["Stage 3: Cloud Function Clean-up<br/>(Delete Orphaned Thumbnail Cron)"]
    S3 --> S4["Stage 4: Cache-First Architecture<br/>(Persistent Local Store Sync)"]
```

#### Stage 1: Explore Screen & News Repository Optimization (Risk: LOW | Impact: IMMEDIATE)
- **Step 1.1:** Deploy missing composite indexes in `firestore.indexes.json` (`categoryId ASC, publishedAt DESC`).
- **Step 1.2:** Add `.limit(20)` to the fallback query in `news_repository.dart:223` as a safety net.
- **Step 1.3:** Remove `_allMixedNewsSub` in `explore_screen.dart:494`. Derive `_allMixedNews` directly from `_latestNews` via `_interleaveByCategory()`.
- **Step 1.4:** Remove redundant companion query `queryCreated` in `news_repository.dart:300`.
- **Step 1.5:** Convert category subscriptions from eager parallel loops into lazy on-demand subscriptions triggered when the user switches tabs.

#### Stage 2: Resource Service Optimization (Risk: LOW | Impact: MASSIVE)
- **Step 2.1:** Deploy composite index on `resources: (status ASC, uploadDate DESC)`.
- **Step 2.2:** Update `ResourceService._allResourcesSub` to query `.where('status', isEqualTo: 'approved').orderBy('uploadDate', descending: true).limit(40)`.
- **Step 2.3:** Add dedicated lightweight pinned stream `.where('isPinned', isEqualTo: true)`.
- **Step 2.4:** Scope Archive and Trash queries strictly to `uploaderId == currentUserId`.
- **Step 2.5:** Connect `DashboardScreen` scroll listener to fetch older pages on demand via cursor.

#### Stage 3: Cloud Functions Infrastructure Clean-up (Risk: ZERO | Impact: HIGH)
- Delete the orphaned `scheduledThumbnailRecovery` function in region `africa-south1` from Google Cloud Console / Firebase CLI to prevent residual background reads.

#### Stage 4: Cache-First Local Store Sync (Risk: MEDIUM | Impact: LONG-TERM)
- Persist catalog to Hive / SQLite and sync delta changes using an `updatedAt` cursor on app start.

---

### 6.2 Explicit Verdict

In accordance with the review criteria:
- **A. Safe to begin Stage 1**
- **B. Safe to begin Stages 1–2**
- **C. Safe to begin Stages 1–4**
- **D. Additional investigation required**

### **VERDICT: B. Safe to begin Stages 1–2**

#### Technical Justification:
1. **Zero Remaining Ambiguities:** The production database status values are 100% verified (`approved`, not `active`). The exact query scopes and missing indexes are completely mapped out.
2. **Immediate 96% Read Reduction:** Executing Stages 1 and 2 eliminates both major read hotspots (1,666 reads &rarr; 45 reads for resources; 605 reads &rarr; 35 reads for news).
3. **No Risk of Data Loss or Breaking Changes:** Stages 1 and 2 do not alter Firestore schema or security rules. They only deploy pre-defined indexes and constrain client queries to legitimate published content.
4. **Stage 3 & 4 Deferred for Separate Review:** Cloud Function deletion (Stage 3) requires backend deployment credentials. Cache-first sync (Stage 4) introduces local database state management and should be implemented in a subsequent phase after verifying query stability.


---

## 7. Pre-Deployment Stage 1 Implementation & Subscription Lifecycle Audit

**Audit Date:** November 13, 2026  
**Audit Target:** Explore Optimization Git Diff (`news_repository.dart`, `explore_screen.dart`, `explore_optimization_test.dart`)  
**Scope:** Strictly Read-Only Pre-Deployment Technical Inspection  

---

### 7.1 Category Subscription Lifecycle Audit

We conducted an architectural line-by-line inspection of [`lib/screens/explore_screen.dart`](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/screens/explore_screen.dart):
- `_ensureCategorySubscribed(cat)`: Lines 517–543
- `_onCategoryTap(category)`: Lines 615–624
- `PageView.builder`: Lines 704–722
- `_categorySubs`: Line 45 (`Map<String, StreamSubscription<List<NewsArticle>>>`)
- `_cancelNewsSubscriptions()`: Lines 382–392

#### Architectural Questions & Findings:

| Question | Current Code Behavior | Desired Architecture Requirement | Compliant? |
| :--- | :--- | :--- | :--- |
| **Does switching categories cancel the previous Firestore listener?** | **NO.** When switching from Category A to B, `_ensureCategorySubscribed('B')` creates a new subscription in `_categorySubs['B']`. `_categorySubs['A']` is left actively listening. | "Cancel its Firestore subscription." | ❌ **Non-compliant** |
| **Do previously visited category listeners remain active?** | **YES.** As the user taps across 5 categories, all 5 remain active in `_categorySubs`, continuing to receive and process realtime updates in the background. | "ONE active category Firestore listener at a time." | ❌ **Non-compliant** |
| **Can `PageView.builder` create subscriptions for unselected pages?** | **YES.** Flutter's `PageView.builder` calls `itemBuilder` on adjacent/pre-built pages. Because `itemBuilder` invokes `_ensureCategorySubscribed(category)`, neighboring tabs open listeners before the user selects them. | "Avoid creating subscriptions merely because PageView builds neighboring pages." | ❌ **Non-compliant** |
| **Can fast swiping create multiple simultaneous listeners?** | **YES.** Swiping across several pages triggers `itemBuilder` and `onPageChanged` for each page traversed, opening parallel listeners in `_categorySubs`. | "ONE active category Firestore listener at a time." | ❌ **Non-compliant** |
| **Do category results remain cached locally after a listener is cancelled?** | **YES.** Results are stored in `_categoryNewsMap` (`Map<String, List<NewsArticle>>`). The UI reads `_categoryNewsMap[category] ?? []`. Cancelling a subscription leaves `_categoryNewsMap` intact. | "Preserve the previous category's latest results in local memory." | ✅ **Compliant** |

#### Root Cause Analysis:
The current implementation achieved *lazy opening* (it avoids opening all 19 categories at screen start), but it did not implement *active single-stream teardown*. It maintains an accumulating `Map<String, StreamSubscription>` instead of a single `StreamSubscription? _activeCategorySub`.

---

### 7.2 Index Necessity Audit

We inspected all queries against `explore_news` across `lib/repositories/news_repository.dart` and the entire codebase:

```mermaid
flowchart TD
    subgraph Active Queries in news_repository.dart
        Q1["watchCategoryNews(cat):<br/>where('categoryId', '==', id)<br/>.orderBy('publishedAt', desc)<br/>.limit(30)"]
        Q2["watchTopStories():<br/>orderBy('publishedAt', desc)<br/>.limit(20)"]
        Q3["watchLatestNews():<br/>orderBy('publishedAt', desc)<br/>.limit(60)"]
    end

    Q1 -->|Requires Composite Index| IDX1["Index 1: (categoryId ASC, publishedAt DESC)"]
    Q2 -->|Single-Field Index| AUTO["Automatic Firestore Built-in Index"]
    Q3 -->|Single-Field Index| AUTO

    subgraph Proposed in firestore.indexes.json
        IDX1
        IDX2["Index 2: (status ASC, publishedAt DESC)"]
        IDX3["Index 3: (categoryId ASC, status ASC, publishedAt DESC)"]
    end

    IDX2 -.->|0 Queries in Codebase| UNUSED1["UNUSED - Status filtered in-memory"]
    IDX3 -.->|0 Queries in Codebase| UNUSED2["UNUSED - Status filtered in-memory"]
```

#### Detailed Breakdown of Proposed Indexes:

1. **`explore_news: (categoryId ASC, publishedAt DESC)`**
   - **Query:** `_firestore.collection('explore_news').where('categoryId', isEqualTo: categoryId).orderBy('publishedAt', descending: true).limit(30)` ([news_repository.dart:185-188](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/repositories/news_repository.dart#L185-L188))
   - **Executed Currently:** YES. Primary query in `watchCategoryNews()`.
   - **Covered by Existing Index?** NO. Live Firestore throws `FirebaseException: The query requires an index`.
   - **Necessity:** **STRICTLY REQUIRED**.

2. **`explore_news: (status ASC, publishedAt DESC)`**
   - **Query:** NONE. In `news_repository.dart:74, 171, 258`, status filtering is executed **in memory** via Dart (`.where((a) => a.status == null || a.status!.isEmpty || a.status == 'published')`).
   - **Executed Currently:** NO.
   - **Necessity:** **UNUSED / NOT REQUIRED**. Deploying it adds index storage and write costs with zero utility.

3. **`explore_news: (categoryId ASC, status ASC, publishedAt DESC)`**
   - **Query:** NONE. No query filters by both `categoryId` and `status` on Firestore.
   - **Executed Currently:** NO.
   - **Necessity:** **UNUSED / NOT REQUIRED**.

> [!IMPORTANT]
> **Index Recommendation:** Only deploy **Index 1 (`categoryId ASC, publishedAt DESC`)**. Indexes 2 and 3 should not be deployed unless server-side status filtering is formally migrated into `news_repository.dart`.

---

### 7.3 Fallback Safety & Retention Verification

We validated the 50-document safety limit in `_createCategoryNewsStream()` ([news_repository.dart:205-207](file:///C:/Users/Hp%20i7/Documents/mirror%20Laikipia3/mirror_laikipia/lib/repositories/news_repository.dart#L205-L207)):

1. **Deterministic Ordering:**
   - The fallback query scopes by `where('categoryId', isEqualTo: categoryId).limit(50)`.
   - `parseSnapshot()` deterministically sorts the returned documents in memory by `publishedAt ?? createdAt ?? epoch 0` descending, then truncates via `.take(30)`.
2. **Article Retention Truth (Production Data Verification):**
   - A full census of all categories in `explore_news` verified that **every category contains between 1 and 30 documents**:
     - *Health, Tech, Sports, Kenya, Africa, Business, Agriculture, Politics, Entertainment, Lifestyle:* Exactly 30 documents.
     - *Economy, Security, Science, International, Environment, Education, Campus, Culture, Innovation:* 1 to 15 documents.
   - Because no category in production exceeds 30 documents, the 50-document safety limit captures **100% of all articles in the category**. Zero articles are hidden or dropped.
3. **Index Fallback Resilience:**
   - When the composite index is missing or building, `indexedQuery.snapshots().listen` triggers `onError`.
   - `activeSub?.cancel()` cleanly tears down the failing stream before `fallbackQuery.snapshots().listen` starts. No duplicate listener is created.

---

### 7.4 Review of Actual Git Diff

Verification of working tree state:
- **Modified Tracked Files (2):**
  - `lib/repositories/news_repository.dart`
  - `lib/screens/explore_screen.dart`
- **Untracked Test Files (1):**
  - `test/explore_optimization_test.dart`
- **Preserved Files:**
  - `final_firestore_optimization_validation.md`
  - `firebase_firestore_read_usage_audit.md`
  - `firebase_read_hotspots.md`
  - `firebase_read_inventory.csv`
  - `firebase_read_optimization_plan.md`
  - `supabase_migration/`
- **Integrity Confirmation:**
  - Zero modifications to `lib/services/resource_service.dart` or academic resource files.
  - Zero modifications to `functions/` (Cloud Functions).
  - Zero modifications to `firestore.rules`.
  - Zero remote deployments executed.

---

### 7.5 Final Verdict

In accordance with the review options:
- **A. Ready for index deployment**
- **B. Subscription correction required before deployment**
- **C. Index definitions need correction**
- **D. Other regression risk identified**

### **VERDICT: B. Subscription correction required before deployment**

#### Technical Rationale:
1. **Subscription Leakage:** While the duplicate Latest/Mixed news stream was successfully eliminated and companion queries were removed, category switching currently allows multiple background listeners to accumulate in `_categorySubs` as the user navigates tabs.
2. **PageView Pre-subscription:** `PageView.builder.itemBuilder` triggers subscriptions for adjacent pre-built pages that the user has not selected.
3. **Required Correction:** Before deploying indexes, `explore_screen.dart` should be adjusted to enforce **ONE active category Firestore listener at a time**:
   - Cancel the previous category's subscription upon tab change or page settle.
   - Retain previous category articles in `_categoryNewsMap` for instantaneous UI back-navigation.
   - Only subscribe in `onPageChanged` / `_onCategoryTap` after a page is settled, removing `_ensureCategorySubscribed` from `itemBuilder`.
