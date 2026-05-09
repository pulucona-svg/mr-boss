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
final resourceServiceProvider = Provider((ref) => ResourceService());

// Upload State Class
class UploadState {
  final UploadMaterialModel material;
  final String uploadMode; // 'material' or 'timetable'
  final bool isUploading;
  final double uploadProgress;
  final String? error;
  final bool isSuccess;
  final bool showReplacePrompt;
  final bool showApprovedMessage;
  final String? existingMaterialId;

  UploadState({
    required this.material,
    this.uploadMode = 'material',
    this.isUploading = false,
    this.uploadProgress = 0.0,
    this.error,
    this.isSuccess = false,
    this.showReplacePrompt = false,
    this.showApprovedMessage = false,
    this.existingMaterialId,
  });

  bool get isValid {
    if (uploadMode == 'material') {
      return material.unitName.isNotEmpty &&
          material.unitCode.isNotEmpty &&
          material.programs.isNotEmpty &&
          material.yearOfStudy.isNotEmpty &&
          material.semester.isNotEmpty &&
          material.yearOfPublication > 1900 &&
          material.materialType.isNotEmpty &&
          material.file != null &&
          material.thumbnail != null;
    } else {
      // Timetable mode: requires programs, programCodes, yearOfStudy, semester, files
      return material.programs.isNotEmpty &&
          material.programCodes.isNotEmpty &&
          material.yearOfStudy.isNotEmpty &&
          material.semester.isNotEmpty &&
          material.yearOfPublication > 1900 &&
          material.file != null &&
          material.thumbnail != null;
    }
  }

  UploadState copyWith({
    UploadMaterialModel? material,
    String? uploadMode,
    bool? isUploading,
    double? uploadProgress,
    String? error,
    bool? isSuccess,
    bool? showReplacePrompt,
    bool? showApprovedMessage,
    String? existingMaterialId,
  }) {
    return UploadState(
      material: material ?? this.material,
      uploadMode: uploadMode ?? this.uploadMode,
      isUploading: isUploading ?? this.isUploading,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      error: error,
      isSuccess: isSuccess ?? this.isSuccess,
      showReplacePrompt: showReplacePrompt ?? this.showReplacePrompt,
      showApprovedMessage: showApprovedMessage ?? this.showApprovedMessage,
      existingMaterialId: existingMaterialId ?? this.existingMaterialId,
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
            programCodes: [],
            yearOfStudy: '1st Year',
            semester: 'Semester 1',
            yearOfPublication: DateTime.now().year,
            uploadedBy: ResourceService.currentUserName,
            uploaderId: ResourceService.currentUserId,
            yearOfUpload: DateTime.now().year,
            materialType: 'Notes',
          ),
        ));

  void updateUploadMode(String mode) {
    state = state.copyWith(
      uploadMode: mode,
      material: state.material.copyWith(
        materialType: mode == 'timetable' ? 'Class Timetable' : 'Notes',
      ),
    );
  }

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

  void updateProgram(String program) {
    final code = _courseService.getProgramCode(program);
    state = state.copyWith(
      material: state.material.copyWith(
        programs: [program],
        programCodes: code != null ? [code] : state.material.programCodes,
      ),
    );
  }

  void updateProgramCode(String code) {
    final program = _courseService.getProgramNameByCode(code);
    state = state.copyWith(
      material: state.material.copyWith(
        programCodes: [code],
        programs: program != null ? [program] : state.material.programs,
      ),
    );
  }

  void toggleLecturer(String lecturer) {
    final lecturers = List<String>.from(state.material.lecturers);
    if (lecturers.contains(lecturer)) {
      lecturers.remove(lecturer);
    } else {
      lecturers.add(lecturer);
    }
    state = state.copyWith(
      material: state.material.copyWith(lecturers: lecturers),
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

  Future<void> pickTimetableImage() async {
    final image = await _fileService.pickImage();
    if (image != null) {
      state = state.copyWith(
        material: state.material.copyWith(
          file: image,
          thumbnail: image,
          fileFormat: 'Image',
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

    // Check for duplicates
    final duplicate = ResourceService().findDuplicate(
      state.material.unitCode,
      state.material.materialType,
      state.material.yearOfStudy,
      state.material.semester,
      state.material.yearOfPublication.toString(),
    );

    if (duplicate != null) {
      if (duplicate.status == 'approved') {
        state = state.copyWith(showApprovedMessage: true);
        return;
      } else {
        state = state.copyWith(
          showReplacePrompt: true,
          existingMaterialId: duplicate.title,
        );
        return;
      }
    }

    await _executeUpload();
  }

  Future<void> _executeUpload({bool isReplacement = false}) async {
    state = state.copyWith(isUploading: true, error: null, isSuccess: false);

    try {
      await _uploadService.uploadMaterial(
        state.material,
        (progress) {
          state = state.copyWith(uploadProgress: progress);
        },
      );

      if (isReplacement && state.existingMaterialId != null) {
        ResourceService().deleteUpload(state.existingMaterialId!);
      }

      // Create a Resource object and add to ResourceService
      final resource = Resource(
        title: state.uploadMode == 'timetable' 
            ? '${state.material.programs.join(", ")} Timetable' 
            : state.material.unitName,
        type: state.material.materialType,
        thumbnailUrl: state.material.thumbnail!.path, // Use the local file path
        unitName: state.material.unitName,
        unitCode: state.material.unitCode,
        year: state.material.yearOfUpload.toString(),
        uploadYear: state.material.yearOfUpload.toString(),
        publicationYear: state.material.yearOfPublication.toString(),
        yearOfStudy: state.material.yearOfStudy,
        semester: state.material.semester,
        lecturer: state.material.lecturers.isNotEmpty 
            ? state.material.lecturers.join(', ') 
            : 'TBD',
        uploadedBy: state.material.uploadedBy,
        uploaderRole: 'Student',
        uploaderId: state.material.uploaderId,
        uploadDate: DateTime.now(),
        status: 'waiting',
        courseProgram: state.material.programs.join(', '),
        programCodes: state.material.programCodes,
      );

      ResourceService().addUpload(resource);

      // Reset fields after successful upload
      reset();
      
      state = state.copyWith(
        isUploading: false, 
        isSuccess: true, 
        uploadProgress: 1.0,
        showReplacePrompt: false,
        existingMaterialId: null,
      );
    } catch (e) {
      state = state.copyWith(isUploading: false, error: e.toString());
    }
  }

  void confirmReplace() {
    _executeUpload(isReplacement: true);
  }

  void cancelReplace() {
    reset();
    state = state.copyWith(showReplacePrompt: false, existingMaterialId: null);
  }

  void dismissApprovedMessage() {
    state = state.copyWith(showApprovedMessage: false);
  }

  void reset() {
    state = UploadState(
      material: UploadMaterialModel(
        unitName: '',
        unitCode: '',
        programs: [],
        programCodes: [],
        lecturers: [],
        yearOfStudy: '1st Year',
        semester: 'Semester 1',
        yearOfPublication: DateTime.now().year,
        uploadedBy: ResourceService.currentUserName,
        uploaderId: ResourceService.currentUserId,
        yearOfUpload: DateTime.now().year,
        materialType: state.uploadMode == 'timetable' ? 'Class Timetable' : 'Notes',
      ),
      uploadMode: state.uploadMode,
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

final lecturerSuggestionsProvider = Provider.family<List<String>, String>((ref, query) {
  final lecturers = ref.watch(resourceServiceProvider).getUniqueLecturers();
  if (query.isEmpty) return lecturers;
  return lecturers
      .where((l) => l.toLowerCase().contains(query.toLowerCase()))
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
