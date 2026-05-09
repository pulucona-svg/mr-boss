import 'package:flutter/material.dart';
import 'dart:io';
import '../services/download_service.dart';

class ResourceDetailsModal extends StatelessWidget {
  final String title;
  final String type;
  final String thumbnailUrl;
  final String unitName;
  final String unitCode;
  final String courseProgram;
  final List<String> programCodes;
  final String materialFormat;
  final String uploadYear;
  final String publicationYear;
  final String yearOfStudy;
  final String semester;
  final String lecturer;
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
    this.courseProgram = '',
    this.programCodes = const [],
    required this.materialFormat,
    required this.uploadYear,
    required this.publicationYear,
    required this.yearOfStudy,
    required this.semester,
    required this.lecturer,
    required this.uploadedBy,
    required this.uploaderRole,
    this.showDownload = true,
  });

  Map<String, String> _getResourceData() {
    return {
      'title': title,
      'type': type,
      'thumbnail': thumbnailUrl,
      'unitName': unitName,
      'unitCode': unitCode,
      'courseProgram': courseProgram,
      'programCodes': programCodes.join(','),
      'materialFormat': materialFormat,
      'uploadYear': uploadYear,
      'publicationYear': publicationYear,
      'yearOfStudy': yearOfStudy,
      'semester': semester,
      'lecturer': lecturer,
      'uploadedBy': uploadedBy,
      'uploaderRole': uploaderRole,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isTimetable = type == 'Time tables' || type.contains('Timetable');

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
      decoration: const BoxDecoration(
        color: Color(0xFF141232),
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          
          // Header
          Row(
            children: [
              // Thumbnail Preview in Details
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
                  : Image.file(File(thumbnailUrl), fit: BoxFit.cover),
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
          
          // Details List
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: isTimetable ? [
                  _buildDetailRow(Icons.school_outlined, 'Program Name', courseProgram),
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
                  _buildDetailRow(Icons.person_outline, 'Lecturer', lecturer),
                  _buildDetailRow(
                    Icons.cloud_upload_outlined, 
                    'Uploaded By', 
                    '$uploadedBy ($uploaderRole)',
                    isLast: true,
                  ),
                ],
              ),
            ),
          ),
          
          if (showDownload) ...[
            const SizedBox(height: 24),
            // Download Button
            ListenableBuilder(
              listenable: DownloadService(),
              builder: (context, child) {
                final isDownloading = DownloadService().isDownloading(title);
                final progress = DownloadService().getProgress(title);
                
                return GestureDetector(
                  onTap: () => DownloadService().startDownload(_getResourceData()),
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

  Widget _buildDetailRow(IconData icon, String label, String value, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF7B5CFF), size: 20),
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
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
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
