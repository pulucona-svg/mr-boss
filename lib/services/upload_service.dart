import 'dart:convert';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/material_model.dart';

class UploadService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<Map<String, dynamic>> uploadMaterial(UploadMaterialModel material, Function(double) onProgress) async {
    onProgress(0.1);
    
    String? fileUrl;
    String? fileId;
    String? thumbnailUrl;
    String? thumbnailId;

    // 1. Upload Main File
    if (material.file != null) {
      final fileBytes = await material.file!.readAsBytes();
      final base64File = base64Encode(fileBytes);
      final fileName = material.file!.path.split(RegExp(r'[/\\]')).last;
      
      final folder = _getFolderForType(material.materialType);
      
      final result = await _functions.httpsCallable('uploadToImageKit').call({
        'file': base64File,
        'fileName': fileName,
        'folder': folder,
      });
      
      fileUrl = result.data['url'];
      fileId = result.data['fileId'];
    }
    
    onProgress(0.6);

    // 2. Upload Thumbnail if exists
    if (material.thumbnail != null) {
      final thumbBytes = await material.thumbnail!.readAsBytes();
      final base64Thumb = base64Encode(thumbBytes);
      final thumbName = 'thumb_${material.thumbnail!.path.split(RegExp(r'[/\\]')).last}';
      
      final result = await _functions.httpsCallable('uploadToImageKit').call({
        'file': base64Thumb,
        'fileName': thumbName,
        'folder': 'THUMBNAILS',
      });
      
      thumbnailUrl = result.data['url'];
      thumbnailId = result.data['fileId'];
    }

    onProgress(1.0);

    return {
      'fileUrl': fileUrl,
      'fileId': fileId,
      'thumbnailUrl': thumbnailUrl,
      'thumbnailId': thumbnailId,
    };
  }

  String _getFolderForType(String type) {
    switch (type) {
      case 'Notes':
        return 'NOTES';
      case 'Exams':
      case 'Main Exams':
        return 'EXAMS';
      case 'CATs':
        return 'CATS';
      case 'Class Timetable':
      case 'EXAM Timetable':
        return 'TIME TABLES';
      case 'Practical Manual':
        return 'PRAC MANUAL';
      case 'Supplementary Exams':
        return 'SUPPLEMENTARY';
      default:
        return 'GENERAL';
    }
  }
}
