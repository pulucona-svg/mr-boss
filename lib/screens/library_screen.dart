import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/category_chip.dart';
import '../widgets/resource_card.dart';
import '../services/download_service.dart';
import '../services/resource_service.dart';
import '../widgets/filter_modal.dart';
import '../services/notification_service.dart';
import '../widgets/notification_modal.dart';
import '../widgets/ad_carousel.dart';
import '../widgets/upload_bottom_sheet.dart';
import '../widgets/draggable_fab.dart';
import '../widgets/skeleton.dart';
import '../widgets/search_dropdown.dart';
import '../providers/theme_provider.dart';
import '../providers/chat_provider.dart';
import 'help_support_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  final bool initialShowUploads;
  const LibraryScreen({super.key, this.initialShowUploads = false});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  static bool _hasLoadedBefore = false;
  String _selectedCategory = 'All';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  Map<String, String> _activeFilters = {};
  late bool _isDownloadsSelected;
  bool _isUploadSheetOpen = false;
  late bool _isLoading;
  String? _lastCorrectedOriginal;
  String? _lastCorrectedResult;
  String _lastSearchValue = '';

  @override
  void initState() {
    super.initState();
    _isDownloadsSelected = !widget.initialShowUploads;
    _isLoading = !_hasLoadedBefore;
    if (_isLoading) {
      _simulateLoading();
    }
    _searchFocusNode.addListener(_onSearchFocusChange);
  }

  int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.generate(t.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        int cost = (s[i] == t[j]) ? 0 : 1;
        v1[j + 1] = [v1[j] + 1, v0[j + 1] + 1, v0[j] + cost].reduce((a, b) => a < b ? a : b);
      }
      for (int j = 0; j < t.length + 1; j++) v0[j] = v1[j];
    }
    return v1[t.length];
  }

  Set<String> _getDictionary() {
    final resources = ResourceService().allResources;
    final dictionary = <String>{};
    for (var res in resources) {
      final codeParts = res.unitCode.split(' ');
      for (var p in codeParts) {
        if (!RegExp(r'^\d+$').hasMatch(p)) dictionary.add(p);
      }
      final nameParts = res.unitName.split(' ');
      for (var p in nameParts) {
        if (p.length > 3) dictionary.add(p);
      }
      for (var l in res.lecturers) {
        final lectParts = l.split(' ');
        for (var p in lectParts) {
          if (p.length > 3) dictionary.add(p);
        }
      }
      dictionary.addAll(['Notes', 'CATs', 'Exams', 'Timetable', 'Manual', 'Supplementary']);
    }
    return dictionary;
  }

  void _handleAutocorrect(String value) {
    if (!value.endsWith(' ')) return;
    
    final words = value.trim().split(RegExp(r'\s+'));
    if (words.isEmpty) return;

    final lastWord = words.last;
    if (lastWord.length < 3 || RegExp(r'^\d+$').hasMatch(lastWord)) return;

    final dictionary = _getDictionary();
    String? bestMatch;
    int minDistance = 2;

    for (var entry in dictionary) {
      final distance = _levenshtein(lastWord.toLowerCase(), entry.toLowerCase());
      if (distance < minDistance) {
        minDistance = distance;
        bestMatch = entry;
      }
    }

    if (bestMatch != null && bestMatch.toLowerCase() != lastWord.toLowerCase()) {
      final newWords = List<String>.from(words);
      newWords[newWords.length - 1] = bestMatch;
      final newText = "${newWords.join(' ')} ";
      
      setState(() {
        _lastCorrectedOriginal = lastWord;
        _lastCorrectedResult = bestMatch;
        _searchController.text = newText;
        _lastSearchValue = newText;
        _searchController.selection = TextSelection.fromPosition(TextPosition(offset: newText.length));
      });
    }
  }

  void _revertAutocorrect() {
    if (_lastCorrectedOriginal == null || _lastCorrectedResult == null) return;
    
    final currentText = _searchController.text;
    final revertedText = currentText.replaceFirst(_lastCorrectedResult!, _lastCorrectedOriginal!);
    
    setState(() {
      _searchController.text = revertedText;
      _lastSearchValue = revertedText;
      _searchController.selection = TextSelection.fromPosition(TextPosition(offset: revertedText.length));
      _lastCorrectedOriginal = null;
      _lastCorrectedResult = null;
    });
  }

  void _handleBack() {
    if (_searchController.text.isNotEmpty) {
      setState(() {
        _searchController.clear();
        _lastSearchValue = '';
      });
      return;
    }
    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
      return;
    }
    if (_lastCorrectedOriginal != null) {
      setState(() {
        _lastCorrectedOriginal = null;
        _lastCorrectedResult = null;
      });
      return;
    }
    _resetAllFilters();
  }

  void _onSearchFocusChange() {
    if (_searchFocusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _scrollController.animateTo(
            150, // Shift up to clear header/ads
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
      // We'll show the overlay in build or via context if needed, but for Library 
      // we need the available resources which are in the ListenableBuilder.
      // So we trigger a rebuild.
      setState(() {});
    } else {
      _hideOverlay();
      if (mounted) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  void _simulateLoading() async {
    await Future.delayed(const Duration(milliseconds: 1500));
    _hasLoadedBefore = true;
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_onSearchFocusChange);
    _searchFocusNode.dispose();
    _hideOverlay();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _showNotifications() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NotificationModal(),
    );
  }

  void _showUploadDialog() async {
    setState(() => _isUploadSheetOpen = true);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const UploadBottomSheet(),
    );
    if (mounted) {
      setState(() => _isUploadSheetOpen = false);
    }
  }

  void _showFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FilterModal(
        initialFilters: _activeFilters,
        onApply: (filters) {
          setState(() {
            _activeFilters = filters;
          });
        },
      ),
    );
  }

  void _resetAllFilters() {
    setState(() {
      _activeFilters = {};
      _selectedCategory = 'All';
      _searchController.clear();
      _hideOverlay();
    });
  }

  final List<Map<String, dynamic>> _categoryData = [
    {'label': 'All', 'color': const Color(0xFF287BFF), 'icon': Icons.grid_view_rounded},
    {'label': 'Notes', 'color': const Color(0xFF00A85A), 'icon': Icons.description_rounded},
    {'label': 'CATs', 'color': const Color(0xFFFF8A00), 'icon': Icons.assignment_rounded},
    {'label': 'Exams', 'color': const Color(0xFF7D46FF), 'icon': Icons.history_edu_rounded},
    {'label': 'Time tables', 'color': const Color(0xFF00D1FF), 'icon': Icons.calendar_month_rounded},
    {'label': 'Prac Manual', 'color': const Color(0xFFFF4667), 'icon': Icons.biotech_rounded},
    {'label': 'Supplementary Exams', 'color': const Color(0xFF00B4D8), 'icon': Icons.auto_stories_rounded},
  ];

  bool _fuzzyMatch(String query, String target) {
    if (query.isEmpty) return true;
    final queryTokens = query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    final targetLower = target.toLowerCase();

    for (final token in queryTokens) {
      if (!targetLower.contains(token)) {
        int matchCount = 0;
        int targetIdx = 0;
        for (int i = 0; i < token.length; i++) {
          while (targetIdx < targetLower.length) {
            if (token[i] == targetLower[targetIdx]) {
              matchCount++;
              targetIdx++;
              break;
            }
            targetIdx++;
          }
        }
        
        bool tokenMatches = false;
        if (token.length <= 3) {
          if (matchCount == token.length) tokenMatches = true;
        } else if (token.length <= 5) {
          if (matchCount >= token.length - 1) tokenMatches = true;
        } else {
          if (matchCount >= (token.length * 0.75).floor()) tokenMatches = true;
        }
        
        if (!tokenMatches) return false;
      }
    }
    return true;
  }

  List<String> _getSuggestions(String query, List<Resource> availableResources) {
    if (query.isEmpty) return [];
    final suggestions = <String>{};
    final q = query.toLowerCase().trim();

    final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    // Priority matches for types
    if ('supplementary exams'.contains(q) || 'supp'.contains(q)) suggestions.add('Supplementary Exams');
    if ('class timetable'.contains(q) || 'table'.contains(q)) suggestions.add('Class Timetable');
    if ('exam timetable'.contains(q)) suggestions.add('EXAM Timetable');
    if ('time tables'.contains(q) || 'timetable'.contains(q)) suggestions.add('Time tables');

    for (var res in availableResources) {
      // Helper to check if all query tokens match a target string
      bool allTokensMatch(String? target) {
        if (target == null) return false;
        final targetLower = target.toLowerCase();
        return tokens.every((token) => targetLower.contains(token));
      }

      void addIfMatch(String? text, {bool appendLecturer = false}) {
        if (allTokensMatch(text)) {
          String suggestion = text!;
          if (appendLecturer && res.lecturers.isNotEmpty) {
            suggestion = "$text - ${res.lecturers.first}";
          }
          suggestions.add(suggestion);
        }
      }

      addIfMatch(res.unitCode, appendLecturer: true);
      addIfMatch(res.title);
      addIfMatch(res.unitName, appendLecturer: true);
      addIfMatch(res.type);
      for (var l in res.lecturers) addIfMatch(l);
      for (var p in res.targetPrograms) addIfMatch(p);
      for (var pc in res.programCodes) addIfMatch(pc);

      // Add semester and year suggestions
      if (q.contains('semester') || q.contains('sem')) {
        suggestions.add("Semester ${res.semester}");
      }
      if (q.contains('year')) {
        suggestions.add("Year ${res.yearOfStudy}");
      }
    }

    final sortedList = suggestions.toList();
    sortedList.sort((a, b) {
      final aLower = a.toLowerCase();
      final bLower = b.toLowerCase();
      
      // Exact matches first
      if (aLower == q && bLower != q) return -1;
      if (bLower == q && aLower != q) return 1;
      
      // Prefix matches second
      final aStarts = aLower.startsWith(q);
      final bStarts = bLower.startsWith(q);
      if (aStarts && !bStarts) return -1;
      if (bStarts && !aStarts) return 1;
      
      // Then by length
      return a.length.compareTo(b.length);
    });

    return sortedList.take(8).toList();
  }

  void _showOverlay(List<Resource> availableResources) {
    _hideOverlay();
    final query = _searchController.text;
    final suggestions = _getSuggestions(query, availableResources);
    if (suggestions.isEmpty) return;

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width - 42,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 60),
          child: CustomSearchDropdown(
            suggestions: suggestions,
            query: query,
            width: size.width - 42,
            onSelected: (selection) {
              setState(() {
                _searchController.text = selection;
                _hideOverlay();
                _searchFocusNode.unfocus();
              });
            },
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF070716) : Colors.white,
        body: const LibrarySkeleton(),
      );
    }

    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? const Color(0xFFC9CBF2) : Colors.black54;

    return ListenableBuilder(
      listenable: Listenable.merge([DownloadService(), ResourceService()]),
      builder: (context, child) {
        final downloadedTitles = DownloadService().downloadedResources.map((r) => r['title']).toSet();
        final allResources = ResourceService().allResources;
        final userUploads = ResourceService().userUploads;
        
        final baseResources = _isDownloadsSelected 
            ? allResources.where((res) => downloadedTitles.contains(res.title)).toList()
            : userUploads;
        
        final filteredResources = baseResources.where((res) {
          final isTimetableCategory = _selectedCategory == 'All' ? false : _selectedCategory == 'Time tables';
          final matchesCategory = _selectedCategory == 'All' || 
              (isTimetableCategory 
                  ? (res.type == 'Time tables' || res.type.toLowerCase().contains('timetable'))
                  : res.type == _selectedCategory);
          
          final query = _searchController.text.trim().toLowerCase();
          
          if (query.isEmpty) return matchesCategory;

          // Check for specialized exact matches across the entire resource set to decide filtering mode
          bool isPrimaryMatch(Resource r, String q) {
            final rUnitCode = r.unitCode.toLowerCase();
            final rUnitName = r.unitName.toLowerCase();
            final rSemester = r.semester.toLowerCase();
            final rYearOfStudy = r.yearOfStudy.toLowerCase();
            final rType = r.type.toLowerCase();
            
            // 1. Exact Material Type Matches
            if (rType == q) return true;
            
            // Broad categories
            if ((q == 'time tables' || q == 'timetable' || q == 'timetables') && rType.contains('timetable')) return true;
            if ((q == 'supp' || q == 'supps' || q == 'supplementary') && rType.contains('supplementary')) return true;
            if ((q == 'manual' || q == 'manuals' || q == 'prac manual') && rType.contains('manual')) return true;

            // 2. Exact matches for primary fields
            if (rUnitCode == q || rUnitName == q) return true;
            if (r.lecturers.any((l) => l.toLowerCase() == q)) return true;
            if (r.targetPrograms.any((p) => p.toLowerCase() == q)) return true;
            if (r.programCodes.any((pc) => pc.toLowerCase() == q)) return true;
            
            // 3. Unit + Type combination (Two criteria)
            final knownTypes = [
              'notes', 'cats', 'exams', 'supplementary exams', 
              'class timetable', 'exam timetable', 'prac manual'
            ];
            
            for (var kt in knownTypes) {
              if (q.contains(kt)) {
                final unitPart = q.replaceAll(kt, '').trim();
                if (unitPart.isNotEmpty) {
                  bool typeMatch = rType == kt;
                  // Handle aliases in combination
                  if (kt == 'exams' && rType == 'exams') typeMatch = true;
                  if (kt == 'notes' && rType == 'notes') typeMatch = true;
                  
                  if (typeMatch && (rUnitCode.contains(unitPart) || rUnitName.contains(unitPart))) {
                    return true;
                  }
                }
              }
            }

            // Fallback for other combinations (like unit + 'exam' without 's')
            final qParts = q.split(' ');
            if (qParts.length >= 2) {
              String? detectedType;
              List<String> remainingParts = [];
              
              for (var part in qParts) {
                if (part == 'exam' || part == 'exams' || 
                    part == 'note' || part == 'notes' ||
                    part == 'cat' || part == 'cats' ||
                    part == 'supp' || part == 'supps' ||
                    part == 'timetable' || part == 'timetables' ||
                    part == 'manual' || part == 'manuals') {
                  detectedType = part;
                } else {
                  remainingParts.add(part);
                }
              }

              if (detectedType != null && remainingParts.isNotEmpty) {
                final unitPart = remainingParts.join(' ');
                bool typeMatch = false;
                if (detectedType.startsWith('exam') && rType.contains('exam')) typeMatch = true;
                else if (detectedType.startsWith('note') && rType.contains('note')) typeMatch = true;
                else if (detectedType.startsWith('cat') && rType.contains('cat')) typeMatch = true;
                else if (detectedType.startsWith('supp') && rType.contains('supplementary')) typeMatch = true;
                else if (detectedType.contains('table') && rType.contains('timetable')) typeMatch = true;
                else if (detectedType.startsWith('manual') && rType.contains('manual')) typeMatch = true;

                if (typeMatch && (rUnitCode.contains(unitPart) || rUnitName.contains(unitPart))) {
                  return true;
                }
              }
            }

            // Semester/Year special handling to avoid over-matching on single digits
            if (q.contains('semester') || q.contains('sem')) {
              final digit = q.replaceAll(RegExp(r'[^0-9]'), '');
              if (digit.isNotEmpty && rSemester.contains(digit)) return true;
            } else if (q.length > 1 && rSemester == q) {
              return true;
            }

            if (q.contains('year')) {
              final digit = q.replaceAll(RegExp(r'[^0-9]'), '');
              if (digit.isNotEmpty && rYearOfStudy.contains(digit)) return true;
            }

            return false;
          }

          // Optimization: Check if ANY resource has a primary match for the current query
          final hasAnyPrimaryMatch = baseResources.any((r) => isPrimaryMatch(r, query));

          bool matchesSearch;
          if (hasAnyPrimaryMatch) {
            // Strict mode: only show those that match primary fields
            matchesSearch = isPrimaryMatch(res, query);
          } else {
            // Check if query matches a material type or specialized category
            final allTypes = baseResources.map((r) => r.type.toLowerCase()).toSet();
            final isTypeSearch = allTypes.contains(query) || 
                                 query == 'timetable' || 
                                 query == 'time tables' ||
                                 query == 'manual' ||
                                 query == 'supp' ||
                                 query == 'supps';

            if (isTypeSearch) {
              // Strict match for type search
              if (query == 'time tables' || query == 'timetable') {
                matchesSearch = res.type.toLowerCase().contains('timetable') || res.type.toLowerCase().contains('time tables');
              } else if (query == 'manual') {
                matchesSearch = res.type.toLowerCase().contains('manual');
              } else if (query == 'supp' || query == 'supps' || query == 'supplementary exams') {
                matchesSearch = res.type.toLowerCase().contains('supplementary');
              } else {
                matchesSearch = res.type.toLowerCase() == query;
              }
            } else {
              // Fuzzy match for general search
              final searchFields = [
                res.title,
                res.unitCode,
                res.unitName,
                res.type,
                res.semester,
                res.yearOfStudy,
                ...res.lecturers,
                ...res.targetPrograms,
                ...res.programCodes,
              ].join(' ');
              matchesSearch = _fuzzyMatch(query, searchFields);
            }
          }
          
          bool matchesFilters = true;
          _activeFilters.forEach((key, value) {
            if (key == 'publicationYear' && res.publicationYear != value) matchesFilters = false;
            if (key == 'yearOfStudy' && res.yearOfStudy != value) matchesFilters = false;
            if (key == 'semester' && res.semester != value) matchesFilters = false;
            if (key == 'lecturer' && !res.lecturers.contains(value)) matchesFilters = false;
            if (key == 'courseProgram' && !res.targetPrograms.contains(value)) matchesFilters = false;
          });

          return matchesCategory && matchesSearch && matchesFilters;
        }).toList();

        final isSearching = _searchFocusNode.hasFocus || _searchController.text.isNotEmpty;
        final hasOtherFilters = _activeFilters.isNotEmpty || _selectedCategory != 'All';

        return PopScope(
          canPop: !isSearching && !hasOtherFilters,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _handleBack();
          },
          child: Stack(
            children: [
              GestureDetector(
                onTap: () {
                  ResourceService().setActiveResource(null);
                  _hideOverlay();
                  _searchFocusNode.unfocus();
                },
                behavior: HitTestBehavior.opaque,
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  body: Container(
                    decoration: BoxDecoration(
                      gradient: isDark
                          ? const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFF140C37), Color(0xFF070716)],
                            )
                          : LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.blue.shade50, Colors.white],
                            ),
                    ),
                    child: SafeArea(
                      child: CustomScrollView(
                        controller: _scrollController,
                        key: const PageStorageKey('library_scroll'),
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Library', style: TextStyle(color: textColor, fontSize: 32, fontWeight: FontWeight.w700)),
                                      Row(
                                        children: [
                                          ListenableBuilder(
                                            listenable: ref.watch(chatServiceProvider),
                                            builder: (context, child) {
                                              final unreadMessages = ref.read(chatServiceProvider).unreadCount;
                                              return Stack(
                                                clipBehavior: Clip.none,
                                                children: [
                                                  IconButton(
                                                    onPressed: () {
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(builder: (context) => const HelpSupportScreen()),
                                                      );
                                                    },
                                                    icon: SvgPicture.asset(
                                                      'assets/messenger.svg',
                                                      height: 28,
                                                      width: 28,
                                                      colorFilter: const ColorFilter.mode(
                                                        Color(0xFF00B2FF),
                                                        BlendMode.srcIn,
                                                      ),
                                                    ),
                                                  ),
                                                  if (unreadMessages > 0)
                                                    Positioned(
                                                      top: 8,
                                                      right: 8,
                                                      child: Container(
                                                        padding: const EdgeInsets.all(4),
                                                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                                        child: Text(
                                                          unreadMessages > 9 ? '9+' : unreadMessages.toString(),
                                                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                          textAlign: TextAlign.center,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              );
                                            },
                                          ),
                                          ListenableBuilder(
                                            listenable: NotificationService(),
                                            builder: (context, child) {
                                              final unreadCount = NotificationService().unreadCount;
                                              return Stack(
                                                clipBehavior: Clip.none,
                                                children: [
                                                  IconButton(
                                                    onPressed: _showNotifications,
                                                    icon: const Text('🔔', style: TextStyle(fontSize: 24)),
                                                  ),
                                                  if (unreadCount > 0)
                                                    Positioned(
                                                      top: 8,
                                                      right: 8,
                                                      child: Container(
                                                        padding: const EdgeInsets.all(4),
                                                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                                        child: Text(
                                                          unreadCount > 9 ? '9+' : unreadCount.toString(),
                                                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                          textAlign: TextAlign.center,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text('Your offline academic hub.', style: TextStyle(color: subTextColor, fontSize: 16)),
                                  const SizedBox(height: 20),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: CompositedTransformTarget(
                                          link: _layerLink,
                                          child: TextField(
                                            controller: _searchController,
                                            focusNode: _searchFocusNode,
                                            textCapitalization: TextCapitalization.sentences,
                                            onChanged: (value) {
                                              if (_lastCorrectedOriginal != null && _lastCorrectedResult != null && !value.endsWith(' ')) {
                                                if (value.length < _lastSearchValue.length) {
                                                  final revertedText = value.replaceFirst(_lastCorrectedResult!, _lastCorrectedOriginal!);
                                                  setState(() {
                                                    _searchController.text = revertedText;
                                                    _lastSearchValue = revertedText;
                                                    _searchController.selection = TextSelection.fromPosition(TextPosition(offset: revertedText.length));
                                                    _lastCorrectedOriginal = null;
                                                    _lastCorrectedResult = null;
                                                  });
                                                  _showOverlay(baseResources);
                                                  return;
                                                } else {
                                                  setState(() {
                                                    _lastCorrectedOriginal = null;
                                                    _lastCorrectedResult = null;
                                                  });
                                                }
                                              }
                                              _handleAutocorrect(value);
                                              setState(() => _lastSearchValue = value);
                                              _showOverlay(baseResources);
                                            },
                                            onTap: () => _showOverlay(baseResources),
                                            style: TextStyle(color: textColor),
                                            decoration: InputDecoration(
                                              hintText: _isDownloadsSelected ? 'Search downloaded units' : 'Search your uploads',
                                              hintStyle: TextStyle(color: textColor.withValues(alpha: 0.5)),
                                              prefixIcon: const Icon(Icons.search, color: Color(0xFF24C7FF)),
                                              suffixIcon: _lastCorrectedOriginal != null
                                                  ? GestureDetector(
                                                      onTap: _revertAutocorrect,
                                                      child: Container(
                                                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                                        decoration: BoxDecoration(
                                                          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                                                          borderRadius: BorderRadius.circular(12),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Text(
                                                              _lastCorrectedOriginal!,
                                                              style: TextStyle(
                                                                color: isDark ? Colors.white54 : Colors.black54,
                                                                fontSize: 10,
                                                                fontWeight: FontWeight.bold,
                                                                decoration: TextDecoration.lineThrough,
                                                              ),
                                                            ),
                                                            const SizedBox(width: 4),
                                                            const Text(
                                                              'Undo',
                                                              style: TextStyle(
                                                                color: Color(0xFF24C7FF),
                                                                fontSize: 10,
                                                                fontWeight: FontWeight.w900,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    )
                                                  : null,
                                              filled: true,
                                              fillColor: isDark ? const Color(0xFF181739).withValues(alpha: 0.72) : Colors.white.withValues(alpha: 0.72),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: isDark ? const Color(0xFF302B65) : Colors.blue.shade100)),
                                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: isDark ? const Color(0xFF302B65) : Colors.blue.shade100)),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      GestureDetector(
                                        onTap: () {
                                          setState(() {});
                                          _hideOverlay();
                                          _searchFocusNode.unfocus();
                                        },
                                        child: Container(
                                          height: 56,
                                          width: 56,
                                          decoration: BoxDecoration(color: const Color(0xFF00A85A), borderRadius: BorderRadius.circular(16)),
                                          child: const Center(child: Text('🔍', style: TextStyle(fontSize: 20))),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    clipBehavior: Clip.none,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Row(
                                        children: _categoryData.map((data) {
                                          final String label = data['label'];
                                          final Color color = data['color'];
                                          final IconData icon = data['icon'];
                                          final isSelected = _selectedCategory == label;
                                          return Padding(
                                            padding: const EdgeInsets.only(right: 12.0),
                                            child: GestureDetector(
                                              onTap: () => setState(() => _selectedCategory = label),
                                              child: CategoryChip(label: label, color: color, icon: icon, isActive: isSelected),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: _showFilters,
                                      icon: Icon(Icons.tune, color: _activeFilters.isNotEmpty ? const Color(0xFF00A85A) : const Color(0xFF24C7FF)),
                                      label: Text(
                                        _activeFilters.isNotEmpty ? 'Filters Active (${_activeFilters.length})' : 'Filter',
                                        style: TextStyle(color: textColor.withValues(alpha: 0.7)),
                                      ),
                                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16)),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  // Toggle Switch
                                  Container(
                                    height: 50,
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1A1A2E) : Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () {
                                              setState(() => _isDownloadsSelected = true);
                                              _hideOverlay();
                                            },
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: _isDownloadsSelected ? const Color(0xFF00A85A) : Colors.transparent,
                                                borderRadius: BorderRadius.circular(21),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  'Downloads',
                                                  style: TextStyle(
                                                    color: _isDownloadsSelected ? Colors.white : (isDark ? Colors.white60 : Colors.black45),
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () {
                                              setState(() => _isDownloadsSelected = false);
                                              _hideOverlay();
                                            },
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: !_isDownloadsSelected ? const Color(0xFF00A85A) : Colors.transparent,
                                                borderRadius: BorderRadius.circular(21),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  'Uploads',
                                                  style: TextStyle(
                                                    color: !_isDownloadsSelected ? Colors.white : (isDark ? Colors.white60 : Colors.black45),
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  // Section Header with lines
                                  Row(
                                    children: [
                                      Expanded(child: Divider(color: textColor.withValues(alpha: 0.1), thickness: 1)),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 16),
                                        child: Text(
                                          _isDownloadsSelected ? 'DOWNLOADS' : 'UPLOADS',
                                          style: TextStyle(
                                            color: textColor.withValues(alpha: 0.5),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 2,
                                          ),
                                        ),
                                      ),
                                      Expanded(child: Divider(color: textColor.withValues(alpha: 0.1), thickness: 1)),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                ],
                              ),
                            ),
                          ),
                          if (filteredResources.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _isDownloadsSelected ? Icons.download_for_offline_outlined : Icons.cloud_off_rounded,
                                      color: textColor.withValues(alpha: 0.1),
                                      size: 64,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _isDownloadsSelected 
                                          ? 'No materials match your filters'
                                          : 'You haven\'t uploaded any materials yet',
                                      style: TextStyle(color: textColor.withValues(alpha: 0.2), fontSize: 16),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              sliver: SliverGrid(
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 0.72,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final res = filteredResources[index];
                                    return ResourceCard(
                                      title: res.title,
                                      type: res.type,
                                      materialFormat: res.materialFormat,
                                      thumbnailUrl: res.thumbnailUrl,
                                      unitName: res.unitName,
                                      unitCode: res.unitCode,
                                      targetPrograms: res.targetPrograms,
                                      programCodes: res.programCodes,
                                      year: res.year,
                                      uploadYear: res.uploadYear,
                                      publicationYear: res.publicationYear,
                                      yearOfStudy: res.yearOfStudy,
                                      semester: res.semester,
                                      lecturers: res.lecturers,
                                      uploadedBy: res.uploadedBy,
                                      uploaderRole: res.uploaderRole,
                                      views: res.views.toString(),
                                      likes: res.likes.toString(),
                                      comments: res.comments.toString(),
                                      isLiked: res.isLiked,
                                      showDownload: false,
                                      status: !_isDownloadsSelected ? res.status : null,
                                      declineReason: !_isDownloadsSelected ? res.declineReason : null,
                                      onLikeToggle: () => ResourceService().toggleLike(res.title),
                                      onViewIncrement: () => ResourceService().incrementViews(res.title),
                                      onTap: () {},
                                    );
                                  },
                                  childCount: filteredResources.length,
                                ),
                              ),
                            ),
                          const SliverToBoxAdapter(child: SizedBox(height: 20)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (!_isDownloadsSelected && !_isUploadSheetOpen)
                DraggableFab(
                  onTap: _showUploadDialog,
                ),
            ],
          ),
        );
      },
    );
  }
}
