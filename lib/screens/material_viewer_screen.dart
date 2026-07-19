import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' hide FileService;
import 'dart:io';
import 'dart:async';
import 'package:intl/intl.dart';
import '../services/persistence_service.dart';
import '../services/progress_service.dart';
import '../services/usage_service.dart';
import '../services/file_service.dart';
import '../services/resource_service.dart';
import '../widgets/resource_details_modal.dart';

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

enum AnnotationType { none, pen, highlighter }

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

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  int _searchMatchesCount = 0;
  int _currentMatchIndex = -1;
  PdfTextSearcher? _textSearcher;

  // Annotation variables
  List<AnnotationStroke> _annotations = [];
  final List<AnnotationStroke> _undoStack = [];
  AnnotationType _activeAnnotationType = AnnotationType.none;
  Timer? _scrollTimer;

  Color _selectedPenColor = Colors.blue;
  double _selectedPenThickness = 4.0;

  Color _selectedHighlightColor = const Color(0xFFFFF066); // Yellow default
  double _selectedHighlightThickness = 20.0;

  String get _bookmarksKey => 'bookmarks_doc_${widget.title}';
  String get _annotationsKey => 'annotations_doc_${widget.title}';

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

    final storedAnnotations = PersistenceService().getJson(_annotationsKey);
    if (storedAnnotations != null) {
      _annotations = (storedAnnotations as List)
          .map((item) => AnnotationStroke.fromJson(item as Map<String, dynamic>))
          .toList();
    }

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

    if (widget.fileUrl == 'test_doc.pdf') {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

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
      _progressNotifier.value = newProgress;
      ProgressService().updateProgress(widget.title, newProgress);
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

  void _onSearchUpdated() {
    if (mounted && _textSearcher != null) {
      setState(() {
        _searchMatchesCount = _textSearcher!.matches.length;
        _currentMatchIndex = _textSearcher!.currentIndex ?? -1;
      });
    }
  }

  void _onSearchChanged(String text) {
    if (_textSearcher == null) return;
    if (text.isEmpty) {
      _textSearcher!.resetTextSearch();
      setState(() {
        _searchMatchesCount = 0;
        _currentMatchIndex = -1;
      });
    } else {
      _textSearcher!.startTextSearch(text, caseInsensitive: true);
    }
  }

  void _goToPrevMatch() {
    _textSearcher?.goToPrevMatch();
  }

  void _goToNextMatch() {
    _textSearcher?.goToNextMatch();
  }

  void _startSearchMode() {
    _searchController.clear();
    if (_textSearcher == null) {
      try {
        _textSearcher = PdfTextSearcher(_pdfController)..addListener(_onSearchUpdated);
      } catch (e) {
        debugPrint('Error initializing PdfTextSearcher: $e');
      }
    }
    _textSearcher?.resetTextSearch();
    setState(() {
      _isSearching = true;
      _searchMatchesCount = 0;
      _currentMatchIndex = -1;
    });
  }

  void _stopSearchMode() {
    _searchController.clear();
    _textSearcher?.resetTextSearch();
    setState(() {
      _isSearching = false;
      _searchMatchesCount = 0;
      _currentMatchIndex = -1;
    });
  }

  Widget _buildSearchField() {
    return Row(
      key: const ValueKey('search_field'),
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: const InputDecoration(
              hintText: 'Search...',
              hintStyle: TextStyle(color: Colors.white38),
              border: InputBorder.none,
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        if (_searchController.text.isNotEmpty) ...[
          if (_searchMatchesCount > 0) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '${_currentMatchIndex >= 0 ? _currentMatchIndex + 1 : 1}/$_searchMatchesCount',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            IconButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white70, size: 20),
              onPressed: _goToPrevMatch,
            ),
            IconButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 20),
              onPressed: _goToNextMatch,
            ),
          ] else ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'No matches found',
                style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white70),
          onPressed: _stopSearchMode,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _pdfController.removeListener(_onControllerChanged);
    UsageService().stopMaterialTracking();
    if (_isPdf) {
      try {
        final page = _pdfController.pageNumber ?? _currentPageNotifier.value;
        final totalPages = _pdfController.pageCount;
        if (totalPages > 0) {
          final finalProgress = (page / totalPages).clamp(0.0, 1.0);
          ProgressService().updateProgress(widget.title, finalProgress);
        }
      } catch (e) {
        debugPrint('Error saving progress during dispose: $e');
      }
      if (_textSearcher != null) {
        _textSearcher!.removeListener(_onSearchUpdated);
        _textSearcher!.dispose();
      }
    }
    _searchController.dispose();
    _searchFocusNode.dispose();
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
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _isSearching
              ? _buildSearchField()
              : Column(
                  key: const ValueKey('normal_title'),
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
                        color: Color(0xFF20C8FF),
                      ),
                    ),
                    if (subtitleLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            subtitleLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                          if (_isPdf) ...[
                            const SizedBox(width: 24),
                            GestureDetector(
                              onTap: _startSearchMode,
                              behavior: HitTestBehavior.translucent,
                              child: const Icon(
                                Icons.search,
                                color: Colors.white70,
                                size: 16,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
        ),
        actions: [
          if (!_isSearching) ...[
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: _showMoreToolsBottomSheet,
                    behavior: HitTestBehavior.translucent,
                    child: const Icon(Icons.more_vert, color: Colors.white70, size: 22),
                  ),
                  if (_isPdf) ...[
                    const SizedBox(height: 2),
                    ValueListenableBuilder<double>(
                      valueListenable: _progressNotifier,
                      builder: (context, progress, child) {
                        return Text(
                          '${(progress * 100).toInt()}%',
                          style: const TextStyle(
                            color: Color(0xFF20C8FF), 
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF20C8FF)))
        : Stack(
            children: [
              _buildViewer(),
              if (_activeAnnotationType != AnnotationType.none) ...[
                // Center-right page navigation scroll buttons
                Positioned(
                  right: 16,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildScrollButton(Icons.keyboard_arrow_up, true),
                        const SizedBox(height: 16),
                        _buildScrollButton(Icons.keyboard_arrow_down, false),
                      ],
                    ),
                  ),
                ),
                // Floating drawing toolbar positioned comfortably above the study toolbar
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: _buildDrawingToolbar(context),
                ),
              ],
            ],
          ),
      bottomNavigationBar: _isLoading ? null : _buildStudyToolbar(context),
    );
  }

  Widget _buildDrawingToolbar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF1F1B46) : Colors.white;
    final defaultColor = isDark ? Colors.white70 : Colors.black87;

    final isPen = _activeAnnotationType == AnnotationType.pen;
    final selectedColor = isPen ? _selectedPenColor : _selectedHighlightColor;

    return Card(
      elevation: 10,
      shadowColor: Colors.black38,
      color: backgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () => _showColorPickerSheet(!isPen),
              behavior: HitTestBehavior.translucent,
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: selectedColor.withOpacity(0.4),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: selectedColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isPen ? 'Pen Mode' : 'Highlighter Mode',
                    style: TextStyle(color: defaultColor, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.undo),
                  color: defaultColor,
                  onPressed: () => _undoLastStroke(),
                ),
                IconButton(
                  icon: const Icon(Icons.redo),
                  color: defaultColor,
                  onPressed: () => _redoLastStroke(),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _exitDrawingMode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF20C8FF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
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
            onTap: _isPdf 
                ? _showPenSettingsSheet 
                : () => _showOnlyPdfSupportSnackbar('Pen'),
          ),
          buildToolbarItem(
            icon: Icons.border_color_outlined,
            label: 'Highlighter',
            onTap: _isPdf 
                ? _showHighlighterSettingsSheet 
                : () => _showOnlyPdfSupportSnackbar('Highlighter'),
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
        ],
      ),
    );
  }

  void _showOnlyPdfSupportSnackbar(String toolName) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$toolName is only available for PDF documents.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showMoreToolsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141232),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).padding.bottom + 32, // Raised slightly above the bottom navigation
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'More Tools',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.info_outline, color: Color(0xFF20C8FF)),
                title: const Text('Material Details', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context); // Close More Tools sheet
                  _showMaterialDetails();  // Open exact same Details Modal
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Color(0xFF20C8FF)),
                title: const Text('Share Material', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showComingSoonSnackbar('Share Material');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMaterialDetails() {
    Resource? matchedResource;
    for (final r in ResourceService().allResources) {
      if (r.title == widget.title || r.fileUrl == widget.fileUrl) {
        matchedResource = r;
        break;
      }
    }

    if (matchedResource != null) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => ResourceDetailsModal(
          title: matchedResource!.title,
          type: matchedResource.type,
          thumbnailUrl: matchedResource.thumbnailUrl,
          fileUrl: matchedResource.fileUrl,
          unitName: matchedResource.unitName,
          unitCode: matchedResource.unitCode,
          targetPrograms: matchedResource.targetPrograms,
          programCodes: matchedResource.programCodes,
          materialFormat: matchedResource.materialFormat,
          uploadYear: matchedResource.uploadYear,
          publicationYear: matchedResource.publicationYear,
          yearOfStudy: matchedResource.yearOfStudy,
          semester: matchedResource.semester,
          lecturers: matchedResource.lecturers,
          uploadedBy: matchedResource.uploadedBy,
          uploaderRole: matchedResource.uploaderRole,
          uploaderId: matchedResource.uploaderId,
          uploaderProfilePic: matchedResource.uploaderProfilePic,
          showDownload: true,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Material details are not available.')),
      );
    }
  }

  void _scrollPage(bool isUp) {
    if (!_pdfController.isReady) return;
    final currentPage = _currentPageNotifier.value;
    final pageCount = _pdfController.pageCount;
    if (isUp) {
      if (currentPage > 1) {
        _pdfController.goToPage(
          pageNumber: currentPage - 1,
          duration: const Duration(milliseconds: 250),
        );
      }
    } else {
      if (currentPage < pageCount) {
        _pdfController.goToPage(
          pageNumber: currentPage + 1,
          duration: const Duration(milliseconds: 250),
        );
      }
    }
  }

  void _onScrollButtonTapDown(TapDownDetails details, bool isUp) {
    _scrollPage(isUp);
    _scrollTimer?.cancel();
    _scrollTimer = Timer(const Duration(milliseconds: 400), () {
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
        _scrollPage(isUp);
      });
    });
  }

  void _onScrollButtonTapUp(TapUpDetails details) {
    _stopContinuousScroll();
  }

  void _stopContinuousScroll() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
  }

  Widget _buildScrollButton(IconData icon, bool isUp) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTapDown: (details) => _onScrollButtonTapDown(details, isUp),
      onTapUp: _onScrollButtonTapUp,
      onTapCancel: _stopContinuousScroll,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F1B46).withOpacity(0.9) : Colors.white.withOpacity(0.9),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: const Color(0xFF20C8FF),
          size: 30,
        ),
      ),
    );
  }

  void _showColorPickerSheet(bool isHighlighter) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141232),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final colors = isHighlighter
                ? [
                    const Color(0xFFFFF066), // Yellow
                    const Color(0xFF66FF66), // Green
                    const Color(0xFFFF66CC), // Pink
                    const Color(0xFF66CCFF), // Blue
                  ]
                : [
                    Colors.blue,
                    Colors.black,
                    Colors.red,
                    Colors.green,
                  ];
            return Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).padding.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isHighlighter ? 'Select Highlight Color' : 'Select Pen Color',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: colors.map((color) {
                      final isSelected = isHighlighter
                          ? _selectedHighlightColor.value == color.value
                          : _selectedPenColor.value == color.value;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isHighlighter) {
                              _selectedHighlightColor = color;
                            } else {
                              _selectedPenColor = color;
                            }
                          });
                          Navigator.pop(context);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? const Color(0xFF20C8FF) : Colors.transparent,
                              width: 2.0,
                            ),
                          ),
                          padding: const EdgeInsets.all(2.0),
                          child: CircleAvatar(
                            backgroundColor: color,
                            radius: 20,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _saveAnnotations() {
    final list = _annotations.map((s) => s.toJson()).toList();
    PersistenceService().setJson(_annotationsKey, list);
  }

  void _paintAnnotations(Canvas canvas, Rect pageRect, PdfPage page) {
    final pageStrokes = _annotations.where((s) => s.pageNumber == page.pageNumber).toList();
    for (final stroke in pageStrokes) {
      if (stroke.normalizedPoints.length < 2) continue;
      final paint = Paint()
        ..color = stroke.isHighlighter 
            ? Color(int.parse(stroke.colorHex)).withOpacity(0.3)
            : Color(int.parse(stroke.colorHex))
        ..strokeWidth = stroke.thickness
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      final p0 = Offset(
        pageRect.left + stroke.normalizedPoints[0].dx * pageRect.width,
        pageRect.top + stroke.normalizedPoints[0].dy * pageRect.height,
      );
      path.moveTo(p0.dx, p0.dy);

      for (int i = 1; i < stroke.normalizedPoints.length; i++) {
        final p = Offset(
          pageRect.left + stroke.normalizedPoints[i].dx * pageRect.width,
          pageRect.top + stroke.normalizedPoints[i].dy * pageRect.height,
        );
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  void _addStroke(AnnotationStroke stroke) {
    setState(() {
      _annotations.add(stroke);
      _undoStack.clear();
    });
    _saveAnnotations();
  }

  void _undoLastStroke({bool? isHighlighterParam}) {
    final isHighlighter = isHighlighterParam ?? (_activeAnnotationType == AnnotationType.highlighter);
    final lastMatchIdx = _annotations.lastIndexWhere((s) => s.isHighlighter == isHighlighter);
    if (lastMatchIdx != -1) {
      final removed = _annotations.removeAt(lastMatchIdx);
      setState(() {
        _undoStack.add(removed);
      });
      _saveAnnotations();
    }
  }

  void _redoLastStroke({bool? isHighlighterParam}) {
    final isHighlighter = isHighlighterParam ?? (_activeAnnotationType == AnnotationType.highlighter);
    final lastMatchIdx = _undoStack.lastIndexWhere((s) => s.isHighlighter == isHighlighter);
    if (lastMatchIdx != -1) {
      final restored = _undoStack.removeAt(lastMatchIdx);
      setState(() {
        _annotations.add(restored);
      });
      _saveAnnotations();
    }
  }

  void _exitDrawingMode() {
    setState(() {
      _activeAnnotationType = AnnotationType.none;
    });
  }

  Widget _buildColorOption(Color color, String name, StateSetter setSheetState, bool isHighlighter) {
    final isSelected = isHighlighter 
        ? _selectedHighlightColor.value == color.value
        : _selectedPenColor.value == color.value;
    return GestureDetector(
      onTap: () {
        setSheetState(() {
          if (isHighlighter) {
            _selectedHighlightColor = color;
          } else {
            _selectedPenColor = color;
          }
        });
      },
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? const Color(0xFF20C8FF) : Colors.transparent,
            width: 2.0,
          ),
        ),
        padding: const EdgeInsets.all(2.0),
        child: CircleAvatar(
          backgroundColor: color,
          radius: 14,
        ),
      ),
    );
  }

  Widget _buildThicknessOption(String label, double value, StateSetter setSheetState, bool isHighlighter) {
    final isSelected = isHighlighter 
        ? _selectedHighlightThickness == value
        : _selectedPenThickness == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFF20C8FF),
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white70),
      backgroundColor: Colors.white10,
      onSelected: (selected) {
        if (selected) {
          setSheetState(() {
            if (isHighlighter) {
              _selectedHighlightThickness = value;
            } else {
              _selectedPenThickness = value;
            }
          });
        }
      },
    );
  }

  void _showPenSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141232),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).padding.bottom + 48, // Comfortably above navigation/viewer bottom bar
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pen Settings',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  
                  const Text('Pen Color', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildColorOption(Colors.blue, 'Blue', setSheetState, false),
                      _buildColorOption(Colors.black, 'Black', setSheetState, false),
                      _buildColorOption(Colors.red, 'Red', setSheetState, false),
                      _buildColorOption(Colors.green, 'Green', setSheetState, false),
                    ],
                  ),
                  const SizedBox(height: 16),

                  const Text('Pen Thickness', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildThicknessOption('Thin', 2.0, setSheetState, false),
                      _buildThicknessOption('Medium', 4.0, setSheetState, false),
                      _buildThicknessOption('Thick', 8.0, setSheetState, false),
                    ],
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.undo, color: Colors.white70),
                              onPressed: () {
                                _undoLastStroke(isHighlighterParam: false);
                                setSheetState(() {});
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.redo, color: Colors.white70),
                              onPressed: () {
                                _redoLastStroke(isHighlighterParam: false);
                                setSheetState(() {});
                              },
                            ),
                          ],
                        ),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF20C8FF),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () {
                                Navigator.pop(context);
                                setState(() {
                                  _activeAnnotationType = AnnotationType.pen;
                                });
                              },
                              child: const Text('Start Drawing'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showHighlighterSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141232),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).padding.bottom + 48, // Comfortably above navigation/viewer bottom bar
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Highlighter Settings',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  
                  const Text('Highlight Color', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildColorOption(const Color(0xFFFFF066), 'Yellow', setSheetState, true),
                      _buildColorOption(const Color(0xFF66FF66), 'Green', setSheetState, true),
                      _buildColorOption(const Color(0xFFFF66CC), 'Pink', setSheetState, true),
                      _buildColorOption(const Color(0xFF66CCFF), 'Blue', setSheetState, true),
                    ],
                  ),
                  const SizedBox(height: 16),

                  const Text('Thickness', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildThicknessOption('Thin', 10.0, setSheetState, true),
                      _buildThicknessOption('Medium', 20.0, setSheetState, true),
                      _buildThicknessOption('Thick', 35.0, setSheetState, true),
                    ],
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.undo, color: Colors.white70),
                              onPressed: () {
                                _undoLastStroke(isHighlighterParam: true);
                                setSheetState(() {});
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.redo, color: Colors.white70),
                              onPressed: () {
                                _redoLastStroke(isHighlighterParam: true);
                                setSheetState(() {});
                              },
                            ),
                          ],
                        ),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF20C8FF),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () {
                                Navigator.pop(context);
                                setState(() {
                                  _activeAnnotationType = AnnotationType.highlighter;
                                });
                              },
                              child: const Text('Start Highlighting'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showComingSoonSnackbar(String toolName) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$toolName is coming soon.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildViewer() {
    if (widget.fileUrl == 'test_doc.pdf') {
      return const Center(child: Text('Mock PDF Viewer'));
    }
    if (_isPdf) {
      final initialProgress = _progressNotifier.value;
      final physics = _activeAnnotationType != AnnotationType.none
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
      return _localPath != null
          ? PdfViewer.file(
              _localPath!,
              controller: _pdfController,
              params: PdfViewerParams(
                scrollPhysics: physics,
                onViewerReady: (document, controller) {
                  if (initialProgress > 0) {
                    final targetPage = (initialProgress * document.pages.length).round().clamp(1, document.pages.length);
                    controller.goToPage(pageNumber: targetPage);
                  }
                },
                onPageChanged: _onPdfChanged,
                pagePaintCallbacks: [
                  _paintAnnotations,
                  if (_textSearcher != null)
                    _textSearcher!.pageTextMatchPaintCallback,
                ],
                pageOverlaysBuilder: _activeAnnotationType != AnnotationType.none
                    ? (context, pageRect, page) {
                        return [
                          PageDrawingOverlay(
                            pageNumber: page.pageNumber,
                            pageRect: pageRect,
                            isDrawingActive: true,
                            selectedColor: _activeAnnotationType == AnnotationType.highlighter 
                                ? _selectedHighlightColor 
                                : _selectedPenColor,
                            selectedThickness: _activeAnnotationType == AnnotationType.highlighter
                                ? _selectedHighlightThickness
                                : _selectedPenThickness,
                            isHighlighter: _activeAnnotationType == AnnotationType.highlighter,
                            savedStrokes: const [],
                            onStrokeAdded: (stroke) {
                              _addStroke(stroke);
                            },
                          ),
                        ];
                      }
                    : null,
              ),
            )
          : PdfViewer.uri(
              Uri.parse(widget.fileUrl),
              controller: _pdfController,
              params: PdfViewerParams(
                scrollPhysics: physics,
                onViewerReady: (document, controller) {
                  if (initialProgress > 0) {
                    final targetPage = (initialProgress * document.pages.length).round().clamp(1, document.pages.length);
                    controller.goToPage(pageNumber: targetPage);
                  }
                },
                onPageChanged: _onPdfChanged,
                pagePaintCallbacks: [
                  _paintAnnotations,
                  if (_textSearcher != null)
                    _textSearcher!.pageTextMatchPaintCallback,
                ],
                pageOverlaysBuilder: _activeAnnotationType != AnnotationType.none
                    ? (context, pageRect, page) {
                        return [
                          PageDrawingOverlay(
                            pageNumber: page.pageNumber,
                            pageRect: pageRect,
                            isDrawingActive: true,
                            selectedColor: _activeAnnotationType == AnnotationType.highlighter 
                                ? _selectedHighlightColor 
                                : _selectedPenColor,
                            selectedThickness: _activeAnnotationType == AnnotationType.highlighter
                                ? _selectedHighlightThickness
                                : _selectedPenThickness,
                            isHighlighter: _activeAnnotationType == AnnotationType.highlighter,
                            savedStrokes: const [],
                            onStrokeAdded: (stroke) {
                              _addStroke(stroke);
                            },
                          ),
                        ];
                      }
                    : null,
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

class AnnotationStroke {
  final int pageNumber;
  final List<Offset> normalizedPoints;
  final String colorHex;
  final double thickness;
  final bool isHighlighter;

  AnnotationStroke({
    required this.pageNumber,
    required this.normalizedPoints,
    required this.colorHex,
    required this.thickness,
    required this.isHighlighter,
  });

  Map<String, dynamic> toJson() => {
    'pageNumber': pageNumber,
    'points': normalizedPoints.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
    'colorHex': colorHex,
    'thickness': thickness,
    'isHighlighter': isHighlighter,
  };

  factory AnnotationStroke.fromJson(Map<String, dynamic> json) {
    final pointsList = json['points'] as List;
    final List<Offset> points = pointsList.map((item) {
      final map = item as Map<String, dynamic>;
      return Offset((map['x'] as num).toDouble(), (map['y'] as num).toDouble());
    }).toList();
    return AnnotationStroke(
      pageNumber: json['pageNumber'] as int,
      normalizedPoints: points,
      colorHex: json['colorHex'] as String,
      thickness: (json['thickness'] as num).toDouble(),
      isHighlighter: json['isHighlighter'] as bool,
    );
  }
}

class PageDrawingOverlay extends StatefulWidget {
  final int pageNumber;
  final Rect pageRect;
  final bool isDrawingActive;
  final Color selectedColor;
  final double selectedThickness;
  final bool isHighlighter;
  final List<AnnotationStroke> savedStrokes;
  final Function(AnnotationStroke) onStrokeAdded;

  const PageDrawingOverlay({
    Key? key,
    required this.pageNumber,
    required this.pageRect,
    required this.isDrawingActive,
    required this.selectedColor,
    required this.selectedThickness,
    required this.isHighlighter,
    required this.savedStrokes,
    required this.onStrokeAdded,
  }) : super(key: key);

  @override
  _PageDrawingOverlayState createState() => _PageDrawingOverlayState();
}

class _PageDrawingOverlayState extends State<PageDrawingOverlay> {
  List<Offset> _currentStrokePoints = [];

  @override
  Widget build(BuildContext context) {
    final pageStrokes = widget.savedStrokes.where((s) => s.pageNumber == widget.pageNumber).toList();

    Widget overlay = CustomPaint(
      size: widget.pageRect.size,
      painter: _OverlayPainter(
        strokes: pageStrokes,
        currentStrokePoints: _currentStrokePoints,
        currentColor: widget.selectedColor,
        currentThickness: widget.selectedThickness,
        isHighlighter: widget.isHighlighter,
      ),
    );

    if (widget.isDrawingActive) {
      overlay = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          setState(() {
            final dx = details.localPosition.dx / widget.pageRect.width;
            final dy = details.localPosition.dy / widget.pageRect.height;
            _currentStrokePoints = [Offset(dx, dy)];
          });
        },
        onPanUpdate: (details) {
          setState(() {
            final dx = details.localPosition.dx / widget.pageRect.width;
            final dy = details.localPosition.dy / widget.pageRect.height;
            _currentStrokePoints.add(Offset(dx, dy));
          });
        },
        onPanEnd: (details) {
          if (_currentStrokePoints.isNotEmpty) {
            final newStroke = AnnotationStroke(
              pageNumber: widget.pageNumber,
              normalizedPoints: List.from(_currentStrokePoints),
              colorHex: '0x${widget.selectedColor.value.toRadixString(16)}',
              thickness: widget.selectedThickness,
              isHighlighter: widget.isHighlighter,
            );
            widget.onStrokeAdded(newStroke);
          }
          setState(() {
            _currentStrokePoints = [];
          });
        },
        child: overlay,
      );
      return RepaintBoundary(
        child: overlay,
      );
    }

    return IgnorePointer(
      child: RepaintBoundary(
        child: overlay,
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final List<AnnotationStroke> strokes;
  final List<Offset> currentStrokePoints;
  final Color currentColor;
  final double currentThickness;
  final bool isHighlighter;

  _OverlayPainter({
    required this.strokes,
    required this.currentStrokePoints,
    required this.currentColor,
    required this.currentThickness,
    required this.isHighlighter,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw saved page strokes
    for (final stroke in strokes) {
      if (stroke.normalizedPoints.length < 2) continue;
      final paint = Paint()
        ..color = stroke.isHighlighter 
            ? Color(int.parse(stroke.colorHex)).withOpacity(0.3)
            : Color(int.parse(stroke.colorHex))
        ..strokeWidth = stroke.thickness
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      final p0 = Offset(
        stroke.normalizedPoints[0].dx * size.width,
        stroke.normalizedPoints[0].dy * size.height,
      );
      path.moveTo(p0.dx, p0.dy);

      for (int i = 1; i < stroke.normalizedPoints.length; i++) {
        final p = Offset(
          stroke.normalizedPoints[i].dx * size.width,
          stroke.normalizedPoints[i].dy * size.height,
        );
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }

    // Draw current active stroke
    if (currentStrokePoints.length >= 2) {
      final paint = Paint()
        ..color = isHighlighter ? currentColor.withOpacity(0.3) : currentColor
        ..strokeWidth = currentThickness
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      final p0 = Offset(
        currentStrokePoints[0].dx * size.width,
        currentStrokePoints[0].dy * size.height,
      );
      path.moveTo(p0.dx, p0.dy);

      for (int i = 1; i < currentStrokePoints.length; i++) {
        final p = Offset(
          currentStrokePoints[i].dx * size.width,
          currentStrokePoints[i].dy * size.height,
        );
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) {
    return true;
  }
}
