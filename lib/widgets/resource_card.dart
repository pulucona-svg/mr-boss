import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'comment_modal.dart';
import 'resource_details_modal.dart';
import '../services/view_service.dart';
import '../services/download_service.dart';
import '../services/comment_service.dart';
import '../services/resource_service.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/user_provider.dart';

class ResourceCard extends ConsumerStatefulWidget {
  const ResourceCard({
    super.key,
    required this.title,
    required this.type,
    required this.thumbnailUrl,
    required this.onTap,
    this.unitName = 'Data Structures & Algorithms',
    this.unitCode = 'COMP 222',
    this.year = '2024',
    this.uploadYear = '2024',
    this.publicationYear = '2023',
    this.yearOfStudy = '2nd Year',
    this.semester = 'Semester 1',
    this.lecturers = const ['Dr. James Kamau'],
    this.uploadedBy = 'Admin',
    this.uploaderRole = 'Administrator',
    this.uploaderId = 'admin',
    this.views = '189',
    this.likes = '27',
    this.comments = '5',
    this.isLiked = false,
    this.showDownload = true,
    this.materialFormat = 'PDF',
    this.targetPrograms = const ['Bachelor of Science Computer Science'],
    this.programCodes = const [],
    this.status,
    this.declineReason,
    this.onLikeToggle,
    this.onViewIncrement,
  });

  final String title;
  final String type;
  final String materialFormat;
  final String thumbnailUrl;
  final VoidCallback onTap;
  final String unitName;
  final String unitCode;
  final List<String> targetPrograms;
  final List<String> programCodes;
  final String year;
  final String uploadYear;
  final String publicationYear;
  final String yearOfStudy;
  final String semester;
  final List<String> lecturers;
  final String uploadedBy;
  final String uploaderRole;
  final String uploaderId;
  final String views;
  final String likes;
  final String comments;
  final bool isLiked;
  final bool showDownload;
  final String? status;
  final String? declineReason;
  final VoidCallback? onLikeToggle;
  final VoidCallback? onViewIncrement;

  @override
  ConsumerState<ResourceCard> createState() => _ResourceCardState();
}

class _ResourceCardState extends ConsumerState<ResourceCard> {
  Timer? _viewTimer;

  @override
  void dispose() {
    _viewTimer?.cancel();
    super.dispose();
  }

  Map<String, String> _getResourceData() {
    final userProfile = ref.read(userProfileProvider);
    final bool isMe = widget.uploaderId == userProfile.uid || widget.uploadedBy == 'Me';
    final String displayUploadedBy = isMe ? userProfile.username : widget.uploadedBy;

    return {
      'title': widget.title,
      'type': widget.type,
      'thumbnail': widget.thumbnailUrl,
      'unitName': widget.unitName,
      'unitCode': widget.unitCode,
      'year': widget.year,
      'uploadYear': widget.uploadYear,
      'publicationYear': widget.publicationYear,
      'yearOfStudy': widget.yearOfStudy,
      'semester': widget.semester,
      'lecturer': widget.lecturers.join(', '),
      'uploadedBy': displayUploadedBy,
      'uploaderRole': widget.uploaderRole,
      'views': widget.views,
      'likes': widget.likes,
      'comments': widget.comments,
      'format': widget.materialFormat,
      'programs': widget.targetPrograms.join(', '),
      'isLiked': widget.isLiked.toString(),
    };
  }

  void _incrementView() {
    _viewTimer?.cancel();
    _viewTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        if (ViewService().canIncrementView(widget.title)) {
          ViewService().recordView(widget.title);
          widget.onViewIncrement?.call();
        }
      }
    });
  }

  void _handleTap() {
    ResourceService().setActiveResource(widget.title);
    widget.onTap();
    _incrementView();
  }

  void _toggleLike() {
    _handleTap();
    widget.onLikeToggle?.call();
  }

  void _showComments() {
    _handleTap();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CommentModal(resourceTitle: widget.title),
    );
  }

  void _showDetails() {
    _handleTap();
    final resource = ResourceService().findResourceByTitle(widget.title);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ResourceDetailsModal(
        title: widget.title,
        type: widget.type,
        thumbnailUrl: widget.thumbnailUrl,
        unitName: widget.unitName,
        unitCode: widget.unitCode,
        targetPrograms: resource?.targetPrograms ?? widget.targetPrograms,
        programCodes: resource?.programCodes ?? widget.programCodes,
        materialFormat: widget.materialFormat,
        uploadYear: widget.uploadYear,
        publicationYear: widget.publicationYear,
        yearOfStudy: widget.yearOfStudy,
        semester: widget.semester,
        lecturers: resource?.lecturers ?? widget.lecturers,
        uploadedBy: widget.uploadedBy,
        uploaderRole: widget.uploaderRole,
        uploaderId: resource?.uploaderId ?? widget.uploaderId,
        showDownload: widget.showDownload,
      ),
    );
  }

  String _getTypeLabel(String type) {
    if (type.contains('Timetable')) return 'TABLE';
    switch (type) {
      case 'Notes':
        return 'NOTES';
      case 'CATs':
        return 'CAT';
      case 'Exams':
        return 'EXAM';
      case 'Prac Manual':
        return 'PRAC';
      case 'Supplementary Exams':
        return 'SUPP';
      case 'Time tables':
        return 'TABLE';
      default:
        return 'DOC';
    }
  }

  Widget _statItem(IconData icon, String value, {Color iconColor = Colors.white54}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _statusTag() {
    if (widget.status == null) return const SizedBox.shrink();

    String text = '';
    Color color = Colors.grey;
    IconData icon = Icons.info_outline;

    switch (widget.status) {
      case 'approved':
        text = 'Approved by Admin';
        color = const Color(0xFF00A85A);
        icon = Icons.check_circle_outline;
        break;
      case 'waiting':
        text = 'Waiting Admin Approval';
        color = const Color(0xFFFF8A00);
        icon = Icons.hourglass_empty_rounded;
        break;
      case 'declined':
        text = 'Declined by Admin';
        color = const Color(0xFFFF4667);
        icon = Icons.cancel_outlined;
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        if (widget.status == 'declined' && widget.declineReason != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              'Reason: ${widget.declineReason}',
              style: const TextStyle(color: Colors.white54, fontSize: 9, fontStyle: FontStyle.italic),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ResourceService(),
      builder: (context, child) {
        final resource = ResourceService().findResourceByTitle(widget.title);
        final isActive = ResourceService().activeResourceId == widget.title;
        
        // Use live data from service if available, otherwise fallback to widget properties
        final viewsCount = resource?.views.toString() ?? widget.views;
        final likesCount = resource?.likes.toString() ?? widget.likes;
        final isLiked = resource?.isLiked ?? widget.isLiked;
        
        return AnimatedScale(
          scale: isActive ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          child: GestureDetector(
            onTap: _handleTap,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF181739).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive ? const Color(0xFF20C8FF) : Colors.white10,
                  width: isActive ? 2 : 1,
                ),
                boxShadow: isActive ? [
                  BoxShadow(
                    color: const Color(0xFF20C8FF).withValues(alpha: 0.3),
                    blurRadius: 15,
                    spreadRadius: 2,
                  )
                ] : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: widget.status != null ? 2 : 3,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        widget.thumbnailUrl.startsWith('http')
                          ? CachedNetworkImage(
                              imageUrl: widget.thumbnailUrl,
                              fit: BoxFit.cover,
                              // Ensure images are cached for long-term offline access
                              cacheKey: widget.thumbnailUrl,
                              placeholder: (context, url) => Container(
                                color: Colors.white10,
                                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.white10,
                                child: const Icon(Icons.broken_image, color: Colors.white24),
                              ),
                            )
                          : Image.file(
                              File(widget.thumbnailUrl),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: Colors.white10,
                                child: const Icon(Icons.broken_image, color: Colors.white24),
                              ),
                            ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                            ),
                          ),
                        ),

                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white24, width: 0.5),
                            ),
                            child: Text(
                              _getTypeLabel(widget.type),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        ),

                        if (widget.type == 'Time tables' || widget.type.contains('Timetable'))
                          Positioned(
                            top: 10,
                            right: widget.showDownload ? 50 : 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: widget.type.contains('EXAM') 
                                    ? const Color(0xFFFF4667).withValues(alpha: 0.8) 
                                    : const Color(0xFF00A85A).withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white24, width: 0.5),
                              ),
                              child: Text(
                                widget.type.contains('EXAM') ? 'EXAM' : 'CLASS',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                          ),
                        
                        if (widget.showDownload)
                          Positioned(
                            top: 10,
                            right: 10,
                            child: ListenableBuilder(
                              listenable: DownloadService(),
                              builder: (context, child) {
                                final isDownloading = DownloadService().isDownloading(widget.title);
                                final progress = DownloadService().getProgress(widget.title);
                                
                                return GestureDetector(
                                  onTap: () {
                                    _handleTap();
                                    DownloadService().startDownload(_getResourceData());
                                  },
                                  behavior: HitTestBehavior.translucent,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      if (isDownloading)
                                        SizedBox(
                                          width: 32,
                                          height: 32,
                                          child: CircularProgressIndicator(
                                            value: progress,
                                            strokeWidth: 3,
                                            color: const Color(0xFF00A85A),
                                            backgroundColor: Colors.white10,
                                          ),
                                        ),
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.black38,
                                          shape: BoxShape.circle,
                                          border: isDownloading ? null : Border.all(color: Colors.white24, width: 0.5),
                                        ),
                                        child: Icon(
                                          isDownloading ? Icons.download_for_offline : Icons.download_rounded,
                                          color: isDownloading ? const Color(0xFF00A85A) : Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                      if (isDownloading)
                                        Positioned(
                                          bottom: -15,
                                          child: Text(
                                            '${(progress * 100).toInt()}%',
                                            style: const TextStyle(color: Color(0xFF00A85A), fontSize: 8, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),

                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Text(
                              widget.title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _pill(
                              (widget.type == 'Time tables' || widget.type.contains('Timetable')) && widget.programCodes.isNotEmpty
                                  ? widget.programCodes.join(', ')
                                  : widget.unitCode,
                              const Color(0xFFD92680),
                            ),
                            const SizedBox(width: 4),
                            _pill(widget.publicationYear, const Color(0xFFD9BD26)),
                            const Spacer(),
                            GestureDetector(
                              onTap: _showDetails,
                              behavior: HitTestBehavior.translucent,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7474E6),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.more_vert, color: Colors.white, size: 14),
                              ),
                            ),
                          ],
                        ),
                        _statusTag(),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ListenableBuilder(
                          listenable: ViewService(),
                          builder: (context, child) {
                            final hasViewed = ViewService().hasViewed(widget.title);
                            return _statItem(
                              Icons.visibility_outlined, 
                              viewsCount,
                              iconColor: hasViewed ? const Color(0xFF00A85A) : Colors.white54,
                            );
                          },
                        ),
                        GestureDetector(
                          onTap: _toggleLike,
                          behavior: HitTestBehavior.translucent,
                          child: _statItem(
                            isLiked ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined, 
                            likesCount, 
                            iconColor: isLiked ? const Color(0xFF20C8FF) : Colors.white54,
                          ),
                        ),
                        GestureDetector(
                          onTap: _showComments,
                          behavior: HitTestBehavior.translucent,
                          child: ListenableBuilder(
                            listenable: CommentService(),
                            builder: (context, child) {
                              final count = CommentService().getCommentCount(widget.title);
                              final displayCount = (resource?.status == 'approved') ? count.toString() : '0';
                              return _statItem(Icons.mode_comment_outlined, displayCount);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
