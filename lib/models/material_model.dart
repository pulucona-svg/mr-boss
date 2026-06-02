import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';

class Resource {
  final String id;
  final String title;
  final String fileName;
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
  final List<String> likedBy;
  final String visibility;
  int _views;
  int _likes;
  int _comments;
  bool isLiked;

  Resource({
    this.id = '',
    required this.title,
    this.fileName = '',
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
    this.likedBy = const [],
    this.visibility = 'public',
    int views = 0,
    int likes = 0,
    int comments = 0,
    this.isLiked = false,
  })  : _views = views,
        _likes = likes,
        _comments = comments;

  int get views => _views;
  int get likes => _likes;
  int get comments => _comments;

  set views(int val) => _views = val;
  set likes(int val) => _likes = val;
  set comments(int val) => _comments = val;

  factory Resource.fromMap(Map<String, dynamic> map, String docId, {String? currentUserId}) {
    final likedByList = List<String>.from(map['likedBy'] ?? []);
    return Resource(
      id: docId,
      title: map['title'] ?? '',
      fileName: map['fileName'] ?? '',
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
      likedBy: likedByList,
      visibility: map['visibility'] ?? 'public',
      views: map['views'] ?? 0,
      likes: map['likes'] ?? 0,
      comments: map['comments'] ?? 0,
      isLiked: currentUserId != null ? likedByList.contains(currentUserId) : false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'fileName': fileName,
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
      'likedBy': likedBy,
      'visibility': visibility,
      'views': _views,
      'likes': _likes,
      'comments': _comments,
    };
  }

  Resource copyWithPoolData(List<String> poolPrograms, List<String> poolLecturers, List<String> poolProgramCodes) {
    return Resource(
      id: id,
      title: title,
      fileName: fileName,
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
      programCodes: poolProgramCodes.isNotEmpty ? poolProgramCodes : poolProgramCodes,
      materialFormat: materialFormat,
      status: status,
      declineReason: declineReason,
      declineDate: declineDate,
      likedBy: likedBy,
      visibility: visibility,
      views: _views,
      likes: _likes,
      comments: _comments,
      isLiked: isLiked,
    );
  }
}

class UploadMaterialModel {
  final String unitName;
  final String unitCode;
  final List<String> programs;
  final List<String> programCodes;
  final List<String> lecturers;
  final String yearOfStudy;
  final String semester;
  final int yearOfPublication;
  final String uploadedBy;
  final String uploaderId;
  final int yearOfUpload;
  final String materialType;
  final String? catType; // 'CAT 1' or 'CAT 2'
  final String? fileFormat;
  final File? file;
  final File? thumbnail;

  UploadMaterialModel({
    required this.unitName,
    required this.unitCode,
    required this.programs,
    this.programCodes = const [],
    this.lecturers = const [],
    required this.yearOfStudy,
    required this.semester,
    required this.yearOfPublication,
    required this.uploadedBy,
    required this.uploaderId,
    required this.yearOfUpload,
    required this.materialType,
    this.catType,
    this.fileFormat,
    this.file,
    this.thumbnail,
  });

  Map<String, dynamic> toJson() {
    return {
      'unitName': unitName,
      'unitCode': unitCode,
      'programs': programs,
      'programCodes': programCodes,
      'lecturers': lecturers,
      'yearOfStudy': yearOfStudy,
      'semester': semester,
      'yearOfPublication': yearOfPublication,
      'uploadedBy': uploadedBy,
      'uploaderId': uploaderId,
      'yearOfUpload': yearOfUpload,
      'materialType': materialType,
      'catType': catType,
      'fileFormat': fileFormat,
      'fileName': file?.path.split(RegExp(r'[/\\]')).last,
      'thumbnailName': thumbnail?.path.split(RegExp(r'[/\\]')).last,
    };
  }

  UploadMaterialModel copyWith({
    String? unitName,
    String? unitCode,
    List<String>? programs,
    List<String>? programCodes,
    List<String>? lecturers,
    String? yearOfStudy,
    String? semester,
    int? yearOfPublication,
    String? uploadedBy,
    String? uploaderId,
    int? yearOfUpload,
    String? materialType,
    String? catType,
    String? fileFormat,
    File? file,
    File? thumbnail,
  }) {
    return UploadMaterialModel(
      unitName: unitName ?? this.unitName,
      unitCode: unitCode ?? this.unitCode,
      programs: programs ?? this.programs,
      programCodes: programCodes ?? this.programCodes,
      lecturers: lecturers ?? this.lecturers,
      yearOfStudy: yearOfStudy ?? this.yearOfStudy,
      semester: semester ?? this.semester,
      yearOfPublication: yearOfPublication ?? this.yearOfPublication,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      uploaderId: uploaderId ?? this.uploaderId,
      yearOfUpload: yearOfUpload ?? this.yearOfUpload,
      materialType: materialType ?? this.materialType,
      catType: catType ?? this.catType,
      fileFormat: fileFormat ?? this.fileFormat,
      file: file ?? this.file,
      thumbnail: thumbnail ?? this.thumbnail,
    );
  }
}
