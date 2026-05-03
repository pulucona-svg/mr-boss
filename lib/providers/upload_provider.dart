import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/material_model.dart';
import '../services/course_service.dart';
import '../services/file_service.dart';
import '../services/upload_service.dart';
import '../services/resource_service.dart';

// Service Providers
final courseServiceProvider = Provider((ref) => CourseService());
final fileServiceProvider = Provider((ref) => FileService());
final uploadServiceProvider = Provider((ref) => UploadService());

// Upload State Class
class UploadState {
  final UploadMaterialModel material;
  final bool isUploading;
  final double uploadProgress;
  final String? error;
  final bool isSuccess;

  UploadState({
    required this.material,
    this.isUploading = false,
    this.uploadProgress = 0.0,
    this.error,
    this.isSuccess = false,
  });

  bool get isValid {
    return material.unitName.isNotEmpty &&
        material.unitCode.isNotEmpty &&
        material.programs.isNotEmpty &&
        material.yearOfStudy.isNotEmpty &&
        material.semester.isNotEmpty &&
        material.yearOfPublication > 1900 &&
        material.materialType.isNotEmpty &&
        material.file != null &&
        material.thumbnail != null;
  }

  UploadState copyWith({
    UploadMaterialModel? material,
    bool? isUploading,
    double? uploadProgress,
    String? error,
    bool? isSuccess,
  }) {
    return UploadState(
      material: material ?? this.material,
      isUploading: isUploading ?? this.isUploading,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      error: error,
      isSuccess: isSuccess ?? this.isSuccess,
    );
  }
}

// Upload Notifier
class UploadNotifier extends StateNotifier<UploadState> {
  final CourseService _courseService;
  final FileService _fileService;
  final UploadService _uploadService;

  UploadNotifier(this._courseService, this._fileService, this._uploadService)
      : super(UploadState(
          material: UploadMaterialModel(
            unitName: '',
            unitCode: '',
            programs: [],
            yearOfStudy: '1st Year',
            semester: 'Semester 1',
            yearOfPublication: DateTime.now().year,
            uploadedBy: ResourceService.currentUserName,
            uploaderId: ResourceService.currentUserId,
            yearOfUpload: DateTime.now().year,
            materialType: 'Notes',
          ),
        ));

  void updateUnitName(String name) {
    final code = _courseService.getCodeByName(name);
    state = state.copyWith(
      material: state.material.copyWith(
        unitName: name,
        unitCode: code ?? state.material.unitCode,
      ),
    );
  }

  void updateUnitCode(String code) {
    final name = _courseService.getNameByCode(code);
    state = state.copyWith(
      material: state.material.copyWith(
        unitCode: code,
        unitName: name ?? state.material.unitName,
      ),
    );
  }

  void toggleProgram(String program) {
    final programs = List<String>.from(state.material.programs);
    if (programs.contains(program)) {
      programs.remove(program);
    } else {
      programs.add(program);
    }
    state = state.copyWith(
      material: state.material.copyWith(programs: programs),
    );
  }

  void updateYearOfStudy(String year) {
    state = state.copyWith(material: state.material.copyWith(yearOfStudy: year));
  }

  void updateSemester(String semester) {
    state = state.copyWith(material: state.material.copyWith(semester: semester));
  }

  void updateYearOfPublication(int year) {
    state = state.copyWith(material: state.material.copyWith(yearOfPublication: year));
  }

  void updateMaterialType(String type) {
    state = state.copyWith(material: state.material.copyWith(materialType: type));
  }

  Future<void> pickDocument() async {
    final file = await _fileService.pickDocument(
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'html', 'htm'],
    );
    if (file != null) {
      final extension = file.path.split('.').last.toLowerCase();
      String format = 'Unknown';
      
      if (['jpg', 'jpeg', 'png'].contains(extension)) {
        format = 'Image';
      } else if (extension == 'pdf') {
        format = 'PDF';
      } else if (['html', 'htm'].contains(extension)) {
        format = 'HTML';
      }
      
      state = state.copyWith(
        material: state.material.copyWith(
          file: file,
          fileFormat: format,
        ),
      );
    }
  }

  Future<void> pickThumbnail() async {
    final thumbnail = await _fileService.pickImage();
    if (thumbnail != null) {
      state = state.copyWith(material: state.material.copyWith(thumbnail: thumbnail));
    }
  }

  Future<void> upload() async {
    if (!state.isValid) return;

    state = state.copyWith(isUploading: true, error: null, isSuccess: false);

    try {
      await _uploadService.uploadMaterial(
        state.material,
        (progress) {
          state = state.copyWith(uploadProgress: progress);
        },
      );

      // Create a Resource object and add to ResourceService
      final resource = Resource(
        title: state.material.unitName, // Using unit name as title for now
        type: state.material.materialType,
        thumbnailUrl: 'https://images.unsplash.com/photo-1581092160562-40aa08e78837?w=400', // Mock URL
        unitName: state.material.unitName,
        unitCode: state.material.unitCode,
        year: state.material.yearOfUpload.toString(),
        uploadYear: state.material.yearOfUpload.toString(),
        publicationYear: state.material.yearOfPublication.toString(),
        yearOfStudy: state.material.yearOfStudy,
        semester: state.material.semester,
        lecturer: 'TBD',
        uploadedBy: state.material.uploadedBy,
        uploaderRole: 'Student',
        uploaderId: state.material.uploaderId,
        uploadDate: DateTime.now(),
        status: 'waiting',
        courseProgram: state.material.programs.join(', '),
      );

      ResourceService().addUpload(resource);

      state = state.copyWith(isUploading: false, isSuccess: true, uploadProgress: 1.0);
    } catch (e) {
      state = state.copyWith(isUploading: false, error: e.toString());
    }
  }

  void reset() {
    state = UploadState(
      material: UploadMaterialModel(
        unitName: '',
        unitCode: '',
        programs: [],
        yearOfStudy: '1st Year',
        semester: 'Semester 1',
        yearOfPublication: DateTime.now().year,
        uploadedBy: ResourceService.currentUserName,
        uploaderId: ResourceService.currentUserId,
        yearOfUpload: DateTime.now().year,
        materialType: 'Notes',
      ),
    );
  }
}

// Provider for the UploadNotifier
final uploadProvider = StateNotifierProvider<UploadNotifier, UploadState>((ref) {
  return UploadNotifier(
    ref.watch(courseServiceProvider),
    ref.watch(fileServiceProvider),
    ref.watch(uploadServiceProvider),
  );
});

// Suggestions provider
final programSuggestionsProvider = Provider.family<List<String>, String>((ref, query) {
  final programs = ref.watch(courseServiceProvider).programsList;
  if (query.isEmpty) return [];
  return programs
      .where((p) => p.toLowerCase().contains(query.toLowerCase()))
      .toList();
});

final unitNameSuggestionsProvider = Provider.family<List<String>, String>((ref, query) {
  final names = ref.watch(courseServiceProvider).courseNames;
  if (query.isEmpty) return names;
  return names
      .where((n) => n.toLowerCase().contains(query.toLowerCase()))
      .toList();
});

final unitCodeSuggestionsProvider = Provider.family<List<String>, String>((ref, query) {
  final codes = ref.watch(courseServiceProvider).courseCodes;
  if (query.isEmpty) return codes;
  return codes
      .where((c) => c.toLowerCase().contains(query.toLowerCase()))
      .toList();
});
