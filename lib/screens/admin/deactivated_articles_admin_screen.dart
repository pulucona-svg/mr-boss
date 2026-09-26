import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/admin_service.dart';

class DeactivatedArticlesAdminScreen extends StatefulWidget {
  const DeactivatedArticlesAdminScreen({super.key});

  @override
  State<DeactivatedArticlesAdminScreen> createState() => _DeactivatedArticlesAdminScreenState();
}

class _DeactivatedArticlesAdminScreenState extends State<DeactivatedArticlesAdminScreen> {
  final AdminService _adminService = AdminService();
  final Set<String> _selectedArticleIds = {};
  bool _isPerformingAction = false;

  void _toggleSelection(String articleId) {
    setState(() {
      if (_selectedArticleIds.contains(articleId)) {
        _selectedArticleIds.remove(articleId);
      } else {
        _selectedArticleIds.add(articleId);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedArticleIds.clear();
    });
  }

  Future<void> _restoreSelected() async {
    if (_selectedArticleIds.isEmpty || _isPerformingAction) return;

    final selectedList = _selectedArticleIds.toList();
    setState(() => _isPerformingAction = true);

    try {
      final success = await _adminService.restoreArticles(selectedList);
      if (mounted) {
        setState(() {
          _isPerformingAction = false;
          _selectedArticleIds.clear();
        });
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Color(0xFF00E676), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${selectedList.length} article(s) restored to active status (30-article retention enforced).',
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1E1B4B),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPerformingAction = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to restore article(s): $e'),
            backgroundColor: Colors.red.shade900,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _deleteSelectedPermanently() async {
    if (_selectedArticleIds.isEmpty || _isPerformingAction) return;

    final count = _selectedArticleIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1830),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.redAccent, width: 1),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Delete Permanently?',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'Delete $count selected article(s) permanently?\n\nThis will permanently remove the article(s) and all associated media from the system. They will no longer be available anywhere and cannot be undone.',
          style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete Permanently', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final selectedList = _selectedArticleIds.toList();
    setState(() => _isPerformingAction = true);

    try {
      final success = await _adminService.deleteArticles(selectedList);
      if (mounted) {
        setState(() {
          _isPerformingAction = false;
          _selectedArticleIds.clear();
        });
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Color(0xFF00E676), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('$count article(s) permanently purged from backend and media storage.'),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1E1B4B),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPerformingAction = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to permanently delete article(s): $e'),
            backgroundColor: Colors.red.shade900,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isSelecting = _selectedArticleIds.isNotEmpty;

    return PopScope(
      canPop: !isSelecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isSelecting) {
          _clearSelection();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF090814),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D0C1D),
          elevation: 0,
          leading: isSelecting
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: _clearSelection,
                  tooltip: 'Cancel Selection',
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
          title: isSelecting
              ? Text(
                  '${_selectedArticleIds.length} Selected',
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                )
              : const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Deactivated Articles',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Admin Recovery & Purge Area',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
          actions: [
            if (isSelecting) ...[
              if (_isPerformingAction)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF20C8FF)),
                    ),
                  ),
                )
              else ...[
                IconButton(
                  icon: const Icon(Icons.restore_from_trash_rounded, color: Color(0xFF00E676)),
                  tooltip: 'Restore Selected',
                  onPressed: _restoreSelected,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                  tooltip: 'Delete Permanently',
                  onPressed: _deleteSelectedPermanently,
                ),
              ],
            ],
          ],
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('explore_news')
              .where('status', isEqualTo: 'deactivated')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF20C8FF)),
              );
            }

            final docs = snapshot.data?.docs ?? [];

            if (docs.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.verified_rounded, size: 54, color: Color(0xFF00E676)),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'No Deactivated Articles',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'All articles are active and published. When you deactivate an article from the Explore list, it will appear here for restoration or permanent purge.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data();
                final articleId = doc.id;
                final isSelected = _selectedArticleIds.contains(articleId);

                final title = data['title'] as String? ?? 'Untitled Article';
                final category = data['category'] as String? ?? 'General';
                final summary = data['summary'] as String? ?? data['editorialSummary'] as String? ?? '';
                final coverImage = data['coverImage'] as String? ??
                    (data['imageUrls'] is List && (data['imageUrls'] as List).isNotEmpty
                        ? data['imageUrls'][0]
                        : null);

                return InkWell(
                  onLongPress: () => _toggleSelection(articleId),
                  onTap: () {
                    if (isSelecting) {
                      _toggleSelection(articleId);
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF20C8FF).withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF20C8FF)
                            : Colors.white.withValues(alpha: 0.1),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Thumbnail
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: coverImage != null && coverImage.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: coverImage,
                                  width: 90,
                                  height: 90,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(
                                    width: 90,
                                    height: 90,
                                    color: Colors.white10,
                                    child: const Center(
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF20C8FF)),
                                    ),
                                  ),
                                  errorWidget: (_, __, ___) => Container(
                                    width: 90,
                                    height: 90,
                                    color: Colors.white10,
                                    child: const Icon(Icons.image_not_supported_rounded, color: Colors.white38),
                                  ),
                                )
                              : Container(
                                  width: 90,
                                  height: 90,
                                  color: Colors.white10,
                                  child: const Icon(Icons.newspaper_rounded, color: Colors.white38),
                                ),
                        ),
                        const SizedBox(width: 12),
                        // Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      category.toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.amber,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white10,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'DEACTIVATED',
                                      style: TextStyle(
                                        color: Colors.white60,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (isSelected)
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: Color(0xFF20C8FF),
                                      size: 20,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  height: 1.25,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (summary.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  summary,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
