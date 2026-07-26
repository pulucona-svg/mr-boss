import 'dart:convert';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/material_model.dart';

class UploadService {
  FirebaseFunctions get _functions => FirebaseFunctions.instance;

  Future<Map<String, dynamic>> uploadMaterial(UploadMaterialModel material, Function(double) onProgress) async {
    onProgress(0.1);
    
    String? fileUrl;
    String? fileId;
    String? thumbnailUrl;
    String? thumbnailId;

    // 1. Upload Main File / Files
    String mainFileName = '';
    if (material.fileFormat == 'Images' && material.files.isNotEmpty) {
      mainFileName = material.files.first.path.split(RegExp(r'[/\\]')).last;
      final List<String> urls = [];
      final List<String> ids = [];
      
      final int totalFiles = material.files.length;
      for (int i = 0; i < totalFiles; i++) {
        final File currentFile = material.files[i];
        final fileBytes = await currentFile.readAsBytes();
        final base64File = base64Encode(fileBytes);
        final name = currentFile.path.split(RegExp(r'[/\\]')).last;
        final folder = _getFolderForType(material.materialType);
        
        final result = await _functions.httpsCallable('uploadToImageKit').call({
          'file': base64File,
          'fileName': name,
          'folder': folder,
        });
        
        urls.add(result.data['url'] ?? '');
        ids.add(result.data['fileId'] ?? '');
        
        // Progress goes from 0.1 to 0.6 as we upload images
        onProgress(0.1 + (0.5 * (i + 1) / totalFiles));
      }
      
      fileUrl = jsonEncode(urls);
      fileId = jsonEncode(ids);
    } else if (material.file != null) {
      mainFileName = material.file!.path.split(RegExp(r'[/\\]')).last;
      final fileBytes = await material.file!.readAsBytes();
      final base64File = base64Encode(fileBytes);
      
      final folder = _getFolderForType(material.materialType);
      
      final result = await _functions.httpsCallable('uploadToImageKit').call({
        'file': base64File,
        'fileName': mainFileName,
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
      'fileName': mainFileName,
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

  /// TASK 1: Intelligent Thumbnail Search for Uploaded Materials
  Future<Map<String, String>?> fetchIntelligentThumbnail({
    required String unitName,
    required String materialType,
    String? catType,
    String? unitCode,
  }) async {
    try {
      final result = await _functions.httpsCallable('searchThumbnailWithGemini').call({
        'unitName': unitName,
        'materialType': materialType,
        'catType': catType,
        'unitCode': unitCode,
      });

      if (result.data != null && result.data['success'] == true) {
        final String? url = result.data['thumbnailUrl'];
        final String? fileId = result.data['thumbnailId'];
        if (url != null && url.isNotEmpty) {
          return {
            'thumbnailUrl': url,
            'thumbnailId': fileId ?? '',
          };
        }
      }
    } catch (e) {
      // Failure handling: thumbnail search error must never disrupt upload
      print('Intelligent thumbnail search error: $e');
    }
    return null;
  }
}

