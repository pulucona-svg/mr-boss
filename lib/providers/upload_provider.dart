import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/material_model.dart';
import '../services/course_service.dart';
import '../services/file_service.dart';
import '../services/upload_service.dart';
import '../services/timetable_upload_service.dart';
import '../services/resource_service.dart';
import '../services/connectivity_service.dart';
import '../services/offline_upload_queue_service.dart';
import 'providers.dart';

// Upload State Class
class UploadState {
  final UploadMaterialModel material;
  final String uploadMode; // 'material' or 'timetable'
  final bool isUploading;
  final double uploadProgress;
  final String? error;
  final bool isSuccess;
  final bool isQueuedOffline;
  final bool isConnectionLost;

  UploadState({
    required this.material,
    this.uploadMode = 'material',
    this.isUploading = false,
    this.uploadProgress = 0.0,
    this.error,
    this.isSuccess = false,
    this.isQueuedOffline = false,
    this.isConnectionLost = false,
  });

  bool get isModifyMode => material.existingMaterialId != null && material.existingMaterialId!.isNotEmpty;

  bool get isValid {
    if (uploadMode == 'material') {
      final hasFile = material.file != null ||
          material.files.isNotEmpty ||
          (material.existingFileUrl != null && material.existingFileUrl!.isNotEmpty);
      return material.unitName.trim().isNotEmpty &&
          material.unitCode.trim().isNotEmpty &&
          material.programs.isNotEmpty &&
          material.yearOfStudy.trim().isNotEmpty &&
          material.semester.trim().isNotEmpty &&
          material.yearOfPublication > 1900 &&
          material.materialType.trim().isNotEmpty &&
          hasFile &&
          error == null;
    } else {
      // Timetable mode: requires programs, programCodes, yearOfStudy, semester, timetable image file
      final hasFile = material.file != null ||
          (material.existingFileUrl != null && material.existingFileUrl!.isNotEmpty);
      return material.programs.isNotEmpty &&
          material.programCodes.isNotEmpty &&
          material.yearOfStudy.trim().isNotEmpty &&
          material.semester.trim().isNotEmpty &&
          material.yearOfPublication > 1900 &&
          hasFile;
    }
  }

  UploadState copyWith({
    UploadMaterialModel? material,
    String? uploadMode,
    bool? isUploading,
    double? uploadProgress,
    String? error,
    bool? isSuccess,
    bool? isQueuedOffline,
    bool? isConnectionLost,
  }) {
    return UploadState(
      material: material ?? this.material,
      uploadMode: uploadMode ?? this.uploadMode,
      isUploading: isUploading ?? this.isUploading,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      error: error,
      isSuccess: isSuccess ?? this.isSuccess,
      isQueuedOffline: isQueuedOffline ?? this.isQueuedOffline,
      isConnectionLost: isConnectionLost ?? this.isConnectionLost,
    );
  }
}

// Upload Notifier
class UploadNotifier extends StateNotifier<UploadState> {
  final CourseService _courseService;
  final FileService _fileService;
  final UploadService _uploadService;
  final TimetableUploadService _timetableUploadService;
  final UserProfile _userProfile;

  UploadNotifier(
    this._courseService,
    this._fileService,
    this._uploadService,
    this._timetableUploadService,
    this._userProfile, {
    String initialMode = 'material',
  }) : super(UploadState(
          uploadMode: initialMode,
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
            materialType: initialMode == 'timetable' ? 'Class Timetable' : 'Notes',
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
    return '1st Year';
  }

  String _normalizeSemester(String sem) {
    final s = sem.trim();
    if (s == '1' || s.toLowerCase().contains('1')) return 'Semester 1';
    if (s == '2' || s.toLowerCase().contains('2')) return 'Semester 2';
    return 'Semester 1';
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
      if (code != null && !codes.contains(code)) {
        codes.add(code);
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
    final p = program.trim();
    if (p.isEmpty) {
      state = state.copyWith(
        material: state.material.copyWith(
          programs: [],
          programCodes: [],
        ),
      );
      return;
    }
    final code = _courseService.getProgramCode(p) ?? p;
    state = state.copyWith(
      material: state.material.copyWith(
        programs: [p],
        programCodes: [code],
      ),
    );
  }

  void updateProgramCode(String code) {
    final c = code.trim();
    if (c.isEmpty) {
      state = state.copyWith(
        material: state.material.copyWith(
          programCodes: [],
        ),
      );
      return;
    }
    final program = _courseService.getProgramNameByCode(c) ?? (state.material.programs.isNotEmpty ? state.material.programs.first : c);
    state = state.copyWith(
      material: state.material.copyWith(
        programCodes: [c],
        programs: [program],
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
    final pickedFiles = await _fileService.pickMultipleFiles(
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'html', 'htm'],
    );
    if (pickedFiles == null || pickedFiles.isEmpty) return;

    final hasPdf = pickedFiles.any((f) => f.path.split('.').last.toLowerCase() == 'pdf');
    final hasHtml = pickedFiles.any((f) => ['html', 'htm'].contains(f.path.split('.').last.toLowerCase()));
    final hasImage = pickedFiles.any((f) => ['jpg', 'jpeg', 'png'].contains(f.path.split('.').last.toLowerCase()));

    if ((hasPdf || hasHtml) && hasImage) {
      state = state.copyWith(
        error: 'Mixing PDF/HTML and images is not allowed.',
      );
      return;
    }

    if ((hasPdf || hasHtml) && pickedFiles.length > 1) {
      state = state.copyWith(
        error: 'Only one PDF/HTML document can be uploaded at a time.',
      );
      return;
    }

    if (hasImage) {
      if (pickedFiles.length > 10) {
        state = state.copyWith(
          error: 'Maximum of 10 images allowed per upload.',
        );
        return;
      }
      state = state.copyWith(
        error: null,
        material: state.material.copyWith(
          file: pickedFiles.first,
          files: pickedFiles,
          fileFormat: 'Images',
        ),
      );
    } else {
      state = state.copyWith(
        error: null,
        material: state.material.copyWith(
          file: pickedFiles.first,
          files: [pickedFiles.first],
          fileFormat: hasPdf ? 'PDF' : 'HTML',
        ),
      );
    }
  }

  void updateIsAnonymous(bool value) {
    state = state.copyWith(
      material: state.material.copyWith(isAnonymous: value),
    );
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  Future<void> pickTimetableImage() async {
    final image = await _fileService.pickImage();
    if (image != null) {
      state = state.copyWith(
        material: state.material.copyWith(
          file: image,
          thumbnail: null,
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

  void initForModify(Resource resource, {bool isModeration = false}) {
    state = state.copyWith(
      uploadMode: resource.type.contains('Timetable') ? 'timetable' : 'material',
      material: UploadMaterialModel(
        unitName: resource.unitName,
        unitCode: resource.unitCode,
        programs: List<String>.from(resource.targetPrograms),
        programCodes: List<String>.from(resource.programCodes),
        lecturers: List<String>.from(resource.lecturers),
        yearOfStudy: resource.yearOfStudy,
        semester: resource.semester,
        yearOfPublication: int.tryParse(resource.publicationYear) ?? (int.tryParse(resource.year) ?? DateTime.now().year),
        uploadedBy: resource.uploadedBy,
        uploaderId: resource.uploaderId,
        yearOfUpload: int.tryParse(resource.uploadYear) ?? (int.tryParse(resource.year) ?? DateTime.now().year),
        materialType: resource.type,
        catType: resource.type == 'CATs'
            ? (resource.title.contains('CAT 2') ? 'CAT 2' : 'CAT 1')
            : null,
        fileFormat: resource.materialFormat,
        isAnonymous: resource.isAnonymous,
        existingMaterialId: resource.id,
        existingFileUrl: resource.fileUrl,
        existingFileName: resource.fileName.isNotEmpty ? resource.fileName : resource.fileUrl.split(RegExp(r'[/\\]')).last,
        existingFileId: resource.fileId,
        existingThumbnailUrl: resource.thumbnailUrl,
        existingThumbnailId: resource.thumbnailId,
        existingThumbnailStatus: resource.thumbnailStatus,
        existingUploadDate: resource.uploadDate,
        existingUploaderRole: resource.uploaderRole,
        existingUploaderProfilePic: resource.uploaderProfilePic,
        existingViews: resource.views,
        existingLikes: resource.likes,
        existingComments: resource.comments,
        existingLikedBy: List<String>.from(resource.likedBy),
        existingStatus: resource.status,
        existingIsPinned: resource.isPinned,
        existingPinnedAt: resource.pinnedAt,
        updatedByAdmin: true,
        updatedAt: DateTime.now(),
        isModerationModify: isModeration,
        adminRemark: resource.adminRemark,
        existingApprovedAt: resource.approvedAt,
        existingRejectionReasons: resource.rejectionReasons,
      ),
    );
  }

  void setAdminRemark(String remark) {
    state = state.copyWith(
      material: state.material.copyWith(adminRemark: remark),
    );
  }

  Future<void> regenerateAiThumbnail() async {
    state = state.copyWith(isUploading: true, error: null);
    try {
      final result = await _uploadService.fetchIntelligentThumbnail(
        unitName: state.material.unitName.isNotEmpty ? state.material.unitName : 'Academic Material',
        materialType: state.material.materialType,
        catType: state.material.catType,
        unitCode: state.material.unitCode,
      );
      if (result != null && result['thumbnailUrl'] != null && result['thumbnailUrl']!.isNotEmpty) {
        state = state.copyWith(
          isUploading: false,
          material: state.material.copyWith(
            thumbnail: null,
            existingThumbnailUrl: result['thumbnailUrl'],
            existingThumbnailId: result['thumbnailId'],
            existingThumbnailStatus: 'completed',
          ),
        );
      } else {
        state = state.copyWith(
          isUploading: false,
          error: 'AI thumbnail generation did not return an image. You can select an image manually.',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isUploading: false,
        error: 'Failed to generate thumbnail: $e',
      );
    }
  }

  bool _isNetworkError(dynamic error) {
    if (ConnectivityService().isOffline) return true;
    if (error == null) return false;

    final errStr = error.toString().toLowerCase();
    return errStr.contains('socketexception') ||
        errStr.contains('clientexception') ||
        errStr.contains('timeoutexception') ||
        errStr.contains('network') ||
        errStr.contains('unavailable') ||
        errStr.contains('deadline-exceeded') ||
        errStr.contains('connection') ||
        errStr.contains('failed host lookup') ||
        errStr.contains('no route to host') ||
        errStr.contains('network_error') ||
        errStr.contains('network request failed') ||
        errStr.contains('failed to connect') ||
        errStr.contains('hostapi.call');
  }

  Future<void> upload() async {
    if (!state.isValid) return;

    if (state.isModifyMode) {
      await _executeModify();
      return;
    }

    if (ConnectivityService().isOffline) {
      // Offline mode: Enqueue to persistent queue immediately
      await OfflineUploadQueueService().enqueue(
        material: state.material,
        uploadMode: state.uploadMode,
        file: state.material.file,
        files: state.material.files,
        thumbnail: state.material.thumbnail,
      );

      reset();
      state = state.copyWith(
        isUploading: false,
        isSuccess: false,
        isQueuedOffline: true,
        isConnectionLost: false,
        uploadProgress: 1.0,
        error: null,
      );
      return;
    }

    await _executeUpload();
  }

  Future<void> _executeModify() async {
    state = state.copyWith(
      isUploading: true,
      error: null,
      isSuccess: false,
      isQueuedOffline: false,
      isConnectionLost: false,
      uploadProgress: 0.1,
    );

    try {
      String finalFileUrl = state.material.existingFileUrl ?? '';
      String finalFileId = state.material.existingFileId ?? '';
      String finalFileName = state.material.existingFileName ?? '';
      String finalThumbUrl = state.material.existingThumbnailUrl ?? '';
      String finalThumbId = state.material.existingThumbnailId ?? '';
      String finalThumbStatus = state.material.existingThumbnailStatus ?? 'completed';

      bool fileReplaced = false;
      bool thumbReplaced = false;

      // 1. If a replacement file was picked, upload it first
      if (state.material.file != null || state.material.files.isNotEmpty) {
        Map<String, dynamic> uploadResult;
        if (state.uploadMode == 'timetable') {
          uploadResult = await _timetableUploadService.uploadTimetable(
            state.material,
            (progress) => state = state.copyWith(uploadProgress: 0.1 + (progress * 0.4)),
          );
        } else {
          uploadResult = await _uploadService.uploadMaterial(
            state.material,
            (progress) => state = state.copyWith(uploadProgress: 0.1 + (progress * 0.4)),
          );
        }
        finalFileUrl = uploadResult['fileUrl'] ?? finalFileUrl;
        finalFileId = uploadResult['fileId'] ?? finalFileId;
        finalFileName = uploadResult['fileName'] ?? finalFileName;
        fileReplaced = true;
      }

      // 2. If a replacement thumbnail was picked manually, upload it
      if (state.material.thumbnail != null) {
        final thumbBytes = await state.material.thumbnail!.readAsBytes();
        final base64Thumb = base64Encode(thumbBytes);
        final thumbName = 'thumb_${state.material.thumbnail!.path.split(RegExp(r'[/\\]')).last}';

        final result = await FirebaseFunctions.instance.httpsCallable('uploadToImageKit').call({
          'file': base64Thumb,
          'fileName': thumbName,
          'folder': 'THUMBNAILS',
        });

        finalThumbUrl = result.data['url'] ?? finalThumbUrl;
        finalThumbId = result.data['fileId'] ?? finalThumbId;
        finalThumbStatus = 'completed';
        thumbReplaced = true;
      }

      state = state.copyWith(uploadProgress: 0.8);

      // 3. Title calculation
      String resourceTitle;
      if (state.uploadMode == 'timetable') {
        resourceTitle = '${state.material.programs.join(", ")} Timetable';
      } else if (state.material.materialType == 'CATs' && state.material.catType != null) {
        resourceTitle = '${state.material.unitName} ${state.material.catType}';
      } else {
        resourceTitle = state.material.unitName;
      }

      // 4. Construct updated Resource with the exact same ID
      final updatedResource = Resource(
        id: state.material.existingMaterialId!,
        title: resourceTitle,
        fileName: finalFileName,
        type: state.material.materialType,
        thumbnailUrl: finalThumbUrl,
        thumbnailId: finalThumbId.isNotEmpty ? finalThumbId : null,
        thumbnailStatus: finalThumbStatus,
        fileUrl: finalFileUrl,
        fileId: finalFileId,
        unitName: state.material.unitName,
        unitCode: state.material.unitCode,
        year: state.material.yearOfUpload.toString(),
        uploadYear: state.material.yearOfUpload.toString(),
        publicationYear: state.material.yearOfPublication.toString(),
        yearOfStudy: state.material.yearOfStudy,
        semester: state.material.semester,
        lecturers: state.material.lecturers.isNotEmpty ? state.material.lecturers : ['TBD'],
        uploadedBy: state.material.uploadedBy,
        uploaderRole: state.material.existingUploaderRole ?? 'Student',
        uploaderId: state.material.uploaderId,
        uploaderProfilePic: state.material.existingUploaderProfilePic,
        uploadDate: state.material.existingUploadDate ?? DateTime.now(),
        status: state.material.isModerationModify ? 'modified' : (state.material.existingStatus ?? 'approved'),
        approvedAt: state.material.isModerationModify ? DateTime.now() : state.material.existingApprovedAt,
        adminRemark: state.material.adminRemark,
        rejectionReasons: state.material.existingRejectionReasons,
        visibility: 'public',
        targetPrograms: state.material.programs,
        programCodes: state.material.programCodes,
        materialFormat: state.uploadMode == 'timetable' ? 'Image' : (state.material.fileFormat ?? 'PDF'),
        isAnonymous: state.uploadMode == 'timetable' ? false : state.material.isAnonymous,
        isPinned: state.material.existingIsPinned,
        pinnedAt: state.material.existingPinnedAt,
        updatedByAdmin: true,
        updatedAt: DateTime.now(),
        views: state.material.existingViews,
        likes: state.material.existingLikes,
        comments: state.material.existingComments,
        likedBy: state.material.existingLikedBy,
      );

      // 5. Commit modification to ResourceService & Backend
      await ResourceService().modifyMaterial(
        updatedResource,
        oldFileId: fileReplaced ? state.material.existingFileId : null,
        oldThumbnailId: thumbReplaced ? state.material.existingThumbnailId : null,
        isModerationModify: state.material.isModerationModify,
      );

      reset();

      state = state.copyWith(
        isUploading: false,
        isSuccess: true,
        isQueuedOffline: false,
        isConnectionLost: false,
        uploadProgress: 1.0,
      );
    } catch (e) {
      state = state.copyWith(
        isUploading: false,
        isSuccess: false,
        error: 'Failed to update material: $e',
      );
    }
  }

  Future<void> _executeUpload() async {
    state = state.copyWith(
      isUploading: true,
      error: null,
      isSuccess: false,
      isQueuedOffline: false,
      isConnectionLost: false,
    );

    try {
      Map<String, dynamic> uploadResult;

      if (state.uploadMode == 'timetable') {
        // Timetables Tab: Use dedicated TimetableUploadService ONLY
        uploadResult = await _timetableUploadService.uploadTimetable(
          state.material,
          (progress) {
            state = state.copyWith(uploadProgress: progress);
          },
        );
      } else {
        // Materials Tab: Use original UploadService.uploadMaterial ONLY
        uploadResult = await _uploadService.uploadMaterial(
          state.material,
          (progress) {
            state = state.copyWith(uploadProgress: progress);
          },
        );
      }

      String resourceTitle;
      if (state.uploadMode == 'timetable') {
        resourceTitle = '${state.material.programs.join(", ")} Timetable';
      } else if (state.material.materialType == 'CATs' && state.material.catType != null) {
        resourceTitle = '${state.material.unitName} ${state.material.catType}';
      } else {
        resourceTitle = state.material.unitName;
      }

      final String finalFileUrl = uploadResult['fileUrl'] ?? '';
      final String finalFileId = uploadResult['fileId'] ?? '';
      final String finalFileName = uploadResult['fileName'] ?? '';
      final String finalThumbUrl = uploadResult['thumbnailUrl'] ?? '';
      final String finalThumbId = uploadResult['thumbnailId'] ?? '';
      final String finalThumbStatus = uploadResult['thumbnailStatus'] ?? (state.uploadMode == 'timetable' ? 'completed' : 'pending');

      final resource = Resource(
        title: resourceTitle,
        fileName: finalFileName,
        type: state.material.materialType,
        thumbnailUrl: finalThumbUrl,
        fileUrl: finalFileUrl,
        fileId: finalFileId,
        thumbnailId: finalThumbId,
        thumbnailStatus: finalThumbStatus,
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
        status: 'approved',
        visibility: 'public',
        targetPrograms: state.material.programs,
        programCodes: state.material.programCodes,
        materialFormat: state.uploadMode == 'timetable' ? 'Image' : (state.material.fileFormat ?? 'PDF'),
        isAnonymous: state.uploadMode == 'timetable' ? false : state.material.isAnonymous,
      );

      await ResourceService().addUpload(resource, _courseService);
      await ResourceService().fetchUserUploadsOnce(state.material.uploaderId);

      reset();
      
      state = state.copyWith(
        isUploading: false, 
        isSuccess: true, 
        isQueuedOffline: false,
        isConnectionLost: false,
        uploadProgress: 1.0,
      );
    } catch (e) {
      if (_isNetworkError(e)) {
        await OfflineUploadQueueService().enqueue(
          material: state.material,
          uploadMode: state.uploadMode,
          file: state.material.file,
          files: state.material.files,
          thumbnail: state.material.thumbnail,
        );
        reset();
        state = state.copyWith(
          isUploading: false,
          isSuccess: false,
          isQueuedOffline: false,
          isConnectionLost: true,
          uploadProgress: 1.0,
          error: null,
        );
      } else {
        state = state.copyWith(
          isUploading: false,
          isSuccess: false,
          isQueuedOffline: false,
          isConnectionLost: false,
          error: e.toString(),
        );
      }
    }
  }

  void reset() {
    state = UploadState(
      uploadMode: state.uploadMode,
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
    );
  }
}

// Separate Isolated Providers for Materials and Timetables
final materialUploadProvider = StateNotifierProvider.autoDispose<UploadNotifier, UploadState>((ref) {
  final userProfile = ref.watch(userProfileProvider);
  return UploadNotifier(
    ref.watch(courseServiceProvider),
    ref.watch(fileServiceProvider),
    ref.watch(uploadServiceProvider),
    ref.watch(timetableUploadServiceProvider),
    userProfile,
    initialMode: 'material',
  );
});

final timetableUploadProvider = StateNotifierProvider.autoDispose<UploadNotifier, UploadState>((ref) {
  final userProfile = ref.watch(userProfileProvider);
  return UploadNotifier(
    ref.watch(courseServiceProvider),
    ref.watch(fileServiceProvider),
    ref.watch(uploadServiceProvider),
    ref.watch(timetableUploadServiceProvider),
    userProfile,
    initialMode: 'timetable',
  );
});

// Alias for backwards compatibility
final uploadProvider = materialUploadProvider;

// Suggestions providers
final programSuggestionsProvider = Provider.autoDispose.family<List<String>, String>((ref, query) {
  final uploadState = ref.watch(materialUploadProvider);
  final unitCode = uploadState.material.unitCode;
  
  if (unitCode.isNotEmpty) {
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
  final uploadState = ref.watch(materialUploadProvider);
  final unitCode = uploadState.material.unitCode;

  if (unitCode.isNotEmpty) {
    final units = ref.watch(courseServiceProvider).getUnitsByCode(unitCode);
    final unitLecturers = units.map((l) => l.lecturerName).where((l) => l.isNotEmpty).toSet().toList();
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
