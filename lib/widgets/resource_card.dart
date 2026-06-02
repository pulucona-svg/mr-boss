import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'comment_modal.dart';
import 'resource_details_modal.dart';
import '../utils/feedback_utils.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/material_model.dart'; // Import Resource type from models
import '../providers/providers.dart';
import '../services/usage_service.dart';

import '../screens/material_viewer_screen.dart';
import 'download_modal.dart';

class ResourceCard extends ConsumerStatefulWidget {
  const ResourceCard({
    super.key,
    required this.resource,
    required this.onTap,
    this.onLikeToggle,
    this.onViewIncrement,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.showPin = true,
    this.showDownload = true,
    this.onLongPress,
  });

  final Resource resource;
  final VoidCallback onTap;
  final VoidCallback? onLikeToggle;
  final VoidCallback? onViewIncrement;
  final bool isSelectionMode;
  final bool isSelected;
  final bool showPin;
  final bool showDownload;
  final VoidCallback? onLongPress;

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
    final bool isMe = widget.resource.uploaderId == userProfile.uid || widget.resource.uploadedBy == 'Me';
    final String displayUploadedBy = isMe ? userProfile.username : widget.resource.uploadedBy;

    return {
      'title': widget.resource.title,
      'type': widget.resource.type,
      'thumbnail': widget.resource.thumbnailUrl,
      'fileUrl': widget.resource.fileUrl,
      'unitName': widget.resource.unitName,
      'unitCode': widget.resource.unitCode,
      'year': widget.resource.year,
      'uploadYear': widget.resource.uploadYear,
      'publicationYear': widget.resource.publicationYear,
      'yearOfStudy': widget.resource.yearOfStudy,
      'semester': widget.resource.semester,
      'lecturer': widget.resource.lecturers.join(', '),
      'uploadedBy': displayUploadedBy,
      'uploaderRole': widget.resource.uploaderRole,
      'views': widget.resource.views.toString(),
      'likes': widget.resource.likes.toString(),
      'comments': widget.resource.comments.toString(),
      'format': widget.resource.materialFormat,
      'programs': widget.resource.targetPrograms.join(', '),
      'isLiked': widget.resource.isLiked.toString(),
    };
  }

  void _incrementView() {
    final viewService = ref.read(viewServiceProvider);
    _viewTimer?.cancel();
    _viewTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        if (viewService.canIncrementView(widget.resource.id)) {
          viewService.recordView(widget.resource.id);
          widget.onViewIncrement?.call();
        }
      }
    });
  }

  void _handleRead() async {
    if (widget.resource.fileUrl.isEmpty) {
      debugPrint('ResourceCard: [ERROR] Attempted to open material with empty fileUrl. ID: ${widget.resource.id}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Material file not found on server.')),
      );
      return;
    }

    if (_hasFullAccess()) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MaterialViewerScreen(
            title: widget.resource.title, 
            fileUrl: widget.resource.fileUrl,
          ),
        ),
      );
    } else {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => DownloadModal(
          resourceTitle: widget.resource.title,
          actionType: AccessActionType.read,
        ),
      );

      if (result == true && mounted) {
        _handleRead();
      }
    }
  }

  bool _hasFullAccess() {
    final subService = ref.read(subscriptionServiceProvider);
    final resourceService = ref.read(resourceServiceProvider);

    final bool isSubscribed = subService.isSubscribed;
    final bool isMyUpload = resourceService.userUploads.any((r) => r.id == widget.resource.id);
    final bool isPermanentlyUnlocked = subService.isResourceUnlocked(widget.resource.title);

    return isSubscribed || isMyUpload || isPermanentlyUnlocked;
  }

  void _setActiveResource() {
    ref.read(resourceServiceProvider).setActiveResource(widget.resource.id);
    _incrementView();
  }

  void _handleTap() {
    _setActiveResource();
    _handleRead();
  }

  void _toggleLike() {
    _setActiveResource();
    widget.onLikeToggle?.call();
  }

  void _showComments() {
    _setActiveResource();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CommentModal(resourceTitle: widget.resource.title),
    );
  }

  void _showDetails() {
    _setActiveResource();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ResourceDetailsModal(
        title: widget.resource.title,
        type: widget.resource.type,
        thumbnailUrl: widget.resource.thumbnailUrl,
        fileUrl: widget.resource.fileUrl,
        unitName: widget.resource.unitName,
        unitCode: widget.resource.unitCode,
        targetPrograms: widget.resource.targetPrograms,
        programCodes: widget.resource.programCodes,
        materialFormat: widget.resource.materialFormat,
        uploadYear: widget.resource.uploadYear,
        publicationYear: widget.resource.publicationYear,
        yearOfStudy: widget.resource.yearOfStudy,
        semester: widget.resource.semester,
        lecturers: widget.resource.lecturers,
        uploadedBy: widget.resource.uploadedBy,
        uploaderRole: widget.resource.uploaderRole,
        uploaderId: widget.resource.uploaderId,
        uploaderProfilePic: widget.resource.uploaderProfilePic,
        showDownload: true,
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
    if (widget.resource.status == null) return const SizedBox.shrink();

    String text = '';
    Color color = Colors.grey;
    IconData icon = Icons.info_outline;

    switch (widget.resource.status) {
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
        if (widget.resource.status == 'declined' && widget.resource.declineReason != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              'Reason: ${widget.resource.declineReason}',
              style: const TextStyle(color: Colors.white54, fontSize: 9, fontStyle: FontStyle.italic),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  void _handleDownload() async {
    if (_hasFullAccess()) {
      ref.read(downloadServiceProvider).startDownload(_getResourceData());
    } else {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => DownloadModal(
          resourceTitle: widget.resource.title,
          actionType: AccessActionType.download,
        ),
      );

      if (result == true && mounted) {
        _handleDownload();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final resourceService = ref.watch(resourceServiceProvider);
    final downloadService = ref.watch(downloadServiceProvider);
    final viewService = ref.watch(viewServiceProvider);
    final commentService = ref.watch(commentServiceProvider);

    final isActive = resourceService.activeResourceId == widget.resource.id;
    final isPinned = downloadService.isPinned(widget.resource.title);
    final isDownloaded = downloadService.isDownloaded(widget.resource.title);
    
    final viewsCount = widget.resource.views.toString();
    final likesCount = widget.resource.likes.toString();
    final isLiked = widget.resource.isLiked;
    
    return ListenableBuilder(
      listenable: Listenable.merge([resourceService, downloadService, ref.watch(subscriptionServiceProvider)]),
      builder: (context, child) {
        return AnimatedScale(
          scale: isActive ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          child: GestureDetector(
            onTap: widget.isSelectionMode ? widget.onTap : _handleTap,
            onLongPress: widget.onLongPress,
            child: Container(
              decoration: BoxDecoration(
                color: widget.isSelected 
                    ? const Color(0xFF20C8FF).withValues(alpha: 0.1)
                    : (widget.isSelectionMode 
                        ? const Color(0xFF20C8FF).withValues(alpha: 0.05)
                        : const Color(0xFF181739).withValues(alpha: 0.9)),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: widget.isSelected 
                      ? const Color(0xFF20C8FF) 
                      : (widget.isSelectionMode 
                          ? const Color(0xFF20C8FF).withValues(alpha: 0.3)
                          : (isActive ? const Color(0xFF20C8FF) : Colors.white10)),
                  width: (isActive || widget.isSelected || widget.isSelectionMode) ? 2 : 1,
                ),
                boxShadow: (isActive || widget.isSelected || widget.isSelectionMode) ? [
                  BoxShadow(
                    color: const Color(0xFF20C8FF).withValues(alpha: widget.isSelected ? 0.3 : 0.1),
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
                    flex: widget.resource.status != null ? 2 : 3,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        widget.resource.thumbnailUrl.startsWith('http')
                          ? CachedNetworkImage(
                              imageUrl: widget.resource.thumbnailUrl,
                              fit: BoxFit.cover,
                              cacheKey: widget.resource.thumbnailUrl,
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
                              File(widget.resource.thumbnailUrl),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: Colors.white10,
                                child: const Icon(Icons.broken_image, color: Colors.white24),
                              ),
                            ),
                        
                        if (widget.isSelectionMode)
                          Container(
                            color: widget.isSelected 
                                ? Colors.black.withValues(alpha: 0.4) 
                                : Colors.black.withValues(alpha: 0.1),
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

                        if (widget.isSelectionMode)
                          Positioned(
                            top: 10,
                            left: 10,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: widget.isSelected ? const Color(0xFF20C8FF) : Colors.transparent,
                                border: Border.all(
                                  color: widget.isSelected ? const Color(0xFF20C8FF) : Colors.white70,
                                  width: 2,
                                ),
                              ),
                              child: widget.isSelected 
                                ? const Icon(Icons.check, color: Colors.white, size: 16) 
                                : null,
                            ),
                          ),

                        if (widget.isSelectionMode)
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${(widget.resource.title.length * 1.5 + 40).toStringAsFixed(2)} kB',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                        else if (isPinned && widget.showPin)
                          const Positioned(
                            top: 10,
                            right: 10,
                            child: Icon(Icons.push_pin, color: Color(0xFF20C8FF), size: 18),
                          ),

                        if (!widget.isSelectionMode)
                          Positioned(
                            top: 10,
                            left: (isPinned && widget.showPin && (widget.resource.type == 'Time tables' || widget.resource.type.contains('Timetable'))) ? 10 : 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white24, width: 0.5),
                              ),
                              child: Text(
                                _getTypeLabel(widget.resource.type),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                          ),

                        if (!widget.isSelectionMode && (widget.resource.type == 'Time tables' || widget.resource.type.contains('Timetable')))
                          Positioned(
                            top: 10,
                            // If pinned and pin is shown (Library), move to left side but after the 'TABLE' badge.
                            left: (isPinned && widget.showPin) ? 65 : null,
                            // On Dashboard (showPin is false), ensure it's on the right, avoiding the download icon if present.
                            right: (isPinned && widget.showPin) ? null : 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: widget.resource.type.contains('EXAM') 
                                    ? const Color(0xFFFF4667).withValues(alpha: 0.8) 
                                    : const Color(0xFF00A85A).withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white24, width: 0.5),
                              ),
                              child: Text(
                                widget.resource.type.contains('EXAM') ? 'EXAM' : 'CLASS',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                          ),
                        
                        if (!widget.isSelectionMode && widget.showDownload)
                          Positioned(
                            top: 10,
                            // If pinned and pin is shown (Library), shift action icon further left to avoid badges.
                            left: (isPinned && widget.showPin && (widget.resource.type == 'Time tables' || widget.resource.type.contains('Timetable'))) ? 115 : null,
                            right: (isPinned && widget.showPin) ? (widget.resource.type.contains('Timetable') ? null : 35) : 10,
                            child: GestureDetector(
                              onTap: () {
                                _setActiveResource(); // Just set active/views, NO auto-read
                                if (isPinned) {
                                  downloadService.unpin(widget.resource.title);
                                  FeedbackUtils.showActionFeedback(
                                    context: context,
                                    type: FeedbackActionType.unpin,
                                    count: 1,
                                    isDownloads: true,
                                  );
                                } else if (isDownloaded) {
                                  downloadService.pin(widget.resource.title);
                                  FeedbackUtils.showActionFeedback(
                                    context: context,
                                    type: FeedbackActionType.pin,
                                    count: 1,
                                    isDownloads: true,
                                  );
                                } else {
                                  _handleDownload();
                                }
                              },
                              behavior: HitTestBehavior.translucent,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  if (downloadService.isDownloading(widget.resource.title))
                                    SizedBox(
                                      width: 32,
                                      height: 32,
                                      child: CircularProgressIndicator(
                                        value: downloadService.getProgress(widget.resource.title),
                                        strokeWidth: 3,
                                        color: const Color(0xFF00A85A),
                                        backgroundColor: Colors.white10,
                                      ),
                                    ),
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: (isPinned && widget.showPin)
                                          ? const Color(0xFFD9BD26) 
                                          : (isDownloaded ? const Color(0xFF00A85A) : Colors.black38),
                                      shape: BoxShape.circle,
                                      border: (downloadService.isDownloading(widget.resource.title) || (isPinned && widget.showPin) || isDownloaded) ? null : Border.all(color: Colors.white24, width: 0.5),
                                    ),
                                    child: Icon(
                                      (isPinned && widget.showPin)
                                          ? Icons.push_pin_rounded 
                                          : (downloadService.isDownloading(widget.resource.title) ? Icons.download_for_offline : (isDownloaded ? Icons.check : Icons.download_rounded)),
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Text(
                              widget.resource.title,
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
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: _pill(
                                      (widget.resource.type == 'Time tables' || 
                                       widget.resource.type == 'Class Timetable' || 
                                       widget.resource.type == 'EXAM Timetable') && widget.resource.programCodes.isNotEmpty
                                          ? widget.resource.programCodes.join(', ')
                                          : widget.resource.unitCode,
                                      const Color(0xFFD92680),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  _pill(widget.resource.publicationYear, const Color(0xFFD9BD26)),
                                ],
                              ),
                            ),
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
                        _statItem(
                          Icons.visibility_outlined, 
                          viewsCount,
                          iconColor: viewService.hasViewed(widget.resource.id) ? const Color(0xFF00A85A) : Colors.white54,
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
                          child: Builder(
                            builder: (context) {
                              final count = commentService.getCommentCount(widget.resource.title);
                              final displayCount = (widget.resource.status == 'approved') ? count.toString() : '0';
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
      }
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
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        softWrap: false,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
