import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

class FileService {
  final Dio _dio = Dio();
  final ImagePicker _imagePicker = ImagePicker();

  /// Picks a document (PDF, DOCX, etc.) from the device.
  Future<File?> pickDocument({List<String>? allowedExtensions}) async {
    try {
      final result = await FilePicker.pickFiles(
        type: allowedExtensions != null ? FileType.custom : FileType.any,
        allowedExtensions: allowedExtensions,
      );

      if (result != null && result.files.single.path != null) {
        return File(result.files.single.path!);
      }
    } catch (e) {
      debugPrint('FileService: [ERROR] pickDocument failed: $e');
    }
    return null;
  }

  /// Picks an image from the gallery or camera.
  Future<File?> pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        return File(image.path);
      }
    } catch (e) {
      debugPrint('FileService: [ERROR] pickImage failed: $e');
    }
    return null;
  }

  /// Downloads a file from [url] and returns the local file path.
  /// If the file already exists locally, it returns the existing path.
  Future<String?> downloadFile(String url, String fileName) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);

      if (await file.exists()) {
        debugPrint('FileService: File already exists at $filePath');
        return filePath;
      }

      debugPrint('FileService: Starting download from $url to $filePath');
      await _dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            debugPrint('FileService: Download progress: ${(received / total * 100).toStringAsFixed(0)}%');
          }
        },
      );

      debugPrint('FileService: Download complete: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('FileService: [ERROR] Download failed: $e');
      return null;
    }
  }

  /// Opens a file using the system's default app for its type.
  Future<void> openFile(String filePath) async {
    try {
      final result = await OpenFilex.open(filePath);
      debugPrint('FileService: Open file result: ${result.message}');
    } catch (e) {
      debugPrint('FileService: [ERROR] Could not open file: $e');
    }
  }

  /// Determines if a file extension is likely to be a PDF.
  bool isPdf(String url) {
    return url.toLowerCase().contains('.pdf');
  }

  /// Determines if a file is an image.
  bool isImage(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.contains('.jpg') || 
           lowerUrl.contains('.jpeg') || 
           lowerUrl.contains('.png') || 
           lowerUrl.contains('.webp');
  }
}
