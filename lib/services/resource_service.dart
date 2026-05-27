import 'package:flutter/material.dart';
import 'notification_service.dart';
import 'course_service.dart';
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
      'lecturer': lecturers.join(', '),
      'uploadedBy': uploadedBy,
      'uploaderRole': uploaderRole,
      'uploaderId': uploaderId,
      'uploaderProfilePic': uploaderProfilePic ?? '',
      'targetPrograms': targetPrograms.join(', '),
      'programCodes': programCodes.join(','),
      'status': status ?? '',
      'declineReason': declineReason ?? '',
      'views': views.toString(),
      'likes': likes.toString(),
      'comments': comments.toString(),
    };
  }

  Resource copyWithPoolData(List<String> poolPrograms, List<String> poolLecturers, List<String> poolProgramCodes) {
    return Resource(
      title: title,
      type: type,
      thumbnailUrl: thumbnailUrl,
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

  bool _isSynchronized = false;
  String? _activeResourceId;
  String? get activeResourceId => _activeResourceId;

  static const String currentUserId = 'user_12345';
  static const String currentUserName = 'Me';
  static const String adminPic = 'assets/admin_pic.jpeg';

  void synchronizeWithPool(CourseService courseService) {
    if (_isSynchronized) return;
    
    for (int i = 0; i < _allResources.length; i++) {
      final units = courseService.getUnitsByCode(_allResources[i].unitCode);
      if (units.isNotEmpty) {
        final poolPrograms = units.map((u) => u.programName).toSet().toList();
        final poolLecturers = units.map((u) => u.lecturerName).toSet().toList();
        final poolProgramCodes = units.map((u) => u.programCode).toSet().toList();
        _allResources[i] = _allResources[i].copyWithPoolData(poolPrograms, poolLecturers, poolProgramCodes);
      }
    }
    
    for (int i = 0; i < _userUploads.length; i++) {
      final units = courseService.getUnitsByCode(_userUploads[i].unitCode);
      if (units.isNotEmpty) {
        final poolPrograms = units.map((u) => u.programName).toSet().toList();
        final poolLecturers = units.map((u) => u.lecturerName).toSet().toList();
        final poolProgramCodes = units.map((u) => u.programCode).toSet().toList();
        _userUploads[i] = _userUploads[i].copyWithPoolData(poolPrograms, poolLecturers, poolProgramCodes);
      }
    }
    
    _isSynchronized = true;
    notifyListeners();
  }

  void setActiveResource(String? id) {
    if (_activeResourceId != id) {
      _activeResourceId = id;
      notifyListeners();
    }
  }

  final List<Resource> _allResources = [
    Resource(
      title: 'Linear Algebra Supp 2023',
      type: 'Supplementary Exams',
      thumbnailUrl: 'https://images.unsplash.com/photo-1509228468518-180dd4864904?w=400',
      unitName: 'Linear Algebra I',
      unitCode: 'MATH 211',
      year: '2023',
      uploadYear: '2024',
      publicationYear: '2023',
      yearOfStudy: '2nd Year',
      semester: 'Semester 1',
      lecturers: ['Prof. Mwangi'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(hours: 1)),
      targetPrograms: ['Bachelor of Science Computer Science', 'Bachelor of Science Applied Statistics'],
      programCodes: ['COMP', 'STAT'],
      status: 'approved',
      views: 45,
      likes: 8,
      comments: 2,
    ),
    Resource(
      title: 'Data Comm Special Exam',
      type: 'Supplementary Exams',
      thumbnailUrl: 'https://images.unsplash.com/photo-1518770660439-4636190af475?w=400',
      unitName: 'Data Communication',
      unitCode: 'COMP 221',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '2nd Year',
      semester: 'Semester 2',
      lecturers: ['Dr. Okoth'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(hours: 2)),
      targetPrograms: ['Bachelor of Science Computer Science'],
      programCodes: ['COMP'],
      status: 'approved',
      views: 32,
      likes: 5,
      comments: 1,
    ),
    Resource(
      title: 'Microeconomics Supp',
      type: 'Supplementary Exams',
      thumbnailUrl: 'https://images.unsplash.com/photo-1460925895917-afdab827c52f?w=400',
      unitName: 'Microeconomics',
      unitCode: 'ECON 111',
      year: '2023',
      uploadYear: '2024',
      publicationYear: '2023',
      yearOfStudy: '1st Year',
      semester: 'Semester 1',
      lecturers: ['Dr. Kamau'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(hours: 3)),
      targetPrograms: ['Bachelor of Commerce', 'Bachelor of Arts'],
      programCodes: ['BCOM', 'ARTS'],
      status: 'approved',
      views: 67,
      likes: 12,
      comments: 4,
    ),
    Resource(
      title: 'Analytical Chemistry Supp',
      type: 'Supplementary Exams',
      thumbnailUrl: 'https://images.unsplash.com/photo-1532094349884-543bc11b234d?w=400',
      unitName: 'Analytical Chemistry',
      unitCode: 'CHEM 211',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '2nd Year',
      semester: 'Semester 1',
      lecturers: ['George G. Njema'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(hours: 4)),
      targetPrograms: ['Bachelor of Science Biomedical Science', 'Bachelor of Education Science'],
      programCodes: ['BMED', 'BEDS'],
      status: 'approved',
      views: 54,
      likes: 9,
      comments: 3,
    ),
    // --- NEW CLASS TIMETABLES ---
    Resource(
      title: 'CS Year 2 Sem 1 Timetable',
      type: 'Class Timetable',
      thumbnailUrl: 'https://images.unsplash.com/photo-1506784983877-45594efa4cbe?w=400',
      unitName: 'Computer Science',
      unitCode: 'COMP DEPT',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '2nd Year',
      semester: 'Semester 1',
      lecturers: ['Department'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(hours: 5)),
      targetPrograms: ['Bachelor of Science Computer Science'],
      programCodes: ['COMP'],
      status: 'approved',
      views: 450,
      likes: 34,
      comments: 12,
    ),
    Resource(
      title: 'BMED Year 1 Sem 2 Table',
      type: 'Class Timetable',
      thumbnailUrl: 'https://images.unsplash.com/photo-1576086213369-97a306d36557?w=400',
      unitName: 'Biomedical Science',
      unitCode: 'BMED DEPT',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '1st Year',
      semester: 'Semester 2',
      lecturers: ['Department'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(hours: 6)),
      targetPrograms: ['Bachelor of Science Biomedical Science'],
      programCodes: ['BMED'],
      status: 'approved',
      views: 380,
      likes: 28,
      comments: 8,
    ),
    Resource(
      title: 'BEd Arts Year 3 Schedule',
      type: 'Class Timetable',
      thumbnailUrl: 'https://images.unsplash.com/photo-1491841573634-28140fc7ced7?w=400',
      unitName: 'Education Arts',
      unitCode: 'BED DEPT',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '3rd Year',
      semester: 'Semester 1',
      lecturers: ['Department'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(hours: 7)),
      targetPrograms: ['Bachelor of Education Arts'],
      programCodes: ['BED'],
      status: 'approved',
      views: 290,
      likes: 21,
      comments: 5,
    ),
    // --- NEW EXAM TIMETABLES ---
    Resource(
      title: 'End of Sem 1 Exams 2024',
      type: 'EXAM Timetable',
      thumbnailUrl: 'https://images.unsplash.com/photo-1434030216411-0b793f4b4173?w=400',
      unitName: 'Main Exams',
      unitCode: 'EXAM BOARD',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: 'All Years',
      semester: 'Semester 1',
      lecturers: ['Board of Exams'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(hours: 8)),
      targetPrograms: ['All Programs'],
      programCodes: ['ALL'],
      status: 'approved',
      views: 1200,
      likes: 156,
      comments: 45,
    ),
    Resource(
      title: 'Year 4 Special Exam Table',
      type: 'EXAM Timetable',
      thumbnailUrl: 'https://images.unsplash.com/photo-1454165833767-027ffea9e77b?w=400',
      unitName: 'Special Exams',
      unitCode: 'SPECIALS',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '4th Year',
      semester: 'Semester 2',
      lecturers: ['Board of Exams'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(hours: 9)),
      targetPrograms: ['All Programs'],
      programCodes: ['ALL'],
      status: 'approved',
      views: 210,
      likes: 15,
      comments: 3,
    ),
    Resource(
      title: 'Masters Sem 2 Exam Table',
      type: 'EXAM Timetable',
      thumbnailUrl: 'https://images.unsplash.com/photo-152305085306e-88e4f6e082ad?w=400',
      unitName: 'Postgraduate Exams',
      unitCode: 'GRAD BOARD',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: 'Masters',
      semester: 'Semester 2',
      lecturers: ['Board of Exams'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(hours: 10)),
      targetPrograms: ['Postgraduate Programs'],
      programCodes: ['GRAD'],
      status: 'approved',
      views: 150,
      likes: 12,
      comments: 2,
    ),
    // --- COMPUTER SCIENCE ---
    Resource(
      title: 'Intro. to Programming Notes',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1515879218367-8466d910aaa4?w=400',
      unitName: 'Intro. to Programming',
      unitCode: 'COMP 113',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '1st Year',
      semester: 'Semester 1',
      lecturers: ['Dr. Oguta J.'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 15)),
      targetPrograms: ['Bachelor of Science Computer Science'],
      status: 'approved',
      views: 1540,
      likes: 245,
      comments: 32,
    ),
    Resource(
      title: 'Discrete Structures I CAT',
      type: 'CATs',
      thumbnailUrl: 'https://images.unsplash.com/photo-1509228468518-180dd4864904?w=400',
      unitName: 'Discrete Structures I',
      unitCode: 'COMP 114',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '1st Year',
      semester: 'Semester 1',
      lecturers: ['Francis Komen'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 12)),
      targetPrograms: [
        'Bachelor of Science Computer Science',
        'Bachelor of Science Applied Computer Science',
        'Bachelor of Science Information Technology'
      ],
      status: 'approved',
      views: 890,
      likes: 112,
      comments: 18,
    ),
    Resource(
      title: 'Object-Oriented Programming I',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1498050108023-c5249f4df085?w=400',
      unitName: 'Object-Oriented Programming I',
      unitCode: 'COMP 211',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '2nd Year',
      semester: 'Semester 1',
      lecturers: ['Francis Komen'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 10)),
      targetPrograms: ['Bachelor of Science Computer Science'],
      status: 'approved',
      views: 2100,
      likes: 432,
      comments: 54,
    ),
    Resource(
      title: 'Digital Electronics II Prac',
      type: 'Prac Manual',
      thumbnailUrl: 'https://images.unsplash.com/photo-1518770660439-4636190af475?w=400',
      unitName: 'Digital Electronics II',
      unitCode: 'COMP 212',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '2nd Year',
      semester: 'Semester 1',
      lecturers: ['Prof. Cheruiyot'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 9)),
      targetPrograms: ['Bachelor of Science Computer Science'],
      status: 'approved',
      views: 650,
      likes: 87,
      comments: 12,
    ),
    Resource(
      title: 'Mobile Application Programming',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1512941937669-90a1b58e7e9c?w=400',
      unitName: 'Mobile Application Programming',
      unitCode: 'COMP 314',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '3rd Year',
      semester: 'Semester 1',
      lecturers: ['William K. Lacktano'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 7)),
      targetPrograms: ['Bachelor of Science Computer Science'],
      status: 'approved',
      views: 3400,
      likes: 721,
      comments: 89,
    ),
    Resource(
      title: 'Principles of Operating Systems',
      type: 'Exams',
      thumbnailUrl: 'https://images.unsplash.com/photo-1518481612222-68bbe828ec1e?w=400',
      unitName: 'Principles of Operating Systems',
      unitCode: 'COMP 315',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2023',
      yearOfStudy: '3rd Year',
      semester: 'Semester 1',
      lecturers: ['William Too'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 6)),
      targetPrograms: ['Bachelor of Science Computer Science'],
      status: 'approved',
      views: 1200,
      likes: 198,
      comments: 24,
    ),
    Resource(
      title: 'Cloud Computing Special Notes',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1451187580459-43490279c0fa?w=400',
      unitName: 'Cloud Computing',
      unitCode: 'COMP 416',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '4th Year',
      semester: 'Semester 1',
      lecturers: ['Jairus E. Ounza'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 4)),
      targetPrograms: ['Bachelor of Science Computer Science'],
      status: 'approved',
      views: 2800,
      likes: 543,
      comments: 67,
    ),
    Resource(
      title: 'Wireless and Mobile Computing',
      type: 'Exams',
      thumbnailUrl: 'https://images.unsplash.com/photo-1558346490-a72e53ae2d4f?w=400',
      unitName: 'Wireless and Mobile Computing',
      unitCode: 'COMP 415',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2023',
      yearOfStudy: '4th Year',
      semester: 'Semester 1',
      lecturers: ['Dr. George Odongo'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 3)),
      targetPrograms: ['Bachelor of Science Computer Science'],
      status: 'approved',
      views: 950,
      likes: 145,
      comments: 16,
    ),

    // --- BIOMEDICAL SCIENCE ---
    Resource(
      title: 'Intro\' to Biomedical Science',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1576086213369-97a306d36557?w=400',
      unitName: 'Intro\' to Biomedical Science',
      unitCode: 'BMED 112',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '1st Year',
      semester: 'Semester 1',
      lecturers: ['Dr. E. Ngetich'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 14)),
      targetPrograms: ['Bachelor of Science Biomedical Science'],
      status: 'approved',
      views: 1100,
      likes: 187,
      comments: 21,
    ),
    Resource(
      title: 'Inorganic Chemistry I Notes',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1532094349884-543bc11b234d?w=400',
      unitName: 'Inorganic Chemistry I',
      unitCode: 'CHEM 111',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '1st Year',
      semester: 'Semester 1',
      lecturers: ['Dr. Kinuthia E'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 13)),
      targetPrograms: ['Bachelor of Science Biomedical Science'],
      status: 'approved',
      views: 740,
      likes: 95,
      comments: 11,
    ),
    Resource(
      title: 'Pathophysiology Detailed Notes',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1530213786676-41ad9f7736f6?w=400',
      unitName: 'Pathophysiology',
      unitCode: 'BMED 212',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '2nd Year',
      semester: 'Semester 1',
      lecturers: ['Prof. John Okoth'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 11)),
      targetPrograms: ['Bachelor of Science Biomedical Science'],
      status: 'approved',
      views: 1800,
      likes: 312,
      comments: 38,
    ),
    Resource(
      title: 'Biology of HIV/AIDS Exam',
      type: 'Exams',
      thumbnailUrl: 'https://images.unsplash.com/photo-1579154235820-21f4560b2984?w=400',
      unitName: 'Biology of HIV/AIDS',
      unitCode: 'BMED 215',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2023',
      yearOfStudy: '2nd Year',
      semester: 'Semester 1',
      lecturers: ['Dr. Wilda Onyancha'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 10)),
      targetPrograms: ['Bachelor of Science Biomedical Science'],
      status: 'approved',
      views: 1350,
      likes: 221,
      comments: 29,
    ),
    Resource(
      title: 'Molecular Biology of the Gene',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1530026405186-ed1f139313f8?w=400',
      unitName: 'Molecular Biology of the Gene',
      unitCode: 'BMED 314',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '3rd Year',
      semester: 'Semester 1',
      lecturers: ['Dr. Sylvia Cherono'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 8)),
      targetPrograms: ['Bachelor of Science Biomedical Science'],
      status: 'approved',
      views: 2400,
      likes: 512,
      comments: 62,
    ),
    Resource(
      title: 'Applied Microbiology Prac',
      type: 'Prac Manual',
      thumbnailUrl: 'https://images.unsplash.com/photo-1581093588401-fbb62a02f120?w=400',
      unitName: 'Applied Microbiology',
      unitCode: 'BMED 313',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '3rd Year',
      semester: 'Semester 1',
      lecturers: ['Prof. Philip Owino'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 7)),
      targetPrograms: ['Bachelor of Science Biomedical Science'],
      status: 'approved',
      views: 580,
      likes: 76,
      comments: 9,
    ),
    Resource(
      title: 'Principles of Immunology Notes',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1576086213369-97a306d36557?w=400',
      unitName: 'Principles of Immunology',
      unitCode: 'BMED 411',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '4th Year',
      semester: 'Semester 1',
      lecturers: ['Dr. J. Mugwe'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 5)),
      targetPrograms: ['Bachelor of Science Biomedical Science'],
      status: 'approved',
      views: 2900,
      likes: 645,
      comments: 81,
    ),
    Resource(
      title: 'Environmental Toxicology Exam',
      type: 'Exams',
      thumbnailUrl: 'https://images.unsplash.com/photo-1532094349884-543bc11b234d?w=400',
      unitName: 'Environmental Toxicology',
      unitCode: 'BMED 413',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2023',
      yearOfStudy: '4th Year',
      semester: 'Semester 1',
      lecturers: ['Prof. John Okoth'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 3)),
      targetPrograms: ['Bachelor of Science Biomedical Science'],
      status: 'approved',
      views: 1050,
      likes: 167,
      comments: 14,
    ),
    Resource(
      title: 'General Mathematics Notes',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1509228468518-180dd4864904?w=400',
      unitName: 'General Mathematics',
      unitCode: 'MATH 111',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '1st Year',
      semester: 'Semester 1',
      lecturers: ['Dr. Limo'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 20)),
      targetPrograms: [
        'Bachelor of Science Biomedical Science',
        'Bachelor of Science Computer Science',
        'Bachelor of Science Applied Computer Science',
        'Bachelor of Science Information Technology'
      ],
      status: 'approved',
      views: 1420,
      likes: 156,
      comments: 22,
    ),
    Resource(
      title: 'Laboratory Animal Science',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1530213786676-41ad9f7736f6?w=400',
      unitName: 'Laboratory Animal Science',
      unitCode: 'BMED 214',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '2nd Year',
      semester: 'Semester 1',
      lecturers: ['Dr. Paul Wanjala'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 18)),
      targetPrograms: ['Bachelor of Science Biomedical Science'],
      status: 'approved',
      views: 890,
      likes: 112,
      comments: 14,
    ),
    Resource(
      title: 'Medical Veterinary Entomology',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1576086213369-97a306d36557?w=400',
      unitName: 'Medical Veterinary Entomology',
      unitCode: 'BMED 213',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '2nd Year',
      semester: 'Semester 1',
      lecturers: ['Dr. E. Ngetich'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 17)),
      targetPrograms: ['Bachelor of Science Biomedical Science'],
      status: 'approved',
      views: 670,
      likes: 84,
      comments: 9,
    ),
    Resource(
      title: 'Medical Cell Biology Summary',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1530026405186-ed1f139313f8?w=400',
      unitName: 'Medical Cell Biology',
      unitCode: 'BMED 211',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '2nd Year',
      semester: 'Semester 1',
      lecturers: ['Dr. A. Mbeke'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 16)),
      targetPrograms: ['Bachelor of Science Biomedical Science'],
      status: 'approved',
      views: 1560,
      likes: 245,
      comments: 31,
    ),
    Resource(
      title: 'Biostatistics Final Exam',
      type: 'Exams',
      thumbnailUrl: 'https://images.unsplash.com/photo-1460925895917-afdab827c52f?w=400',
      unitName: 'Biostatistics',
      unitCode: 'BOTA 311',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2023',
      yearOfStudy: '3rd Year',
      semester: 'Semester 1',
      lecturers: ['Dr. Daniel Osieko'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 15)),
      targetPrograms: ['Bachelor of Science Biomedical Science'],
      status: 'approved',
      views: 1100,
      likes: 178,
      comments: 24,
    ),
    Resource(
      title: 'Nutrition and Disease Notes',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1490645935967-10de6ba17061?w=400',
      unitName: 'Nutrition and Disease',
      unitCode: 'BMED 316',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '3rd Year',
      semester: 'Semester 1',
      lecturers: ['Dr. W Mwangi'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 14)),
      targetPrograms: ['Bachelor of Science Biomedical Science'],
      status: 'approved',
      views: 1250,
      likes: 194,
      comments: 26,
    ),
    Resource(
      title: 'Fundamentals of Enzymology',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1581093588401-fbb62a02f120?w=400',
      unitName: 'Fundamentals of Enzymology',
      unitCode: 'BMED 315',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '3rd Year',
      semester: 'Semester 1',
      lecturers: ['Dr. W Mwangi'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 13)),
      targetPrograms: ['Bachelor of Science Biomedical Science'],
      status: 'approved',
      views: 940,
      likes: 132,
      comments: 18,
    ),
    Resource(
      title: 'Animal Cell Culture Prac',
      type: 'Prac Manual',
      thumbnailUrl: 'https://images.unsplash.com/photo-1579154235820-21f4560b2984?w=400',
      unitName: 'Animal Cell Culture',
      unitCode: 'BMED 414',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '4th Year',
      semester: 'Semester 1',
      lecturers: ['Dr. A. Mbeke'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 12)),
      targetPrograms: ['Bachelor of Science Biomedical Science'],
      status: 'approved',
      views: 720,
      likes: 98,
      comments: 12,
    ),
    Resource(
      title: 'Recombinant DNA Techniques',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1530026405186-ed1f139313f8?w=400',
      unitName: 'Lab Recombinant DNA Techniques',
      unitCode: 'BMED 412',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '4th Year',
      semester: 'Semester 1',
      lecturers: ['Dr. Wilda Onyancha'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 11)),
      targetPrograms: ['Bachelor of Science Biomedical Science'],
      status: 'approved',
      views: 1650,
      likes: 278,
      comments: 34,
    ),
    Resource(
      title: 'Research Methods & Seminars',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1454165833767-027ffea9e77b?w=400',
      unitName: 'Research Methods and Seminars',
      unitCode: 'BMED 417',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '4th Year',
      semester: 'Semester 1',
      lecturers: ['Dr. Pande'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 10)),
      targetPrograms: ['Bachelor of Science Biomedical Science'],
      status: 'approved',
      views: 1100,
      likes: 145,
      comments: 19,
    ),
    Resource(
      title: 'Fundamentals of Bioprocessing',
      type: 'Exams',
      thumbnailUrl: 'https://images.unsplash.com/photo-1581093588401-fbb62a02f120?w=400',
      unitName: 'Fundamentals of Bioprocessing',
      unitCode: 'BMED 415',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2023',
      yearOfStudy: '4th Year',
      semester: 'Semester 1',
      lecturers: ['Oduor Peter'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 9)),
      targetPrograms: ['Bachelor of Science Biomedical Science'],
      status: 'approved',
      views: 890,
      likes: 124,
      comments: 15,
    ),
    Resource(
      title: 'Physical Chemistry I Notes',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1532094349884-543bc11b234d?w=400',
      unitName: 'Physical Chemistry I',
      unitCode: 'CHEM 112',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '1st Year',
      semester: 'Semester 1',
      lecturers: ['George G. Njema'],
      uploadedBy: 'Admin',
      uploaderRole: 'Administrator',
      uploaderId: 'admin_001',
      uploaderProfilePic: adminPic,
      uploadDate: DateTime.now().subtract(const Duration(days: 8)),
      targetPrograms: ['Bachelor of Science Biomedical Science'],
      status: 'approved',
      views: 1120,
      likes: 142,
      comments: 17,
    ),
  ];

  final List<Resource> _userUploads = [
    Resource(
      title: 'Human Rights Full Summary',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1589829545856-d10d557cf95f?w=400',
      unitName: 'Human Rights',
      unitCode: 'HURI 111',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '1st Year',
      semester: 'Semester 1',
      lecturers: ['Lucy Wamuyu'],
      uploadedBy: 'Me',
      uploaderRole: 'Student',
      uploaderId: currentUserId,
      uploadDate: DateTime.now().subtract(const Duration(days: 1)),
      targetPrograms: [
        'Bachelor of Science Computer Science',
        'Bachelor of Science Biomedical Science',
        'Bachelor of Science Applied Computer Science',
        'Bachelor of Education Arts',
        'Bachelor of Arts'
      ],
      status: 'approved',
    ),
    Resource(
      title: 'Fundamentals of Computing Notes',
      type: 'Notes',
      thumbnailUrl: 'https://images.unsplash.com/photo-1518770660439-4636190af475?w=400',
      unitName: 'Fundamentals of Computing',
      unitCode: 'COMP 112',
      year: '2024',
      uploadYear: '2024',
      publicationYear: '2024',
      yearOfStudy: '1st Year',
      semester: 'Semester 1',
      lecturers: ['Francis Komen'],
      uploadedBy: 'Me',
      uploaderRole: 'Student',
      uploaderId: currentUserId,
      uploadDate: DateTime.now(),
      targetPrograms: ['Bachelor of Science Computer Science'],
      status: 'waiting',
    ),
  ];

  List<Resource> get allResources {
    final approvedFromUploads = _userUploads.where((r) => r.status == 'approved');
    final combined = [..._allResources, ...approvedFromUploads];
    combined.sort((a, b) => b.uploadDate.compareTo(a.uploadDate));
    return combined;
  }

  final List<String> _pinnedUploadTitles = [];
  final List<String> _recentlyUnpinnedUploads = [];
  final List<Resource> _archivedUploads = [];
  final List<Map<String, dynamic>> _trashedUploads = [];

  bool isPinned(String title) => _pinnedUploadTitles.contains(title);
  List<Resource> get archivedUploads => _archivedUploads;
  List<Map<String, dynamic>> get trashedUploads {
    _autoDeleteExpiredTrash();
    return _trashedUploads;
  }

  void _autoDeleteExpiredTrash() {
    final now = DateTime.now();
    _trashedUploads.removeWhere((item) {
      final deletedAt = DateTime.parse(item['deletedAt'] as String);
      return now.difference(deletedAt).inDays >= 30;
    });
  }

  void _enforcePinLimit() {
    while (_pinnedUploadTitles.length > 4) {
      final evicted = _pinnedUploadTitles.removeLast();
      _recentlyUnpinnedUploads.remove(evicted);
      _recentlyUnpinnedUploads.insert(0, evicted);
    }
  }

  Resource? _findAndRemove(String title) {
    // Search active uploads
    int idx = _userUploads.indexWhere((r) => r.title == title);
    if (idx != -1) {
      final res = _userUploads.removeAt(idx);
      _pinnedUploadTitles.remove(title);
      _recentlyUnpinnedUploads.remove(title);
      return res;
    }
    // Search archive
    idx = _archivedUploads.indexWhere((r) => r.title == title);
    if (idx != -1) return _archivedUploads.removeAt(idx);
    // Search trash
    idx = _trashedUploads.indexWhere((item) => (item['resource'] as Resource).title == title);
    if (idx != -1) return _trashedUploads.removeAt(idx)['resource'] as Resource;

    return null;
  }

  void pin(String title) {
    final res = findResourceByTitle(title);
    if (res != null) {
      _pinnedUploadTitles.remove(title);
      _recentlyUnpinnedUploads.remove(title);
      _pinnedUploadTitles.insert(0, title);
      _enforcePinLimit();
      notifyListeners();
    }
  }

  void unpin(String title) {
    if (_pinnedUploadTitles.contains(title)) {
      _pinnedUploadTitles.remove(title);
      _recentlyUnpinnedUploads.remove(title);
      _recentlyUnpinnedUploads.insert(0, title);
      notifyListeners();
    }
  }

  void togglePin(String title) {
    if (isPinned(title)) unpin(title);
    else pin(title);
  }

  void pinMultiple(List<String> titles) {
    for (var title in titles) {
      _pinnedUploadTitles.remove(title);
      _recentlyUnpinnedUploads.remove(title);
    }
    for (var title in titles.reversed) {
      _pinnedUploadTitles.insert(0, title);
    }
    _enforcePinLimit();
    notifyListeners();
  }

  void unpinMultiple(List<String> titles) {
    for (var title in titles) {
      if (_pinnedUploadTitles.contains(title)) {
        _pinnedUploadTitles.remove(title);
        _recentlyUnpinnedUploads.remove(title);
        _recentlyUnpinnedUploads.insert(0, title);
      }
    }
    notifyListeners();
  }

  void archiveMultiple(List<String> titles) {
    for (var title in titles) {
      final res = _findAndRemove(title);
      if (res != null) {
        _archivedUploads.insert(0, res);
      }
    }
    notifyListeners();
  }

  void deleteMultiple(List<String> titles) {
    for (var title in titles) {
      final res = _findAndRemove(title);
      if (res != null) {
        _trashedUploads.insert(0, {
          'resource': res,
          'deletedAt': DateTime.now().toIso8601String(),
        });
      }
    }
    notifyListeners();
  }

  void restoreMultiple(List<String> titles) {
    for (var title in titles) {
      final res = _findAndRemove(title);
      if (res != null) {
        _userUploads.add(res);
      }
    }
    notifyListeners();
  }

  void permanentlyDeleteMultiple(List<String> titles) {
    _trashedUploads.removeWhere((item) => titles.contains((item['resource'] as Resource).title));
    notifyListeners();
  }

  List<Resource> get userUploads {
    _cleanRejectedUploads();
    
    final pinned = <Resource>[];
    final recentlyUnpinned = <Resource>[];
    final others = <Resource>[];

    for (var title in _pinnedUploadTitles) {
      final res = _userUploads.firstWhere((r) => r.title == title, orElse: () => Resource(title: '', type: '', thumbnailUrl: '', unitName: '', unitCode: '', year: '', uploadYear: '', publicationYear: '', yearOfStudy: '', semester: '', lecturers: [], uploadedBy: '', uploaderRole: '', uploaderId: '', uploadDate: DateTime.now()));
      if (res.title.isNotEmpty) pinned.add(res);
    }

    for (var title in _recentlyUnpinnedUploads) {
      if (!_pinnedUploadTitles.contains(title)) {
        final res = _userUploads.firstWhere((r) => r.title == title, orElse: () => Resource(title: '', type: '', thumbnailUrl: '', unitName: '', unitCode: '', year: '', uploadYear: '', publicationYear: '', yearOfStudy: '', semester: '', lecturers: [], uploadedBy: '', uploaderRole: '', uploaderId: '', uploadDate: DateTime.now()));
        if (res.title.isNotEmpty) recentlyUnpinned.add(res);
      }
    }

    final sortedUserUploads = List<Resource>.from(_userUploads);
    sortedUserUploads.sort((a, b) => b.uploadDate.compareTo(a.uploadDate));

    for (var res in sortedUserUploads) {
      if (!_pinnedUploadTitles.contains(res.title) && !_recentlyUnpinnedUploads.contains(res.title)) {
        others.add(res);
      }
    }

    return [...pinned, ...recentlyUnpinned, ...others];
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

  void addUpload(Resource resource, CourseService courseService) {
    final units = courseService.getUnitsByCode(resource.unitCode);
    Resource finalResource = resource;
    if (units.isNotEmpty) {
      final poolPrograms = units.map((u) => u.programName).toSet().toList();
      final poolLecturers = units.map((u) => u.lecturerName).toSet().toList();
      final poolProgramCodes = units.map((u) => u.programCode).toSet().toList();
      finalResource = resource.copyWithPoolData(poolPrograms, poolLecturers, poolProgramCodes);
    }
    _userUploads.add(finalResource);
    notifyListeners();
  }

  Resource? findDuplicate(String unitCode, String type, String yearOfStudy, String semester, String publicationYear) {
    try {
      // Check in user uploads first
      return _userUploads.firstWhere(
        (r) => r.unitCode == unitCode && 
               r.type == type && 
               r.yearOfStudy == yearOfStudy && 
               r.semester == semester &&
               r.publicationYear == publicationYear
      );
    } catch (_) {
      try {
        // Then check in approved global resources
        return _allResources.firstWhere(
          (r) => r.unitCode == unitCode && 
                 r.type == type && 
                 r.yearOfStudy == yearOfStudy && 
                 r.semester == semester &&
                 r.publicationYear == publicationYear
        );
      } catch (_) {
        return null;
      }
    }
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

  List<String> getUniqueLecturers() => allResources.expand((r) => r.lecturers).toSet().toList();
  List<String> getUniquePrograms() => allResources.expand((r) => r.targetPrograms).toSet().toList();
}
