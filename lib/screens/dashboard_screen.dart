import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/category_chip.dart';
import '../widgets/resource_card.dart';
import '../widgets/smart_ad_banner.dart';
import '../widgets/inline_ad_banner.dart';
import '../services/subscription_service.dart';
import '../services/notification_service.dart';
import '../widgets/notification_modal.dart';
import '../services/resource_service.dart';
import '../services/download_service.dart';
import '../services/connectivity_service.dart';
import '../widgets/filter_modal.dart';
import '../widgets/skeleton.dart';
import '../widgets/search_dropdown.dart';
import '../providers/providers.dart';
import '../services/top_notification_service.dart';
import 'help_support_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  static bool _hasLoadedBefore = false;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  late bool _isLoading;
  String? _lastCorrectedOriginal;
  String? _lastCorrectedResult;
  String _lastSearchValue = '';
  List<Resource> _shuffledResources = [];

  @override
  void initState() {
    super.initState();
    final uiState = ref.read(uiStateProvider);
    _searchController.text = uiState.dashboardSearch;
    _lastSearchValue = uiState.dashboardSearch;
    
    _isLoading = !_hasLoadedBefore;
    if (_isLoading) {
      _simulateLoading();
    } else {
      _shuffledResources = List.from(ResourceService().allResources);
    }
    _searchFocusNode.addListener(_onSearchFocusChange);
  }

  void _onSearchFocusChange() {
    if (_searchFocusNode.hasFocus) {
      // Small delay to ensure the keyboard is coming up and layout is stable
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _scrollController.animateTo(
            150, // Shift up by approximately the height of the header
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
      _showOverlay();
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
        _shuffledResources = List.from(ResourceService().allResources);
      });
    }
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

  List<String> _getSuggestions(String query) {
    if (query.isEmpty) return [];
    final allResources = ResourceService().allResources;
    final suggestions = <String>{};
    final q = query.toLowerCase().trim();
    final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    // 1. Primary Category Hits
    final categories = [
      'Notes', 'CATs', 'Exams', 'Supplementary Exams', 
      'Class Timetable', 'EXAM Timetable', 'Time tables', 'Prac Manual'
    ];
    for (var cat in categories) {
      final cLower = cat.toLowerCase();
      if (cLower.startsWith(q) || (q.length > 2 && cLower.contains(q)) || 
          (q == 'supp' && cLower.contains('supplementary')) ||
          (q == 'table' && cLower.contains('timetable'))) {
        suggestions.add(cat);
      }
    }

    // 2. Smart Combinations and Field Matches
    for (var res in allResources) {
      final codeLower = res.unitCode.toLowerCase();
      final nameLower = res.unitName.toLowerCase();
      final typeLower = res.type.toLowerCase();

      // Helper to check if all query tokens match a target string
      bool allTokensMatch(String target) {
        final targetLower = target.toLowerCase();
        return tokens.every((token) => targetLower.contains(token));
      }

      // Check for Program + Type
      for (var p in res.targetPrograms) {
        final pLower = p.toLowerCase();
        bool matchesProgram = allTokensMatch(pLower);
        bool matchesType = tokens.any((t) => typeLower.contains(t) || 
                                           (typeLower.contains('supplementary') && t == 'supp') ||
                                           (typeLower.contains('timetable') && t == 'table'));
        
        if (matchesProgram && matchesType) {
           suggestions.add("$p ${res.type}");
        }
        if (matchesProgram) {
           suggestions.add(p);
        }
      }

      // Check for Program Code + Type
      for (var pc in res.programCodes) {
        final pcLower = pc.toLowerCase();
        bool matchesPC = allTokensMatch(pcLower);
        bool matchesType = tokens.any((t) => typeLower.contains(t) || 
                                           (typeLower.contains('supplementary') && t == 'supp') ||
                                           (typeLower.contains('timetable') && t == 'table'));
        
        if (matchesPC && matchesType) {
           suggestions.add("$pc ${res.type}");
        }
        if (matchesPC) {
           suggestions.add(pc);
        }
      }

      // Check for Unit + Type
      bool matchesUnit = allTokensMatch(codeLower) || allTokensMatch(nameLower);
      bool matchesType = tokens.any((t) => typeLower.contains(t) || 
                                         (typeLower.contains('supplementary') && t == 'supp') ||
                                         (typeLower.contains('timetable') && t == 'table'));

      if (matchesUnit && matchesType) {
        suggestions.add("${res.unitCode} ${res.type}");
        suggestions.add("${res.unitName} ${res.type}");
      }
      
      if (allTokensMatch(codeLower)) suggestions.add(res.unitCode);
      if (allTokensMatch(nameLower)) suggestions.add(res.unitName);
      
      if (allTokensMatch(res.uploadedBy.toLowerCase())) {
        suggestions.add(res.uploadedBy);
      }
      
      for (var l in res.lecturers) {
        if (allTokensMatch(l)) suggestions.add(l);
      }

      // Check for Semester/Year
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
      
      if (aLower == q && bLower != q) return -1;
      if (bLower == q && aLower != q) return 1;
      
      final aStarts = aLower.startsWith(q);
      final bStarts = bLower.startsWith(q);
      if (aStarts && !bStarts) return -1;
      if (bStarts && !aStarts) return 1;
      
      return a.length.compareTo(b.length);
    });

    return sortedList.take(8).toList();
  }

  Future<void> _handleRefresh() async {
    if (ConnectivityService().isOffline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.wifi_off_rounded, color: Colors.white, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Connect to the internet to refresh and load the latest content.',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.redAccent.withValues(alpha: 0.9),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Real network refresh by re-attaching Firestore listeners
    final userId = ResourceService().userUploads.isNotEmpty 
        ? ResourceService().userUploads.first.uploaderId 
        : ''; // Fallback, initialize handles this gracefully
    
    await ResourceService().refresh(userId);

    if (mounted) {
      setState(() {
        _shuffledResources = List.from(ResourceService().allResources)..shuffle();
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

  void _showFilters() {
    final uiState = ref.read(uiStateProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FilterModal(
        initialFilters: uiState.dashboardFilters,
        onApply: (filters) {
          ref.read(uiStateProvider.notifier).setDashboardFilters(filters);
        },
      ),
    );
  }

  void _resetAllFilters() {
    _searchController.clear();
    _lastSearchValue = '';
    ref.read(uiStateProvider.notifier).resetDashboardUI();
    _hideOverlay();
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

  void _handleAutocorrect(String value) {
    if (!value.endsWith(' ')) return;
    
    final words = value.trim().split(RegExp(r'\s+'));
    if (words.isEmpty) return;

    final lastWord = words.last;
    if (lastWord.length < 3 || RegExp(r'^\d+$').hasMatch(lastWord)) return;

    final dictionary = _getDictionary();
    String? bestMatch;
    int minDistance = 2; // Allow up to 1 error for short words, 2 for longer

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
        ref.read(uiStateProvider.notifier).setDashboardSearch(newText);
      });
    }
  }

  void _revertAutocorrect() {
    if (_lastCorrectedOriginal == null || _lastCorrectedResult == null) return;
    
    final currentText = _searchController.text;
    // Replace the result back with original
    final revertedText = currentText.replaceFirst(_lastCorrectedResult!, _lastCorrectedOriginal!);
    
    setState(() {
      _searchController.text = revertedText;
      _lastSearchValue = revertedText;
      _searchController.selection = TextSelection.fromPosition(TextPosition(offset: revertedText.length));
      _lastCorrectedOriginal = null;
      _lastCorrectedResult = null;
      ref.read(uiStateProvider.notifier).setDashboardSearch(revertedText);
    });
  }

  void _handleBack() {
    if (_searchController.text.isNotEmpty) {
      setState(() {
        _searchController.clear();
        _lastSearchValue = '';
        ref.read(uiStateProvider.notifier).setDashboardSearch('');
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

  void _showOverlay() {
    _hideOverlay();
    final query = _searchController.text;
    final suggestions = _getSuggestions(query);
    if (suggestions.isEmpty) return;

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width - 42, // Adjusted for full width padding
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
                _lastSearchValue = selection;
                _hideOverlay();
                _searchFocusNode.unfocus();
                ref.read(uiStateProvider.notifier).setDashboardSearch(selection);
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
    final uiState = ref.watch(uiStateProvider);
    final isDark = themeMode == ThemeMode.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF070716) : Colors.white,
        body: const DashboardSkeleton(),
      );
    }

    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? const Color(0xFFC9CBF2) : Colors.black54;

    return ListenableBuilder(
      listenable: Listenable.merge([ResourceService(), DownloadService()]),
      builder: (context, child) {
        final allResources = ResourceService().allResources;

        final sourceResources = _shuffledResources.isEmpty ? allResources : _shuffledResources;

        final filteredResources = sourceResources.where((res) {
          // 1. Filter out pinned non-timetable items
          final isPinned = DownloadService().isPinned(res.title);
          final isTimetableType = res.type.toLowerCase().contains('timetable') || 
                                res.type.toLowerCase().contains('time tables') ||
                                res.type.toLowerCase().contains('time table');
          if (isPinned && !isTimetableType) return false;

          // 2. Strict Category Match
          final isTimetableCategory = uiState.dashboardCategory == 'Time tables';
          final isAllCategory = uiState.dashboardCategory == 'All';
          
          bool matchesCategory;
          if (isAllCategory) {
            // "All" now acts as a "Materials" tab, excluding timetables
            matchesCategory = !isTimetableType;
          } else if (isTimetableCategory) {
            // "Time tables" category only shows timetables
            matchesCategory = isTimetableType;
          } else {
            // Other categories (Notes, CATs, etc.) match exactly
            matchesCategory = res.type == uiState.dashboardCategory;
          }
          
          if (!matchesCategory) return false;

          // 3. Strict Search Query Match
          final query = _searchController.text.trim().toLowerCase();
          if (query.isNotEmpty) {
            final searchFields = [
              res.title,
              res.unitCode,
              res.unitName,
              res.type,
              res.semester,
              res.yearOfStudy,
              res.uploadedBy,
              ...res.lecturers,
              ...res.targetPrograms,
              ...res.programCodes,
            ].map((s) => s.toLowerCase().trim()).join(' ');
            
            final tokens = query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
            final matchesSearch = tokens.every((token) => searchFields.contains(token));
            if (!matchesSearch) return false;
          }

          // 4. Strict AND Filter Logic
          bool matchesFilters = true;
          uiState.dashboardFilters.forEach((key, value) {
            final normalizedValue = value.toLowerCase().trim();
            if (key == 'publicationYear') {
              if (res.publicationYear.toLowerCase().trim() != normalizedValue) matchesFilters = false;
            } else if (key == 'yearOfStudy') {
              if (res.yearOfStudy.toLowerCase().trim() != normalizedValue) matchesFilters = false;
            } else if (key == 'semester') {
              if (res.semester.toLowerCase().trim() != normalizedValue) matchesFilters = false;
            } else if (key == 'lecturer') {
              if (!res.lecturers.any((l) => l.toLowerCase().trim() == normalizedValue)) matchesFilters = false;
            } else if (key == 'courseProgram') {
              if (!res.targetPrograms.any((p) => p.toLowerCase().trim() == normalizedValue)) matchesFilters = false;
            }
          });

          return matchesFilters;
        }).toList();

        final isSearching = _searchFocusNode.hasFocus || _searchController.text.isNotEmpty;
        final hasOtherFilters = uiState.dashboardFilters.isNotEmpty || uiState.dashboardCategory != 'All';

        return PopScope(
          canPop: !isSearching && !hasOtherFilters,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _handleBack();
          },
          child: GestureDetector(
            onTap: () {
              ResourceService().setActiveResource(null);
              _hideOverlay();
              _searchFocusNode.unfocus();
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
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
                child: RefreshIndicator(
                  onRefresh: _handleRefresh,
                  color: const Color(0xFF24C7FF),
                  backgroundColor: isDark ? const Color(0xFF181739) : Colors.white,
                  child: CustomScrollView(
                    controller: _scrollController,
                    key: const PageStorageKey('dashboard_scroll'),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const SizedBox(),
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
                              Text('Dashboard', style: TextStyle(color: textColor, fontSize: 28, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              Text('Find your academic edge.', style: TextStyle(color: subTextColor)),
                              const SizedBox(height: 20),
                              const SmartAdBanner(),
                              const SizedBox(height: 20),
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
                                      final isSelected = uiState.dashboardCategory == label;
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 12.0),
                                        child: GestureDetector(
                                          onTap: () => ref.read(uiStateProvider.notifier).setDashboardCategory(label),
                                          child: CategoryChip(label: label, icon: icon, color: color, isActive: isSelected),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
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
                                              // Backspaced the space -> Revert
                                              final revertedText = value.replaceFirst(_lastCorrectedResult!, _lastCorrectedOriginal!);
                                              setState(() {
                                                _searchController.text = revertedText;
                                                _lastSearchValue = revertedText;
                                                _searchController.selection = TextSelection.fromPosition(TextPosition(offset: revertedText.length));
                                                _lastCorrectedOriginal = null;
                                                _lastCorrectedResult = null;
                                                ref.read(uiStateProvider.notifier).setDashboardSearch(revertedText);
                                              });
                                              _showOverlay();
                                              return;
                                            } else {
                                              // Typed forward -> Accept (hide undo)
                                              setState(() {
                                                _lastCorrectedOriginal = null;
                                                _lastCorrectedResult = null;
                                              });
                                            }
                                          }
                                          _handleAutocorrect(value);
                                          setState(() => _lastSearchValue = value);
                                          ref.read(uiStateProvider.notifier).setDashboardSearch(value);
                                          _showOverlay();
                                        },
                                        onTap: _showOverlay,
                                        style: TextStyle(color: textColor),
                                        decoration: InputDecoration(
                                          hintText: 'Search materials...',
                                          hintStyle: const TextStyle(color: Colors.grey),
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
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: _showFilters,
                                  icon: Icon(Icons.tune, color: uiState.dashboardFilters.isNotEmpty ? const Color(0xFF00A85A) : const Color(0xFF24C7FF)),
                                  label: Text(
                                    uiState.dashboardFilters.isNotEmpty ? 'Filters Active (${uiState.dashboardFilters.length})' : 'Filter',
                                    style: TextStyle(color: textColor.withValues(alpha: 0.7)),
                                  ),
                                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16)),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  Expanded(child: Divider(color: textColor.withValues(alpha: 0.1), thickness: 1)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Text('FOR YOU', style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2)),
                                  ),
                                  Expanded(child: Divider(color: textColor.withValues(alpha: 0.1), thickness: 1)),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                      ..._buildGridWithAds(filteredResources, textColor),
                      const SliverToBoxAdapter(child: SizedBox(height: 20)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildGridWithAds(List<Resource> filteredResources, Color textColor) {
    if (filteredResources.isEmpty) {
      return [
        SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off_rounded, color: textColor.withValues(alpha: 0.1), size: 64),
                const SizedBox(height: 16),
                Text('No materials match your search', style: TextStyle(color: textColor.withValues(alpha: 0.2), fontSize: 16)),
                const SizedBox(height: 8),
                const TextButton(onPressed: null, child: Text('Try searching something else', style: TextStyle(color: Color(0xFF20C8FF)))),
              ],
            ),
          ),
        )
      ];
    }

    List<Widget> slivers = [];
    const int itemsPerRow = 2;
    const int rowsPerAd = 4;
    const int itemsPerAd = itemsPerRow * rowsPerAd;

    for (int i = 0; i < filteredResources.length; i += itemsPerAd) {
      final end = (i + itemsPerAd < filteredResources.length) ? i + itemsPerAd : filteredResources.length;
      final chunk = filteredResources.sublist(i, end);

      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.72),
            delegate: SliverChildBuilderDelegate(
               (context, index) {
                 final res = chunk[index];
                 return ResourceCard(
                   resource: res,
                   onLikeToggle: () => ref.read(resourceServiceProvider).toggleLike(res.id, res.isLiked),
                   onViewIncrement: () => ref.read(resourceServiceProvider).incrementViews(res.id),
                   showPin: false,
                   onTap: () {},
                 );
               },
               childCount: chunk.length,
             ),
          ),
        ),
      );

      if (end < filteredResources.length && !SubscriptionService().isSubscribed) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              child: InlineAdBanner(),
            ),
          ),
        );
      }
    }

    return slivers;
  }
}
