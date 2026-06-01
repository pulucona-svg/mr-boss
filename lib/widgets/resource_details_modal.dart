import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/progress_service.dart';
import '../providers/upload_provider.dart';
import '../screens/material_viewer_screen.dart';
import '../providers/theme_provider.dart';
import '../providers/user_provider.dart';
import '../services/course_service.dart';

import 'download_modal.dart';

class ResourceDetailsModal extends ConsumerWidget {
  final String title;
  final String type;
  final String thumbnailUrl;
  final String unitName;
  final String unitCode;
  final List<String> targetPrograms;
  final List<String> programCodes;
  final String materialFormat;
  final String uploadYear;
  final String publicationYear;
  final String yearOfStudy;
  final String semester;
  final List<String> lecturers;
  final String uploadedBy;
  final String uploaderRole;
  final String uploaderId;
  final String? uploaderProfilePic;
  final bool showDownload;

  const ResourceDetailsModal({
    super.key,
    required this.title,
    required this.type,
    required this.thumbnailUrl,
    required this.unitName,
    required this.unitCode,
    this.targetPrograms = const [],
    this.programCodes = const [],
    required this.materialFormat,
    required this.uploadYear,
    required this.publicationYear,
    required this.yearOfStudy,
    required this.semester,
    required this.lecturers,
    required this.uploadedBy,
    required this.uploaderRole,
    this.uploaderId = 'admin',
    this.uploaderProfilePic,
    this.showDownload = true,
  });

  Map<String, String> _getResourceData(List<String> displayPrograms, List<String> displayLecturers, WidgetRef ref) {
    final userProfile = ref.read(userProfileProvider);
    final bool isMe = uploaderId == userProfile.uid || uploadedBy == 'Me';
    final String displayUploadedBy = isMe ? userProfile.username : uploadedBy;

    return {
      'title': title,
      'type': type,
      'thumbnail': thumbnailUrl,
      'unitName': unitName,
      'unitCode': unitCode,
      'targetPrograms': displayPrograms.join(', '),
      'programCodes': programCodes.join(','),
      'materialFormat': materialFormat,
      'uploadYear': uploadYear,
      'publicationYear': publicationYear,
      'yearOfStudy': yearOfStudy,
      'semester': semester,
      'lecturer': displayLecturers.join(', '),
      'uploadedBy': displayUploadedBy,
      'uploaderRole': uploaderRole,
      'uploaderId': uploaderId,
      'uploaderProfilePic': uploaderProfilePic ?? '',
    };
  }

  bool _hasFullAccess(WidgetRef ref) {
    final subService = ref.read(subscriptionServiceProvider);
    final resourceService = ref.read(resourceServiceProvider);

    final bool isSubscribed = subService.isSubscribed;
    final bool isMyUpload = resourceService.userUploads.any((r) => r.title == title);
    final bool isPermanentlyUnlocked = subService.isResourceUnlocked(title);

    // After plan expiry, downloaded materials require ad-unlock or new subscription
    return isSubscribed || isMyUpload || isPermanentlyUnlocked;
  }

  void _handleMaterialAction(BuildContext context, WidgetRef ref, List<String> displayPrograms, List<String> displayLecturers, bool isDownload) async {
    final resourceData = _getResourceData(displayPrograms, displayLecturers, ref);
    
    if (_hasFullAccess(ref)) {
      if (isDownload) {
        ref.read(downloadServiceProvider).startDownload(resourceData);
      } else {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MaterialViewerScreen(title: title),
          ),
        );
      }
    } else {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => DownloadModal(
          resourceTitle: title,
          actionType: isDownload ? AccessActionType.download : AccessActionType.read,
        ),
      );

      if (result == true) {
        // Auto-resume action after unlock
        _handleMaterialAction(context, ref, displayPrograms, displayLecturers, isDownload);
      }
    }
  }

  Widget _buildProgressBar(bool isDark, double progress) {
    final subTextColor = isDark ? Colors.white38 : Colors.black38;
    final dividerColor = isDark ? Colors.white10 : Colors.black12;
    final borderColor = isDark ? Colors.white24 : Colors.black26;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reading Progress',
          style: TextStyle(
            color: subTextColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              children: [
                Expanded(
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: borderColor, width: 2),
                    ),
                    child: Stack(
                      children: [
                        LayoutBuilder(
                          builder: (context, innerConstraints) {
                            return Container(
                              width: innerConstraints.maxWidth * progress,
                              decoration: BoxDecoration(
                                color: const Color(0xFF00A85A),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            );
                          }
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 5,
                  height: 15,
                  decoration: BoxDecoration(
                    color: borderColor,
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 45, 
                  child: Text(
                    '${(progress * 100).toInt()}%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Color(0xFF00A85A),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          }
        ),
        const SizedBox(height: 16),
        Divider(color: dividerColor, height: 1),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;

    final isTimetable = type == 'Time tables' || type.contains('Timetable');

    final courseService = ref.watch(courseServiceProvider);
    final relatedUnits = courseService.getUnitsByCode(unitCode);
    
    final poolPrograms = relatedUnits
        .map((u) => u.programName)
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList();
        
    final poolLecturers = relatedUnits
        .map((u) => u.lecturerName)
        .where((l) => l.isNotEmpty)
        .toSet()
        .toList();

    final displayPrograms = poolPrograms.isNotEmpty ? poolPrograms : targetPrograms;
    final displayLecturers = poolLecturers.isNotEmpty ? poolLecturers : lecturers;

    final userProfile = ref.watch(userProfileProvider);
    final bool isMe = uploaderId == userProfile.uid || uploadedBy == 'Me';
    final String displayUploadedBy = isMe ? userProfile.username : uploadedBy;

    final bgColor = isDark ? const Color(0xFF141232) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white38 : Colors.black38;
    final dividerColor = isDark ? Colors.white10 : Colors.black12;

    final subService = ref.watch(subscriptionServiceProvider);
    final downloadService = ref.watch(downloadServiceProvider);
    final resourceService = ref.watch(resourceServiceProvider);

    return ListenableBuilder(
      listenable: Listenable.merge([subService, downloadService, resourceService]),
      builder: (context, child) {
        return Container(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: subTextColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: dividerColor),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: thumbnailUrl.startsWith('http')
                      ? CachedNetworkImage(
                          imageUrl: thumbnailUrl,
                          fit: BoxFit.cover,
                          cacheKey: thumbnailUrl,
                          placeholder: (context, url) => Container(
                            color: dividerColor,
                            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: dividerColor,
                            child: Icon(Icons.broken_image, color: subTextColor),
                          ),
                        )
                      : thumbnailUrl.isNotEmpty 
                          ? Image.file(
                              File(thumbnailUrl), 
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: dividerColor,
                                child: Icon(Icons.broken_image, color: subTextColor),
                              ),
                            )
                          : Icon(Icons.description, color: subTextColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isTimetable ? 'Timetable Details' : 'Material Details',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          title,
                          style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: subTextColor),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: isTimetable ? [
                      _buildDetailRow(
                        isDark,
                        Icons.school_outlined, 
                        'Program Name', 
                        '', 
                        customValueWidget: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: displayPrograms.map((program) => Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF20C8FF).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: const Color(0xFF20C8FF).withOpacity(0.3),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        program,
                                        style: const TextStyle(
                                          color: Color(0xFF20C8FF),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )).toList(),
                          ),
                        ),
                      ),
                      _buildDetailRow(isDark, Icons.code_rounded, 'Program Code', programCodes.join(', ')),
                      _buildDetailRow(isDark, Icons.info_outline, 'Type of Timetable', type.contains('EXAM') ? 'Exam Timetable' : 'Class Timetable'),
                      _buildDetailRow(isDark, Icons.history_edu_outlined, 'Year of Publication', publicationYear),
                      _buildDetailRow(isDark, Icons.school_outlined, 'Year of Study', yearOfStudy),
                      _buildDetailRow(isDark, Icons.layers_outlined, 'Semester', semester),
                      _buildDetailRow(
                        isDark,
                        Icons.cloud_upload_outlined, 
                        'Uploaded By', 
                        '$displayUploadedBy ($uploaderRole)',
                        isLast: true,
                        customValueWidget: _buildUploaderProfilePic(ref, isMe, userProfile.profileImagePath, userProfile.photoURL),                  ),
                    ] : [
                      _buildDetailRow(isDark, Icons.book_outlined, 'Unit Name', unitName),
                      _buildDetailRow(isDark, Icons.code_rounded, 'Unit Code', unitCode),
                      _buildDetailRow(isDark, Icons.file_present_outlined, 'Material Format', materialFormat),
                      _buildDetailRow(isDark, Icons.calendar_month_outlined, 'Year of Upload', uploadYear),
                      _buildDetailRow(isDark, Icons.history_edu_outlined, 'Year of Publication', publicationYear),
                      _buildDetailRow(isDark, Icons.school_outlined, 'Year of Study', yearOfStudy),
                      _buildDetailRow(isDark, Icons.layers_outlined, 'Semester', semester),
                      _buildDetailRow(
                        isDark,
                        Icons.person_outline, 
                        'Lecturer', 
                        '', 
                        customValueWidget: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: displayLecturers.map((lecturer) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00A85A).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFF00A85A).withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                lecturer,
                                style: const TextStyle(
                                  color: Color(0xFF00A85A),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )).toList(),
                          ),
                        ),
                      ),
                      _buildDetailRow(
                        isDark,
                        Icons.cloud_upload_outlined, 
                        'Uploaded By', 
                        '$displayUploadedBy ($uploaderRole)',
                        customValueWidget: _buildUploaderProfilePic(ref, isMe, userProfile.profileImagePath, userProfile.photoURL),                  ),
                      
                      Builder(
                        builder: (context) {
                          final isDownloaded = downloadService.downloadedResources.any((r) => r['title'] == title);
                          if (isDownloaded) {
                            final progress = ProgressService().getProgress(title);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.auto_graph_rounded, color: Color(0xFF20C8FF), size: 20),
                                  const SizedBox(width: 16),
                                  Expanded(child: _buildProgressBar(isDark, progress)),
                                ],
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),

                      _buildDetailRow(
                        isDark,
                        Icons.school_outlined, 
                        'Target Programs', 
                        '', 
                        isLast: true,
                        customValueWidget: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: displayPrograms.map((program) => Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF20C8FF).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: const Color(0xFF20C8FF).withOpacity(0.3),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        program,
                                        style: const TextStyle(
                                          color: Color(0xFF20C8FF),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              GestureDetector(
                onTap: () => _handleMaterialAction(context, ref, displayPrograms, displayLecturers, false),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF20C8FF),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.menu_book_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          _hasFullAccess(ref) ? 'Read Material' : 'Unlock to Read',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              if (showDownload) ...[
                const SizedBox(height: 12),
                Builder(
                  builder: (context) {
                    final isDownloading = downloadService.isDownloading(title);
                    final isDownloaded = downloadService.downloadedResources.any((r) => r['title'] == title);
                    final progress = downloadService.getProgress(title);
                    
                    if (isDownloaded) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00A85A).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: const Color(0xFF00A85A).withValues(alpha: 0.3)),
                        ),
                        child: const Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_rounded, color: Color(0xFF00A85A), size: 20),
                              SizedBox(width: 10),
                              Text(
                                'Downloaded',
                                style: TextStyle(
                                  color: Color(0xFF00A85A),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return GestureDetector(
                      onTap: () => _handleMaterialAction(context, ref, displayPrograms, displayLecturers, true),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: isDownloading 
                              ? dividerColor 
                              : const Color(0xFF00A85A),
                          borderRadius: BorderRadius.circular(15),
                          border: isDownloading 
                              ? Border.all(color: dividerColor) 
                              : null,
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (isDownloading)
                                Padding(
                                  padding: const EdgeInsets.only(right: 12.0),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      value: progress,
                                      strokeWidth: 2,
                                      color: const Color(0xFF00A85A),
                                      backgroundColor: dividerColor,
                                    ),
                                  ),
                                ),
                              Text(
                                isDownloading 
                                    ? 'Downloading ${ (progress * 100).toInt()}%' 
                                    : (_hasFullAccess(ref) ? 'Download for Offline View' : 'Unlock to Download'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        );
      }
    );
  }

  Widget _buildUploaderProfilePic(WidgetRef ref, bool isMe, String? myProfilePic, String? myPhotoUrl) {
    final String? profilePic = isMe ? (myProfilePic ?? myPhotoUrl) : uploaderProfilePic;
    
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF20C8FF), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF20C8FF).withValues(alpha: 0.2),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipOval(
        child: _buildProfileImage(profilePic),
      ),
    );
  }

  Widget _buildProfileImage(String? path) {
    if (path == null || path.isEmpty) {
      return Container(
        color: const Color(0xFF20C8FF).withValues(alpha: 0.1),
        child: const Icon(Icons.person, color: Color(0xFF20C8FF), size: 20),
      );
    }

    if (path.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: path,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.white10),
        errorWidget: (context, url, error) => const Icon(Icons.person, color: Colors.white24),
      );
    } else if (path.startsWith('assets/')) {
      return Image.asset(path, fit: BoxFit.cover);
    } else {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, color: Colors.white24),
      );
    }
  }

  Widget _buildDetailRow(bool isDark, IconData icon, String label, String value, {bool isLast = false, Widget? customValueWidget}) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white38 : Colors.black38;
    final dividerColor = isDark ? Colors.white10 : Colors.black12;

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF20C8FF), size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: subTextColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                if (value.isNotEmpty && customValueWidget != null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          value,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      customValueWidget,
                    ],
                  )
                else if (value.isNotEmpty)
                  Text(
                    value,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  )
                else if (customValueWidget != null)
                  customValueWidget,
                
                if (!isLast) ...[
                  const SizedBox(height: 12),
                  Divider(color: dividerColor, height: 1),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
