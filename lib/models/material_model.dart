import 'dart:io';

class UploadMaterialModel {
  final String unitName;
  final String unitCode;
  final List<String> programs;
  final String yearOfStudy;
  final String semester;
  final int yearOfPublication;
  final String uploadedBy;
  final int yearOfUpload;
  final String materialType;
  final String? fileFormat;
  final File? file;
  final File? thumbnail;

  UploadMaterialModel({
    required this.unitName,
    required this.unitCode,
    required this.programs,
    required this.yearOfStudy,
    required this.semester,
    required this.yearOfPublication,
    required this.uploadedBy,
    required this.yearOfUpload,
    required this.materialType,
    this.fileFormat,
    this.file,
    this.thumbnail,
  });

  Map<String, dynamic> toJson() {
    return {
      'unitName': unitName,
      'unitCode': unitCode,
      'programs': programs,
      'yearOfStudy': yearOfStudy,
      'semester': semester,
      'yearOfPublication': yearOfPublication,
      'uploadedBy': uploadedBy,
      'yearOfUpload': yearOfUpload,
      'materialType': materialType,
      'fileFormat': fileFormat,
      'fileName': file?.path.split('/').last,
      'thumbnailName': thumbnail?.path.split('/').last,
    };
  }

  UploadMaterialModel copyWith({
    String? unitName,
    String? unitCode,
    List<String>? programs,
    String? yearOfStudy,
    String? semester,
    int? yearOfPublication,
    String? uploadedBy,
    int? yearOfUpload,
    String? materialType,
    String? fileFormat,
    File? file,
    File? thumbnail,
  }) {
    return UploadMaterialModel(
      unitName: unitName ?? this.unitName,
      unitCode: unitCode ?? this.unitCode,
      programs: programs ?? this.programs,
      yearOfStudy: yearOfStudy ?? this.yearOfStudy,
      semester: semester ?? this.semester,
      yearOfPublication: yearOfPublication ?? this.yearOfPublication,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      yearOfUpload: yearOfUpload ?? this.yearOfUpload,
      materialType: materialType ?? this.materialType,
      fileFormat: fileFormat ?? this.fileFormat,
      file: file ?? this.file,
      thumbnail: thumbnail ?? this.thumbnail,
    );
  }
}
