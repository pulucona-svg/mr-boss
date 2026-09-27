import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'course_service.dart';
import 'download_service.dart';
import 'offline_upload_queue_service.dart';
import 'persistence_service.dart';
import '../models/material_model.dart';
export '../models/material_model.dart' show Resource;

// Riverpod Providers are now consolidated in lib/providers/service_providers.dart

class ResourceService extends ChangeNotifier {
  static ResourceService _instance = ResourceService._internal();
  factory ResourceService() => _instance;
  ResourceService._internal() {
    _restoreData();
  }

  @visibleForTesting
  static void resetInstance() {
    _instance._allResourcesSub?.cancel();
    _instance._userUploadsSub?.cancel();
    _instance = ResourceService._internal();
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  String? _activeResourceId;
  String? get activeResourceId => _activeResourceId;

  List<Resource> _allResources = [];
  List<Resource> _userUploads = [];
  List<Resource> _archivedResources = [];
  List<Map<String, dynamic>> _trashedResources = [];
  StreamSubscription? _allResourcesSub;
  StreamSubscription? _userUploadsSub;

  void initialize(String userId) {
    if (userId.isEmpty) {
      debugPrint('ResourceService: [DEBUG] initialize called with empty userId. Clearing state...');
      clear();
      return;
    }

    debugPrint('ResourceService: [DEBUG] Initializing for user: $userId');
    
    // 1. Cancel existing subscriptions
    _allResourcesSub?.cancel();
    _userUploadsSub?.cancel();
    
    // 2. Clear current state to prevent leakage
    _allResources = [];
    _userUploads = [];
    notifyListeners();

    // 3. Attach fresh listeners
    _allResourcesSub = _firestore
        .collection('resources')
        .orderBy('uploadDate', descending: true)
        .snapshots()
        .listen((snapshot) {
      final resources = snapshot.docs
          .map((doc) => Resource.fromMap(doc.data(), doc.id, currentUserId: userId))
          .toList();
      _processServerResources(resources);
    }, onError: (e) => debugPrint('ResourceService: [ERROR] allResources listener failed: $e'));

    _userUploadsSub = _firestore
        .collection('resources')
        .where('uploaderId', isEqualTo: userId)
        .orderBy('uploadDate', descending: true)
        .snapshots()
        .listen((snapshot) {
      _userUploads = snapshot.docs
          .map((doc) => Resource.fromMap(doc.data(), doc.id, currentUserId: userId))
          .toList();
      notifyListeners();
    }, onError: (e) => debugPrint('ResourceService: [ERROR] userUploads listener failed: $e'));
  }

  /// Fully resets the service state and cancels all listeners.
  /// Call this during logout to prevent state leakage.
  void clear() {
    debugPrint('ResourceService: [DEBUG] Clearing all data and listeners.');
    _allResourcesSub?.cancel();
    _userUploadsSub?.cancel();
    _allResourcesSub = null;
    _userUploadsSub = null;
    _allResources = [];
    _userUploads = [];
    _archivedResources = [];
    _trashedResources = [];
    _activeResourceId = null;
    notifyListeners();
  }

  @visibleForTesting
  void setAllResources(List<Resource> resources) {
    _processServerResources(resources);
  }

  // Force re-attach listeners for pull-to-refresh
  Future<void> refresh(String userId) async {
    initialize(userId);
    // Wait briefly to allow the new stream to emit
    await Future.delayed(const Duration(milliseconds: 500));
  }

  List<Resource> get allResources {
    return _allResources;
  }

  List<Resource> get userUploads {
    final queued = OfflineUploadQueueService().queuedResources;
    final combined = [...queued, ..._userUploads];
    final seen = <String>{};
    final unique = combined.where((r) => seen.add(r.id)).toList();
    unique.sort((a, b) => b.uploadDate.compareTo(a.uploadDate));
    return unique;
  }

  List<Resource> get archivedUploads => _archivedResources;

  List<Map<String, dynamic>> get trashedUploads {
    _autoDeleteExpiredTrash();
    return _trashedResources;
  }

  void setActiveResource(String? id) {
    if (_activeResourceId != id) {
      _activeResourceId = id;
      notifyListeners();
    }
  }

  Future<void> addUpload(Resource resource, CourseService courseService) async {
    final units = courseService.getUnitsByCode(resource.unitCode);
    Resource finalResource = resource;
    if (units.isNotEmpty) {
      final poolPrograms = units.map((u) => u.programName).toSet().toList();
      final poolLecturers = units.map((u) => u.lecturerName).toSet().toList();
      final poolProgramCodes = units.map((u) => u.programCode).toSet().toList();
      finalResource = resource.copyWithPoolData(poolPrograms, poolLecturers, poolProgramCodes);
    }

    try {
      await _firestore.collection('resources').add(finalResource.toMap());
    } catch (e) {
      debugPrint('ResourceService: [ERROR] Failed to add resource: $e');
      rethrow;
    }
  }

  Future<void> fetchUserUploadsOnce(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('resources')
          .where('uploaderId', isEqualTo: userId)
          .orderBy('uploadDate', descending: true)
          .get();
      
      _userUploads = snapshot.docs
          .map((doc) => Resource.fromMap(doc.data(), doc.id, currentUserId: userId))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('ResourceService: [ERROR] fetchUserUploadsOnce failed: $e');
    }
  }

  Future<void> fetchAllResourcesOnce() async {
    try {
      final String? userId = FirebaseAuth.instance.currentUser?.uid;
      final snapshot = await _firestore
          .collection('resources')
          .orderBy('uploadDate', descending: true)
          .get();

      final resources = snapshot.docs
          .map((doc) => Resource.fromMap(doc.data(), doc.id, currentUserId: userId))
          .toList();
      _processServerResources(resources);
    } catch (e) {
      debugPrint('ResourceService: [ERROR] fetchAllResourcesOnce failed: $e');
    }
  }

  void _restoreData() {
    try {
      final activeJson = PersistenceService().getJson('resources_active');
      final archivedJson = PersistenceService().getJson('resources_archived');
      final trashedJson = PersistenceService().getJson('resources_trashed');

      if (activeJson is List && activeJson.isNotEmpty) {
        _allResources = _sortResources(
          activeJson.map((m) => Resource.fromMap(Map<String, dynamic>.from(m), m['id'] ?? '')).toList(),
        );
      }
      if (archivedJson is List && archivedJson.isNotEmpty) {
        _archivedResources = archivedJson
            .map((m) => Resource.fromMap(Map<String, dynamic>.from(m), m['id'] ?? ''))
            .toList();
      }
      if (trashedJson is List && trashedJson.isNotEmpty) {
        _trashedResources = trashedJson.map((item) {
          final map = Map<String, dynamic>.from(item);
          final resMap = Map<String, dynamic>.from(map['resource'] as Map);
          return {
            'resource': Resource.fromMap(resMap, resMap['id'] ?? ''),
            'deletedAt': map['deletedAt'] ?? DateTime.now().toIso8601String(),
          };
        }).toList();
      }
    } catch (e) {
      debugPrint('ResourceService: [WARN] Failed to restore local resources cache: $e');
    }
  }

  void _saveToPersistence() {
    try {
      PersistenceService().setJson(
        'resources_active',
        _allResources.map((r) => {...r.toJson(), 'id': r.id}).toList(),
      );
      PersistenceService().setJson(
        'resources_archived',
        _archivedResources.map((r) => {...r.toJson(), 'id': r.id}).toList(),
      );
      PersistenceService().setJson(
        'resources_trashed',
        _trashedResources.map((item) => {
          'resource': {...(item['resource'] as Resource).toJson(), 'id': (item['resource'] as Resource).id},
          'deletedAt': item['deletedAt'],
        }).toList(),
      );
    } catch (e) {
      debugPrint('ResourceService: [WARN] Failed to save local resources cache: $e');
    }
  }

  Future<void> synchronizeWithPool(CourseService courseService) async {
    // Placeholder for background pool synchronization logic
  }

  Future<void> deleteUpload(String docId, String fileId, String? thumbnailId) async {
    try {
      await _functions.httpsCallable('deleteFromImageKit').call({'fileId': fileId});
      if (thumbnailId != null && thumbnailId.isNotEmpty) {
        await _functions.httpsCallable('deleteFromImageKit').call({'fileId': thumbnailId});
      }
      await _firestore.collection('resources').doc(docId).delete();
    } catch (e) {
      debugPrint('ResourceService: [ERROR] Failed to delete resource: $e');
      rethrow;
    }
  }

  Future<void> toggleLike(String docId, bool currentIsLiked) async {
    final String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final docRef = _firestore.collection('resources').doc(docId);
    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) return;

        final data = snapshot.data() ?? {};
        final likedByList = List<String>.from(data['likedBy'] ?? []);

        int likesCount = data['likes'] ?? 0;
        if (likedByList.contains(userId)) {
          likedByList.remove(userId);
          likesCount = (likesCount - 1).clamp(0, 999999).toInt();
        } else {
          likedByList.add(userId);
          likesCount += 1;
        }

        transaction.update(docRef, {
          'likedBy': likedByList,
          'likes': likesCount,
        });
      });
    } catch (e) {
      debugPrint('ResourceService: [ERROR] Failed to toggle like transaction: $e');
    }
  }

  Future<void> incrementViews(String docId) async {
    try {
      await _firestore.collection('resources').doc(docId).update({
        'views': FieldValue.increment(1),
      });
    } catch (e) {
      debugPrint('ResourceService: [ERROR] Failed to increment views: $e');
    }
  }

  Future<void> incrementComments(String docId) async {
    try {
      await _firestore.collection('resources').doc(docId).update({
        'comments': FieldValue.increment(1),
      });
    } catch (e) {
      debugPrint('ResourceService: [ERROR] Failed to increment comments: $e');
    }
  }

  List<Resource> _sortResources(List<Resource> list) {
    final pinned = list.where((r) => r.isPinned).toList();
    final unpinned = list.where((r) => !r.isPinned).toList();

    // Pinned: newest pinnedAt at top
    pinned.sort((a, b) {
      if (a.pinnedAt != null && b.pinnedAt != null) {
        return b.pinnedAt!.compareTo(a.pinnedAt!);
      }
      if (a.pinnedAt != null) return -1;
      if (b.pinnedAt != null) return 1;
      return b.uploadDate.compareTo(a.uploadDate);
    });

    // Unpinned: uploadDate descending
    unpinned.sort((a, b) => b.uploadDate.compareTo(a.uploadDate));

    return [...pinned, ...unpinned];
  }

  void _processServerResources(List<Resource> loaded) {
    final active = <Resource>[];
    final archived = <Resource>[];
    final trashed = <Map<String, dynamic>>[];

    for (final res in loaded) {
      if (res.status == 'archived') {
        archived.add(res);
      } else if (res.status == 'trash' || res.status == 'trashed') {
        trashed.add({
          'resource': res,
          'deletedAt': (res.deletedAt ?? res.uploadDate).toIso8601String(),
        });
      } else if (res.status != 'declined') {
        active.add(res);
      }
    }

    _allResources = _sortResources(active);
    _archivedResources = archived;
    _trashedResources = trashed;

    // Critical security reconciliation:
    // If a normal user downloaded a material that is now archived, trashed, or deleted,
    // immediately remove it from local downloads and disk cache.
    final invalidTitles = <String>{
      ...archived.map((r) => r.title),
      ...trashed.map((item) => (item['resource'] as Resource).title),
    };
    DownloadService().purgeArchivedOrTrashed(invalidTitles);

    _saveToPersistence();
    notifyListeners();
  }

  void _autoDeleteExpiredTrash() {
    final now = DateTime.now();
    final expiredTitles = <String>[];
    for (final item in _trashedResources) {
      try {
        final deletedAt = DateTime.parse(item['deletedAt'] as String);
        if (now.difference(deletedAt).inDays >= 30) {
          expiredTitles.add((item['resource'] as Resource).title);
        }
      } catch (_) {}
    }
    if (expiredTitles.isNotEmpty) {
      permanentlyDeleteMultiple(expiredTitles);
    }
  }

  Resource? findResourceById(String id) {
    try {
      return allResources.firstWhere((r) => r.id == id);
    } catch (_) {
      try {
        return _archivedResources.firstWhere((r) => r.id == id);
      } catch (_) {
        try {
          final item = _trashedResources.firstWhere((item) => (item['resource'] as Resource).id == id);
          return item['resource'] as Resource;
        } catch (_) {
          return null;
        }
      }
    }
  }

  Resource? findResourceByTitle(String title) {
    try {
      return allResources.firstWhere((r) => r.title == title);
    } catch (_) {
      try {
        return _archivedResources.firstWhere((r) => r.title == title);
      } catch (_) {
        try {
          final item = _trashedResources.firstWhere((item) => (item['resource'] as Resource).title == title);
          return item['resource'] as Resource;
        } catch (_) {
          return null;
        }
      }
    }
  }

  bool isPinned(String title) {
    return _allResources.any((r) => r.title == title && r.isPinned);
  }

  void pinMultiple(List<String> titles) async {
    final toPin = <Resource>[];
    for (final t in titles) {
      final match = findResourceByTitle(t);
      if (match != null) toPin.add(match);
    }
    if (toPin.isEmpty) return;

    final now = DateTime.now();
    // Preserve selection order:
    // First selected gets newest pinnedAt (so it appears at index 0)
    final updatedPinned = <Resource>[];
    for (int i = 0; i < toPin.length; i++) {
      final res = toPin[i];
      final pinTime = now.add(Duration(milliseconds: (toPin.length - i) * 10));
      updatedPinned.add(res.copyWith(isPinned: true, pinnedAt: pinTime));
    }

    // Keep existing pinned items not in toPin
    final existingPinned = _allResources
        .where((r) => r.isPinned && !titles.contains(r.title))
        .toList();

    final allPinned = [...updatedPinned, ...existingPinned];

    // Enforce max 4 pinned items (like Library)
    final finalPinned = allPinned.take(4).toList();
    final evicted = allPinned.skip(4).map((r) => r.copyWith(isPinned: false, pinnedAt: null)).toList();

    // Reconstruct unpinned items
    final finalPinnedTitles = finalPinned.map((r) => r.title).toSet();
    final unpinned = _allResources
        .where((r) => !finalPinnedTitles.contains(r.title))
        .map((r) => titles.contains(r.title) ? r.copyWith(isPinned: false, pinnedAt: null) : r)
        .toList();

    _allResources = [...finalPinned, ...unpinned];
    _saveToPersistence();
    notifyListeners();

    // Persist to backend / Firestore
    try {
      final batch = _firestore.batch();
      for (final res in finalPinned) {
        if (res.id.isNotEmpty) {
          batch.update(_firestore.collection('resources').doc(res.id), {
            'isPinned': true,
            'pinnedAt': Timestamp.fromDate(res.pinnedAt ?? now),
          });
        }
      }
      for (final res in evicted) {
        if (res.id.isNotEmpty) {
          batch.update(_firestore.collection('resources').doc(res.id), {
            'isPinned': false,
            'pinnedAt': null,
          });
        }
      }
      await batch.commit();
    } catch (e) {
      debugPrint('ResourceService: [ERROR] pinMultiple Firestore batch failed: $e');
    }
  }

  void unpinMultiple(List<String> titles) async {
    final toUnpin = _allResources.where((r) => titles.contains(r.title)).toList();
    if (toUnpin.isEmpty) return;

    final updated = _allResources.map((r) {
      if (titles.contains(r.title)) {
        return r.copyWith(isPinned: false, pinnedAt: null);
      }
      return r;
    }).toList();

    _allResources = _sortResources(updated);
    _saveToPersistence();
    notifyListeners();

    try {
      final batch = _firestore.batch();
      for (final res in toUnpin) {
        if (res.id.isNotEmpty) {
          batch.update(_firestore.collection('resources').doc(res.id), {
            'isPinned': false,
            'pinnedAt': null,
          });
        }
      }
      await batch.commit();
    } catch (e) {
      debugPrint('ResourceService: [ERROR] unpinMultiple Firestore batch failed: $e');
    }
  }

  void archiveMultiple(List<String> titles) async {
    final toArchive = _allResources.where((r) => titles.contains(r.title)).toList();
    if (toArchive.isEmpty) return;

    final now = DateTime.now();
    final archivedItems = toArchive.map((r) => r.copyWith(
      status: 'archived',
      archivedAt: now,
      isPinned: false,
      pinnedAt: null,
    )).toList();

    _allResources.removeWhere((r) => titles.contains(r.title));
    for (final res in archivedItems) {
      _archivedResources.removeWhere((r) => r.title == res.title);
      _archivedResources.insert(0, res);
    }

    // Purge local downloads immediately
    DownloadService().purgeArchivedOrTrashed(titles.toSet());

    _saveToPersistence();
    notifyListeners();

    try {
      final batch = _firestore.batch();
      for (final res in archivedItems) {
        if (res.id.isNotEmpty) {
          batch.update(_firestore.collection('resources').doc(res.id), {
            'status': 'archived',
            'archivedAt': Timestamp.fromDate(now),
            'isPinned': false,
            'pinnedAt': null,
          });
        }
      }
      await batch.commit();
    } catch (e) {
      debugPrint('ResourceService: [ERROR] archiveMultiple Firestore batch failed: $e');
    }
  }

  void deleteMultiple(List<String> titles) async {
    final toTrash = [
      ..._allResources.where((r) => titles.contains(r.title)),
      ..._archivedResources.where((r) => titles.contains(r.title)),
    ];
    if (toTrash.isEmpty) return;

    final now = DateTime.now();
    final trashedItems = toTrash.map((r) => r.copyWith(
      status: 'trash',
      deletedAt: now,
      isPinned: false,
      pinnedAt: null,
    )).toList();

    _allResources.removeWhere((r) => titles.contains(r.title));
    _archivedResources.removeWhere((r) => titles.contains(r.title));

    for (final res in trashedItems) {
      _trashedResources.removeWhere((item) => (item['resource'] as Resource).title == res.title);
      _trashedResources.insert(0, {
        'resource': res,
        'deletedAt': now.toIso8601String(),
      });
    }

    // Purge local downloads immediately
    DownloadService().purgeArchivedOrTrashed(titles.toSet());

    _saveToPersistence();
    notifyListeners();

    try {
      final batch = _firestore.batch();
      for (final res in trashedItems) {
        if (res.id.isNotEmpty) {
          batch.update(_firestore.collection('resources').doc(res.id), {
            'status': 'trash',
            'deletedAt': Timestamp.fromDate(now),
            'isPinned': false,
            'pinnedAt': null,
          });
        }
      }
      await batch.commit();
    } catch (e) {
      debugPrint('ResourceService: [ERROR] deleteMultiple Firestore batch failed: $e');
    }
  }

  void restoreMultiple(List<String> titles) async {
    final fromTrash = _trashedResources
        .where((item) => titles.contains((item['resource'] as Resource).title))
        .map((item) => item['resource'] as Resource)
        .toList();

    final fromArchive = _archivedResources
        .where((r) => titles.contains(r.title))
        .toList();

    final toRestore = [...fromTrash, ...fromArchive];
    if (toRestore.isEmpty) return;

    final now = DateTime.now();
    final restoredItems = toRestore.map((r) => r.copyWith(
      status: 'approved',
      archivedAt: null,
      deletedAt: null,
    )).toList();

    _trashedResources.removeWhere((item) => titles.contains((item['resource'] as Resource).title));
    _archivedResources.removeWhere((r) => titles.contains(r.title));

    for (final res in restoredItems) {
      _allResources.removeWhere((r) => r.title == res.title);
      _allResources.add(res);
    }
    _allResources = _sortResources(_allResources);

    _saveToPersistence();
    notifyListeners();

    try {
      final batch = _firestore.batch();
      for (final res in restoredItems) {
        if (res.id.isNotEmpty) {
          batch.update(_firestore.collection('resources').doc(res.id), {
            'status': 'approved',
            'archivedAt': null,
            'deletedAt': null,
            'restoredAt': Timestamp.fromDate(now),
          });
        }
      }
      await batch.commit();
    } catch (e) {
      debugPrint('ResourceService: [ERROR] restoreMultiple Firestore batch failed: $e');
    }
  }

  void permanentlyDeleteMultiple(List<String> titles) async {
    final toDelete = [
      ..._trashedResources
          .where((item) => titles.contains((item['resource'] as Resource).title))
          .map((item) => item['resource'] as Resource),
      ..._archivedResources.where((r) => titles.contains(r.title)),
      ..._allResources.where((r) => titles.contains(r.title)),
    ];

    if (toDelete.isEmpty) return;

    _trashedResources.removeWhere((item) => titles.contains((item['resource'] as Resource).title));
    _archivedResources.removeWhere((r) => titles.contains(r.title));
    _allResources.removeWhere((r) => titles.contains(r.title));

    DownloadService().purgeArchivedOrTrashed(titles.toSet());

    _saveToPersistence();
    notifyListeners();

    for (final res in toDelete) {
      try {
        if (res.fileId.isNotEmpty) {
          try {
            await _functions.httpsCallable('deleteFromImageKit').call({'fileId': res.fileId});
          } catch (e) {
            debugPrint('ResourceService: [WARN] Failed to delete fileId ${res.fileId} from ImageKit: $e');
          }
        }
        if (res.thumbnailId != null && res.thumbnailId!.isNotEmpty) {
          try {
            await _functions.httpsCallable('deleteFromImageKit').call({'fileId': res.thumbnailId});
          } catch (e) {
            debugPrint('ResourceService: [WARN] Failed to delete thumbnailId ${res.thumbnailId} from ImageKit: $e');
          }
        }
        if (res.id.isNotEmpty) {
          await _firestore.collection('resources').doc(res.id).delete();
        }
      } catch (e) {
        debugPrint('ResourceService: [ERROR] permanentlyDeleteMultiple failed for ${res.id}: $e');
      }
    }
  }

  List<String> getUniqueLecturers() => allResources.expand((r) => r.lecturers).toSet().toList();
  List<String> getUniquePrograms() => allResources.expand((r) => r.targetPrograms).toSet().toList();
  List<String> getUniqueUnitCodes() => allResources.map((r) => r.unitCode).where((c) => c.isNotEmpty).toSet().toList();

  @override
  // ignore: must_call_super
  void dispose() {
    _allResourcesSub?.cancel();
    _userUploadsSub?.cancel();
    // Do not call super.dispose() on a singleton service to prevent killing the persistent singleton
  }
}
