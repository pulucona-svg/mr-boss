import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'notification_service.dart';
import 'course_service.dart';
import '../models/notification.dart';

// Riverpod Providers
final resourceServiceProvider = ChangeNotifierProvider((ref) => ResourceService());

class Resource {
  final String id;
  final String title;
  final String type;
  final String thumbnailUrl;
  final String? thumbnailId;
  final String fileUrl;
  final String fileId;
  final String unitName;
  final String unitCode;
  final String year;
  final String uploadYear;
  final String publicationYear;
  final String yearOfStudy;
  final String semester;
  final List<String> lecturers;
  final String uploadedBy;
  final String uploaderRole;
  final String uploaderId;
  final String? uploaderProfilePic;
  final List<String> targetPrograms;
  final List<String> programCodes;
  final String materialFormat;
  final DateTime uploadDate;
  String? status; // 'approved', 'waiting', 'declined'
  final String? declineReason;
  final DateTime? declineDate;
  int _views;
  int _likes;
  int _comments;
  bool isLiked;

  Resource({
    this.id = '',
    required this.title,
    required this.type,
    required this.thumbnailUrl,
    this.thumbnailId,
    required this.fileUrl,
    required this.fileId,
    required this.unitName,
    required this.unitCode,
    required this.year,
    required this.uploadYear,
    required this.publicationYear,
    required this.yearOfStudy,
    required this.semester,
    required this.lecturers,
    required this.uploadedBy,
    required this.uploaderRole,
    required this.uploaderId,
    this.uploaderProfilePic,
    required this.uploadDate,
    this.targetPrograms = const ['Computer Science'],
    this.programCodes = const [],
    this.materialFormat = 'PDF',
    this.status,
    this.declineReason,
    this.declineDate,
    int views = 0,
    int likes = 0,
    int comments = 0,
    this.isLiked = false,
  })  : _views = views,
        _likes = likes,
        _comments = comments;

  int get views => status == 'approved' ? _views : 0;
  int get likes => status == 'approved' ? _likes : 0;
  int get comments => status == 'approved' ? _comments : 0;

  set views(int val) => _views = val;
  set likes(int val) => _likes = val;
  set comments(int val) => _comments = val;

  factory Resource.fromMap(Map<String, dynamic> map, String docId) {
    return Resource(
      id: docId,
      title: map['title'] ?? '',
      type: map['type'] ?? '',
      thumbnailUrl: map['thumbnailUrl'] ?? '',
      thumbnailId: map['thumbnailId'],
      fileUrl: map['fileUrl'] ?? '',
      fileId: map['fileId'] ?? '',
      unitName: map['unitName'] ?? '',
      unitCode: map['unitCode'] ?? '',
      year: map['year'] ?? '',
      uploadYear: map['uploadYear'] ?? '',
      publicationYear: map['publicationYear'] ?? '',
      yearOfStudy: map['yearOfStudy'] ?? '',
      semester: map['semester'] ?? '',
      lecturers: List<String>.from(map['lecturers'] ?? []),
      uploadedBy: map['uploadedBy'] ?? '',
      uploaderRole: map['uploaderRole'] ?? '',
      uploaderId: map['uploaderId'] ?? '',
      uploaderProfilePic: map['uploaderProfilePic'],
      uploadDate: map['uploadDate'] != null ? (map['uploadDate'] as Timestamp).toDate() : DateTime.now(),
      targetPrograms: List<String>.from(map['targetPrograms'] ?? []),
      programCodes: List<String>.from(map['programCodes'] ?? []),
      materialFormat: map['materialFormat'] ?? 'PDF',
      status: map['status'],
      declineReason: map['declineReason'],
      declineDate: map['declineDate'] != null ? (map['declineDate'] as Timestamp).toDate() : null,
      views: map['views'] ?? 0,
      likes: map['likes'] ?? 0,
      comments: map['comments'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'type': type,
      'thumbnailUrl': thumbnailUrl,
      'thumbnailId': thumbnailId,
      'fileUrl': fileUrl,
      'fileId': fileId,
      'unitName': unitName,
      'unitCode': unitCode,
      'year': year,
      'uploadYear': uploadYear,
      'publicationYear': publicationYear,
      'yearOfStudy': yearOfStudy,
      'semester': semester,
      'lecturers': lecturers,
      'uploadedBy': uploadedBy,
      'uploaderRole': uploaderRole,
      'uploaderId': uploaderId,
      'uploaderProfilePic': uploaderProfilePic,
      'uploadDate': Timestamp.fromDate(uploadDate),
      'targetPrograms': targetPrograms,
      'programCodes': programCodes,
      'materialFormat': materialFormat,
      'status': status,
      'declineReason': declineReason,
      'declineDate': declineDate != null ? Timestamp.fromDate(declineDate!) : null,
      'views': _views,
      'likes': _likes,
      'comments': _comments,
    };
  }

  Resource copyWithPoolData(List<String> poolPrograms, List<String> poolLecturers, List<String> poolProgramCodes) {
    return Resource(
      id: id,
      title: title,
      type: type,
      thumbnailUrl: thumbnailUrl,
      thumbnailId: thumbnailId,
      fileUrl: fileUrl,
      fileId: fileId,
      unitName: unitName,
      unitCode: unitCode,
      year: year,
      uploadYear: uploadYear,
      publicationYear: publicationYear,
      yearOfStudy: yearOfStudy,
      semester: semester,
      lecturers: poolLecturers.isNotEmpty ? poolLecturers : lecturers,
      uploadedBy: uploadedBy,
      uploaderRole: uploaderRole,
      uploaderId: uploaderId,
      uploaderProfilePic: uploaderProfilePic,
      uploadDate: uploadDate,
      targetPrograms: poolPrograms.isNotEmpty ? poolPrograms : targetPrograms,
      programCodes: poolProgramCodes.isNotEmpty ? poolProgramCodes : programCodes,
      materialFormat: materialFormat,
      status: status,
      declineReason: declineReason,
      declineDate: declineDate,
      views: _views,
      likes: _likes,
      comments: _comments,
      isLiked: isLiked,
    );
  }
}

class ResourceService extends ChangeNotifier {
  static final ResourceService _instance = ResourceService._internal();
  factory ResourceService() => _instance;
  ResourceService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  String? _activeResourceId;
  String? get activeResourceId => _activeResourceId;

  static const String currentUserId = 'user_12345';
  static const String currentUserName = 'Me';

  List<Resource> _allResources = [];
  List<Resource> _userUploads = [];
  StreamSubscription? _allResourcesSub;
  StreamSubscription? _userUploadsSub;

  void initialize(String userId) {
    _allResourcesSub?.cancel();
    _userUploadsSub?.cancel();

    _allResourcesSub = _firestore
        .collection('resources')
        .where('status', isEqualTo: 'approved')
        .orderBy('uploadDate', descending: true)
        .snapshots()
        .listen((snapshot) {
      _allResources = snapshot.docs
          .map((doc) => Resource.fromMap(doc.data(), doc.id))
          .toList();
      notifyListeners();
    });

    _userUploadsSub = _firestore
        .collection('resources')
        .where('uploaderId', isEqualTo: userId)
        .orderBy('uploadDate', descending: true)
        .snapshots()
        .listen((snapshot) {
      _userUploads = snapshot.docs
          .map((doc) => Resource.fromMap(doc.data(), doc.id))
          .toList();
      notifyListeners();
    });
  }

  List<Resource> get allResources {
    final approvedFromUploads = _userUploads.where((r) => r.status == 'approved');
    final combined = [..._allResources, ...approvedFromUploads];
    // Remove duplicates based on ID
    final seen = <String>{};
    final unique = combined.where((r) => seen.add(r.id)).toList();
    unique.sort((a, b) => b.uploadDate.compareTo(a.uploadDate));
    return unique;
  }

  List<Resource> get userUploads {
    return _userUploads;
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
    try {
      await _firestore.collection('resources').doc(docId).update({
        'likes': FieldValue.increment(currentIsLiked ? -1 : 1),
      });
    } catch (e) {
      debugPrint('ResourceService: [ERROR] Failed to toggle like: $e');
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
  void deleteMultiple(List<String> titles) {} // Placeholder

  List<String> getUniqueLecturers() => allResources.expand((r) => r.lecturers).toSet().toList();
  List<String> getUniquePrograms() => allResources.expand((r) => r.targetPrograms).toSet().toList();

  @override
  void dispose() {
    _allResourcesSub?.cancel();
    _userUploadsSub?.cancel();
    super.dispose();
  }
}
