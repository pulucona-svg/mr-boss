import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' hide FileService;
import 'dart:io';
import 'package:intl/intl.dart';
import '../services/persistence_service.dart';
import '../services/progress_service.dart';
import '../services/usage_service.dart';
import '../services/file_service.dart';

class MaterialViewerScreen extends StatefulWidget {
  final String title;
  final String fileUrl;
  final String? unitName;
  final String? unitCode;
  final String? category;
  final String? publicationYear;

  const MaterialViewerScreen({
    super.key,
    required this.title,
    required this.fileUrl,
    this.unitName,
    this.unitCode,
    this.category,
    this.publicationYear,
  });

  @override
  State<MaterialViewerScreen> createState() => _MaterialViewerScreenState();
}

class _MaterialViewerScreenState extends State<MaterialViewerScreen> {
  final FileService _fileService = FileService();
  bool _isLoading = true;
  String? _localPath;
  String? _htmlContent;
  bool _isPdf = false;
  bool _isImage = false;
  bool _isHtml = false;
  late final ValueNotifier<double> _progressNotifier;
  late final ValueNotifier<int> _currentPageNotifier;
  late final ValueNotifier<List<int>> _bookmarksNotifier;
  final PdfViewerController _pdfController = PdfViewerController();

  String get _bookmarksKey => 'bookmarks_doc_${widget.title}';

  @override
  void initState() {
    super.initState();
    final initialProgress = ProgressService().getProgress(widget.title);
    _progressNotifier = ValueNotifier<double>(initialProgress);
    _currentPageNotifier = ValueNotifier<int>(1);

    final stored = PersistenceService().getJson(_bookmarksKey);
    List<int> initialBookmarks = [];
    if (stored != null) {
      initialBookmarks = (stored as List).map((item) => item['pageNumber'] as int).toList();
    }
    _bookmarksNotifier = ValueNotifier<List<int>>(initialBookmarks);

    _isPdf = _fileService.isPdf(widget.fileUrl);
    _isImage = _fileService.isImage(widget.fileUrl);
    _isHtml = _fileService.isHtml(widget.fileUrl);
    
    // Continuously monitor scroll page changes from controller
    _pdfController.addListener(_onControllerChanged);

    // Start tracking reading time
    UsageService().startMaterialTracking(widget.title);

    _prepareFile();
  }

  void _onControllerChanged() {
    final page = _pdfController.pageNumber;
    if (page != null && page != _currentPageNotifier.value) {
      _currentPageNotifier.value = page;
    }
  }

  Future<void> _prepareFile() async {
    debugPrint('MaterialViewerScreen: [DEBUG] Opening resource: ${widget.title}');
    debugPrint('MaterialViewerScreen: [DEBUG] fileUrl: ${widget.fileUrl}');

    if (widget.fileUrl.isEmpty) {
      if (mounted) {
        setState(() => _isLoading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error: Resource URL is empty.')),
            );
          }
        });
      }
      return;
    }

    try {
      // 1. Check if the file is already cached (or downloaded)
      final fileInfo = await DefaultCacheManager().getFileFromCache(widget.fileUrl);
      File? file;
      if (fileInfo != null && await fileInfo.file.exists() && await fileInfo.file.length() > 0) {
        file = fileInfo.file;
        debugPrint('MaterialViewerScreen: Loaded valid cached/downloaded file from path: ${file.path}');
      } else {
        debugPrint('MaterialViewerScreen: File not cached. Fetching and storing in cache...');
        // 2. Fetch and store in cache
        file = await DefaultCacheManager().getSingleFile(widget.fileUrl);
        debugPrint('MaterialViewerScreen: File fetched and cached at path: ${file.path}');
      }

      _localPath = file.path;

      if (_isHtml) {
        _htmlContent = await file.readAsString();
      }

      // If it's not a PDF, Image, or HTML, open with system app
      if (!_isPdf && !_isImage && !_isHtml) {
        await _fileService.openFile(_localPath!);
        if (mounted) Navigator.pop(context);
        return;
      }
    } catch (e) {
      debugPrint('MaterialViewerScreen: [ERROR] Caching failed: $e');

      // Fallback for non-PDF/Image/HTML if cache fails
      if (!_isPdf && !_isImage && !_isHtml) {
        final fileName = '${widget.title.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}';
        final path = await _fileService.downloadFile(widget.fileUrl, fileName);
        if (path != null) {
          await _fileService.openFile(path);
          if (mounted) Navigator.pop(context);
        } else {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error: Could not download file.')),
            );
          }
        }
        return;
      }

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading file: $e')),
        );
      }
      return;
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _onPdfChanged(int? pageNumber) {
    if (pageNumber == null) return;
    _currentPageNotifier.value = pageNumber;
    final totalPages = _pdfController.pageCount;
    if (totalPages > 0) {
      final newProgress = (pageNumber / totalPages).clamp(0.0, 1.0);
      if ((newProgress - _progressNotifier.value).abs() > 0.05) {
        _progressNotifier.value = newProgress;
        ProgressService().updateProgress(widget.title, newProgress);
      }
    }
  }

  void _toggleBookmark() {
    final page = _pdfController.pageNumber ?? _currentPageNotifier.value;
    final currentList = List<int>.from(_bookmarksNotifier.value);
    final stored = PersistenceService().getJson(_bookmarksKey) as List? ?? [];
    final List<Map<String, dynamic>> bookmarksList = List<Map<String, dynamic>>.from(
      stored.map((item) => Map<String, dynamic>.from(item as Map)),
    );

    bool isBookmarked = currentList.contains(page);
    if (isBookmarked) {
      currentList.remove(page);
      bookmarksList.removeWhere((item) => item['pageNumber'] == page);
      _bookmarksNotifier.value = currentList;
      PersistenceService().setJson(_bookmarksKey, bookmarksList);

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bookmark removed.'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      currentList.add(page);
      bookmarksList.add({
        'pageNumber': page,
        'dateBookmarked': DateTime.now().toIso8601String(),
      });
      bookmarksList.sort((a, b) => (a['pageNumber'] as int).compareTo(b['pageNumber'] as int));
      currentList.sort();

      _bookmarksNotifier.value = currentList;
      PersistenceService().setJson(_bookmarksKey, bookmarksList);

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Page $page bookmarked.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showBookmarksBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _BookmarksBottomSheet(
        bookmarksKey: _bookmarksKey,
        onTapBookmark: (pageNumber) {
          Navigator.pop(context);
          _pdfController.goToPage(pageNumber: pageNumber);
        },
      ),
    );
  }

  @override
  void dispose() {
    _pdfController.removeListener(_onControllerChanged);
    UsageService().stopMaterialTracking();
    _progressNotifier.dispose();
    _currentPageNotifier.dispose();
    _bookmarksNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String displayUnitName = (widget.unitName != null && widget.unitName!.isNotEmpty)
        ? widget.unitName!
        : widget.title;
    final String unitCodeSuffix = (widget.unitCode != null && widget.unitCode!.isNotEmpty)
        ? ' (${widget.unitCode})'
        : '';
    final String titleLine = '$displayUnitName$unitCodeSuffix';

    final String categoryPart = (widget.category != null && widget.category!.isNotEmpty)
        ? widget.category!
        : '';
    final String yearPart = (widget.publicationYear != null && widget.publicationYear!.isNotEmpty)
        ? widget.publicationYear!
        : '';

    String subtitleLine = '';
    if (categoryPart.isNotEmpty && yearPart.isNotEmpty) {
      subtitleLine = '$categoryPart • $yearPart';
    } else if (categoryPart.isNotEmpty) {
      subtitleLine = categoryPart;
    } else if (yearPart.isNotEmpty) {
      subtitleLine = yearPart;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF070716),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141232),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              titleLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (subtitleLine.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitleLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (_isPdf)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: ValueListenableBuilder<double>(
                  valueListenable: _progressNotifier,
                  builder: (context, progress, child) {
                    return Text(
                      '${(progress * 100).toInt()}%',
                      style: const TextStyle(color: Color(0xFF20C8FF), fontWeight: FontWeight.bold),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF20C8FF)))
        : _buildViewer(),
      bottomNavigationBar: _isLoading ? null : _buildStudyToolbar(context),
    );
  }

  Widget _buildStudyToolbar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final backgroundColor = isDark ? const Color(0xFF141232) : Colors.white;
    final defaultColor = isDark ? Colors.white70 : Colors.black87;
    final borderColor = isDark ? Colors.white10 : Colors.black12;

    Widget buildToolbarItem({
      required IconData icon,
      Color? iconColor,
      required String label,
      required VoidCallback onTap,
      VoidCallback? onLongPress,
    }) {
      final color = iconColor ?? defaultColor;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          top: BorderSide(color: borderColor, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black45 : Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          buildToolbarItem(
            icon: Icons.edit_outlined,
            label: 'Pen',
            onTap: () => _showComingSoonSnackbar('Pen'),
          ),
          buildToolbarItem(
            icon: Icons.border_color_outlined,
            label: 'Highlighter',
            onTap: () => _showComingSoonSnackbar('Highlighter'),
          ),
          buildToolbarItem(
            icon: Icons.note_alt_outlined,
            label: 'Notes',
            onTap: () => _showComingSoonSnackbar('Notes'),
          ),
          buildToolbarItem(
            icon: Icons.volume_up_outlined,
            label: 'Read Aloud',
            onTap: () => _showComingSoonSnackbar('Read Aloud'),
          ),
          ValueListenableBuilder<int>(
            valueListenable: _currentPageNotifier,
            builder: (context, currentPage, child) {
              return ValueListenableBuilder<List<int>>(
                valueListenable: _bookmarksNotifier,
                builder: (context, bookmarkedPages, child) {
                  final isBookmarked = bookmarkedPages.contains(currentPage);
                  return buildToolbarItem(
                    icon: isBookmarked ? Icons.bookmark : Icons.bookmark_border_outlined,
                    iconColor: isBookmarked ? const Color(0xFF20C8FF) : null,
                    label: 'Bookmarks',
                    onTap: _toggleBookmark,
                    onLongPress: _showBookmarksBottomSheet,
                  );
                },
              );
            },
          ),
          buildToolbarItem(
            icon: Icons.more_horiz,
            label: 'More Tools',
            onTap: () => _showComingSoonSnackbar('More Tools'),
          ),
        ],
      ),
    );
  }

  void _showComingSoonSnackbar(String toolName) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coming soon.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildViewer() {
    if (_isPdf) {
      final initialProgress = _progressNotifier.value;
      return _localPath != null
          ? PdfViewer.file(
              _localPath!,
              controller: _pdfController,
              params: PdfViewerParams(
                scrollPhysics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                onViewerReady: (document, controller) {
                  if (initialProgress > 0) {
                    final targetPage = (initialProgress * document.pages.length).round().clamp(1, document.pages.length);
                    controller.goToPage(pageNumber: targetPage);
                  }
                },
                onPageChanged: _onPdfChanged,
              ),
            )
          : PdfViewer.uri(
              Uri.parse(widget.fileUrl),
              controller: _pdfController,
              params: PdfViewerParams(
                scrollPhysics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                onViewerReady: (document, controller) {
                  if (initialProgress > 0) {
                    final targetPage = (initialProgress * document.pages.length).round().clamp(1, document.pages.length);
                    controller.goToPage(pageNumber: targetPage);
                  }
                },
                onPageChanged: _onPdfChanged,
              ),
            );
    } else if (_isImage) {
      return Center(
        child: InteractiveViewer(
          child: _localPath != null
              ? Image.file(
                  File(_localPath!),
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 100, color: Colors.white24),
                )
              : CachedNetworkImage(
                  imageUrl: widget.fileUrl,
                  placeholder: (context, url) => const CircularProgressIndicator(),
                  errorWidget: (context, url, error) => const Icon(Icons.broken_image, size: 100, color: Colors.white24),
                ),
        ),
      );
    } else if (_isHtml) {
      return Container(
        color: Colors.white, // HTML content is usually better on white background
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: HtmlWidget(
            _htmlContent ?? widget.fileUrl,
            factoryBuilder: () => WidgetFactory(),
            textStyle: const TextStyle(color: Colors.black),
            onLoadingBuilder: (context, element, loadingProgress) => const Center(
              child: CircularProgressIndicator(color: Color(0xFF20C8FF)),
            ),
          ),
        ),
      );
    } else {
      return const Center(
        child: Text(
          'File format not supported for in-app viewing.\nOpening in system app...',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
  }
}

class _BookmarksBottomSheet extends StatelessWidget {
  final String bookmarksKey;
  final Function(int) onTapBookmark;

  const _BookmarksBottomSheet({
    required this.bookmarksKey,
    required this.onTapBookmark,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF141232) : Colors.white;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;
    final dividerColor = isDark ? Colors.white10 : Colors.black12;

    final stored = PersistenceService().getJson(bookmarksKey) as List? ?? [];
    final List<Map<String, dynamic>> bookmarks = List<Map<String, dynamic>>.from(
      stored.map((item) => Map<String, dynamic>.from(item as Map)),
    );

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.only(top: 10, bottom: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Bookmarks',
            style: TextStyle(
              color: titleColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: dividerColor, height: 1),
          if (bookmarks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bookmark_border_rounded,
                    size: 48,
                    color: isDark ? Colors.white24 : Colors.black12,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No bookmarks yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bookmark important pages to find them quickly.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: subTextColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: bookmarks.length,
                separatorBuilder: (context, index) => Divider(color: dividerColor, height: 1),
                itemBuilder: (context, index) {
                  final bookmark = bookmarks[index];
                  final page = bookmark['pageNumber'] as int;
                  final dateStr = bookmark['dateBookmarked'] as String;
                  
                  String formattedDate = '';
                  try {
                    final date = DateTime.parse(dateStr);
                    formattedDate = DateFormat('MMM d, yyyy').format(date);
                  } catch (e) {
                    formattedDate = dateStr;
                  }

                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF20C8FF).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.description_outlined,
                        color: Color(0xFF20C8FF),
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Page $page',
                      style: TextStyle(
                        color: titleColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      'Bookmarked on $formattedDate',
                      style: TextStyle(
                        color: subTextColor,
                        fontSize: 11,
                      ),
                    ),
                    onTap: () => onTapBookmark(page),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
