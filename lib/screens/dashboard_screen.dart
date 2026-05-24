import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/category_chip.dart';
import '../widgets/resource_card.dart';
import '../widgets/ad_carousel.dart';
import '../services/notification_service.dart';
import '../widgets/notification_modal.dart';
import '../services/resource_service.dart';
import '../widgets/filter_modal.dart';
import '../widgets/skeleton.dart';
import '../widgets/search_dropdown.dart';
import '../providers/theme_provider.dart';
import '../providers/chat_provider.dart';
import 'help_support_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  static bool _hasLoadedBefore = false;
  String _selectedCategory = 'All';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  Map<String, String> _activeFilters = {};
  late bool _isLoading;

  @override
  void initState() {
    super.initState();
    _isLoading = !_hasLoadedBefore;
    if (_isLoading) {
      _simulateLoading();
    }
    _searchFocusNode.addListener(_onSearchFocusChange);
  }

  void _handleBack() {
    if (_searchController.text.isNotEmpty) {
      setState(() {
        _searchController.clear();
      });
      return;
    }
    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
      return;
    }
    _resetAllFilters();
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

  List<String> _getSuggestions(String query) {
    if (query.isEmpty) return [];
    final allResources = ResourceService().allResources;
    final suggestions = <String>{};

    for (var res in allResources) {
      if (res.title.toLowerCase().contains(query.toLowerCase())) suggestions.add(res.title);
      if (res.unitCode.toLowerCase().contains(query.toLowerCase())) suggestions.add(res.unitCode);
      if (res.unitName.toLowerCase().contains(query.toLowerCase())) suggestions.add(res.unitName);
    }

    return suggestions.take(6).toList();
  }

  void _showOverlay() {
    _hideOverlay();
    final suggestions = _getSuggestions(_searchController.text);
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
        body: const DashboardSkeleton(),
      );
    }

    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? const Color(0xFFC9CBF2) : Colors.black54;

    return ListenableBuilder(
      listenable: ResourceService(),
      builder: (context, child) {
        final allResources = ResourceService().allResources;

        final filteredResources = allResources.where((res) {
          final matchesCategory = _selectedCategory == 'All' || res.type == _selectedCategory;
          final query = _searchController.text.trim();

          final searchFields = [
            res.title,
            res.unitCode,
            res.unitName,
            res.type,
            ...res.lecturers,
            ...res.targetPrograms,
          ].join(' ');

          final matchesSearch = query.isEmpty || _fuzzyMatch(query, searchFields);

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
                                        setState(() {});
                                        _showOverlay();
                                      },
                                      style: TextStyle(color: textColor),
                                      decoration: InputDecoration(
                                        hintText: 'Search materials...',
                                        hintStyle: const TextStyle(color: Colors.grey),
                                        prefixIcon: const Icon(Icons.search, color: Color(0xFF24C7FF)),
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
                                icon: Icon(Icons.tune, color: _activeFilters.isNotEmpty ? const Color(0xFF00A85A) : const Color(0xFF24C7FF)),
                                label: Text(
                                  _activeFilters.isNotEmpty ? 'Filters Active (${_activeFilters.length})' : 'Filter',
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
                    if (filteredResources.isEmpty)
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
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.8),
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
        );
      },
    );
  }
}
