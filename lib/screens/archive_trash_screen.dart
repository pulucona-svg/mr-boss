import 'package:flutter/material.dart';
import '../services/download_service.dart';
import '../services/resource_service.dart';
import '../utils/feedback_utils.dart';

class ArchiveTrashScreen extends StatefulWidget {
  final bool isDownloads;
  final bool isTrash;

  const ArchiveTrashScreen({
    super.key,
    required this.isDownloads,
    required this.isTrash,
  });

  @override
  State<ArchiveTrashScreen> createState() => _ArchiveTrashScreenState();
}

class _ArchiveTrashScreenState extends State<ArchiveTrashScreen> {
  final Set<String> _selectedTitles = {};
  bool _isSelectionMode = false;

  void _toggleSelection(String title) {
    setState(() {
      if (_selectedTitles.contains(title)) {
        _selectedTitles.remove(title);
        if (_selectedTitles.isEmpty) _isSelectionMode = false;
      } else {
        _selectedTitles.add(title);
      }
    });
  }

  void _enterSelectionMode(String title) {
    setState(() {
      _isSelectionMode = true;
      _selectedTitles.add(title);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedTitles.clear();
    });
  }

  void _handleRestore() {
    final titles = _selectedTitles.toList();
    if (widget.isDownloads) {
      DownloadService().restoreMultiple(titles);
    } else {
      ResourceService().restoreMultiple(titles);
    }
    FeedbackUtils.showActionFeedback(
      context: context,
      type: widget.isTrash ? FeedbackActionType.restore : FeedbackActionType.unarchive,
      count: titles.length,
      isDownloads: widget.isDownloads,
    );
    _exitSelectionMode();
  }

  void _handlePermanentDelete() {
    final titles = _selectedTitles.toList();
    if (widget.isDownloads) {
      DownloadService().permanentlyDeleteMultiple(titles);
    } else {
      ResourceService().permanentlyDeleteMultiple(titles);
    }
    FeedbackUtils.showActionFeedback(
      context: context,
      type: FeedbackActionType.permanentDelete,
      count: titles.length,
      isDownloads: widget.isDownloads,
    );
    _exitSelectionMode();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([DownloadService(), ResourceService()]),
      builder: (context, child) {
        List<dynamic> items = [];
        if (widget.isDownloads) {
          items = widget.isTrash 
              ? DownloadService().trashedResources 
              : DownloadService().archivedResources;
        } else {
          items = widget.isTrash 
              ? ResourceService().trashedUploads 
              : ResourceService().archivedUploads;
        }

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              _isSelectionMode ? '${_selectedTitles.length} selected' : (widget.isTrash ? 'Trash' : 'Archived'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            actions: [
              if (_isSelectionMode) ...[
                IconButton(
                  icon: const Icon(Icons.restore, color: Colors.white),
                  onPressed: _handleRestore,
                ),
                if (widget.isTrash)
                  IconButton(
                    icon: const Icon(Icons.delete_forever, color: Colors.white),
                    onPressed: _handlePermanentDelete,
                  ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: _exitSelectionMode,
                ),
              ]
            ],
          ),
          body: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF140C37), Color(0xFF070716)],
              ),
            ),
            child: SafeArea(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.isTrash ? Icons.delete_outline : Icons.archive_outlined,
                            size: 80,
                            color: Colors.white24,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.isTrash 
                                ? 'No items in Trash' 
                                : 'Archived materials appear here',
                            style: const TextStyle(color: Colors.white54, fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        Resource? res;
                        String? remainingDays;

                        if (widget.isDownloads) {
                          if (widget.isTrash) {
                            final map = item as Map<String, dynamic>;
                            final data = map['resource'] as Map<String, String>;
                            res = ResourceService().findResourceByTitle(data['title']!);
                            final deletedAt = DateTime.parse(map['deletedAt'] as String);
                            remainingDays = '${30 - DateTime.now().difference(deletedAt).inDays} days left';
                          } else {
                            final data = item as Map<String, String>;
                            res = ResourceService().findResourceByTitle(data['title']!);
                          }
                        } else {
                          if (widget.isTrash) {
                            final map = item as Map<String, dynamic>;
                            res = map['resource'] as Resource;
                            final deletedAt = DateTime.parse(map['deletedAt'] as String);
                            remainingDays = '${30 - DateTime.now().difference(deletedAt).inDays} days left';
                          } else {
                            res = item as Resource;
                          }
                        }

                        if (res == null) return const SizedBox.shrink();

                        final isSelected = _selectedTitles.contains(res.title);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GestureDetector(
                            onLongPress: () => _enterSelectionMode(res!.title),
                            onTap: () {
                              if (_isSelectionMode) {
                                _toggleSelection(res!.title);
                              }
                            },
                            child: Stack(
                              children: [
                                Opacity(
                                  opacity: isSelected ? 0.6 : 1.0,
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isSelected ? const Color(0xFF20C8FF) : Colors.white10,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(
                                            res.thumbnailUrl,
                                            width: 60,
                                            height: 60,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Container(
                                              color: Colors.white10,
                                              width: 60,
                                              height: 60,
                                              child: const Icon(Icons.broken_image, color: Colors.white24),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                res.title,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                res.unitCode,
                                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                                              ),
                                              if (remainingDays != null)
                                                Text(
                                                  remainingDays,
                                                  style: const TextStyle(color: Colors.orange, fontSize: 11),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  const Positioned(
                                    right: 12,
                                    top: 12,
                                    child: Icon(Icons.check_circle, color: Color(0xFF20C8FF)),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }
}
