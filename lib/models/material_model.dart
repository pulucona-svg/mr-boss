import 'dart:io';

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
