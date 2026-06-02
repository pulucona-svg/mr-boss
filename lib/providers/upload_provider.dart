import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/material_model.dart';
import '../services/course_service.dart';
import '../services/file_service.dart';
import '../services/upload_service.dart';
import '../services/resource_service.dart';
import '../services/subscription_service.dart';
import '../services/download_service.dart';
import '../services/view_service.dart';
import '../services/comment_service.dart';
import 'providers.dart';

// Service Providers - Consolidated in service_providers.dart

// Upload State Class
class UploadState {
  final UploadMaterialModel material;
  final String uploadMode; // 'material' or 'timetable'
  final bool isUploading;
  final double uploadProgress;
  final String? error;
  final bool isSuccess;

  UploadState({
    required this.material,
    this.uploadMode = 'material',
    this.isUploading = false,
    this.uploadProgress = 0.0,
    this.error,
    this.isSuccess = false,
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
          material.file != null;
    } else {
      // Timetable mode: requires programs, programCodes, yearOfStudy, semester, files
      return material.programs.isNotEmpty &&
          material.programCodes.isNotEmpty &&
          material.yearOfStudy.isNotEmpty &&
          material.semester.isNotEmpty &&
          material.yearOfPublication > 1900 &&
          material.file != null;
    }
  }

  UploadState copyWith({
    UploadMaterialModel? material,
    String? uploadMode,
    bool? isUploading,
    double? uploadProgress,
    String? error,
    bool? isSuccess,
  }) {
    return UploadState(
      material: material ?? this.material,
      uploadMode: uploadMode ?? this.uploadMode,
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
  final UserProfile _userProfile;

  UploadNotifier(this._courseService, this._fileService, this._uploadService, this._userProfile)
      : super(UploadState(
          material: UploadMaterialModel(
            unitName: '',
            unitCode: '',
            programs: [],
            programCodes: [],
            yearOfStudy: '1st Year',
            semester: 'Semester 1',
            yearOfPublication: DateTime.now().year,
            uploadedBy: _userProfile.username,
            uploaderId: _userProfile.uid,
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
    final units = _courseService.getUnitsByCode(code ?? '');
    
    String yearOfStudy = state.material.yearOfStudy;
    String semester = state.material.semester;
    Set<String> programs = Set.from(state.material.programs);
    Set<String> programCodes = Set.from(state.material.programCodes);
    Set<String> lecturers = Set.from(state.material.lecturers);

    if (units.isNotEmpty) {
      // Aggregate all programs and lecturers for this unit
      programs.clear();
      programCodes.clear();
      lecturers.clear();
      
      for (var u in units) {
        if (u.programName.isNotEmpty) programs.add(u.programName);
        if (u.programCode.isNotEmpty) programCodes.add(u.programCode);
        if (u.lecturerName.isNotEmpty) lecturers.add(u.lecturerName);
      }
      
      // Use the first unit match for year and semester
      final firstMatch = units.first;
      yearOfStudy = _normalizeYear(firstMatch.yearOfStudy);
      semester = _normalizeSemester(firstMatch.semester);
    }

    state = state.copyWith(
      material: state.material.copyWith(
        unitName: name,
        unitCode: code ?? state.material.unitCode,
        yearOfStudy: yearOfStudy,
        semester: semester,
        programs: programs.toList(),
        programCodes: programCodes.toList(),
        lecturers: lecturers.toList(),
      ),
    );
  }

  void updateUnitCode(String code) {
    final name = _courseService.getNameByCode(code);
    final units = _courseService.getUnitsByCode(code);
    
    String yearOfStudy = state.material.yearOfStudy;
    String semester = state.material.semester;
    Set<String> programs = Set.from(state.material.programs);
    Set<String> programCodes = Set.from(state.material.programCodes);
    Set<String> lecturers = Set.from(state.material.lecturers);

    if (units.isNotEmpty) {
      programs.clear();
      programCodes.clear();
      lecturers.clear();
      
      for (var u in units) {
        if (u.programName.isNotEmpty) programs.add(u.programName);
        if (u.programCode.isNotEmpty) programCodes.add(u.programCode);
        if (u.lecturerName.isNotEmpty) lecturers.add(u.lecturerName);
      }
      
      final firstMatch = units.first;
      yearOfStudy = _normalizeYear(firstMatch.yearOfStudy);
      semester = _normalizeSemester(firstMatch.semester);
    }

    state = state.copyWith(
      material: state.material.copyWith(
        unitCode: code,
        unitName: name ?? state.material.unitName,
        yearOfStudy: yearOfStudy,
        semester: semester,
        programs: programs.toList(),
        programCodes: programCodes.toList(),
        lecturers: lecturers.toList(),
      ),
    );
  }

  String _normalizeYear(String year) {
    final y = year.trim();
    if (y == '1' || y.toLowerCase().startsWith('1st')) return '1st Year';
    if (y == '2' || y.toLowerCase().startsWith('2nd')) return '2nd Year';
    if (y == '3' || y.toLowerCase().startsWith('3rd')) return '3rd Year';
    if (y == '4' || y.toLowerCase().startsWith('4th')) return '4th Year';
    return '1st Year'; // Default fallback
  }

  String _normalizeSemester(String sem) {
    final s = sem.trim();
    if (s == '1' || s.toLowerCase().contains('1')) return 'Semester 1';
    if (s == '2' || s.toLowerCase().contains('2')) return 'Semester 2';
    return 'Semester 1'; // Default fallback
  }

  void toggleProgram(String program) {
    final programs = List<String>.from(state.material.programs);
    final codes = List<String>.from(state.material.programCodes);
    final code = _courseService.getProgramCode(program);

    if (programs.contains(program)) {
      programs.remove(program);
      if (code != null) codes.remove(code);
    } else {
      programs.add(program);
      if (code != null) {
        if (!codes.contains(code)) codes.add(code);
      }
    }
    
    state = state.copyWith(
      material: state.material.copyWith(
        programs: programs,
        programCodes: codes,
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
    state = state.copyWith(
      material: state.material.copyWith(
        materialType: type,
        catType: type == 'CATs' ? 'CAT 1' : null,
      ),
    );
  }

  void updateCatType(String catType) {
    state = state.copyWith(
      material: state.material.copyWith(catType: catType),
    );
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
    await _executeUpload();
  }

  Future<void> _executeUpload() async {
    state = state.copyWith(isUploading: true, error: null, isSuccess: false);

    try {
      String resourceTitle;
      if (state.uploadMode == 'timetable') {
        resourceTitle = '${state.material.programs.join(", ")} Timetable';
      } else if (state.material.materialType == 'CATs' && state.material.catType != null) {
        resourceTitle = '${state.material.unitName} ${state.material.catType}';
      } else {
        resourceTitle = state.material.unitName;
      }

      // Generate a thematic thumbnail URL based on the unit name
      final thumbnailUrl = _getThematicThumbnail(state.material.unitName, state.material.unitCode);

      // Perform the upload and get ImageKit data
      final uploadResult = await _uploadService.uploadMaterial(
        state.material,
        (progress) {
          state = state.copyWith(uploadProgress: progress);
        },
      );

      final String finalFileUrl = uploadResult['fileUrl'] ?? '';
      final String finalFileId = uploadResult['fileId'] ?? '';
      final String finalFileName = uploadResult['fileName'] ?? '';
      final String finalThumbUrl = uploadResult['thumbnailUrl'] ?? thumbnailUrl;
      final String finalThumbId = uploadResult['thumbnailId'] ?? '';

      // Create a Resource object and add to ResourceService
      final resource = Resource(
        title: resourceTitle,
        fileName: finalFileName,
        type: state.material.materialType,
        thumbnailUrl: finalThumbUrl,
        fileUrl: finalFileUrl,
        fileId: finalFileId,
        thumbnailId: finalThumbId,
        unitName: state.material.unitName,
        unitCode: state.material.unitCode,
        year: state.material.yearOfUpload.toString(),
        uploadYear: state.material.yearOfUpload.toString(),
        publicationYear: state.material.yearOfPublication.toString(),
        yearOfStudy: state.material.yearOfStudy,
        semester: state.material.semester,
        lecturers: state.material.lecturers.isNotEmpty 
            ? state.material.lecturers 
            : ['TBD'],
        uploadedBy: state.material.uploadedBy,
        uploaderRole: 'Student',
        uploaderId: state.material.uploaderId,
        uploadDate: DateTime.now(),
        status: 'waiting',
        targetPrograms: state.material.programs,
        programCodes: state.material.programCodes,
      );

      await ResourceService().addUpload(resource, _courseService);
      
      // Force immediate refresh of user uploads to update list in UI
      await ResourceService().fetchUserUploadsOnce(state.material.uploaderId);

      // Reset fields after successful upload
      reset();
      
      state = state.copyWith(
        isUploading: false, 
        isSuccess: true, 
        uploadProgress: 1.0,
      );
    } catch (e) {
      state = state.copyWith(isUploading: false, error: e.toString());
    }
  }

  String _getThematicThumbnail(String unitName, String unitCode) {
    final name = unitName.toLowerCase();
    final code = unitCode.toLowerCase();
    
    // Map keywords to Unsplash search terms for academic subjects
    if (name.contains('comput') || name.contains('digital') || name.contains('software') || code.startsWith('comp')) {
      return 'https://images.unsplash.com/photo-1518770660439-4636190af475?w=400&q=80'; // Tech/CPU
    } else if (name.contains('math') || name.contains('calculus') || name.contains('stat') || code.startsWith('math')) {
      return 'https://images.unsplash.com/photo-1509228468518-180dd4864904?w=400&q=80'; // Math/Blackboard
    } else if (name.contains('physics') || name.contains('electron') || code.startsWith('phys')) {
      return 'https://images.unsplash.com/photo-1635070041078-e363dbe004041078e363dbe00?w=400&q=80'; // Physics/Atom
    } else if (name.contains('biolog') || name.contains('anatomy') || name.contains('health') || code.startsWith('biol')) {
      return 'https://images.unsplash.com/photo-1530213786676-41ad9f7736f6?w=400&q=80'; // Biology/Cells
    } else if (name.contains('chem') || code.startsWith('chem')) {
      return 'https://images.unsplash.com/photo-1532094349884-543bc11b234d?w=400&q=80'; // Chemistry/Lab
    } else if (name.contains('business') || name.contains('econom') || name.contains('account') || code.startsWith('bcom') || code.startsWith('econ')) {
      return 'https://images.unsplash.com/photo-1460925895917-afdab827c52f?w=400&q=80'; // Business/Charts
    } else if (name.contains('law') || name.contains('huri') || code.startsWith('huri')) {
      return 'https://images.unsplash.com/photo-1589829545856-d10d557cf95f?w=400&q=80'; // Law/Gavel
    } else if (name.contains('literat') || name.contains('hist') || name.contains('psychol')) {
      return 'https://images.unsplash.com/photo-1491841573634-28140fc7ced7?w=400&q=80'; // Arts/Books
    }
    
    // Default academic thumbnail
    return 'https://images.unsplash.com/photo-1516116216624-53e697fedbea?w=400&q=80';
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
        uploadedBy: _userProfile.username,
        uploaderId: _userProfile.uid,
        yearOfUpload: DateTime.now().year,
        materialType: state.uploadMode == 'timetable' ? 'Class Timetable' : 'Notes',
      ),
      uploadMode: state.uploadMode,
    );
  }
}

// Provider for the UploadNotifier
final uploadProvider = StateNotifierProvider.autoDispose<UploadNotifier, UploadState>((ref) {
  final userProfile = ref.watch(userProfileProvider);
  return UploadNotifier(
    ref.watch(courseServiceProvider),
    ref.watch(fileServiceProvider),
    ref.watch(uploadServiceProvider),
    userProfile,
  );
});

// Suggestions providers
final programSuggestionsProvider = Provider.autoDispose.family<List<String>, String>((ref, query) {
  final uploadState = ref.watch(uploadProvider);
  final unitCode = uploadState.material.unitCode;
  
  if (unitCode.isNotEmpty) {
    // If a unit is selected, suggest only programs associated with that unit
    final units = ref.watch(courseServiceProvider).getUnitsByCode(unitCode);
    final unitPrograms = units.map((u) => u.programName).where((p) => p.isNotEmpty).toSet().toList();
    if (query.isEmpty) return unitPrograms;
    return unitPrograms.where((p) => p.toLowerCase().contains(query.toLowerCase())).toList();
  }

  final programs = ref.watch(courseServiceProvider).programsList;
  if (query.isEmpty) return [];
  return programs
      .where((p) => p.toLowerCase().contains(query.toLowerCase()))
      .toList();
});

final lecturerSuggestionsProvider = Provider.autoDispose.family<List<String>, String>((ref, query) {
  final uploadState = ref.watch(uploadProvider);
  final unitCode = uploadState.material.unitCode;

  if (unitCode.isNotEmpty) {
    final units = ref.watch(courseServiceProvider).getUnitsByCode(unitCode);
    final unitLecturers = units.map((u) => u.lecturerName).where((l) => l.isNotEmpty).toSet().toList();
    if (query.isEmpty) return unitLecturers;
    return unitLecturers.where((l) => l.toLowerCase().contains(query.toLowerCase())).toList();
  }

  final lecturers = ref.watch(resourceServiceProvider).getUniqueLecturers();
  if (query.isEmpty) return lecturers;
  return lecturers
      .where((l) => l.toLowerCase().contains(query.toLowerCase()))
      .toList();
});

final unitNameSuggestionsProvider = Provider.autoDispose.family<List<String>, String>((ref, query) {
  final names = ref.watch(courseServiceProvider).courseNames;
  if (query.isEmpty) return names;
  return names
      .where((n) => n.toLowerCase().contains(query.toLowerCase()))
      .toList();
});

final unitCodeSuggestionsProvider = Provider.autoDispose.family<List<String>, String>((ref, query) {
  final codes = ref.watch(courseServiceProvider).courseCodes;
  if (query.isEmpty) return codes;
  return codes
      .where((c) => c.toLowerCase().contains(query.toLowerCase()))
      .toList();
});
