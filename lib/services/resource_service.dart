import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'course_service.dart';
import 'download_service.dart';
import 'offline_upload_queue_service.dart';
import 'persistence_service.dart';
import 'notification_service.dart';
import '../models/material_model.dart';
import '../models/notification.dart';
export '../models/material_model.dart' show Resource;

// Riverpod Providers are now consolidated in lib/providers/service_providers.dart

class ResourceService extends ChangeNotifier {
  static ResourceService _instance = ResourceService._internal();
  factory ResourceService() => _instance;
  ResourceService._internal() {
    _restoreData();
  }

  static bool get _isTesting {
    if (!kIsWeb) {
      try {
        if (Platform.environment.containsKey('FLUTTER_TEST')) return true;
      } catch (_) {}
    }
    final binding = WidgetsBinding.instance;
    return binding.runtimeType.toString().contains('Test');
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
  List<Resource> _pendingResources = [];
  List<Resource> _approvedResources = [];
  List<Resource> _modifiedResources = [];
  List<Resource> _rejectedResources = [];
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
    _archivedResources = [];
    _trashedResources = [];
    _pendingResources = [];
    _approvedResources = [];
    _modifiedResources = [];
    _rejectedResources = [];
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
    _pendingResources = [];
    _approvedResources = [];
    _modifiedResources = [];
    _rejectedResources = [];
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

  List<Resource> get pendingResources => List.unmodifiable(_pendingResources);
  List<Resource> get approvedResources => List.unmodifiable(_approvedResources);
  List<Resource> get modifiedResources => List.unmodifiable(_modifiedResources);
  List<Resource> get rejectedResources => List.unmodifiable(_rejectedResources);

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

    // Unpinned: release date (approvedAt ?? uploadDate) descending
    unpinned.sort((a, b) {
      final cmp = b.effectiveReleaseDate.compareTo(a.effectiveReleaseDate);
      if (cmp != 0) return cmp;
      return b.uploadDate.compareTo(a.uploadDate);
    });

    return [...pinned, ...unpinned];
  }

  void _processServerResources(List<Resource> loaded) {
    final active = <Resource>[];
    final archived = <Resource>[];
    final trashed = <Map<String, dynamic>>[];
    final pending = <Resource>[];
    final approved = <Resource>[];
    final modified = <Resource>[];
    final rejected = <Resource>[];

    for (final res in loaded) {
      final status = (res.status ?? '').toLowerCase().trim();
      if (status == 'archived') {
        archived.add(res);
      } else if (status == 'trash' || status == 'trashed') {
        trashed.add({
          'resource': res,
          'deletedAt': (res.deletedAt ?? res.uploadDate).toIso8601String(),
        });
      } else if (status == 'pending' || status == 'waiting') {
        pending.add(res);
      } else if (status == 'rejected' || status == 'declined') {
        rejected.add(res);
      } else if (status == 'modified') {
        modified.add(res);
        active.add(res);
      } else if (status == 'approved') {
        approved.add(res);
        active.add(res);
      } else {
        // Legacy or unmoderated materials with empty/null status -> active and approved
        approved.add(res);
        active.add(res);
      }
    }

    // Pending: strictly ordered oldest uploaded material first
    pending.sort((a, b) => a.uploadDate.compareTo(b.uploadDate));
    // Approved: newest first
    approved.sort((a, b) => (b.approvedAt ?? b.uploadDate).compareTo(a.approvedAt ?? a.uploadDate));
    // Modified: newest first
    modified.sort((a, b) => (b.updatedAt ?? b.uploadDate).compareTo(a.updatedAt ?? a.uploadDate));
    // Rejected: newest first
    rejected.sort((a, b) => (b.rejectedAt ?? b.uploadDate).compareTo(a.rejectedAt ?? a.uploadDate));

    _allResources = _sortResources(active);
    _archivedResources = archived;
    _trashedResources = trashed;
    _pendingResources = pending;
    _approvedResources = approved;
    _modifiedResources = modified;
    _rejectedResources = rejected;

    // Critical security reconciliation:
    // If a normal user downloaded a material that is now archived, trashed, or rejected,
    // immediately remove it from local downloads and disk cache.
    final invalidIdentifiers = <String>{
      ...archived.map((r) => r.id).where((id) => id.isNotEmpty),
      ...trashed.map((item) => (item['resource'] as Resource).id).where((id) => id.isNotEmpty),
      ...rejected.map((r) => r.id).where((id) => id.isNotEmpty),
      ...archived.map((r) => r.title),
      ...trashed.map((item) => (item['resource'] as Resource).title),
      ...rejected.map((r) => r.title),
    };
    DownloadService().purgeArchivedOrTrashed(invalidIdentifiers);
    DownloadService().reconcileUpdatedResources(active);

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
          try {
            return _pendingResources.firstWhere((r) => r.id == id);
          } catch (_) {
            try {
              return _rejectedResources.firstWhere((r) => r.id == id);
            } catch (_) {
              try {
                return _approvedResources.firstWhere((r) => r.id == id);
              } catch (_) {
                try {
                  return _modifiedResources.firstWhere((r) => r.id == id);
                } catch (_) {
                  return null;
                }
              }
            }
          }
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

  bool isPinned(String idOrTitle) {
    return _allResources.any((r) => (r.id == idOrTitle || r.title == idOrTitle) && r.isPinned);
  }

  bool isPinnedById(String id) {
    return _allResources.any((r) => r.id == id && r.isPinned);
  }

  List<Resource> _resolveResources(List<String> identifiers, List<Resource> source) {
    final result = <Resource>[];
    for (final idOrTitle in identifiers) {
      final matchById = source.where((r) => r.id.isNotEmpty && r.id == idOrTitle).toList();
      if (matchById.isNotEmpty) {
        result.addAll(matchById);
      } else {
        final matchByTitle = source.where((r) => r.title == idOrTitle).toList();
        result.addAll(matchByTitle);
      }
    }
    final seen = <Resource>{};
    return result.where((r) => seen.add(r)).toList();
  }

  void pinMaterialsById(List<String> ids) => pinMultiple(ids);
  void unpinMaterialsById(List<String> ids) => unpinMultiple(ids);
  void archiveMaterialsById(List<String> ids) => archiveMultiple(ids);
  void deleteMaterialsById(List<String> ids) => deleteMultiple(ids);
  void restoreMaterialsById(List<String> ids) => restoreMultiple(ids);
  void permanentlyDeleteMaterialsById(List<String> ids) => permanentlyDeleteMultiple(ids);

  void pinMultiple(List<String> identifiers) async {
    final toPin = _resolveResources(identifiers, _allResources);
    if (toPin.isEmpty) return;

    final targetIds = toPin.map((r) => r.id).where((id) => id.isNotEmpty).toSet();
    final targetTitles = toPin.map((r) => r.title).toSet();

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
        .where((r) => r.isPinned && !targetIds.contains(r.id) && (r.id.isNotEmpty || !targetTitles.contains(r.title)))
        .toList();

    final allPinned = [...updatedPinned, ...existingPinned];

    // Enforce max 4 pinned items (like Library)
    final finalPinned = allPinned.take(4).toList();
    final evicted = allPinned.skip(4).map((r) => r.copyWith(isPinned: false, pinnedAt: null)).toList();

    // Reconstruct unpinned items
    final finalPinnedIds = finalPinned.map((r) => r.id).where((id) => id.isNotEmpty).toSet();
    final unpinned = _allResources
        .where((r) => !finalPinnedIds.contains(r.id))
        .map((r) => (targetIds.contains(r.id) || (r.id.isEmpty && targetTitles.contains(r.title)))
            ? r.copyWith(isPinned: false, pinnedAt: null)
            : r)
        .toList();

    _allResources = [...finalPinned, ...unpinned];
    _saveToPersistence();
    notifyListeners();

    if (_isTesting) return;

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
      await batch.commit().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('ResourceService: [ERROR] pinMultiple Firestore batch failed: $e');
    }

    try {
      if (targetIds.isNotEmpty) {
        await _functions.httpsCallable('pinAdminMaterials').call({'materialIds': targetIds.toList()}).timeout(const Duration(seconds: 3));
      }
    } catch (_) {}
  }

  void unpinMultiple(List<String> identifiers) async {
    final toUnpin = _resolveResources(identifiers, _allResources);
    if (toUnpin.isEmpty) return;

    final targetIds = toUnpin.map((r) => r.id).where((id) => id.isNotEmpty).toSet();
    final targetTitles = toUnpin.map((r) => r.title).toSet();

    final updated = _allResources.map((r) {
      if (targetIds.contains(r.id) || (r.id.isEmpty && targetTitles.contains(r.title))) {
        return r.copyWith(isPinned: false, pinnedAt: null);
      }
      return r;
    }).toList();

    _allResources = _sortResources(updated);
    _saveToPersistence();
    notifyListeners();

    if (_isTesting) return;

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
      await batch.commit().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('ResourceService: [ERROR] unpinMultiple Firestore batch failed: $e');
    }

    try {
      if (targetIds.isNotEmpty) {
        await _functions.httpsCallable('unpinAdminMaterials').call({'materialIds': targetIds.toList()}).timeout(const Duration(seconds: 3));
      }
    } catch (_) {}
  }

  void archiveMultiple(List<String> identifiers) async {
    final toArchive = _resolveResources(identifiers, _allResources);
    if (toArchive.isEmpty) return;

    final targetIds = toArchive.map((r) => r.id).where((id) => id.isNotEmpty).toSet();
    final targetTitles = toArchive.map((r) => r.title).toSet();

    final now = DateTime.now();
    final archivedItems = toArchive.map((r) => r.copyWith(
      status: 'archived',
      archivedAt: now,
      isPinned: false,
      pinnedAt: null,
    )).toList();

    _allResources.removeWhere((r) => targetIds.contains(r.id) || (r.id.isEmpty && targetTitles.contains(r.title)));
    for (final res in archivedItems) {
      _archivedResources.removeWhere((r) => (res.id.isNotEmpty && r.id == res.id) || (res.id.isEmpty && r.title == res.title));
      _archivedResources.insert(0, res);
    }

    // Purge local downloads immediately targeting exact ID and title
    DownloadService().purgeArchivedOrTrashed({...targetIds, ...targetTitles});

    _saveToPersistence();
    notifyListeners();

    if (_isTesting) return;

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
      await batch.commit().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('ResourceService: [ERROR] archiveMultiple Firestore batch failed: $e');
    }

    try {
      if (targetIds.isNotEmpty) {
        await _functions.httpsCallable('archiveAdminMaterials').call({'materialIds': targetIds.toList()}).timeout(const Duration(seconds: 3));
      }
    } catch (_) {}
  }

  void deleteMultiple(List<String> identifiers) async {
    final toTrashActive = _resolveResources(identifiers, _allResources);
    final toTrashArchived = _resolveResources(identifiers, _archivedResources);
    final toTrash = [...toTrashActive, ...toTrashArchived];
    if (toTrash.isEmpty) return;

    final targetIds = toTrash.map((r) => r.id).where((id) => id.isNotEmpty).toSet();
    final targetTitles = toTrash.map((r) => r.title).toSet();

    final now = DateTime.now();
    final trashedItems = toTrash.map((r) => r.copyWith(
      status: 'trash',
      deletedAt: now,
      isPinned: false,
      pinnedAt: null,
    )).toList();

    _allResources.removeWhere((r) => targetIds.contains(r.id) || (r.id.isEmpty && targetTitles.contains(r.title)));
    _archivedResources.removeWhere((r) => targetIds.contains(r.id) || (r.id.isEmpty && targetTitles.contains(r.title)));

    for (final res in trashedItems) {
      _trashedResources.removeWhere((item) {
        final r = item['resource'] as Resource;
        return (res.id.isNotEmpty && r.id == res.id) || (res.id.isEmpty && r.title == res.title);
      });
      _trashedResources.insert(0, {
        'resource': res,
        'deletedAt': now.toIso8601String(),
      });
    }

    // Purge local downloads immediately targeting exact ID and title
    DownloadService().purgeArchivedOrTrashed({...targetIds, ...targetTitles});

    _saveToPersistence();
    notifyListeners();

    if (_isTesting) return;

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
      await batch.commit().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('ResourceService: [ERROR] deleteMultiple Firestore batch failed: $e');
    }

    try {
      if (targetIds.isNotEmpty) {
        await _functions.httpsCallable('trashAdminMaterials').call({'materialIds': targetIds.toList()}).timeout(const Duration(seconds: 3));
      }
    } catch (_) {}
  }

  void restoreMultiple(List<String> identifiers) async {
    final trashedResourcesList = _trashedResources.map((item) => item['resource'] as Resource).toList();
    final fromTrash = _resolveResources(identifiers, trashedResourcesList);
    final fromArchive = _resolveResources(identifiers, _archivedResources);

    final toRestore = [...fromTrash, ...fromArchive];
    if (toRestore.isEmpty) return;

    final targetIds = toRestore.map((r) => r.id).where((id) => id.isNotEmpty).toSet();
    final targetTitles = toRestore.map((r) => r.title).toSet();

    final now = DateTime.now();
    final restoredItems = toRestore.map((r) => r.copyWith(
      status: 'approved',
      archivedAt: null,
      deletedAt: null,
    )).toList();

    _trashedResources.removeWhere((item) {
      final r = item['resource'] as Resource;
      return targetIds.contains(r.id) || (r.id.isEmpty && targetTitles.contains(r.title));
    });
    _archivedResources.removeWhere((r) => targetIds.contains(r.id) || (r.id.isEmpty && targetTitles.contains(r.title)));

    for (final res in restoredItems) {
      _allResources.removeWhere((r) => (res.id.isNotEmpty && r.id == res.id) || (res.id.isEmpty && r.title == res.title));
      _allResources.add(res);
    }
    _allResources = _sortResources(_allResources);

    _saveToPersistence();
    notifyListeners();

    if (_isTesting) return;

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
      await batch.commit().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('ResourceService: [ERROR] restoreMultiple Firestore batch failed: $e');
    }

    try {
      if (targetIds.isNotEmpty) {
        await _functions.httpsCallable('restoreAdminMaterials').call({'materialIds': targetIds.toList()}).timeout(const Duration(seconds: 3));
      }
    } catch (_) {}
  }

  void permanentlyDeleteMultiple(List<String> identifiers) async {
    final trashedResourcesList = _trashedResources.map((item) => item['resource'] as Resource).toList();
    final fromTrash = _resolveResources(identifiers, trashedResourcesList);
    final fromArchive = _resolveResources(identifiers, _archivedResources);
    final fromActive = _resolveResources(identifiers, _allResources);

    final toDelete = [...fromTrash, ...fromArchive, ...fromActive];
    if (toDelete.isEmpty) return;

    final targetIds = toDelete.map((r) => r.id).where((id) => id.isNotEmpty).toSet();
    final targetTitles = toDelete.map((r) => r.title).toSet();

    _trashedResources.removeWhere((item) {
      final r = item['resource'] as Resource;
      return targetIds.contains(r.id) || (r.id.isEmpty && targetTitles.contains(r.title));
    });
    _archivedResources.removeWhere((r) => targetIds.contains(r.id) || (r.id.isEmpty && targetTitles.contains(r.title)));
    _allResources.removeWhere((r) => targetIds.contains(r.id) || (r.id.isEmpty && targetTitles.contains(r.title)));

    DownloadService().purgeArchivedOrTrashed({...targetIds, ...targetTitles});

    _saveToPersistence();
    notifyListeners();

    if (_isTesting) return;

    for (final res in toDelete) {
      try {
        if (res.fileId.isNotEmpty) {
          try {
            await _functions.httpsCallable('deleteFromImageKit').call({'fileId': res.fileId}).timeout(const Duration(seconds: 3));
          } catch (e) {
            debugPrint('ResourceService: [WARN] Failed to delete fileId ${res.fileId} from ImageKit: $e');
          }
        }
        if (res.thumbnailId != null && res.thumbnailId!.isNotEmpty) {
          try {
            await _functions.httpsCallable('deleteFromImageKit').call({'fileId': res.thumbnailId}).timeout(const Duration(seconds: 3));
          } catch (e) {
            debugPrint('ResourceService: [WARN] Failed to delete thumbnailId ${res.thumbnailId} from ImageKit: $e');
          }
        }
        if (res.id.isNotEmpty) {
          await _firestore.collection('resources').doc(res.id).delete().timeout(const Duration(seconds: 3));
        }
      } catch (e) {
        debugPrint('ResourceService: [ERROR] permanentlyDeleteMultiple failed for ${res.id}: $e');
      }
    }

    try {
      if (targetIds.isNotEmpty) {
        await _functions.httpsCallable('deleteAdminMaterials').call({'materialIds': targetIds.toList()}).timeout(const Duration(seconds: 3));
      }
    } catch (_) {}
  }

  Future<void> modifyMaterial(
    Resource updatedResource, {
    String? oldFileId,
    String? oldThumbnailId,
    bool isModerationModify = false,
  }) async {
    final docId = updatedResource.id;
    if (docId.isEmpty) return;

    final isModified = isModerationModify || updatedResource.status == 'modified';
    final targetStatus = isModified ? 'modified' : updatedResource.status;

    // 1. In-place update in whichever bucket this material belongs to
    final archiveIdx = _archivedResources.indexWhere((r) => r.id == docId);
    final trashIdx = _trashedResources.indexWhere((item) {
      final r = item['resource'] as Resource;
      return r.id == docId;
    });
    final pendingIdx = _pendingResources.indexWhere((r) => r.id == docId);

    if (archiveIdx != -1) {
      // Material is in Archives -> keep it archived in-place
      final currentArchived = _archivedResources[archiveIdx];
      final preservedResource = updatedResource.copyWith(
        status: 'archived',
        archivedAt: currentArchived.archivedAt,
        isPinned: false,
        pinnedAt: null,
      );
      _archivedResources[archiveIdx] = preservedResource;
      _allResources.removeWhere((r) => r.id == docId);
    } else if (trashIdx != -1) {
      // Material is in Trash -> keep it in Trash in-place
      final currentTrashItem = _trashedResources[trashIdx];
      final currentTrashRes = currentTrashItem['resource'] as Resource;
      final preservedResource = updatedResource.copyWith(
        status: 'trash',
        deletedAt: currentTrashRes.deletedAt,
        isPinned: false,
        pinnedAt: null,
      );
      _trashedResources[trashIdx] = {
        'resource': preservedResource,
        'deletedAt': currentTrashItem['deletedAt'],
      };
      _allResources.removeWhere((r) => r.id == docId);
    } else if (isModified || pendingIdx != -1) {
      // Moderation modified material: becomes approved & modified
      _pendingResources.removeWhere((r) => r.id == docId);
      final finalModRes = updatedResource.copyWith(
        status: 'modified',
        approvedAt: updatedResource.approvedAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        approvedByAdmin: true,
      );
      _modifiedResources.removeWhere((r) => r.id == docId);
      _modifiedResources.insert(0, finalModRes);

      _allResources.removeWhere((r) => r.id == docId);
      _allResources.insert(0, finalModRes);
      _allResources = _sortResources(_allResources);

      NotificationService().addModerationNotification(
        type: NotificationType.materialModified,
        resourceTitle: finalModRes.title,
        id: 'notif_modify_$docId',
        materialId: docId,
        remark: finalModRes.adminRemark,
      );
    } else {
      // Active material
      final idx = _allResources.indexWhere((r) => r.id == docId);
      if (idx != -1) {
        _allResources[idx] = updatedResource;
      } else {
        _allResources.insert(0, updatedResource);
      }
      _allResources = _sortResources(_allResources);
    }

    // 2. In-place update user uploads if present
    final userIdx = _userUploads.indexWhere((r) => r.id == docId);
    if (userIdx != -1) {
      _userUploads[userIdx] = isModified
          ? updatedResource.copyWith(status: 'modified', approvedByAdmin: true)
          : updatedResource;
    }

    // 3. Reconcile downloads / cache: If fileUrl changed, remove old cached file and update record
    DownloadService().reconcileUpdatedResources([updatedResource]);

    _saveToPersistence();
    notifyListeners();

    if (_isTesting) return;

    // 4. Update backend via Cloud Function modifyAdminMaterial (with fallback to direct firestore update)
    try {
      await _functions.httpsCallable('modifyAdminMaterial').call({
        'materialId': docId,
        'unitName': updatedResource.unitName,
        'unitCode': updatedResource.unitCode,
        'title': updatedResource.title,
        'materialType': updatedResource.type,
        'catType': updatedResource.type == 'CATs'
            ? (updatedResource.title.contains('CAT 2') ? 'CAT 2' : 'CAT 1')
            : null,
        'yearOfPublication': int.tryParse(updatedResource.publicationYear),
        'yearOfStudy': updatedResource.yearOfStudy,
        'semester': updatedResource.semester,
        'targetPrograms': updatedResource.targetPrograms,
        'programCodes': updatedResource.programCodes,
        'lecturers': updatedResource.lecturers,
        'fileUrl': updatedResource.fileUrl,
        'fileId': updatedResource.fileId,
        'fileName': updatedResource.fileName,
        'materialFormat': updatedResource.materialFormat,
        'thumbnailUrl': updatedResource.thumbnailUrl,
        'thumbnailId': updatedResource.thumbnailId,
        'thumbnailStatus': updatedResource.thumbnailStatus,
        'isAnonymous': updatedResource.isAnonymous,
        'yearOfUpload': int.tryParse(updatedResource.uploadYear),
        'oldFileId': oldFileId,
        'oldThumbnailId': oldThumbnailId,
        if (isModified) 'status': 'modified',
        if (updatedResource.adminRemark != null && updatedResource.adminRemark!.trim().isNotEmpty)
          'adminRemark': updatedResource.adminRemark!.trim(),
      }).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('ResourceService: [WARN] modifyAdminMaterial callable error, writing directly to Firestore: $e');
      try {
        final statusToPersist = (archiveIdx != -1)
            ? 'archived'
            : (trashIdx != -1 ? 'trash' : targetStatus);
        final mapData = <String, dynamic>{
          ...updatedResource.toMap(),
          'status': statusToPersist,
          'updatedByAdmin': true,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (isModified) {
          mapData['approvedAt'] = FieldValue.serverTimestamp();
        }
        await _firestore.collection('resources').doc(docId).update(mapData).timeout(const Duration(seconds: 4));
      } catch (err) {
        debugPrint('ResourceService: [ERROR] Firestore update failed: $err');
      }
    }
  }

  Future<void> approveMaterial(String materialId, {String? adminRemark}) async {
    final cleanId = materialId.trim();
    if (cleanId.isEmpty) return;

    final existing = findResourceById(cleanId);
    final now = DateTime.now();

    final approvedRes = existing?.copyWith(
      status: 'approved',
      approvedAt: now,
      approvedByAdmin: true,
      adminRemark: adminRemark,
      updatedAt: now,
    );

    _pendingResources.removeWhere((r) => r.id == cleanId);
    if (approvedRes != null) {
      _approvedResources.removeWhere((r) => r.id == cleanId);
      _approvedResources.insert(0, approvedRes);

      _allResources.removeWhere((r) => r.id == cleanId);
      _allResources.insert(0, approvedRes);
      _allResources = _sortResources(_allResources);

      final userIdx = _userUploads.indexWhere((r) => r.id == cleanId);
      if (userIdx != -1) {
        _userUploads[userIdx] = approvedRes;
      }

      NotificationService().addModerationNotification(
        type: NotificationType.materialApproved,
        resourceTitle: approvedRes.title,
        id: 'notif_approve_$cleanId',
        materialId: cleanId,
        remark: adminRemark,
      );
    }

    _saveToPersistence();
    notifyListeners();

    if (_isTesting) return;

    try {
      await _functions.httpsCallable('approveAdminMaterial').call({
        'materialId': cleanId,
        if (adminRemark != null && adminRemark.trim().isNotEmpty) 'adminRemark': adminRemark.trim(),
      }).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('ResourceService: [WARN] approveAdminMaterial callable error, writing directly to Firestore: $e');
      try {
        final updateData = <String, dynamic>{
          'status': 'approved',
          'approvedAt': FieldValue.serverTimestamp(),
          'approvedByAdmin': true,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (adminRemark != null && adminRemark.trim().isNotEmpty) {
          updateData['adminRemark'] = adminRemark.trim();
        }
        await _firestore.collection('resources').doc(cleanId).update(updateData);
      } catch (err) {
        debugPrint('ResourceService: [ERROR] Direct Firestore approve failed: $err');
      }
    }
  }

  Future<void> rejectMaterial(
    String materialId, {
    required List<String> rejectionReasons,
    String? adminRemark,
  }) async {
    final cleanId = materialId.trim();
    if (cleanId.isEmpty) return;

    final existing = findResourceById(cleanId);
    final now = DateTime.now();

    final rejectedRes = existing?.copyWith(
      status: 'rejected',
      rejectedAt: now,
      deletedAt: now,
      rejectedByAdmin: true,
      rejectionReasons: rejectionReasons,
      adminRemark: adminRemark,
      updatedAt: now,
    );

    _pendingResources.removeWhere((r) => r.id == cleanId);
    _allResources.removeWhere((r) => r.id == cleanId);
    _approvedResources.removeWhere((r) => r.id == cleanId);
    _modifiedResources.removeWhere((r) => r.id == cleanId);

    if (rejectedRes != null) {
      _rejectedResources.removeWhere((r) => r.id == cleanId);
      _rejectedResources.insert(0, rejectedRes);

      final userIdx = _userUploads.indexWhere((r) => r.id == cleanId);
      if (userIdx != -1) {
        _userUploads[userIdx] = rejectedRes;
      }

      DownloadService().purgeArchivedOrTrashed({cleanId, rejectedRes.title});

      NotificationService().addModerationNotification(
        type: NotificationType.materialRejected,
        resourceTitle: rejectedRes.title,
        id: 'notif_reject_$cleanId',
        materialId: cleanId,
        rejectionReasons: rejectionReasons,
        remark: adminRemark,
      );
    }

    _saveToPersistence();
    notifyListeners();

    if (_isTesting) return;

    try {
      await _functions.httpsCallable('rejectAdminMaterial').call({
        'materialId': cleanId,
        'rejectionReasons': rejectionReasons,
        if (adminRemark != null && adminRemark.trim().isNotEmpty) 'adminRemark': adminRemark.trim(),
      }).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('ResourceService: [WARN] rejectAdminMaterial callable error, writing directly to Firestore: $e');
      try {
        final updateData = <String, dynamic>{
          'status': 'rejected',
          'rejectedAt': FieldValue.serverTimestamp(),
          'deletedAt': FieldValue.serverTimestamp(),
          'rejectedByAdmin': true,
          'rejectionReasons': rejectionReasons,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (adminRemark != null && adminRemark.trim().isNotEmpty) {
          updateData['adminRemark'] = adminRemark.trim();
        }
        await _firestore.collection('resources').doc(cleanId).update(updateData);
      } catch (err) {
        debugPrint('ResourceService: [ERROR] Direct Firestore reject failed: $err');
      }
    }
  }

  Future<void> reconsiderMaterial(String materialId) async {
    final cleanId = materialId.trim();
    if (cleanId.isEmpty) return;

    final existing = findResourceById(cleanId);
    final now = DateTime.now();

    final reconsideredRes = existing?.copyWith(
      status: 'pending',
      reconsideredAt: now,
      clearRejection: true,
      clearAdminRemark: true,
      clearDeletedAt: true,
      updatedAt: now,
    );

    _rejectedResources.removeWhere((r) => r.id == cleanId);
    if (reconsideredRes != null) {
      _pendingResources.removeWhere((r) => r.id == cleanId);
      _pendingResources.add(reconsideredRes);
      _pendingResources.sort((a, b) => a.uploadDate.compareTo(b.uploadDate));

      final userIdx = _userUploads.indexWhere((r) => r.id == cleanId);
      if (userIdx != -1) {
        _userUploads[userIdx] = reconsideredRes;
      }
    }

    _saveToPersistence();
    notifyListeners();

    if (_isTesting) return;

    try {
      await _functions.httpsCallable('reconsiderAdminMaterial').call({
        'materialId': cleanId,
      }).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('ResourceService: [WARN] reconsiderAdminMaterial callable error, writing directly to Firestore: $e');
      try {
        await _firestore.collection('resources').doc(cleanId).update({
          'status': 'pending',
          'reconsideredAt': FieldValue.serverTimestamp(),
          'rejectedAt': FieldValue.delete(),
          'deletedAt': FieldValue.delete(),
          'rejectionReasons': FieldValue.delete(),
          'adminRemark': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (err) {
        debugPrint('ResourceService: [ERROR] Direct Firestore reconsider failed: $err');
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
