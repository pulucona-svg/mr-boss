import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'notification_service.dart';
import 'course_service.dart';
import '../models/notification.dart';
import '../models/material_model.dart';
export '../models/material_model.dart' show Resource;

// Riverpod Providers are now consolidated in lib/providers/service_providers.dart

class ResourceService extends ChangeNotifier {
  static final ResourceService _instance = ResourceService._internal();
  factory ResourceService() => _instance;
  ResourceService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  String? _activeResourceId;
  String? get activeResourceId => _activeResourceId;

  List<Resource> _allResources = [];
  List<Resource> _userUploads = [];
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
      _allResources = snapshot.docs
          .map((doc) => Resource.fromMap(doc.data(), doc.id, currentUserId: userId))
          .toList();
      notifyListeners();
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
    _activeResourceId = null;
    notifyListeners();
  }

  // Force re-attach listeners for pull-to-refresh
  Future<void> refresh(String userId) async {
    initialize(userId);
    // Wait briefly to allow the new stream to emit
    await Future.delayed(const Duration(milliseconds: 500));
  }

  List<Resource> get allResources {
    // Single source of truth from Firestore snapshots
    final combined = [..._allResources, ..._userUploads];
    
    // Remove duplicates based on document ID
    final seen = <String>{};
    final unique = combined.where((r) => seen.add(r.id)).toList();
    
    unique.sort((a, b) => b.uploadDate.compareTo(a.uploadDate));
    return unique;
  }

  List<Resource> get userUploads {
    return _userUploads;
  }

  List<Resource> get trashedUploads => _userUploads.where((r) => r.status == 'declined').toList();
  List<Resource> get archivedUploads => []; // Placeholder

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
      
      _allResources = snapshot.docs
          .map((doc) => Resource.fromMap(doc.data(), doc.id, currentUserId: userId))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('ResourceService: [ERROR] fetchAllResourcesOnce failed: $e');
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

  Resource? findResourceById(String id) {
    try {
      return allResources.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  Resource? findResourceByTitle(String title) {
    try {
      return allResources.firstWhere((r) => r.title == title);
    } catch (_) {
      return null;
    }
  }

  bool isPinned(String title) => false; // Placeholder
  void pinMultiple(List<String> titles) {} // Placeholder
  void unpinMultiple(List<String> titles) {} // Placeholder
  void archiveMultiple(List<String> titles) {} // Placeholder
  void restoreMultiple(List<String> titles) {} // Placeholder
  void deleteMultiple(List<String> titles) {} // Placeholder
  void permanentlyDeleteMultiple(List<String> titles) {} // Placeholder

  List<String> getUniqueLecturers() => allResources.expand((r) => r.lecturers).toSet().toList();
  List<String> getUniquePrograms() => allResources.expand((r) => r.targetPrograms).toSet().toList();

  @override
  void dispose() {
    _allResourcesSub?.cancel();
    _userUploadsSub?.cancel();
    super.dispose();
  }
}
