import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import '../services/download_service.dart';
import '../services/progress_service.dart';
import '../providers/upload_provider.dart';
import '../screens/material_viewer_screen.dart';

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
    this.showDownload = true,
  });

  Map<String, String> _getResourceData(List<String> displayPrograms, List<String> displayLecturers) {
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
      'uploadedBy': uploadedBy,
      'uploaderRole': uploaderRole,
    };
  }

  Widget _buildProgressBar(double progress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reading Progress',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final barWidth = availableWidth - 60; // Leave room for percentage text
            
            return Row(
              children: [
                // Battery-style bar (Dynamically sized to fill space)
                Container(
                  width: barWidth,
                  height: 30,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white24, width: 2),
                  ),
                  child: Stack(
                    children: [
                      Container(
                        width: (barWidth - 8) * progress,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00A85A),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ),
                ),
                // Battery tip
                Container(
                  width: 5,
                  height: 15,
                  decoration: const BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.horizontal(right: Radius.circular(3)),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: const TextStyle(
                    color: Color(0xFF00A85A),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            );
          }
        ),
        const SizedBox(height: 16),
        const Divider(color: Colors.white10, height: 1),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
      decoration: const BoxDecoration(
        color: Color(0xFF141232),
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
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
                  border: Border.all(color: Colors.white10),
                ),
                clipBehavior: Clip.antiAlias,
                child: thumbnailUrl.startsWith('http')
                  ? Image.network(thumbnailUrl, fit: BoxFit.cover)
                  : thumbnailUrl.isNotEmpty 
                      ? Image.file(File(thumbnailUrl), fit: BoxFit.cover)
                      : const Icon(Icons.description, color: Colors.white24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isTimetable ? 'Timetable Details' : 'Material Details',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      title,
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white38),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: isTimetable ? [
                  _buildDetailRow(
                    Icons.school_outlined, 
                    'Program Name', 
                    '', 
                    customValueWidget: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: displayPrograms.map((program) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF20C8FF).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFF20C8FF).withValues(alpha: 0.3),
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
                        )).toList(),
                      ),
                    ),
                  ),
                  _buildDetailRow(Icons.code_rounded, 'Program Code', programCodes.join(', ')),
                  _buildDetailRow(Icons.info_outline, 'Type of Timetable', type.contains('EXAM') ? 'Exam Timetable' : 'Class Timetable'),
                  _buildDetailRow(Icons.history_edu_outlined, 'Year of Publication', publicationYear),
                  _buildDetailRow(Icons.school_outlined, 'Year of Study', yearOfStudy),
                  _buildDetailRow(Icons.layers_outlined, 'Semester', semester),
                  _buildDetailRow(
                    Icons.cloud_upload_outlined, 
                    'Uploaded By', 
                    '$uploadedBy ($uploaderRole)',
                    isLast: true,
                  ),
                ] : [
                  _buildDetailRow(Icons.book_outlined, 'Unit Name', unitName),
                  _buildDetailRow(Icons.code_rounded, 'Unit Code', unitCode),
                  _buildDetailRow(Icons.file_present_outlined, 'Material Format', materialFormat),
                  _buildDetailRow(Icons.calendar_month_outlined, 'Year of Upload', uploadYear),
                  _buildDetailRow(Icons.history_edu_outlined, 'Year of Publication', publicationYear),
                  _buildDetailRow(Icons.school_outlined, 'Year of Study', yearOfStudy),
                  _buildDetailRow(Icons.layers_outlined, 'Semester', semester),
                  _buildDetailRow(
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
                            color: const Color(0xFF00A85A).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFF00A85A).withValues(alpha: 0.3),
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
                    Icons.cloud_upload_outlined, 
                    'Uploaded By', 
                    '$uploadedBy ($uploaderRole)',
                  ),
                  
                  ListenableBuilder(
                    listenable: Listenable.merge([DownloadService(), ProgressService()]),
                    builder: (context, child) {
                      final isDownloaded = DownloadService().downloadedResources.any((r) => r['title'] == title);
                      if (isDownloaded) {
                        final progress = ProgressService().getProgress(title);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.auto_graph_rounded, color: Color(0xFF20C8FF), size: 20),
                              const SizedBox(width: 16),
                              Expanded(child: _buildProgressBar(progress)),
                            ],
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),

                  _buildDetailRow(
                    Icons.school_outlined, 
                    'Target Programs', 
                    '', 
                    isLast: true,
                    customValueWidget: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: displayPrograms.map((program) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF20C8FF).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFF20C8FF).withValues(alpha: 0.3),
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
                        )).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          if (showDownload) ...[
            const SizedBox(height: 24),
            ListenableBuilder(
              listenable: DownloadService(),
              builder: (context, child) {
                final isDownloading = DownloadService().isDownloading(title);
                final isDownloaded = DownloadService().downloadedResources.any((r) => r['title'] == title);
                final progress = DownloadService().getProgress(title);
                
                if (isDownloaded) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MaterialViewerScreen(title: title),
                        ),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF20C8FF),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.menu_book_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 10),
                            Text(
                              'Read Material',
                              style: TextStyle(
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
                }

                return GestureDetector(
                  onTap: () => DownloadService().startDownload(_getResourceData(displayPrograms, displayLecturers)),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isDownloading 
                          ? Colors.white10 
                          : const Color(0xFF00A85A),
                      borderRadius: BorderRadius.circular(15),
                      border: isDownloading 
                          ? Border.all(color: Colors.white10) 
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
                                  backgroundColor: Colors.white12,
                                ),
                              ),
                            ),
                          Text(
                            isDownloading 
                                ? 'Downloading ${ (progress * 100).toInt()}%' 
                                : 'Download for Offline View',
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

  Widget _buildDetailRow(IconData icon, String label, String value, {bool isLast = false, Widget? customValueWidget}) {
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
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                if (value.isNotEmpty)
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                if (customValueWidget != null) customValueWidget,
                if (!isLast) ...[
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white10, height: 1),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
