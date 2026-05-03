import '../models/material_model.dart';

class UploadService {
  Future<void> uploadMaterial(UploadMaterialModel material, Function(double) onProgress) async {
    // Simulate upload progress
    double progress = 0.0;
    while (progress < 1.0) {
      await Future.delayed(const Duration(milliseconds: 500));
      progress += 0.2;
      if (progress > 1.0) progress = 1.0;
      onProgress(progress);
    }
    
    // Simulate final server response
  }
}
