import 'package:flutter/material.dart';
import 'notification_service.dart';
import '../models/notification.dart';

class Resource {
  final String title;
  final String type;
  final String thumbnailUrl;
  final String unitName;
  final String unitCode;
  final String year;
  final String uploadYear;
  final String publicationYear;
  final String yearOfStudy;
  final String semester;
  final String lecturer;
  final String uploadedBy;
  final String uploaderRole;
  final String uploaderId;
  final String courseProgram;
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
    required this.title,
    required this.type,
    required this.thumbnailUrl,
    required this.unitName,
    required this.unitCode,
    required this.year,
    required this.uploadYear,
    required this.publicationYear,
    required this.yearOfStudy,
    required this.semester,
    required this.lecturer,
    required this.uploadedBy,
    required this.uploaderRole,
    required this.uploaderId,
    required this.uploadDate,
    this.courseProgram = 'Computer Science',
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

  // Social metrics are always zero if not approved
  int get views => status == 'approved' ? _views : 0;
  int get likes => status == 'approved' ? _likes : 0;
  int get comments => status == 'approved' ? _comments : 0;

  // Setters to update underlying values
  set views(int val) => _views = val;
  set likes(int val) => _likes = val;
  set comments(int val) => _comments = val;

  Map<String, String> toMap() {
    return {
      'title': title,
      'type': type,
      'thumbnail': thumbnailUrl,
      'unitName': unitName,
      'unitCode': unitCode,
      'materialFormat': materialFormat,
      'year': year,
      'uploadYear': uploadYear,
      'publicationYear': publicationYear,
      'yearOfStudy': yearOfStudy,
      'semester': semester,
      'lecturer': lecturer,
      'uploadedBy': uploadedBy,
      'uploaderRole': uploaderRole,
      'courseProgram': courseProgram,
      'status': status ?? '',
      'declineReason': declineReason ?? '',
      'views': views.toString(),
      'likes': likes.toString(),
      'comments': comments.toString(),
    };
  }
}

class ResourceService extends ChangeNotifier {
  static final ResourceService _instance = ResourceService._internal();
  factory ResourceService() => _instance;
  ResourceService._internal();

  String? _activeResourceId;
  String? get activeResourceId => _activeResourceId;

  static const String currentUserId = 'user_123';
  static const String currentUserName = 'Me';

  void setActiveResource(String? id) {
    if (_activeResourceId != id) {
      _activeResourceId = id;
      notifyListeners();
    }
  }

  final List<Resource> _allResources = [
    Resource(
      title: 'Data Structures & Algorithms',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1516116216624-53e697fedbea?w=400',
      unitName: 'Data Structures & Algorithms',
      unitCode: 'COMP 211',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2023',
      yearOfStudy: '2nd Year',
      semester: 'Semester 1',
      lecturer: 'Dr. Sarah Wambui',
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploadDate: DateTime.now().subtract(const Duration(days: 10)),
      courseProgram: 'BSc. Computer Science',
      status: 'approved',
      views: 245,
      likes: 32,
      comments: 8,
    ),
    Resource(
      title: 'Calculus II CAT 1 2023',
      type: 'CATs',
      thumbnailUrl: 'https://images.unsplash.com/photo-1509228468518-180dd4864904?w=400',
      unitName: 'Calculus II',
      unitCode: 'MATH 122',
      year: '2023',
      uploadYear: '2023',
      publicationYear: '2023',
      yearOfStudy: '1st Year',
      semester: 'Semester 2',
      lecturer: 'Prof. James Kimani',
      uploadedBy: 'Jane Doe',
      uploaderRole: 'Class Rep',
      uploaderId: 'user_456',
      uploadDate: DateTime.now().subtract(const Duration(days: 5)),
      courseProgram: 'BSc. Mathematics',
      status: 'approved',
      views: 189,
      likes: 27,
      comments: 5,
    ),
    Resource(
      title: 'Operating Systems Final',
      type: 'Exams',
      thumbnailUrl: 'https://images.unsplash.com/photo-1518770660439-4636190af475?w=400',
      unitName: 'Operating Systems',
      unitCode: 'COMP 311',
      year: '2025',
      uploadYear: '2025',
      publicationYear: '2024',
      yearOfStudy: '3rd Year',
      semester: 'Semester 1',
      lecturer: 'Dr. Peter Omondi',
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploadDate: DateTime.now().subtract(const Duration(days: 2)),
      courseProgram: 'BSc. Computer Science',
      status: 'approved',
      views: 512,
      likes: 89,
      comments: 12,
    ),
    Resource(
      title: 'Physics II Laboratory Manual',
      type: 'Prac Manual',
      thumbnailUrl: 'https://images.unsplash.com/photo-1532094349884-543bc11b234d?w=400',
      unitName: 'Physics II',
      unitCode: 'PHYS 122',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '1st Year',
      semester: 'Semester 2',
      lecturer: 'Ms. Lucy Njeri',
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploadDate: DateTime.now().subtract(const Duration(days: 8)),
      courseProgram: 'BSc. Physics',
      status: 'approved',
      views: 98,
      likes: 15,
      comments: 3,
    ),
    Resource(
      title: 'Linear Algebra II Supplementary',
      type: 'Supplementary Exams',
      thumbnailUrl: 'https://images.unsplash.com/photo-1635070041078-e363dbe005cb?w=400',
      unitName: 'Linear Algebra II',
      unitCode: 'MATH 221',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2023',
      yearOfStudy: '2nd Year',
      semester: 'Semester 1',
      lecturer: 'Dr. Andrew Otieno',
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploadDate: DateTime.now().subtract(const Duration(days: 3)),
      courseProgram: 'BSc. Statistics',
      status: 'approved',
      views: 321,
      likes: 45,
      comments: 7,
    ),
    Resource(
      title: 'Database Systems Notes',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1544383835-bda2bc66a55d?w=400',
      unitName: 'Database Systems',
      unitCode: 'COMP 222',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '2nd Year',
      semester: 'Semester 2',
      lecturer: 'Dr. Mary Atieno',
      uploadedBy: 'Brian Chege',
      uploaderRole: 'Student',
      uploaderId: 'user_789',
      uploadDate: DateTime.now().subtract(const Duration(days: 1)),
      courseProgram: 'BSc. Software Engineering',
      status: 'approved',
      views: 412,
      likes: 67,
      comments: 10,
    ),
  ];

  final List<Resource> _userUploads = [
    Resource(
      title: 'Digital Electronics Lab 1',
      type: 'Prac Manual',
      thumbnailUrl: 'https://images.unsplash.com/photo-1550751827-4bd374c3f58b?w=400',
      unitName: 'Digital Electronics',
      unitCode: 'COMP 212',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '2nd Year',
      semester: 'Semester 1',
      lecturer: 'Eng. David Ngugi',
      uploadedBy: 'Me',
      uploaderRole: 'Student',
      uploaderId: currentUserId,
      uploadDate: DateTime.now().subtract(const Duration(days: 1)),
      status: 'approved',
    ),
    Resource(
      title: 'Discrete Math Summary',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1509228468518-180dd4864904?w=400',
      unitName: 'Discrete Mathematics',
      unitCode: 'MATH 211',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '2nd Year',
      semester: 'Semester 1',
      lecturer: 'Dr. John Kamau',
      uploadedBy: 'Me',
      uploaderRole: 'Student',
      uploaderId: currentUserId,
      uploadDate: DateTime.now(),
      status: 'waiting',
    ),
    Resource(
      title: 'Comp Arch CAT 2 2023',
      type: 'CATs',
      thumbnailUrl: 'https://images.unsplash.com/photo-1518770660439-4636190af475?w=400',
      unitName: 'Computer Architecture',
      unitCode: 'COMP 221',
      year: '2023',
      uploadYear: '2023',
      publicationYear: '2023',
      yearOfStudy: '2nd Year',
      semester: 'Semester 2',
      lecturer: 'Prof. Alice Wanjiku',
      uploadedBy: 'Me',
      uploaderRole: 'Student',
      uploaderId: currentUserId,
      uploadDate: DateTime.now().subtract(const Duration(days: 8)),
      status: 'declined',
      declineReason: 'Blurry photos, please re-upload clear ones.',
      declineDate: DateTime.now().subtract(const Duration(days: 8)),
    ),
  ];

  List<Resource> get allResources {
    final approvedFromUploads = _userUploads.where((r) => r.status == 'approved');
    final combined = [..._allResources, ...approvedFromUploads];
    combined.sort((a, b) => b.uploadDate.compareTo(a.uploadDate));
    return combined;
  }

  List<Resource> get userUploads {
    _cleanRejectedUploads();
    final sorted = List<Resource>.from(_userUploads);
    sorted.sort((a, b) => b.uploadDate.compareTo(a.uploadDate));
    return sorted;
  }

  void _cleanRejectedUploads() {
    final now = DateTime.now();
    _userUploads.removeWhere((r) {
      if (r.status == 'declined' && r.declineDate != null) {
        return now.difference(r.declineDate!).inDays >= 7;
      }
      return false;
    });
  }

  void addUpload(Resource resource) {
    _userUploads.add(resource);
    notifyListeners();
  }

  void deleteUpload(String title) {
    _userUploads.removeWhere((r) => r.title == title);
    notifyListeners();
  }

  Resource? findResourceByTitle(String title) {
    try {
      return _userUploads.firstWhere((r) => r.title == title);
    } catch (_) {
      try {
        return _allResources.firstWhere((r) => r.title == title);
      } catch (_) {
        return null;
      }
    }
  }

  void toggleLike(String title, {String likerName = currentUserName}) {
    final resource = findResourceByTitle(title);
    if (resource == null) return;

    resource.isLiked = !resource.isLiked;
    
    if (resource.isLiked) {
      resource.likes++;
      _notifyOwner(resource, NotificationType.like, likerName);
    } else {
      resource.likes--;
    }
    notifyListeners();
  }

  void incrementComments(String title, {String commenterName = currentUserName}) {
    final resource = findResourceByTitle(title);
    if (resource == null) return;

    resource.comments++;
    _notifyOwner(resource, NotificationType.reply, commenterName);
    notifyListeners();
  }

  void _notifyOwner(Resource resource, NotificationType type, String senderName) {
    if (resource.uploaderId == currentUserId) return;

    // Check if uploader still has this in their menu
    final isStillInMenu = _userUploads.any((r) => r.title == resource.title && r.uploaderId == resource.uploaderId) || 
                          resource.uploaderId.startsWith('admin_');
    
    if (isStillInMenu) {
      NotificationService().addNotification(
        type: type,
        senderName: senderName,
        resourceTitle: resource.title,
      );
    }
  }

  void incrementViews(String title) {
    final resource = findResourceByTitle(title);
    if (resource == null) return;

    resource.views++;
    notifyListeners();
  }

  List<String> getUniqueLecturers() => allResources.map((r) => r.lecturer).toSet().toList();
  List<String> getUniquePrograms() => allResources.map((r) => r.courseProgram).toSet().toList();
}
