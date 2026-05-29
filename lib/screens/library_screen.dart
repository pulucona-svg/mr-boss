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
import '../widgets/smart_ad_banner.dart';
import '../widgets/inline_ad_banner.dart';
import '../services/subscription_service.dart';
import '../widgets/upload_bottom_sheet.dart';
import '../widgets/draggable_fab.dart';
import '../widgets/skeleton.dart';
import '../widgets/search_dropdown.dart';
import '../providers/theme_provider.dart';
import '../providers/chat_provider.dart';
import 'help_support_screen.dart';
import 'archive_trash_screen.dart';
import '../utils/feedback_utils.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  final bool initialShowUploads;
  const LibraryScreen({super.key, this.initialShowUploads = false});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  static bool _hasLoadedBefore = false;
  String _selectedCategory = 'All';
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  Map<String, String> _activeFilters = {};
  late bool _isDownloadsSelected;
  bool _isUploadSheetOpen = false;
  late bool _isLoading;
  
  // Downloads State
  bool _isDownloadSelectionMode = false;
  final Set<String> _selectedDownloadTitles = {};
  final ScrollController _scrollControllerDownloads = ScrollController();
  final TextEditingController _searchControllerDownloads = TextEditingController();
  final FocusNode _searchFocusNodeDownloads = FocusNode();
  String? _lastCorrectedOriginalDownloads;
  String? _lastCorrectedResultDownloads;
  String _lastSearchValueDownloads = '';

  // Uploads State
  bool _isUploadSelectionMode = false;
  final Set<String> _selectedUploadTitles = {};
  final ScrollController _scrollControllerUploads = ScrollController();
  final TextEditingController _searchControllerUploads = TextEditingController();
  final FocusNode _searchFocusNodeUploads = FocusNode();
  String? _lastCorrectedOriginalUploads;
  String? _lastCorrectedResultUploads;
  String _lastSearchValueUploads = '';

  @override
  void initState() {
    super.initState();
    _isDownloadsSelected = !widget.initialShowUploads;
    _isLoading = !_hasLoadedBefore;
    if (_isLoading) {
      _simulateLoading();
    }
    _searchFocusNodeDownloads.addListener(_onSearchFocusChange);
    _searchFocusNodeUploads.addListener(_onSearchFocusChange);
  }

  void _onSearchFocusChange() {
    final activeController = _isDownloadsSelected ? _scrollControllerDownloads : _scrollControllerUploads;
    final activeFocusNode = _isDownloadsSelected ? _searchFocusNodeDownloads : _searchFocusNodeUploads;
    
    if (activeFocusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          activeController.animateTo(
            150, // Shift up to clear header
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
      setState(() {});
    } else {
      _hideOverlay();
      if (mounted) {
        activeController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  void dispose() {
    _searchFocusNodeDownloads.removeListener(_onSearchFocusChange);
    _searchFocusNodeUploads.removeListener(_onSearchFocusChange);
    _searchFocusNodeDownloads.dispose();
    _searchFocusNodeUploads.dispose();
    _hideOverlay();
    _searchControllerDownloads.dispose();
    _searchControllerUploads.dispose();
    _scrollControllerDownloads.dispose();
    _scrollControllerUploads.dispose();
    super.dispose();
  }

  void _toggleSelection(String title, bool isDownloads) {
    setState(() {
      final selectedSet = isDownloads ? _selectedDownloadTitles : _selectedUploadTitles;
      if (selectedSet.contains(title)) {
        selectedSet.remove(title);
        if (selectedSet.isEmpty) {
          if (isDownloads) _isDownloadSelectionMode = false;
          else _isUploadSelectionMode = false;
        }
      } else {
        selectedSet.add(title);
      }
    });
  }

  void _enterSelectionMode(String title, bool isDownloads) {
    setState(() {
      if (isDownloads) {
        _isDownloadSelectionMode = true;
        _selectedDownloadTitles.add(title);
      } else {
        _isUploadSelectionMode = true;
        _selectedUploadTitles.add(title);
      }
    });
  }

  void _exitSelectionMode({required bool isDownloads}) {
    setState(() {
      if (isDownloads) {
        _isDownloadSelectionMode = false;
        _selectedDownloadTitles.clear();
      } else {
        _isUploadSelectionMode = false;
        _selectedUploadTitles.clear();
      }
    });
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
      
      final controller = _isDownloadsSelected ? _searchControllerDownloads : _searchControllerUploads;
      
      setState(() {
        if (_isDownloadsSelected) {
          _lastCorrectedOriginalDownloads = lastWord;
          _lastCorrectedResultDownloads = bestMatch;
          _lastSearchValueDownloads = newText;
        } else {
          _lastCorrectedOriginalUploads = lastWord;
          _lastCorrectedResultUploads = bestMatch;
          _lastSearchValueUploads = newText;
        }
        controller.text = newText;
        controller.selection = TextSelection.fromPosition(TextPosition(offset: newText.length));
      });
    }
  }

  void _revertAutocorrect() {
    final controller = _isDownloadsSelected ? _searchControllerDownloads : _searchControllerUploads;
    final lastOriginal = _isDownloadsSelected ? _lastCorrectedOriginalDownloads : _lastCorrectedOriginalUploads;
    final lastResult = _isDownloadsSelected ? _lastCorrectedResultDownloads : _lastCorrectedResultUploads;
    
    if (lastOriginal == null || lastResult == null) return;
    
    final currentText = controller.text;
    final revertedText = currentText.replaceFirst(lastResult, lastOriginal);
    
    setState(() {
      controller.text = revertedText;
      if (_isDownloadsSelected) {
        _lastSearchValueDownloads = revertedText;
        _lastCorrectedOriginalDownloads = null;
        _lastCorrectedResultDownloads = null;
      } else {
        _lastSearchValueUploads = revertedText;
        _lastCorrectedOriginalUploads = null;
        _lastCorrectedResultUploads = null;
      }
      controller.selection = TextSelection.fromPosition(TextPosition(offset: revertedText.length));
    });
  }

  void _handleBack() {
    final controller = _isDownloadsSelected ? _searchControllerDownloads : _searchControllerUploads;
    final focusNode = _isDownloadsSelected ? _searchFocusNodeDownloads : _searchFocusNodeUploads;
    final lastOriginal = _isDownloadsSelected ? _lastCorrectedOriginalDownloads : _lastCorrectedOriginalUploads;

    if (controller.text.isNotEmpty) {
      setState(() {
        controller.clear();
        if (_isDownloadsSelected) _lastSearchValueDownloads = '';
        else _lastSearchValueUploads = '';
      });
      return;
    }
    if (focusNode.hasFocus) {
      focusNode.unfocus();
      return;
    }
    if (lastOriginal != null) {
      setState(() {
        if (_isDownloadsSelected) {
          _lastCorrectedOriginalDownloads = null;
          _lastCorrectedResultDownloads = null;
        } else {
          _lastCorrectedOriginalUploads = null;
          _lastCorrectedResultUploads = null;
        }
      });
      return;
    }
    _resetAllFilters();
  }

  void _triggerOverlay(bool isDownloads) {
    final baseResources = isDownloads 
      ? DownloadService().downloadedResources
          .map((map) => ResourceService().findResourceByTitle(map['title']!))
          .whereType<Resource>()
          .toList()
      : ResourceService().userUploads;
    _showOverlay(baseResources);
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

  Future<void> _handleRefresh() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      setState(() {});
    }
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
      _searchControllerDownloads.clear();
      _searchControllerUploads.clear();
      _lastSearchValueDownloads = '';
      _lastSearchValueUploads = '';
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
    final controller = _isDownloadsSelected ? _searchControllerDownloads : _searchControllerUploads;
    final query = controller.text;
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
                controller.text = selection;
                _hideOverlay();
                final focusNode = _isDownloadsSelected ? _searchFocusNodeDownloads : _searchFocusNodeUploads;
                focusNode.unfocus();
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

  Widget _buildSelectionBar(bool isDownloads) {
    final selectedTitles = isDownloads ? _selectedDownloadTitles : _selectedUploadTitles;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF181739).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF20C8FF).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF20C8FF).withValues(alpha: 0.1),
            blurRadius: 10,
            spreadRadius: 2,
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            onPressed: () => _exitSelectionMode(isDownloads: isDownloads),
            icon: const Icon(Icons.close, color: Colors.white, size: 24),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              selectedTitles.length.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
          if (selectedTitles.length <= 4)
            Builder(
              builder: (context) {
                final allPinned = isDownloads 
                    ? selectedTitles.every((t) => DownloadService().isPinned(t))
                    : selectedTitles.every((t) => ResourceService().isPinned(t));
                
                return IconButton(
                  onPressed: () {
                    final titles = selectedTitles.toList();
                    if (isDownloads) {
                      if (allPinned) {
                        DownloadService().unpinMultiple(titles);
                        FeedbackUtils.showActionFeedback(
                          context: context,
                          type: FeedbackActionType.unpin,
                          count: titles.length,
                          isDownloads: true,
                        );
                      } else {
                        DownloadService().pinMultiple(titles);
                        FeedbackUtils.showActionFeedback(
                          context: context,
                          type: FeedbackActionType.pin,
                          count: titles.length,
                          isDownloads: true,
                        );
                      }
                    } else {
                      if (allPinned) {
                        ResourceService().unpinMultiple(titles);
                        FeedbackUtils.showActionFeedback(
                          context: context,
                          type: FeedbackActionType.unpin,
                          count: titles.length,
                          isDownloads: false,
                        );
                      } else {
                        ResourceService().pinMultiple(titles);
                        FeedbackUtils.showActionFeedback(
                          context: context,
                          type: FeedbackActionType.pin,
                          count: titles.length,
                          isDownloads: false,
                        );
                      }
                    }
                    _exitSelectionMode(isDownloads: isDownloads);
                  },
                  icon: Icon(
                    allPinned ? Icons.push_pin : Icons.push_pin_outlined, 
                    color: Colors.white, 
                    size: 24
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                );
              }
            ),
          IconButton(
            onPressed: () {
              final titles = selectedTitles.toList();
              if (isDownloads) {
                DownloadService().archiveMultiple(titles);
                FeedbackUtils.showActionFeedback(
                  context: context,
                  type: FeedbackActionType.archive,
                  count: titles.length,
                  isDownloads: true,
                );
              } else {
                ResourceService().archiveMultiple(titles);
                FeedbackUtils.showActionFeedback(
                  context: context,
                  type: FeedbackActionType.archive,
                  count: titles.length,
                  isDownloads: false,
                );
              }
              _exitSelectionMode(isDownloads: isDownloads);
            },
            icon: const Icon(Icons.archive_outlined, color: Colors.white, size: 24),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          IconButton(
            onPressed: () {
              final titles = selectedTitles.toList();
              if (isDownloads) {
                DownloadService().deleteMultiple(titles);
                FeedbackUtils.showActionFeedback(
                  context: context,
                  type: FeedbackActionType.moveToTrash,
                  count: titles.length,
                  isDownloads: true,
                );
              } else {
                ResourceService().deleteMultiple(titles);
                FeedbackUtils.showActionFeedback(
                  context: context,
                  type: FeedbackActionType.moveToTrash,
                  count: titles.length,
                  isDownloads: false,
                );
              }
              _exitSelectionMode(isDownloads: isDownloads);
            },
            icon: const Icon(Icons.delete_outline, color: Colors.white, size: 24),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onSelected: (value) {
              if (value == 'select_all') {
                setState(() {
                  final baseResources = isDownloads 
                      ? DownloadService().downloadedResources
                          .map((map) => ResourceService().findResourceByTitle(map['title']!))
                          .whereType<Resource>()
                          .toList()
                      : ResourceService().userUploads;
                  
                  final filteredResources = baseResources.where((res) {
                    final isTimetableCategory = _selectedCategory == 'All' ? false : _selectedCategory == 'Time tables';
                    final matchesCategory = _selectedCategory == 'All' || 
                        (isTimetableCategory 
                            ? (res.type == 'Time tables' || res.type.toLowerCase().contains('timetable'))
                            : res.type == _selectedCategory);
                    if (!matchesCategory) return false;
                    return true; // Simplified for select all
                  }).toList();

                  final targetSet = isDownloads ? _selectedDownloadTitles : _selectedUploadTitles;
                  for (var res in filteredResources) {
                    targetSet.add(res.title);
                  }
                });
              } else if (value == 'archives') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ArchiveTrashScreen(isDownloads: isDownloads, isTrash: false),
                  ),
                );
              } else if (value == 'trash') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ArchiveTrashScreen(isDownloads: isDownloads, isTrash: true),
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'archives', child: Text('Archives')),
              const PopupMenuItem(value: 'trash', child: Text('Trash')),
              const PopupMenuItem(value: 'select_all', child: Text('Select All')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDownloads, Color textColor, Color subTextColor, bool isDark) {
    final controller = isDownloads ? _searchControllerDownloads : _searchControllerUploads;
    final focusNode = isDownloads ? _searchFocusNodeDownloads : _searchFocusNodeUploads;
    final lastOriginal = isDownloads ? _lastCorrectedOriginalDownloads : _lastCorrectedOriginalUploads;
    final lastSearchValue = isDownloads ? _lastSearchValueDownloads : _lastSearchValueUploads;

    return Padding(
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
          const SmartAdBanner(),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: CompositedTransformTarget(
                  link: _layerLink,
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (value) {
                      final currentLastResult = isDownloads ? _lastCorrectedResultDownloads : _lastCorrectedResultUploads;
                      final currentLastOriginal = isDownloads ? _lastCorrectedOriginalDownloads : _lastCorrectedOriginalUploads;
                      final currentLastSearchValue = isDownloads ? _lastSearchValueDownloads : _lastSearchValueUploads;

                      if (currentLastOriginal != null && currentLastResult != null && !value.endsWith(' ')) {
                        if (value.length < currentLastSearchValue.length) {
                          final revertedText = value.replaceFirst(currentLastResult, currentLastOriginal);
                          setState(() {
                            controller.text = revertedText;
                            if (isDownloads) {
                              _lastSearchValueDownloads = revertedText;
                              _lastCorrectedOriginalDownloads = null;
                              _lastCorrectedResultDownloads = null;
                            } else {
                              _lastSearchValueUploads = revertedText;
                              _lastCorrectedOriginalUploads = null;
                              _lastCorrectedResultUploads = null;
                            }
                            controller.selection = TextSelection.fromPosition(TextPosition(offset: revertedText.length));
                          });
                          _triggerOverlay(isDownloads);
                          return;
                        } else {
                          setState(() {
                            if (isDownloads) {
                              _lastCorrectedOriginalDownloads = null;
                              _lastCorrectedResultDownloads = null;
                            } else {
                              _lastCorrectedOriginalUploads = null;
                              _lastCorrectedResultUploads = null;
                            }
                          });
                        }
                      }
                      _handleAutocorrect(value);
                      setState(() {
                        if (isDownloads) _lastSearchValueDownloads = value;
                        else _lastSearchValueUploads = value;
                      });
                      _triggerOverlay(isDownloads);
                    },
                    onTap: () {
                      focusNode.requestFocus();
                      _triggerOverlay(isDownloads);
                    },
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      hintText: isDownloads ? 'Search downloaded units' : 'Search your uploads',
                      hintStyle: TextStyle(color: textColor.withValues(alpha: 0.5)),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF24C7FF)),
                      suffixIcon: lastOriginal != null
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
                                      lastOriginal,
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
                  focusNode.unfocus();
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
                      _hideOverlay();
                      _searchFocusNodeDownloads.unfocus();
                      _searchFocusNodeUploads.unfocus();
                      setState(() => _isDownloadsSelected = true);
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
                      _hideOverlay();
                      _searchFocusNodeDownloads.unfocus();
                      _searchFocusNodeUploads.unfocus();
                      setState(() => _isDownloadsSelected = false);
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
          Row(
            children: [
              Expanded(child: Divider(color: textColor.withValues(alpha: 0.1), thickness: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  isDownloads ? 'DOWNLOADS' : 'UPLOADS',
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
    );
  }

  Widget _buildTabContent({required bool isDownloads}) {
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? const Color(0xFFC9CBF2) : Colors.black54;
    final isSelectionMode = isDownloads ? _isDownloadSelectionMode : _isUploadSelectionMode;
    final selectedTitles = isDownloads ? _selectedDownloadTitles : _selectedUploadTitles;
    final controller = isDownloads ? _scrollControllerDownloads : _scrollControllerUploads;

    final userUploads = ResourceService().userUploads;
    final baseResources = isDownloads 
        ? DownloadService().downloadedResources
            .map((map) => ResourceService().findResourceByTitle(map['title']!))
            .whereType<Resource>()
            .toList()
        : userUploads;
    
    final filteredResources = baseResources.where((res) {
      // 1. Strict Category Match
      final isTimetableCategory = _selectedCategory == 'All' ? false : _selectedCategory == 'Time tables';
      final matchesCategory = _selectedCategory == 'All' || 
          (isTimetableCategory 
              ? (res.type == 'Time tables' || res.type.toLowerCase().contains('timetable'))
              : res.type == _selectedCategory);
      if (!matchesCategory) return false;

      // 2. Strict Search Query Match
      final searchController = isDownloads ? _searchControllerDownloads : _searchControllerUploads;
      final query = searchController.text.trim().toLowerCase();
      if (query.isNotEmpty) {
        final searchFields = [
          res.title,
          res.unitCode,
          res.unitName,
          res.type,
          res.semester,
          res.yearOfStudy,
          res.uploadedBy,
          res.uploaderRole,
          ...res.lecturers,
          ...res.targetPrograms,
          ...res.programCodes,
        ].map((s) => s.toLowerCase().trim()).join(' ');
        
        final tokens = query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
        final matchesSearch = tokens.every((token) => searchFields.contains(token));
        if (!matchesSearch) return false;
      }

      // 3. Strict AND Filter Logic
      bool matchesFilters = true;
      _activeFilters.forEach((key, value) {
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

    return Container(
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
          onRefresh: () => _handleRefresh(),
          color: const Color(0xFF24C7FF),
          backgroundColor: isDark ? const Color(0xFF181739) : Colors.white,
          child: CustomScrollView(
            controller: controller,
            key: PageStorageKey(isDownloads ? 'downloads_scroll' : 'uploads_scroll'),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(isDownloads, textColor, subTextColor, isDark)),
              if (isSelectionMode)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: SelectionHeaderDelegate(
                    child: _buildSelectionBar(isDownloads),
                  ),
                ),
              ..._buildLibraryGridWithAds(
                filteredResources: filteredResources,
                isDownloads: isDownloads,
                isSelectionMode: isSelectionMode,
                selectedTitles: selectedTitles,
                textColor: textColor,
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildLibraryGridWithAds({
    required List<Resource> filteredResources,
    required bool isDownloads,
    required bool isSelectionMode,
    required Set<String> selectedTitles,
    required Color textColor,
  }) {
    if (filteredResources.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isDownloads ? Icons.download_for_offline_outlined : Icons.cloud_off_rounded,
                    color: textColor.withValues(alpha: 0.1),
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No results found',
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.5), 
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Try another keyword',
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.3), 
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
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
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.72,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final res = chunk[index];
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
                  status: !isDownloads ? res.status : null,
                  declineReason: !isDownloads ? res.declineReason : null,
                  onLikeToggle: () => ResourceService().toggleLike(res.title),
                  onViewIncrement: () => ResourceService().incrementViews(res.title),
                  isSelectionMode: isSelectionMode,
                  isSelected: selectedTitles.contains(res.title),
                  onLongPress: () {
                    if (!isSelectionMode) {
                      _enterSelectionMode(res.title, isDownloads);
                    }
                  },
                  onTap: () {
                    if (isSelectionMode) {
                      _toggleSelection(res.title, isDownloads);
                    }
                  },
                );
              },
              childCount: chunk.length,
            ),
          ),
        ),
      );

      if (end < filteredResources.length && 
          isDownloads && 
          filteredResources.length > 4 && 
          !SubscriptionService().isSubscribed) {
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

  @override
  Widget build(BuildContext context) {
    final activeFocusNode = _isDownloadsSelected ? _searchFocusNodeDownloads : _searchFocusNodeUploads;
    final activeController = _isDownloadsSelected ? _searchControllerDownloads : _searchControllerUploads;
    
    final isSearching = activeFocusNode.hasFocus || activeController.text.isNotEmpty;
    final hasOtherFilters = _activeFilters.isNotEmpty || _selectedCategory != 'All';
    final currentSelectionMode = _isDownloadsSelected ? _isDownloadSelectionMode : _isUploadSelectionMode;

    if (_isLoading) {
      final isDark = ref.watch(themeProvider) == ThemeMode.dark;
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF070716) : Colors.white,
        body: const LibrarySkeleton(),
      );
    }

    return ListenableBuilder(
      listenable: Listenable.merge([DownloadService(), ResourceService()]),
      builder: (context, child) {
        return PopScope(
          canPop: !isSearching && !hasOtherFilters && !currentSelectionMode,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (currentSelectionMode) {
              _exitSelectionMode(isDownloads: _isDownloadsSelected);
              return;
            }
            _handleBack();
          },
          child: Stack(
            children: [
              GestureDetector(
                onTap: () {
                  ResourceService().setActiveResource(null);
                  _hideOverlay();
                  _searchFocusNodeDownloads.unfocus();
                  _searchFocusNodeUploads.unfocus();
                },
                behavior: HitTestBehavior.opaque,
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  body: IndexedStack(
                    index: _isDownloadsSelected ? 0 : 1,
                    children: [
                      _buildTabContent(isDownloads: true),
                      _buildTabContent(isDownloads: false),
                    ],
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

class SelectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  SelectionHeaderDelegate({required this.child});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  double get maxExtent => 56.0;

  @override
  double get minExtent => 56.0;

  @override
  bool shouldRebuild(covariant SelectionHeaderDelegate oldDelegate) => true;
}
