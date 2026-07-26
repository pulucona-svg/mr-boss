import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_laikipia/models/material_model.dart';
import 'package:mirror_laikipia/providers/upload_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Offline & Network Exception User-Friendly UI Tests', () {
    final sampleMaterial = UploadMaterialModel(
      unitName: 'Digital Electronics',
      unitCode: 'COMP 212',
      programs: ['Computer Science'],
      programCodes: ['COMP'],
      yearOfStudy: '2nd Year',
      semester: 'Semester 1',
      yearOfPublication: 2026,
      uploadedBy: 'TestUser',
      uploaderId: 'uid123',
      yearOfUpload: 2026,
      materialType: 'Notes',
    );

    test('1. UploadState initializes flags correctly for offline queueing', () {
      final state = UploadState(
        material: sampleMaterial,
        isUploading: false,
        isSuccess: false,
        isQueuedOffline: true,
        isConnectionLost: false,
        error: null,
      );

      expect(state.isQueuedOffline, isTrue);
      expect(state.isConnectionLost, isFalse);
      expect(state.isSuccess, isFalse);
      expect(state.error, null);
    });

    test('2. UploadState initializes flags correctly for mid-upload connection loss', () {
      final state = UploadState(
        material: sampleMaterial,
        isUploading: false,
        isSuccess: false,
        isQueuedOffline: false,
        isConnectionLost: true,
        error: null,
      );

      expect(state.isQueuedOffline, isFalse);
      expect(state.isConnectionLost, isTrue);
      expect(state.isSuccess, isFalse);
      expect(state.error, null);
    });

    test('3. Real unrecoverable error sets error string and leaves network flags false', () {
      final state = UploadState(
        material: sampleMaterial,
        isUploading: false,
        isSuccess: false,
        isQueuedOffline: false,
        isConnectionLost: false,
        error: 'Unsupported file format',
      );

      expect(state.isQueuedOffline, isFalse);
      expect(state.isConnectionLost, isFalse);
      expect(state.isSuccess, isFalse);
      expect(state.error, equals('Unsupported file format'));
    });
  });
}
