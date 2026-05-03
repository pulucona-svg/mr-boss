import 'package:flutter/material.dart';

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
  final String courseProgram;
  final String? status; // 'approved', 'waiting', 'declined'
  final String? declineReason;
  int views;
  int likes;
  int comments;
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
    this.courseProgram = 'Computer Science',
    this.status,
    this.declineReason,
    this.views = 0,
    this.likes = 0,
    this.comments = 0,
    this.isLiked = false,
  });

  Map<String, String> toMap() {
    return {
      'title': title,
      'type': type,
      'thumbnail': thumbnailUrl,
      'unitName': unitName,
      'unitCode': unitCode,
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
      courseProgram: 'BSc. Computer Science',
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
      courseProgram: 'BSc. Mathematics',
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
      courseProgram: 'BSc. Computer Science',
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
      courseProgram: 'BSc. Physics',
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
      courseProgram: 'BSc. Statistics',
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
      courseProgram: 'BSc. Software Engineering',
      views: 412,
      likes: 67,
      comments: 10,
    ),
  ];

  List<Resource> get allResources => _allResources;

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
      status: 'declined',
      declineReason: 'Blurry photos, please re-upload clear ones.',
    ),
  ];

  List<Resource> get userUploads => _userUploads;

  void addUpload(Resource resource) {
    _userUploads.add(resource);
    notifyListeners();
  }

  List<String> getUniqueLecturers() {
    return _allResources.map((r) => r.lecturer).toSet().toList();
  }

  List<String> getUniquePrograms() {
    return _allResources.map((r) => r.courseProgram).toSet().toList();
  }

  void toggleLike(String title) {
    final resource = _allResources.firstWhere((r) => r.title == title);
    resource.isLiked = !resource.isLiked;
    if (resource.isLiked) {
      resource.likes++;
    } else {
      resource.likes--;
    }
    notifyListeners();
  }

  void incrementViews(String title) {
    final resource = _allResources.firstWhere((r) => r.title == title);
    resource.views++;
    notifyListeners();
  }
}
