import 'dart:convert';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/material_model.dart';

class TimetableUploadService {
  FirebaseFunctions get _functions => FirebaseFunctions.instance;

  /// Dedicated Timetable Upload Pipeline
  /// Uploads a single timetable image file to ImageKit.
  /// Reuses the uploaded file URL and ID directly as thumbnailUrl and thumbnailId with thumbnailStatus = 'completed'.
  /// Performs ZERO calls to thumbnail search, Gemini, Pixabay, or Wikimedia.
  Future<Map<String, dynamic>> uploadTimetable(
    UploadMaterialModel timetableModel,
    Function(double) onProgress,
  ) async {
    onProgress(0.1);

    if (timetableModel.file == null) {
      throw Exception('Timetable image file is required');
    }

    final File imageFile = timetableModel.file!;
    final String fileName = imageFile.path.split(RegExp(r'[/\\]')).last;
    final List<int> fileBytes = await imageFile.readAsBytes();
    final String base64File = base64Encode(fileBytes);

    onProgress(0.4);

    final result = await _functions.httpsCallable('uploadToImageKit').call({
      'file': base64File,
      'fileName': fileName,
      'folder': 'TIME_TABLES',
    });

    onProgress(0.9);

    final String fileUrl = result.data['url'] ?? '';
    final String fileId = result.data['fileId'] ?? '';

    onProgress(1.0);

    return {
      'fileUrl': fileUrl,
      'fileId': fileId,
      'fileName': fileName,
      'thumbnailUrl': fileUrl,
      'thumbnailId': fileId,
      'thumbnailStatus': 'completed',
    };
  }
}
