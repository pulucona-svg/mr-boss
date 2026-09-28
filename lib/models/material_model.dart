import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';

class Resource {
  final String id;
  final String title;
  final String fileName;
  final String type;
  final String thumbnailUrl;
  final String? thumbnailId;
  final String thumbnailStatus;
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
  String? status; // 'approved', 'waiting', 'declined', 'archived', 'trash', 'pending', 'rejected', 'modified'
  final String? declineReason;
  final DateTime? declineDate;
  final List<String>? rejectionReasons;
  final String? adminRemark;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;
  final DateTime? reconsideredAt;
  final bool approvedByAdmin;
  final bool rejectedByAdmin;
  final List<String> likedBy;
  final String visibility;
  final bool isAnonymous;
  final bool isPinned;
  final DateTime? pinnedAt;
  final DateTime? archivedAt;
  final DateTime? deletedAt;
  final bool updatedByAdmin;
  final DateTime? updatedAt;
  int views;
  int likes;
  int comments;
  bool isLiked;

  Resource({
    this.id = '',
    required this.title,
    this.fileName = '',
    required this.type,
    required this.thumbnailUrl,
    this.thumbnailId,
    this.thumbnailStatus = 'completed',
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
    this.rejectionReasons,
    this.adminRemark,
    this.approvedAt,
    this.rejectedAt,
    this.reconsideredAt,
    this.approvedByAdmin = false,
    this.rejectedByAdmin = false,
    this.likedBy = const [],
    this.visibility = 'public',
    this.isAnonymous = false,
    this.isPinned = false,
    this.pinnedAt,
    this.archivedAt,
    this.deletedAt,
    this.updatedByAdmin = false,
    this.updatedAt,
    this.views = 0,
    this.likes = 0,
    this.comments = 0,
    this.isLiked = false,
  });

  factory Resource.fromMap(Map<String, dynamic> map, String docId, {String? currentUserId}) {
    final likedByList = List<String>.from(map['likedBy'] ?? []);
    final url = (map['thumbnailUrl'] ?? '').toString();
    final status = (map['thumbnailStatus'] ?? (url.trim().isNotEmpty ? 'completed' : 'pending')).toString();

    return Resource(
      id: docId,
      title: map['title'] ?? '',
      fileName: map['fileName'] ?? '',
      type: map['type'] ?? '',
      thumbnailUrl: url,
      thumbnailId: map['thumbnailId'],
      thumbnailStatus: status,
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
      uploadDate: map['uploadDate'] != null
          ? (map['uploadDate'] is Timestamp
              ? (map['uploadDate'] as Timestamp).toDate()
              : (DateTime.tryParse(map['uploadDate'].toString()) ?? DateTime.now()))
          : DateTime.now(),
      targetPrograms: List<String>.from(map['targetPrograms'] ?? []),
      programCodes: List<String>.from(map['programCodes'] ?? []),
      materialFormat: map['materialFormat'] ?? 'PDF',
      status: map['status'],
      declineReason: map['declineReason'],
      declineDate: map['declineDate'] != null
          ? (map['declineDate'] is Timestamp
              ? (map['declineDate'] as Timestamp).toDate()
              : DateTime.tryParse(map['declineDate'].toString()))
          : null,
      rejectionReasons: map['rejectionReasons'] != null ? List<String>.from(map['rejectionReasons']) : null,
      adminRemark: map['adminRemark'],
      approvedAt: map['approvedAt'] != null
          ? (map['approvedAt'] is Timestamp
              ? (map['approvedAt'] as Timestamp).toDate()
              : DateTime.tryParse(map['approvedAt'].toString()))
          : null,
      rejectedAt: map['rejectedAt'] != null
          ? (map['rejectedAt'] is Timestamp
              ? (map['rejectedAt'] as Timestamp).toDate()
              : DateTime.tryParse(map['rejectedAt'].toString()))
          : null,
      reconsideredAt: map['reconsideredAt'] != null
          ? (map['reconsideredAt'] is Timestamp
              ? (map['reconsideredAt'] as Timestamp).toDate()
              : DateTime.tryParse(map['reconsideredAt'].toString()))
          : null,
      approvedByAdmin: map['approvedByAdmin'] == true,
      rejectedByAdmin: map['rejectedByAdmin'] == true,
      likedBy: likedByList,
      visibility: map['visibility'] ?? 'public',
      isAnonymous: map['isAnonymous'] ?? false,
      isPinned: map['isPinned'] == true,
      pinnedAt: map['pinnedAt'] != null
          ? (map['pinnedAt'] is Timestamp
              ? (map['pinnedAt'] as Timestamp).toDate()
              : DateTime.tryParse(map['pinnedAt'].toString()))
          : null,
      archivedAt: map['archivedAt'] != null
          ? (map['archivedAt'] is Timestamp
              ? (map['archivedAt'] as Timestamp).toDate()
              : DateTime.tryParse(map['archivedAt'].toString()))
          : null,
      deletedAt: map['deletedAt'] != null
          ? (map['deletedAt'] is Timestamp
              ? (map['deletedAt'] as Timestamp).toDate()
              : DateTime.tryParse(map['deletedAt'].toString()))
          : null,
      updatedByAdmin: map['updatedByAdmin'] == true,
      updatedAt: map['updatedAt'] != null
          ? (map['updatedAt'] is Timestamp
              ? (map['updatedAt'] as Timestamp).toDate()
              : DateTime.tryParse(map['updatedAt'].toString()))
          : null,
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
      'thumbnailStatus': thumbnailStatus,
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
      if (rejectionReasons != null) 'rejectionReasons': rejectionReasons,
      if (adminRemark != null) 'adminRemark': adminRemark,
      if (approvedAt != null) 'approvedAt': Timestamp.fromDate(approvedAt!),
      if (rejectedAt != null) 'rejectedAt': Timestamp.fromDate(rejectedAt!),
      if (reconsideredAt != null) 'reconsideredAt': Timestamp.fromDate(reconsideredAt!),
      'approvedByAdmin': approvedByAdmin,
      'rejectedByAdmin': rejectedByAdmin,
      'likedBy': likedBy,
      'visibility': visibility,
      'isAnonymous': isAnonymous,
      'isPinned': isPinned,
      'pinnedAt': pinnedAt != null ? Timestamp.fromDate(pinnedAt!) : null,
      'archivedAt': archivedAt != null ? Timestamp.fromDate(archivedAt!) : null,
      'deletedAt': deletedAt != null ? Timestamp.fromDate(deletedAt!) : null,
      'updatedByAdmin': updatedByAdmin,
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      'views': views,
      'likes': likes,
      'comments': comments,
    };
  }

  Map<String, dynamic> toJson() {
    final map = toMap();
    map['uploadDate'] = uploadDate.toIso8601String();
    if (declineDate != null) map['declineDate'] = declineDate!.toIso8601String();
    if (approvedAt != null) map['approvedAt'] = approvedAt!.toIso8601String();
    if (rejectedAt != null) map['rejectedAt'] = rejectedAt!.toIso8601String();
    if (reconsideredAt != null) map['reconsideredAt'] = reconsideredAt!.toIso8601String();
    if (pinnedAt != null) map['pinnedAt'] = pinnedAt!.toIso8601String();
    if (archivedAt != null) map['archivedAt'] = archivedAt!.toIso8601String();
    if (deletedAt != null) map['deletedAt'] = deletedAt!.toIso8601String();
    if (updatedAt != null) map['updatedAt'] = updatedAt!.toIso8601String();
    return map;
  }

  Resource copyWith({
    String? id,
    String? title,
    String? fileName,
    String? type,
    String? thumbnailUrl,
    String? thumbnailId,
    String? thumbnailStatus,
    String? fileUrl,
    String? fileId,
    String? unitName,
    String? unitCode,
    String? year,
    String? uploadYear,
    String? publicationYear,
    String? yearOfStudy,
    String? semester,
    List<String>? lecturers,
    String? uploadedBy,
    String? uploaderRole,
    String? uploaderId,
    String? uploaderProfilePic,
    List<String>? targetPrograms,
    List<String>? programCodes,
    String? materialFormat,
    DateTime? uploadDate,
    String? status,
    String? declineReason,
    DateTime? declineDate,
    List<String>? rejectionReasons,
    String? adminRemark,
    DateTime? approvedAt,
    DateTime? rejectedAt,
    DateTime? reconsideredAt,
    bool? approvedByAdmin,
    bool? rejectedByAdmin,
    List<String>? likedBy,
    String? visibility,
    bool? isAnonymous,
    bool? isPinned,
    DateTime? pinnedAt,
    DateTime? archivedAt,
    DateTime? deletedAt,
    bool? updatedByAdmin,
    DateTime? updatedAt,
    int? views,
    int? likes,
    int? comments,
    bool? isLiked,
    bool clearRejection = false,
    bool clearAdminRemark = false,
    bool clearDeletedAt = false,
  }) {
    return Resource(
      id: id ?? this.id,
      title: title ?? this.title,
      fileName: fileName ?? this.fileName,
      type: type ?? this.type,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      thumbnailId: thumbnailId ?? this.thumbnailId,
      thumbnailStatus: thumbnailStatus ?? this.thumbnailStatus,
      fileUrl: fileUrl ?? this.fileUrl,
      fileId: fileId ?? this.fileId,
      unitName: unitName ?? this.unitName,
      unitCode: unitCode ?? this.unitCode,
      year: year ?? this.year,
      uploadYear: uploadYear ?? this.uploadYear,
      publicationYear: publicationYear ?? this.publicationYear,
      yearOfStudy: yearOfStudy ?? this.yearOfStudy,
      semester: semester ?? this.semester,
      lecturers: lecturers ?? this.lecturers,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      uploaderRole: uploaderRole ?? this.uploaderRole,
      uploaderId: uploaderId ?? this.uploaderId,
      uploaderProfilePic: uploaderProfilePic ?? this.uploaderProfilePic,
      uploadDate: uploadDate ?? this.uploadDate,
      targetPrograms: targetPrograms ?? this.targetPrograms,
      programCodes: programCodes ?? this.programCodes,
      materialFormat: materialFormat ?? this.materialFormat,
      status: status ?? this.status,
      declineReason: declineReason ?? this.declineReason,
      declineDate: declineDate ?? this.declineDate,
      rejectionReasons: clearRejection ? null : (rejectionReasons ?? this.rejectionReasons),
      adminRemark: clearAdminRemark ? null : (adminRemark ?? this.adminRemark),
      approvedAt: approvedAt ?? this.approvedAt,
      rejectedAt: clearRejection ? null : (rejectedAt ?? this.rejectedAt),
      reconsideredAt: reconsideredAt ?? this.reconsideredAt,
      approvedByAdmin: approvedByAdmin ?? this.approvedByAdmin,
      rejectedByAdmin: clearRejection ? false : (rejectedByAdmin ?? this.rejectedByAdmin),
      likedBy: likedBy ?? this.likedBy,
      visibility: visibility ?? this.visibility,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      isPinned: isPinned ?? this.isPinned,
      pinnedAt: pinnedAt ?? this.pinnedAt,
      archivedAt: archivedAt ?? this.archivedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      updatedByAdmin: updatedByAdmin ?? this.updatedByAdmin,
      updatedAt: updatedAt ?? this.updatedAt,
      views: views ?? this.views,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      isLiked: isLiked ?? this.isLiked,
    );
  }

  Resource copyWithPoolData(List<String> poolPrograms, List<String> poolLecturers, List<String> poolProgramCodes) {
    return Resource(
      id: id,
      title: title,
      fileName: fileName,
      type: type,
      thumbnailUrl: thumbnailUrl,
      thumbnailId: thumbnailId,
      thumbnailStatus: thumbnailStatus,
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
      rejectionReasons: rejectionReasons,
      adminRemark: adminRemark,
      approvedAt: approvedAt,
      rejectedAt: rejectedAt,
      reconsideredAt: reconsideredAt,
      approvedByAdmin: approvedByAdmin,
      rejectedByAdmin: rejectedByAdmin,
      likedBy: likedBy,
      visibility: visibility,
      isAnonymous: isAnonymous,
      isPinned: isPinned,
      pinnedAt: pinnedAt,
      archivedAt: archivedAt,
      deletedAt: deletedAt,
      updatedByAdmin: updatedByAdmin,
      updatedAt: updatedAt,
      views: views,
      likes: likes,
      comments: comments,
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
  final List<File> files;
  final bool isAnonymous;
  final String? existingMaterialId;
  final String? existingFileUrl;
  final String? existingFileName;
  final String? existingFileId;
  final String? existingThumbnailUrl;
  final String? existingThumbnailId;
  final String? existingThumbnailStatus;
  final DateTime? existingUploadDate;
  final String? existingUploaderRole;
  final String? existingUploaderProfilePic;
  final int existingViews;
  final int existingLikes;
  final int existingComments;
  final List<String> existingLikedBy;
  final String? existingStatus;
  final bool existingIsPinned;
  final DateTime? existingPinnedAt;
  final bool updatedByAdmin;
  final DateTime? updatedAt;
  final bool isModerationModify;
  final String? adminRemark;
  final DateTime? existingApprovedAt;
  final List<String>? existingRejectionReasons;

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
    this.files = const [],
    this.isAnonymous = false,
    this.existingMaterialId,
    this.existingFileUrl,
    this.existingFileName,
    this.existingFileId,
    this.existingThumbnailUrl,
    this.existingThumbnailId,
    this.existingThumbnailStatus,
    this.existingUploadDate,
    this.existingUploaderRole,
    this.existingUploaderProfilePic,
    this.existingViews = 0,
    this.existingLikes = 0,
    this.existingComments = 0,
    this.existingLikedBy = const [],
    this.existingStatus,
    this.existingIsPinned = false,
    this.existingPinnedAt,
    this.updatedByAdmin = false,
    this.updatedAt,
    this.isModerationModify = false,
    this.adminRemark,
    this.existingApprovedAt,
    this.existingRejectionReasons,
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
      'fileName': file?.path.split(RegExp(r'[/\\]')).last ?? existingFileName,
      'thumbnailName': thumbnail?.path.split(RegExp(r'[/\\]')).last,
      'isAnonymous': isAnonymous,
      if (existingMaterialId != null) 'existingMaterialId': existingMaterialId,
      if (existingFileUrl != null) 'existingFileUrl': existingFileUrl,
      if (existingFileId != null) 'existingFileId': existingFileId,
      if (existingThumbnailUrl != null) 'existingThumbnailUrl': existingThumbnailUrl,
      if (existingThumbnailId != null) 'existingThumbnailId': existingThumbnailId,
      if (existingThumbnailStatus != null) 'existingThumbnailStatus': existingThumbnailStatus,
      if (existingUploadDate != null) 'existingUploadDate': existingUploadDate!.toIso8601String(),
      if (updatedByAdmin) 'updatedByAdmin': true,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  Map<String, dynamic> toMap() {
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
      'isAnonymous': isAnonymous,
      if (existingMaterialId != null) 'existingMaterialId': existingMaterialId,
      if (existingFileUrl != null) 'existingFileUrl': existingFileUrl,
      if (existingFileName != null) 'existingFileName': existingFileName,
      if (existingFileId != null) 'existingFileId': existingFileId,
      if (existingThumbnailUrl != null) 'existingThumbnailUrl': existingThumbnailUrl,
      if (existingThumbnailId != null) 'existingThumbnailId': existingThumbnailId,
      if (existingThumbnailStatus != null) 'existingThumbnailStatus': existingThumbnailStatus,
      if (existingUploadDate != null) 'existingUploadDate': existingUploadDate,
      if (updatedByAdmin) 'updatedByAdmin': true,
      if (updatedAt != null) 'updatedAt': updatedAt,
    };
  }

  factory UploadMaterialModel.fromMap(Map<String, dynamic> map) {
    return UploadMaterialModel(
      unitName: (map['unitName'] ?? '').toString(),
      unitCode: (map['unitCode'] ?? '').toString(),
      programs: List<String>.from(map['programs'] ?? []),
      programCodes: List<String>.from(map['programCodes'] ?? []),
      lecturers: List<String>.from(map['lecturers'] ?? []),
      yearOfStudy: (map['yearOfStudy'] ?? '1st Year').toString(),
      semester: (map['semester'] ?? 'Semester 1').toString(),
      yearOfPublication: map['yearOfPublication'] ?? DateTime.now().year,
      uploadedBy: (map['uploadedBy'] ?? '').toString(),
      uploaderId: (map['uploaderId'] ?? '').toString(),
      yearOfUpload: map['yearOfUpload'] ?? DateTime.now().year,
      materialType: (map['materialType'] ?? 'Notes').toString(),
      catType: map['catType']?.toString(),
      fileFormat: map['fileFormat']?.toString(),
      isAnonymous: map['isAnonymous'] ?? false,
      existingMaterialId: map['existingMaterialId']?.toString(),
      existingFileUrl: map['existingFileUrl']?.toString(),
      existingFileName: map['existingFileName']?.toString(),
      existingFileId: map['existingFileId']?.toString(),
      existingThumbnailUrl: map['existingThumbnailUrl']?.toString(),
      existingThumbnailId: map['existingThumbnailId']?.toString(),
      existingThumbnailStatus: map['existingThumbnailStatus']?.toString(),
      existingUploadDate: map['existingUploadDate'] != null
          ? (map['existingUploadDate'] is DateTime
              ? map['existingUploadDate'] as DateTime
              : DateTime.tryParse(map['existingUploadDate'].toString()))
          : null,
      existingUploaderRole: map['existingUploaderRole']?.toString(),
      existingUploaderProfilePic: map['existingUploaderProfilePic']?.toString(),
      existingViews: map['existingViews'] ?? 0,
      existingLikes: map['existingLikes'] ?? 0,
      existingComments: map['existingComments'] ?? 0,
      existingLikedBy: List<String>.from(map['existingLikedBy'] ?? []),
      existingStatus: map['existingStatus']?.toString(),
      existingIsPinned: map['existingIsPinned'] == true,
      existingPinnedAt: map['existingPinnedAt'] != null
          ? (map['existingPinnedAt'] is DateTime
              ? map['existingPinnedAt'] as DateTime
              : DateTime.tryParse(map['existingPinnedAt'].toString()))
          : null,
      updatedByAdmin: map['updatedByAdmin'] == true,
      updatedAt: map['updatedAt'] != null
          ? (map['updatedAt'] is DateTime
              ? map['updatedAt'] as DateTime
              : DateTime.tryParse(map['updatedAt'].toString()))
          : null,
    );
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
    List<File>? files,
    bool? isAnonymous,
    String? existingMaterialId,
    String? existingFileUrl,
    String? existingFileName,
    String? existingFileId,
    String? existingThumbnailUrl,
    String? existingThumbnailId,
    String? existingThumbnailStatus,
    DateTime? existingUploadDate,
    String? existingUploaderRole,
    String? existingUploaderProfilePic,
    int? existingViews,
    int? existingLikes,
    int? existingComments,
    List<String>? existingLikedBy,
    String? existingStatus,
    bool? existingIsPinned,
    DateTime? existingPinnedAt,
    bool? updatedByAdmin,
    DateTime? updatedAt,
    bool? isModerationModify,
    String? adminRemark,
    DateTime? existingApprovedAt,
    List<String>? existingRejectionReasons,
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
      files: files ?? this.files,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      existingMaterialId: existingMaterialId ?? this.existingMaterialId,
      existingFileUrl: existingFileUrl ?? this.existingFileUrl,
      existingFileName: existingFileName ?? this.existingFileName,
      existingFileId: existingFileId ?? this.existingFileId,
      existingThumbnailUrl: existingThumbnailUrl ?? this.existingThumbnailUrl,
      existingThumbnailId: existingThumbnailId ?? this.existingThumbnailId,
      existingThumbnailStatus: existingThumbnailStatus ?? this.existingThumbnailStatus,
      existingUploadDate: existingUploadDate ?? this.existingUploadDate,
      existingUploaderRole: existingUploaderRole ?? this.existingUploaderRole,
      existingUploaderProfilePic: existingUploaderProfilePic ?? this.existingUploaderProfilePic,
      existingViews: existingViews ?? this.existingViews,
      existingLikes: existingLikes ?? this.existingLikes,
      existingComments: existingComments ?? this.existingComments,
      existingLikedBy: existingLikedBy ?? this.existingLikedBy,
      existingStatus: existingStatus ?? this.existingStatus,
      existingIsPinned: existingIsPinned ?? this.existingIsPinned,
      existingPinnedAt: existingPinnedAt ?? this.existingPinnedAt,
      updatedByAdmin: updatedByAdmin ?? this.updatedByAdmin,
      updatedAt: updatedAt ?? this.updatedAt,
      isModerationModify: isModerationModify ?? this.isModerationModify,
      adminRemark: adminRemark ?? this.adminRemark,
      existingApprovedAt: existingApprovedAt ?? this.existingApprovedAt,
      existingRejectionReasons: existingRejectionReasons ?? this.existingRejectionReasons,
    );
  }
}
