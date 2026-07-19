import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' hide FileService;
import 'dart:io';
import 'dart:async';
import 'dart:convert';
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

class TtsSentence {
  final String text;
  final int start;
  final int end;

  TtsSentence({
    required this.text,
    required this.start,
    required this.end,
  });
}

class _MaterialViewerScreenState extends State<MaterialViewerScreen> {
  final FileService _fileService = FileService();
  bool _isLoading = true;
  String? _localPath;
  String? _htmlContent;
  bool _isPdf = false;
  bool _isImage = false;
  bool _isHtml = false;
  bool _isMultiImage = false;
  List<String> _multiImageLocalPaths = [];
  List<String> _multiImageUrls = [];
  final ScrollController _multiImageScrollController = ScrollController();
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
  // Read Aloud variables
  final FlutterTts _flutterTts = FlutterTts();
  bool _isPlaying = false;
  bool _isPaused = false;
  List<TtsSentence> _sentences = [];
  int _currentSentenceIndex = 0;
  int? _ttsPageNumber;
  PdfPageText? _ttsPageText;
  double _speechRate = 1.0; 
  double _speechPitch = 1.0; 
  String? _selectedVoiceName; 
  List<Map<String, String>> _availableVoices = [];
  bool _ttsInitialized = false;
  PdfDocument? _pdfDocument;
  Future<void>? _ttsInitFuture;

  // Notes variables
  List<DocumentNote> _notes = [];
  int? _highlightedPageNumber;
  Timer? _highlightTimer;

  Color _selectedPenColor = Colors.blue;
  double _selectedPenThickness = 4.0;

  Color _selectedHighlightColor = const Color(0xFFFFF066); // Yellow default
  double _selectedHighlightThickness = 20.0;

  String get _bookmarksKey => 'bookmarks_doc_${widget.title}';
  String get _annotationsKey => 'annotations_doc_${widget.title}';
  String get _notesKey => 'notes_doc_${widget.title}';

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

    final storedNotes = PersistenceService().getJson(_notesKey);
    if (storedNotes != null) {
      _notes = (storedNotes as List)
          .map((item) => DocumentNote.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    _isMultiImage = widget.fileUrl.startsWith('[') && widget.fileUrl.endsWith(']');
    _isPdf = !_isMultiImage && _fileService.isPdf(widget.fileUrl);
    _isImage = !_isMultiImage && _fileService.isImage(widget.fileUrl);
    _isHtml = !_isMultiImage && _fileService.isHtml(widget.fileUrl);
    
    // Continuously monitor scroll page changes from controller
    _pdfController.addListener(_onControllerChanged);

    // Start tracking reading time
    UsageService().startMaterialTracking(widget.title);

    _prepareFile();
    _initTts();
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
      if (_isMultiImage) {
        final List<dynamic> urls = jsonDecode(widget.fileUrl);
        final List<String> localPaths = [];
        for (final url in urls) {
          if (url is String && url.isNotEmpty) {
            final fileInfo = await DefaultCacheManager().getFileFromCache(url);
            File? file;
            if (fileInfo != null && await fileInfo.file.exists() && await fileInfo.file.length() > 0) {
              file = fileInfo.file;
            } else {
              file = await DefaultCacheManager().getSingleFile(url);
            }
            localPaths.add(file.path);
          }
        }
        _multiImageLocalPaths = localPaths;
        _multiImageUrls = List<String>.from(urls);

        // Restore progress
        final initialProgress = _progressNotifier.value;
        if (initialProgress > 0 && _multiImageUrls.isNotEmpty) {
          final targetPage = (initialProgress * _multiImageUrls.length).round().clamp(1, _multiImageUrls.length);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _goToMultiImagePage(targetPage);
          });
        }
      } else {
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
      }

      // If it's not a PDF, Image, HTML or MultiImage, open with system app
      if (!_isPdf && !_isImage && !_isHtml && !_isMultiImage) {
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
      ],
    );
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _highlightTimer?.cancel();
    _pdfController.removeListener(_onControllerChanged);
    UsageService().stopMaterialTracking();
    _flutterTts.stop();
    if (_isPdf || _isMultiImage) {
      try {
        final page = _currentPageNotifier.value;
        final totalPages = _totalPages;
        if (totalPages > 0) {
          final finalProgress = (page / totalPages).clamp(0.0, 1.0);
          ProgressService().updateProgress(widget.title, finalProgress);
        }
      } catch (e) {
        debugPrint('Error saving progress during dispose: $e');
      }
      if (_isPdf && _textSearcher != null) {
        _textSearcher!.removeListener(_onSearchUpdated);
        _textSearcher!.dispose();
      }
    }
    _searchController.dispose();
    _searchFocusNode.dispose();
    _progressNotifier.dispose();
    _currentPageNotifier.dispose();
    _bookmarksNotifier.dispose();
    _multiImageScrollController.dispose();
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

    return PopScope(
      canPop: !_isSearching && _activeAnnotationType == AnnotationType.none,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSearching) {
          _stopSearchMode();
        } else if (_activeAnnotationType != AnnotationType.none) {
          _exitDrawingMode();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF070716),
        appBar: AppBar(
          backgroundColor: const Color(0xFF141232),
          elevation: 0,
          automaticallyImplyLeading: !_isSearching,
          leading: _isSearching
              ? IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: _stopSearchMode,
                )
              : null,
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
      ),
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
        child: SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              GestureDetector(
                onTap: () => _showColorPickerSheet(!isPen),
                behavior: HitTestBehavior.translucent,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
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
                mainAxisSize: MainAxisSize.min,
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
            onTap: () => _showNotesBottomSheet(),
          ),
          buildToolbarItem(
            icon: Icons.volume_up_outlined,
            label: 'Read Aloud',
            onTap: _isPdf 
                ? _showReadAloudBottomSheet 
                : () => _showOnlyPdfSupportSnackbar('Read Aloud'),
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
          isAnonymous: matchedResource.isAnonymous,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Material details are not available.')),
      );
    }
  }

  int get _totalPages {
    if (_isPdf) {
      return _pdfController.isReady ? _pdfController.pageCount : 1;
    } else if (_isMultiImage) {
      return _multiImageUrls.length;
    }
    return 1;
  }

  void _goToMultiImagePage(int pageNumber) {
    if (pageNumber < 1 || pageNumber > _totalPages) return;
    final pageIndex = pageNumber - 1;
    final pageHeight = MediaQuery.of(context).size.width * 1.414;
    _multiImageScrollController.animateTo(
      pageIndex * pageHeight,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  Widget _buildImagePageOverlay(int pageNumber) {
    final pageHasNotes = _notes.any((n) => n.pageNumber == pageNumber);
    final isHighlighted = pageNumber == _highlightedPageNumber;

    return Stack(
      children: [
        if (isHighlighted)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            color: const Color(0xFF20C8FF).withOpacity(0.2),
          ),
        if (pageHasNotes)
          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _openNotesForPage(pageNumber);
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF20C8FF),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.sticky_note_2_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _scrollPage(bool isUp) {
    final currentPage = _currentPageNotifier.value;
    final pageCount = _totalPages;
    if (isUp) {
      if (currentPage > 1) {
        if (_isPdf) {
          _pdfController.goToPage(
            pageNumber: currentPage - 1,
            duration: const Duration(milliseconds: 250),
          );
        } else if (_isMultiImage) {
          _goToMultiImagePage(currentPage - 1);
        }
      }
    } else {
      if (currentPage < pageCount) {
        if (_isPdf) {
          _pdfController.goToPage(
            pageNumber: currentPage + 1,
            duration: const Duration(milliseconds: 250),
          );
        } else if (_isMultiImage) {
          _goToMultiImagePage(currentPage + 1);
        }
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
    if (page.pageNumber == _highlightedPageNumber) {
      canvas.drawRect(
        pageRect,
        Paint()
          ..color = const Color(0xFF20C8FF).withOpacity(0.2)
          ..style = PaintingStyle.fill,
      );
    }
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
    if (_isMultiImage) {
      final physics = _activeAnnotationType != AnnotationType.none
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
      return NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          final pageHeight = MediaQuery.of(context).size.width * 1.414;
          if (_multiImageScrollController.hasClients) {
            final offset = _multiImageScrollController.offset;
            final page = (offset / pageHeight).round() + 1;
            final clampedPage = page.clamp(1, _totalPages);
            if (clampedPage != _currentPageNotifier.value) {
              _currentPageNotifier.value = clampedPage;
              _progressNotifier.value = (clampedPage / _totalPages).clamp(0.0, 1.0);
            }
          }
          return false;
        },
        child: ListView.builder(
          controller: _multiImageScrollController,
          itemCount: _multiImageUrls.length,
          physics: physics,
          itemBuilder: (context, index) {
            final url = _multiImageUrls[index];
            final localPath = _multiImageLocalPaths.length > index ? _multiImageLocalPaths[index] : null;
            final pageHeight = MediaQuery.of(context).size.width * 1.414;
            final pageWidth = MediaQuery.of(context).size.width;

            return Container(
              width: pageWidth,
              height: pageHeight,
              margin: const EdgeInsets.only(bottom: 8),
              color: const Color(0xFF141232),
              child: Stack(
                children: [
                  InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 4.0,
                    child: Center(
                      child: localPath != null && File(localPath).existsSync()
                          ? Image.file(
                              File(localPath),
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 100, color: Colors.white24),
                            )
                          : CachedNetworkImage(
                              imageUrl: url,
                              fit: BoxFit.contain,
                              placeholder: (context, url) => const Center(
                                child: CircularProgressIndicator(color: Color(0xFF20C8FF)),
                              ),
                              errorWidget: (context, url, error) => const Icon(Icons.broken_image, size: 100, color: Colors.white24),
                            ),
                    ),
                  ),
                  Positioned.fill(
                    child: _buildImagePageOverlay(index + 1),
                  ),
                ],
              ),
            );
          },
        ),
      );
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
                  _pdfDocument = document;
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
                pageOverlaysBuilder: _buildPageOverlays,
              ),
            )
          : PdfViewer.uri(
              Uri.parse(widget.fileUrl),
              controller: _pdfController,
              params: PdfViewerParams(
                scrollPhysics: physics,
                onViewerReady: (document, controller) {
                  _pdfDocument = document;
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
                pageOverlaysBuilder: _buildPageOverlays,
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

  void _saveNotes() {
    final list = _notes.map((n) => n.toJson()).toList();
    PersistenceService().setJson(_notesKey, list);
  }

  void _openNotesForPage(int pageNumber) {
    _showNotesBottomSheet(filterPageNumber: pageNumber);
  }

  void _navigateToPageAndHighlight(int pageNumber) {
    if (!_pdfController.isReady) return;
    _pdfController.goToPage(
      pageNumber: pageNumber,
      duration: const Duration(milliseconds: 300),
    );
    setState(() {
      _highlightedPageNumber = pageNumber;
    });
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 1500), () {
      setState(() {
        _highlightedPageNumber = null;
      });
    });
  }

  void _confirmDeleteNote(DocumentNote note, {StateSetter? setSheetState}) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141232),
          title: const Text('Delete Note', style: TextStyle(color: Colors.white)),
          content: const Text('Are you sure you want to delete this note?', style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () {
                setState(() {
                  _notes.removeWhere((n) => n.id == note.id);
                });
                _saveNotes();
                if (setSheetState != null) {
                  setSheetState(() {});
                }
                Navigator.pop(context);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showNoteEditor({DocumentNote? noteToEdit, int? targetPageNumber, StateSetter? setSheetState}) {
    final isEdit = noteToEdit != null;
    final pageNum = targetPageNumber ?? _currentPageNotifier.value;
    
    final titleCtrl = TextEditingController(text: noteToEdit?.title ?? '');
    final bodyCtrl = TextEditingController(text: noteToEdit?.body ?? '');
    final titleFocus = FocusNode();
    final bodyFocus = FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      titleFocus.requestFocus();
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141232),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isEdit ? 'Edit Note (Page $pageNum)' : 'New Note (Page $pageNum)',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF20C8FF),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            final bodyText = bodyCtrl.text.trim();
                            if (bodyText.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Note body cannot be empty.')),
                              );
                              return;
                            }
                            final titleText = titleCtrl.text.trim();
                            
                            setState(() {
                              if (isEdit) {
                                noteToEdit.title = titleText;
                                noteToEdit.body = bodyText;
                                noteToEdit.timestamp = DateTime.now();
                              } else {
                                final newNote = DocumentNote(
                                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                                  documentId: widget.title,
                                  pageNumber: pageNum,
                                  timestamp: DateTime.now(),
                                  title: titleText,
                                  body: bodyText,
                                );
                                _notes.add(newNote);
                              }
                            });
                            _saveNotes();
                            if (setSheetState != null) {
                              setSheetState(() {});
                            }
                            Navigator.pop(context);
                          },
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleCtrl,
                  focusNode: titleFocus,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: 'Title (Optional)',
                    hintStyle: TextStyle(color: Colors.white38),
                    border: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF20C8FF)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: bodyCtrl,
                  focusNode: bodyFocus,
                  maxLines: null,
                  minLines: 5,
                  style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                  decoration: const InputDecoration(
                    hintText: 'Write your note here...',
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showNotesBottomSheet({int? filterPageNumber}) {
    String searchQuery = '';
    String sortType = 'Newest';
    final searchCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141232),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            List<DocumentNote> filteredNotes = _notes;
            if (filterPageNumber != null) {
              filteredNotes = filteredNotes.where((n) => n.pageNumber == filterPageNumber).toList();
            }
            if (searchQuery.isNotEmpty) {
              final q = searchQuery.toLowerCase();
              filteredNotes = filteredNotes.where((n) =>
                n.title.toLowerCase().contains(q) || n.body.toLowerCase().contains(q)
              ).toList();
            }
            
            if (sortType == 'Newest') {
              filteredNotes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            } else if (sortType == 'Oldest') {
              filteredNotes.sort((a, b) => a.timestamp.compareTo(b.timestamp));
            } else if (sortType == 'Page Number') {
              filteredNotes.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
            }

            final sheetHeight = MediaQuery.of(context).size.height * 0.7;

            return Container(
              height: sheetHeight,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      filterPageNumber != null ? 'Notes (Page $filterPageNumber)' : 'Notes',
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF20C8FF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        _showNoteEditor(
                          targetPageNumber: filterPageNumber ?? _currentPageNotifier.value,
                          setSheetState: setSheetState,
                        );
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('+ New Note', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: searchCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search notes...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 20),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) {
                      setSheetState(() {
                        searchQuery = val.trim();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text('Sort by: ', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(width: 8),
                        _buildSortChip('Newest', sortType, (selected) {
                          setSheetState(() => sortType = 'Newest');
                        }),
                        const SizedBox(width: 8),
                        _buildSortChip('Oldest', sortType, (selected) {
                          setSheetState(() => sortType = 'Oldest');
                        }),
                        if (filterPageNumber == null) ...[
                          const SizedBox(width: 8),
                          _buildSortChip('Page Number', sortType, (selected) {
                            setSheetState(() => sortType = 'Page Number');
                          }),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filteredNotes.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.note_alt_outlined, size: 48, color: Colors.white24),
                                const SizedBox(height: 12),
                                Text(
                                  searchQuery.isNotEmpty ? 'No matching notes found' : 'No notes created yet',
                                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredNotes.length,
                            itemBuilder: (context, index) {
                              final note = filteredNotes[index];
                              return Card(
                                color: const Color(0xFF1F1B46),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.all(12),
                                  title: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          note.title.isNotEmpty ? note.title : 'Untitled Note',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF20C8FF).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Page ${note.pageNumber}',
                                          style: const TextStyle(color: Color(0xFF20C8FF), fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(
                                        note.body,
                                        style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        DateFormat('MMM d, yyyy • h:mm a').format(note.timestamp),
                                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                                      ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, color: Colors.white54, size: 18),
                                        onPressed: () {
                                          _showNoteEditor(
                                            noteToEdit: note,
                                            setSheetState: setSheetState,
                                          );
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                        onPressed: () {
                                          _confirmDeleteNote(note, setSheetState: setSheetState);
                                        },
                                      ),
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _navigateToPageAndHighlight(note.pageNumber);
                                  },
                                ),
                              );
                            },
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

  Widget _buildSortChip(String label, String selectedType, Function(bool) onSelected) {
    final isSelected = selectedType == label;
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
      selected: isSelected,
      onSelected: onSelected,
      selectedColor: const Color(0xFF20C8FF),
      backgroundColor: Colors.white.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide.none,
      showCheckmark: false,
    );
  }

  Future<void> _initTts() {
    if (_ttsInitFuture != null) return _ttsInitFuture!;
    _ttsInitFuture = _doInitTts();
    return _ttsInitFuture!;
  }

  Future<void> _doInitTts() async {
    if (_ttsInitialized) return;
    
    final savedRate = PersistenceService().getDouble('tts_speech_rate');
    final savedPitch = PersistenceService().getDouble('tts_speech_pitch');
    _selectedVoiceName = PersistenceService().getString('tts_voice_name');
    
    if (savedRate != null) {
      _speechRate = savedRate;
    } else {
      _speechRate = 0.8;
      PersistenceService().setDouble('tts_speech_rate', 0.8);
    }
    
    if (savedPitch != null) {
      _speechPitch = savedPitch;
    } else {
      _speechPitch = 1.0;
      PersistenceService().setDouble('tts_speech_pitch', 1.0);
    }
    
    try {
      await _flutterTts.setSpeechRate(_speechRate);
      await _flutterTts.setPitch(_speechPitch);
    } catch (e) {
      debugPrint('Error configuring TTS: $e');
    }
    
    try {
      final voices = await _flutterTts.getVoices;
      if (voices != null) {
        _availableVoices = List<Map<dynamic, dynamic>>.from(voices as List)
            .map((v) => {
                  'name': v['name']?.toString() ?? '',
                  'locale': v['locale']?.toString() ?? '',
                })
            .where((v) => v['name']!.isNotEmpty)
            .toList();
            
        final friendlyVoices = _getFriendlyVoices();
        
        if (_selectedVoiceName != null) {
          final voiceExists = _availableVoices.any((v) => v['name'] == _selectedVoiceName);
          if (voiceExists) {
            final voice = _availableVoices.firstWhere((v) => v['name'] == _selectedVoiceName);
            await _flutterTts.setVoice(Map<String, String>.from(voice));
          }
        } else {
          final defaultVoice = _determineDefaultVoice(friendlyVoices);
          if (defaultVoice != null) {
            _selectedVoiceName = defaultVoice.rawName;
            PersistenceService().setString('tts_voice_name', defaultVoice.rawName);
            await _flutterTts.setVoice({
              'name': defaultVoice.rawName,
              'locale': defaultVoice.rawLocale,
            });
          }
        }
      } else if (widget.fileUrl == 'test_doc.pdf') {
        _availableVoices = [
          {'name': 'en-us-x-sfg-local', 'locale': 'en-US'},
          {'name': 'en-us-x-tpf-local', 'locale': 'en-US'},
          {'name': 'en-gb-x-rjs-local', 'locale': 'en-GB'},
          {'name': 'fr-fr-x-xyz-network', 'locale': 'fr-FR'},
        ];
        
        final friendlyVoices = _getFriendlyVoices();
        if (_selectedVoiceName == null) {
          final defaultVoice = _determineDefaultVoice(friendlyVoices);
          if (defaultVoice != null) {
            _selectedVoiceName = defaultVoice.rawName;
            PersistenceService().setString('tts_voice_name', defaultVoice.rawName);
            await _flutterTts.setVoice({
              'name': defaultVoice.rawName,
              'locale': defaultVoice.rawLocale,
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading TTS voices: $e');
      if (widget.fileUrl == 'test_doc.pdf') {
        _availableVoices = [
          {'name': 'en-us-x-sfg-local', 'locale': 'en-US'},
          {'name': 'en-us-x-tpf-local', 'locale': 'en-US'},
          {'name': 'en-gb-x-rjs-local', 'locale': 'en-GB'},
          {'name': 'fr-fr-x-xyz-network', 'locale': 'fr-FR'},
        ];
        
        final friendlyVoices = _getFriendlyVoices();
        if (_selectedVoiceName == null) {
          final defaultVoice = _determineDefaultVoice(friendlyVoices);
          if (defaultVoice != null) {
            _selectedVoiceName = defaultVoice.rawName;
            PersistenceService().setString('tts_voice_name', defaultVoice.rawName);
            await _flutterTts.setVoice({
              'name': defaultVoice.rawName,
              'locale': defaultVoice.rawLocale,
            });
          }
        }
      }
    }
    
    try {
      _flutterTts.setCompletionHandler(() {
        _onSentenceCompleted();
      });
      
      _flutterTts.setErrorHandler((msg) {
        debugPrint('TTS Error: $msg');
        setState(() {
          _isPlaying = false;
          _isPaused = false;
        });
      });
    } catch (e) {
      debugPrint('Error setting TTS handlers: $e');
    }
    
    _ttsInitialized = true;
    if (mounted) {
      setState(() {});
    }
  }

  List<TtsSentence> _splitIntoTtsSentences(String text) {
    final RegExp sentenceRegExp = RegExp(r'[^.!?]+[.!?]*');
    final List<TtsSentence> list = [];
    for (final match in sentenceRegExp.allMatches(text)) {
      final sentenceText = match.group(0)!;
      final trimmed = sentenceText.trim();
      if (trimmed.isNotEmpty) {
        final startOffset = sentenceText.indexOf(trimmed);
        final start = match.start + startOffset;
        final end = start + trimmed.length;
        list.add(TtsSentence(text: trimmed, start: start, end: end));
      }
    }
    return list;
  }

  void _startPlayback() {
    if (_isPaused) {
      setState(() {
        _isPlaying = true;
        _isPaused = false;
      });
      if (_sentences.isNotEmpty && _currentSentenceIndex < _sentences.length) {
        final sentence = _sentences[_currentSentenceIndex].text;
        try {
          _flutterTts.speak(sentence);
        } catch (e) {
          debugPrint('Error resuming TTS: $e');
        }
      }
      return;
    }
    
    final pageNum = _currentPageNotifier.value;
    _ttsPageNumber = pageNum;
    
    String pageTextStr = '';
    if (_pdfDocument != null) {
      try {
        final page = _pdfDocument!.pages[pageNum - 1];
        page.loadStructuredText().then((textObj) {
          _ttsPageText = textObj;
          pageTextStr = textObj.fullText;
          _sentences = _splitIntoTtsSentences(pageTextStr);
          if (_sentences.isEmpty) {
            setState(() {
              _isPlaying = false;
              _isPaused = false;
            });
            return;
          }
          setState(() {
            _isPlaying = true;
            _isPaused = false;
            _currentSentenceIndex = 0;
          });
          final sentence = _sentences[0].text;
          try {
            _flutterTts.speak(sentence);
          } catch (e) {
            debugPrint('Error starting TTS: $e');
          }
        }).catchError((e) {
          debugPrint('Error loading page text: $e');
          _handleNoText(pageNum);
        });
      } catch (e) {
        debugPrint('Error loading page text: $e');
        _handleNoText(pageNum);
      }
      return;
    } else if (widget.fileUrl == 'test_doc.pdf') {
      pageTextStr = 'Mock PDF page text for testing.';
    }
    
    if (pageTextStr.isEmpty) {
      _handleNoText(pageNum);
      return;
    }
    
    _sentences = _splitIntoTtsSentences(pageTextStr);
    if (_sentences.isEmpty) {
      setState(() {
        _isPlaying = false;
        _isPaused = false;
      });
      return;
    }
    
    setState(() {
      _isPlaying = true;
      _isPaused = false;
      _currentSentenceIndex = 0;
    });
    
    final sentence = _sentences[0].text;
    try {
      _flutterTts.speak(sentence);
    } catch (e) {
      debugPrint('Error starting TTS: $e');
    }
  }

  void _handleNoText(int pageNum) {
    setState(() {
      _isPlaying = false;
      _isPaused = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Read Aloud is unavailable for Page $pageNum (no selectable text).'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _onSentenceCompleted() {
    if (!mounted || !_isPlaying) return;
    
    setState(() {
      _currentSentenceIndex++;
    });
    
    if (_currentSentenceIndex < _sentences.length) {
      final sentence = _sentences[_currentSentenceIndex].text;
      try {
        _flutterTts.speak(sentence);
      } catch (e) {
        debugPrint('Error speaking sentence: $e');
      }
    } else {
      _stopPlayback();
    }
  }

  void _pausePlayback() {
    try {
      _flutterTts.pause();
    } catch (e) {
      debugPrint('Error pausing TTS: $e');
    }
    setState(() {
      _isPlaying = false;
      _isPaused = true;
    });
  }
  
  void _stopPlayback() {
    try {
      _flutterTts.stop();
    } catch (e) {
      debugPrint('Error stopping TTS: $e');
    }
    setState(() {
      _isPlaying = false;
      _isPaused = false;
      _currentSentenceIndex = 0;
      _sentences = [];
      _ttsPageNumber = null;
      _ttsPageText = null;
    });
  }

  List<Widget> _buildPageOverlays(BuildContext context, Rect pageRect, PdfPage page) {
    final pageHasNotes = _notes.any((n) => n.pageNumber == page.pageNumber);
    final isDrawing = _activeAnnotationType != AnnotationType.none;
    final isTtsActive = (_isPlaying || _isPaused) && page.pageNumber == _ttsPageNumber;

    if (!isDrawing && !pageHasNotes && !isTtsActive) {
      return const [];
    }

    return [
      if (isTtsActive && _sentences.isNotEmpty && _currentSentenceIndex < _sentences.length)
        TtsHighlightOverlay(
          page: page,
          pageRect: pageRect,
          pageText: _ttsPageText,
          sentence: _sentences[_currentSentenceIndex],
        ),
      if (isDrawing)
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
      if (pageHasNotes)
        Positioned(
          top: 6,
          right: 6,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _openNotesForPage(page.pageNumber);
            },
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(
                color: Color(0xFF20C8FF),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.sticky_note_2_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ),
    ];
  }

  void _goToPageTts(int pageNum) {
    if (pageNum < 1 || pageNum > _totalPages) return;
    
    final wasPlaying = _isPlaying;
    _stopPlayback();
    
    if (_isPdf) {
      if (!_pdfController.isReady) return;
      _pdfController.goToPage(
        pageNumber: pageNum,
        duration: const Duration(milliseconds: 300),
      );
    } else if (_isMultiImage) {
      _goToMultiImagePage(pageNum);
    }
    
    if (wasPlaying) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _startPlayback();
      });
    }
  }

  void _showReadAloudBottomSheet() {
    if (!_isPdf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Read Aloud is only available for PDF documents.')),
      );
      return;
    }
    
    final initFuture = _initTts();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141232),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return ValueListenableBuilder<int>(
              valueListenable: _currentPageNotifier,
              builder: (context, currentPage, child) {
                final totalPages = _pdfController.isReady ? _pdfController.pageCount : 1;
                
                return Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 20,
                    bottom: MediaQuery.of(context).padding.bottom + 24,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Read Aloud',
                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Page $currentPage of $totalPages',
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 36),
                            onPressed: currentPage > 1
                                ? () {
                                    _goToPageTts(currentPage - 1);
                                    setSheetState(() {});
                                  }
                                : null,
                          ),
                          const SizedBox(width: 16),
                          GestureDetector(
                            onTap: () {
                              if (_isPlaying) {
                                _pausePlayback();
                              } else {
                                _startPlayback();
                              }
                              setSheetState(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                color: Color(0xFF20C8FF),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            icon: const Icon(Icons.stop_rounded, color: Colors.white, size: 36),
                            onPressed: _isPlaying || _isPaused
                                ? () {
                                    _stopPlayback();
                                    setSheetState(() {});
                                  }
                                : null,
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 36),
                            onPressed: currentPage < totalPages
                                ? () {
                                    _goToPageTts(currentPage + 1);
                                    setSheetState(() {});
                                  }
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          const Icon(Icons.speed, color: Colors.white70, size: 20),
                          const SizedBox(width: 12),
                          const Text('Speed', style: TextStyle(color: Colors.white70, fontSize: 14)),
                          Expanded(
                            child: Slider(
                              value: _speechRate,
                              min: 0.5,
                              max: 2.0,
                              divisions: 6,
                              label: '${_speechRate}x',
                              activeColor: const Color(0xFF20C8FF),
                              inactiveColor: Colors.white24,
                              onChanged: (val) async {
                                setState(() {
                                  _speechRate = val;
                                });
                                setSheetState(() {});
                                try {
                                  await _flutterTts.setSpeechRate(val);
                                } catch (e) {
                                  debugPrint('Error setting speech rate: $e');
                                }
                                PersistenceService().setDouble('tts_speech_rate', val);
                              },
                            ),
                          ),
                          Text(
                            '${_speechRate.toStringAsFixed(1)}x',
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Icon(Icons.hearing, color: Colors.white70, size: 20),
                          const SizedBox(width: 12),
                          const Text('Pitch', style: TextStyle(color: Colors.white70, fontSize: 14)),
                          Expanded(
                            child: Slider(
                              value: _speechPitch,
                              min: 0.5,
                              max: 2.0,
                              divisions: 6,
                              label: _speechPitch.toStringAsFixed(1),
                              activeColor: const Color(0xFF20C8FF),
                              inactiveColor: Colors.white24,
                              onChanged: (val) async {
                                setState(() {
                                  _speechPitch = val;
                                });
                                setSheetState(() {});
                                try {
                                  await _flutterTts.setPitch(val);
                                } catch (e) {
                                  debugPrint('Error setting pitch: $e');
                                }
                                PersistenceService().setDouble('tts_speech_pitch', val);
                              },
                            ),
                          ),
                          Text(
                            _speechPitch.toStringAsFixed(1),
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      FutureBuilder<void>(
                        future: initFuture,
                        builder: (context, snapshot) {
                          if (_availableVoices.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: () {
                                  _showVoiceSelectionBottomSheet(setSheetState);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.record_voice_over_rounded, color: Colors.white70, size: 20),
                                      const SizedBox(width: 12),
                                      const Text('Voice', style: TextStyle(color: Colors.white70, fontSize: 14)),
                                      const Spacer(),
                                      Text(
                                        _getCurrentVoiceFriendlyName(),
                                        style: const TextStyle(color: Color(0xFF20C8FF), fontSize: 14, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white30, size: 14),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Card(
                                elevation: 0,
                                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.08),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                    width: 1,
                                  ),
                                ),
                                margin: EdgeInsets.zero,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '💡',
                                        style: TextStyle(fontSize: 14),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: RichText(
                                          text: TextSpan(
                                            style: const TextStyle(
                                              fontSize: 12,
                                              height: 1.4,
                                              color: Colors.white70,
                                            ),
                                            children: const [
                                              TextSpan(
                                                text: 'Best experience:\n',
                                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                              ),
                                              TextSpan(
                                                text: 'Use an Online voice for the highest quality and most natural speech.',
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _getLanguageName(String langCode) {
    switch (langCode.toLowerCase()) {
      case 'en': return 'English';
      case 'es': return 'Spanish';
      case 'fr': return 'French';
      case 'de': return 'German';
      case 'it': return 'Italian';
      case 'ja': return 'Japanese';
      case 'zh': return 'Chinese';
      case 'pt': return 'Portuguese';
      case 'ru': return 'Russian';
      case 'ko': return 'Korean';
      case 'ar': return 'Arabic';
      case 'nl': return 'Dutch';
      case 'hi': return 'Hindi';
      case 'tr': return 'Turkish';
      case 'sv': return 'Swedish';
      case 'pl': return 'Polish';
      case 'vi': return 'Vietnamese';
      default: return langCode.toUpperCase();
    }
  }

  String _getCountryName(String countryCode) {
    switch (countryCode.toUpperCase()) {
      case 'US': return 'US';
      case 'GB': return 'UK';
      case 'UK': return 'UK';
      case 'AU': return 'Australia';
      case 'CA': return 'Canada';
      case 'IN': return 'India';
      case 'ES': return 'Spain';
      case 'FR': return 'France';
      case 'DE': return 'Germany';
      case 'IT': return 'Italy';
      case 'JP': return 'Japan';
      case 'CN': return 'China';
      case 'TW': return 'Taiwan';
      case 'BR': return 'Brazil';
      case 'PT': return 'Portugal';
      case 'RU': return 'Russia';
      case 'KR': return 'South Korea';
      case 'MX': return 'Mexico';
      case 'ZA': return 'South Africa';
      case 'NZ': return 'New Zealand';
      case 'SG': return 'Singapore';
      case 'HK': return 'Hong Kong';
      default: return countryCode.toUpperCase();
    }
  }

  List<FriendlyVoice> _getFriendlyVoices() {
    final List<FriendlyVoice> list = [];
    final Map<String, List<Map<String, String>>> baseGroups = {};
    
    for (final voice in _availableVoices) {
      final name = voice['name'] ?? '';
      final locale = voice['locale'] ?? '';
      if (name.isEmpty || locale.isEmpty) continue;
      
      final parts = locale.split(RegExp(r'[-_]'));
      final langCode = parts[0];
      final countryCode = parts.length > 1 ? parts[1] : '';
      
      final langName = _getLanguageName(langCode);
      final countryName = countryCode.isNotEmpty ? _getCountryName(countryCode) : '';
      final baseFriendlyName = countryName.isNotEmpty ? '$langName ($countryName)' : langName;
      
      baseGroups.putIfAbsent(baseFriendlyName, () => []).add(voice.cast<String, String>());
    }
    
    baseGroups.forEach((baseFriendlyName, voices) {
      voices.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
      
      final hasMultiple = voices.length > 1;
      for (int i = 0; i < voices.length; i++) {
        final voice = voices[i];
        final name = voice['name'] ?? '';
        final locale = voice['locale'] ?? '';
        
        final parts = locale.split(RegExp(r'[-_]'));
        final langCode = parts[0];
        final countryCode = parts.length > 1 ? parts[1] : '';
        final langName = _getLanguageName(langCode);
        final countryName = countryCode.isNotEmpty ? _getCountryName(countryCode) : '';
        
        final isOnline = name.toLowerCase().contains('network') ||
                         name.toLowerCase().contains('online') ||
                         name.toLowerCase().contains('neural') ||
                         name.toLowerCase().contains('premium');
        final displayName = hasMultiple ? '$baseFriendlyName Voice ${i + 1}' : baseFriendlyName;
        
        list.add(FriendlyVoice(
          rawName: name,
          rawLocale: locale,
          languageName: langName,
          displayName: displayName,
          isOnline: isOnline,
          countryName: countryName,
        ));
      }
    });
    
    list.sort((a, b) {
      final langCompare = a.languageName.compareTo(b.languageName);
      if (langCompare != 0) return langCompare;
      return a.displayName.compareTo(b.displayName);
    });
    
    return list;
  }

  String _getCurrentVoiceFriendlyName() {
    if (_selectedVoiceName == null) return 'Default Voice';
    
    final friendlyVoices = _getFriendlyVoices();
    final match = friendlyVoices.firstWhere(
      (v) => v.rawName == _selectedVoiceName,
      orElse: () => FriendlyVoice(
        rawName: _selectedVoiceName!,
        rawLocale: '',
        languageName: '',
        displayName: 'Custom Voice',
        isOnline: false,
        countryName: '',
      ),
    );
    return match.displayName;
  }

  int _getEnglishCountryPriority(String locale) {
    final parts = locale.split(RegExp(r'[-_]'));
    final country = parts.length > 1 ? parts[1].toUpperCase() : '';
    switch (country) {
      case 'US': return 1;
      case 'GB':
      case 'UK': return 2;
      case 'AU': return 3;
      case 'CA': return 4;
      case 'IN': return 5;
      default: return 6;
    }
  }

  bool _isHighQuality(String rawName) {
    final lower = rawName.toLowerCase();
    return lower.contains('online') ||
        lower.contains('neural') ||
        lower.contains('premium') ||
        lower.contains('network');
  }

  int _getQualityScore(FriendlyVoice v) {
    final name = v.rawName.toLowerCase();
    
    final isNeural = name.contains('neural');
    final isOnline = name.contains('online') || name.contains('network') || v.isOnline;
    final isPremium = name.contains('premium') || name.contains('enhanced');
    final isNetwork = name.contains('network');
    
    if (isOnline && isNeural) return 5;
    if (isOnline) return 4;
    if (isPremium) return 3;
    if (isNetwork) return 2;
    return 1; // Offline
  }

  int _scoreVoiceForDefault(FriendlyVoice v) {
    final parts = v.rawLocale.split(RegExp(r'[-_]'));
    final lang = parts[0].toLowerCase();
    final country = parts.length > 1 ? parts[1].toUpperCase() : '';
    
    final isEnglish = lang == 'en';
    
    if (isEnglish) {
      int countryScore;
      if (country == 'US') {
        countryScore = 60;
      } else if (country == 'GB' || country == 'UK') {
        countryScore = 50;
      } else if (country == 'AU') {
        countryScore = 40;
      } else if (country == 'CA') {
        countryScore = 30;
      } else if (country == 'IN') {
        countryScore = 20;
      } else {
        countryScore = 10;
      }
      return countryScore * 10 + _getQualityScore(v);
    } else {
      // Non-English voice
      return _getQualityScore(v);
    }
  }

  FriendlyVoice? _determineDefaultVoice(List<FriendlyVoice> friendlyVoices) {
    if (friendlyVoices.isEmpty) return null;

    final List<FriendlyVoice> sorted = List.from(friendlyVoices);
    sorted.sort((a, b) {
      final scoreA = _scoreVoiceForDefault(a);
      final scoreB = _scoreVoiceForDefault(b);
      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA); // Highest score first
      }
      return a.displayName.compareTo(b.displayName); // Alphabetical fallback
    });

    return sorted.first;
  }

  Map<String, List<FriendlyVoice>> _getGroupedAndSortedVoices(List<FriendlyVoice> voices) {
    final List<FriendlyVoice> englishVoices = voices.where((v) => v.languageName == 'English').toList();
    final List<FriendlyVoice> otherVoices = voices.where((v) => v.languageName != 'English').toList();

    englishVoices.sort((a, b) {
      final priorityA = _getEnglishCountryPriority(a.rawLocale);
      final priorityB = _getEnglishCountryPriority(b.rawLocale);
      if (priorityA != priorityB) return priorityA.compareTo(priorityB);

      final highA = _isHighQuality(a.rawName);
      final highB = _isHighQuality(b.rawName);
      if (highA != highB) return highA ? -1 : 1;

      return a.displayName.compareTo(b.displayName);
    });

    if (englishVoices.isNotEmpty && _selectedVoiceName != null) {
      final selectedIndex = englishVoices.indexWhere((v) => v.rawName == _selectedVoiceName);
      if (selectedIndex != -1) {
        final selectedVoice = englishVoices.removeAt(selectedIndex);
        englishVoices.insert(0, selectedVoice);
      }
    }

    final Map<String, List<FriendlyVoice>> otherGroups = {};
    for (final v in otherVoices) {
      otherGroups.putIfAbsent(v.languageName, () => []).add(v);
    }

    otherGroups.forEach((lang, list) {
      list.sort((a, b) => a.displayName.compareTo(b.displayName));
      if (_selectedVoiceName != null) {
        final selectedIndex = list.indexWhere((v) => v.rawName == _selectedVoiceName);
        if (selectedIndex != -1) {
          final selectedVoice = list.removeAt(selectedIndex);
          list.insert(0, selectedVoice);
        }
      }
    });

    final sortedOtherLanguages = otherGroups.keys.toList()..sort();

    final Map<String, List<FriendlyVoice>> finalGroups = {};
    if (englishVoices.isNotEmpty) {
      finalGroups['English Voices (Recommended)'] = englishVoices;
    }
    for (final lang in sortedOtherLanguages) {
      finalGroups[lang] = otherGroups[lang]!;
    }

    return finalGroups;
  }

  List<String> _getQualityChips(FriendlyVoice voice) {
    final List<String> chips = [];
    final nameLower = voice.rawName.toLowerCase();
    
    if (nameLower.contains('online') || voice.isOnline) {
      chips.add('Online');
    }
    if (nameLower.contains('neural')) {
      chips.add('Neural');
    }
    if (nameLower.contains('premium') || nameLower.contains('enhanced')) {
      chips.add('Premium');
    }
    if (nameLower.contains('network')) {
      chips.add('Network');
    }
    
    if (chips.isEmpty) {
      chips.add('Offline');
    }
    return chips;
  }

  Widget _buildQualityChip(String label, BuildContext context) {
    final isOnlineOrNeural = label == 'Online' || label == 'Neural' || label == 'Premium' || label == 'Network';
    final themeColor = isOnlineOrNeural ? const Color(0xFF20C8FF) : Colors.white60;
    
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: themeColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: themeColor.withOpacity(0.25),
          width: 0.8,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: themeColor,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _getFullLocaleName(FriendlyVoice voice) {
    final parts = voice.rawLocale.split(RegExp(r'[-_]'));
    final country = parts.length > 1 ? parts[1].toUpperCase() : '';
    
    String countryFull = '';
    switch (country) {
      case 'US': countryFull = 'United States'; break;
      case 'GB':
      case 'UK': countryFull = 'United Kingdom'; break;
      case 'AU': countryFull = 'Australia'; break;
      case 'CA': countryFull = 'Canada'; break;
      case 'IN': countryFull = 'India'; break;
      case 'FR': countryFull = 'France'; break;
      case 'DE': countryFull = 'Germany'; break;
      case 'ES': countryFull = 'Spain'; break;
      case 'IT': countryFull = 'Italy'; break;
      case 'JP': countryFull = 'Japan'; break;
      case 'CN': countryFull = 'China'; break;
      case 'TW': countryFull = 'Taiwan'; break;
      case 'BR': countryFull = 'Brazil'; break;
      case 'PT': countryFull = 'Portugal'; break;
      case 'RU': countryFull = 'Russia'; break;
      case 'KR': countryFull = 'South Korea'; break;
      case 'MX': countryFull = 'Mexico'; break;
      case 'ZA': countryFull = 'South Africa'; break;
      case 'NZ': countryFull = 'New Zealand'; break;
      case 'SG': countryFull = 'Singapore'; break;
      case 'HK': countryFull = 'Hong Kong'; break;
      default: countryFull = voice.countryName; break;
    }
    
    if (countryFull.isNotEmpty) {
      return '${voice.languageName} ($countryFull)';
    }
    return voice.languageName;
  }

  void _showVoiceSelectionBottomSheet(StateSetter parentSetState) {
    final friendlyVoices = _getFriendlyVoices();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141232),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        String searchQuery = '';
        final searchController = TextEditingController();

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final query = searchQuery.trim().toLowerCase();
            final filteredVoices = friendlyVoices.where((v) {
              if (query.isEmpty) return true;
              
              final nameMatch = v.displayName.toLowerCase().contains(query) || v.rawName.toLowerCase().contains(query);
              final langMatch = v.languageName.toLowerCase().contains(query) || _getFullLocaleName(v).toLowerCase().contains(query);
              final localeMatch = v.rawLocale.toLowerCase().contains(query);
              final countryMatch = v.countryName.toLowerCase().contains(query);
              
              bool keywordMatch = false;
              final chips = _getQualityChips(v).map((c) => c.toLowerCase()).toList();
              if (query == 'online' || query == 'offline' || query == 'neural' || query == 'premium' || query == 'network') {
                keywordMatch = chips.contains(query);
              } else {
                keywordMatch = chips.any((c) => c.contains(query));
              }
              
              return nameMatch || langMatch || localeMatch || countryMatch || keywordMatch;
            }).toList();

            final groupedAndSorted = _getGroupedAndSortedVoices(filteredVoices);

            final List<VoiceSheetItem> flatItems = [];
            groupedAndSorted.forEach((lang, voicesList) {
              flatItems.add(VoiceHeaderItem(lang));
              for (final voice in voicesList) {
                flatItems.add(VoiceRowItem(voice));
              }
              flatItems.add(VoiceSeparatorItem());
            });

            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Select Voice',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white70),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: TextField(
                        controller: searchController,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        cursorColor: const Color(0xFF20C8FF),
                        decoration: InputDecoration(
                          hintText: 'Search voice, language, or country...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
                          suffixIcon: searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, color: Colors.white54),
                                  onPressed: () {
                                    searchController.clear();
                                    setSheetState(() {
                                      searchQuery = '';
                                    });
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.06),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: const BorderSide(color: Color(0xFF20C8FF), width: 1.5),
                          ),
                        ),
                        onChanged: (value) {
                          setSheetState(() {
                            searchQuery = value;
                          });
                        },
                      ),
                    ),
                    const Divider(color: Colors.white10, height: 1),
                    Expanded(
                      child: flatItems.isEmpty
                          ? const Center(
                              child: Text(
                                'No matching voices found.',
                                style: TextStyle(color: Colors.white70, fontSize: 16),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: flatItems.length,
                              itemBuilder: (context, index) {
                                final item = flatItems[index];
                                if (item is VoiceHeaderItem) {
                                  return Padding(
                                    padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
                                    child: Text(
                                      item.title,
                                      style: const TextStyle(
                                        color: Color(0xFF20C8FF),
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  );
                                } else if (item is VoiceRowItem) {
                                  final voice = item.voice;
                                  final isSelected = _selectedVoiceName == voice.rawName;
                                  final chips = _getQualityChips(voice);
                                  
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            voice.displayName,
                                            style: TextStyle(
                                              color: isSelected ? Colors.white : Colors.white70,
                                              fontSize: 15,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: chips.map((chip) => _buildQualityChip(chip, context)).toList(),
                                        ),
                                        const SizedBox(width: 8),
                                        if (isSelected)
                                          const Icon(Icons.check_rounded, color: Color(0xFF20C8FF), size: 18),
                                      ],
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        _getFullLocaleName(voice),
                                        style: TextStyle(
                                          color: isSelected ? Colors.white54 : Colors.white38,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    onTap: () async {
                                      setState(() {
                                        _selectedVoiceName = voice.rawName;
                                      });
                                      parentSetState(() {});
                                      try {
                                        await _flutterTts.setVoice({
                                          'name': voice.rawName,
                                          'locale': voice.rawLocale,
                                        });
                                        if (!_isPlaying) {
                                          await _flutterTts.speak("This is a preview of the selected voice.");
                                        }
                                      } catch (e) {
                                        debugPrint('Error setting voice: $e');
                                      }
                                      PersistenceService().setString('tts_voice_name', voice.rawName);
                                      if (context.mounted) {
                                        Navigator.pop(context);
                                      }
                                    },
                                  );
                                } else {
                                  return const Column(
                                    children: [
                                      SizedBox(height: 8),
                                      Divider(color: Colors.white10, height: 1),
                                    ],
                                  );
                                }
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class FriendlyVoice {
  final String rawName;
  final String rawLocale;
  final String languageName;
  final String displayName;
  final bool isOnline;
  final String countryName;
  
  FriendlyVoice({
    required this.rawName,
    required this.rawLocale,
    required this.languageName,
    required this.displayName,
    required this.isOnline,
    required this.countryName,
  });
}

abstract class VoiceSheetItem {}

class VoiceHeaderItem extends VoiceSheetItem {
  final String title;
  VoiceHeaderItem(this.title);
}

class VoiceRowItem extends VoiceSheetItem {
  final FriendlyVoice voice;
  VoiceRowItem(this.voice);
}

class VoiceSeparatorItem extends VoiceSheetItem {}

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

class DocumentNote {
  final String id;
  final String documentId;
  final int pageNumber;
  DateTime timestamp;
  String title;
  String body;

  DocumentNote({
    required this.id,
    required this.documentId,
    required this.pageNumber,
    required this.timestamp,
    required this.title,
    required this.body,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'documentId': documentId,
    'pageNumber': pageNumber,
    'timestamp': timestamp.toIso8601String(),
    'title': title,
    'body': body,
  };

  factory DocumentNote.fromJson(Map<String, dynamic> json) {
    return DocumentNote(
      id: json['id'] as String,
      documentId: json['documentId'] as String,
      pageNumber: json['pageNumber'] as int,
      timestamp: DateTime.parse(json['timestamp'] as String),
      title: json['title'] as String,
      body: json['body'] as String,
    );
  }
}

class TtsHighlightOverlay extends StatefulWidget {
  final PdfPage page;
  final Rect pageRect;
  final PdfPageText? pageText;
  final TtsSentence sentence;

  const TtsHighlightOverlay({
    Key? key,
    required this.page,
    required this.pageRect,
    required this.pageText,
    required this.sentence,
  }) : super(key: key);

  @override
  State<TtsHighlightOverlay> createState() => _TtsHighlightOverlayState();
}

class _TtsHighlightOverlayState extends State<TtsHighlightOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  TtsSentence? _prevSentence;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward(from: 0.0);
    _prevSentence = widget.sentence;
  }

  @override
  void didUpdateWidget(covariant TtsHighlightOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sentence.start != widget.sentence.start ||
        oldWidget.sentence.end != widget.sentence.end) {
      _prevSentence = oldWidget.sentence;
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pageText == null) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return CustomPaint(
          size: widget.pageRect.size,
          painter: _TtsHighlightPainter(
            page: widget.page,
            pageRect: widget.pageRect,
            pageText: widget.pageText!,
            currentSentence: widget.sentence,
            prevSentence: _prevSentence,
            progress: _animation.value,
          ),
        );
      },
    );
  }
}

class _TtsHighlightPainter extends CustomPainter {
  final PdfPage page;
  final Rect pageRect;
  final PdfPageText pageText;
  final TtsSentence currentSentence;
  final TtsSentence? prevSentence;
  final double progress;

  _TtsHighlightPainter({
    required this.page,
    required this.pageRect,
    required this.pageText,
    required this.currentSentence,
    this.prevSentence,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const softBlue = Color(0xFF20C8FF);
    
    if (prevSentence != null && prevSentence!.start != currentSentence.start) {
      final opacity = 0.15 * (1.0 - progress);
      if (opacity > 0.01) {
        final paint = Paint()
          ..color = softBlue.withOpacity(opacity)
          ..style = PaintingStyle.fill;
        _drawSentenceHighlight(canvas, prevSentence!, paint);
      }
    }

    final currentOpacity = 0.15 * progress;
    if (currentOpacity > 0.01) {
      final paint = Paint()
        ..color = softBlue.withOpacity(currentOpacity)
        ..style = PaintingStyle.fill;
      _drawSentenceHighlight(canvas, currentSentence, paint);
    }
  }

  void _drawSentenceHighlight(Canvas canvas, TtsSentence sentence, Paint paint) {
    try {
      final range = PdfPageTextRange(
        pageText: pageText,
        start: sentence.start,
        end: sentence.end,
      );
      final fragmentRects = range.enumerateFragmentBoundingRects();
      for (final fragmentRect in fragmentRects) {
        final pdfRect = fragmentRect.bounds;
        final rect = pdfRect.toRect(page: page, scaledPageSize: pageRect.size);
        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
        canvas.drawRRect(rrect, paint);
      }
    } catch (e) {
      debugPrint('Error painting TTS highlight: $e');
    }
  }

  @override
  bool shouldRepaint(covariant _TtsHighlightPainter oldDelegate) {
    return oldDelegate.currentSentence.start != currentSentence.start ||
        oldDelegate.currentSentence.end != currentSentence.end ||
        oldDelegate.progress != progress ||
        oldDelegate.pageRect.size != pageRect.size;
  }
}
