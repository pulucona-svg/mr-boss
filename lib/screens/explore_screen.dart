import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/theme_provider.dart';
import '../services/notification_service.dart';
import '../providers/chat_provider.dart';
import '../widgets/notification_modal.dart';
import '../screens/help_support_screen.dart';
import '../services/subscription_service.dart';
import '../services/connectivity_service.dart';
import '../providers/ui_provider.dart';
import '../providers/service_providers.dart';
import '../widgets/resource_card.dart';
import '../services/resource_service.dart';
import 'more_options_screen.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  late PageController _pageController;
  late ScrollController _tabScrollController;

  final List<String> _categories = [
    'All',
    'Tech',
    'Business',
    'Health',
    'Agriculture',
    'Education',
  ];

  @override
  void initState() {
    super.initState();
    final uiState = ref.read(uiStateProvider);
    String currentCat = uiState.exploreCategory;
    if (!_categories.contains(currentCat)) {
      currentCat = 'All';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(uiStateProvider.notifier).setExploreCategory('All');
      });
    }

    final initialIndex = _categories.indexOf(currentCat);
    final validInitialIndex = initialIndex != -1 ? initialIndex : 0;
    
    _pageController = PageController(initialPage: validInitialIndex);
    _tabScrollController = ScrollController();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCategory(validInitialIndex);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _tabScrollController.dispose();
    super.dispose();
  }

  void _scrollToCategory(int index) {
    if (!_tabScrollController.hasClients) return;

    const double approxButtonWidth = 100.0;
    final double screenWidth = MediaQuery.of(context).size.width;
    
    final double targetScroll = (index * approxButtonWidth) - (screenWidth / 2) + (approxButtonWidth / 2);
    
    final double maxScroll = _tabScrollController.position.maxScrollExtent;
    final double clampedScroll = targetScroll.clamp(0.0, maxScroll);

    _tabScrollController.animateTo(
      clampedScroll,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _showNotifications() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NotificationModal(),
    );
  }

  void _onCategoryTap(String category) {
    ref.read(uiStateProvider.notifier).setExploreCategory(category);
    final index = _categories.indexOf(category);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  List<Resource> _filterResourcesByCategory(List<Resource> resources, String category) {
    if (category == 'All') {
      return resources;
    }
    
    final String normalizedCat = category.toLowerCase();
    
    return resources.where((r) {
      // 1. Check target programs
      final matchesProgram = r.targetPrograms.any((p) {
        final lp = p.toLowerCase();
        if (normalizedCat == 'tech') {
          return lp.contains('comput') || lp.contains('science') || lp.contains('information') || lp.contains('tech') || lp.contains('software');
        } else if (normalizedCat == 'business') {
          return lp.contains('business') || lp.contains('commerce') || lp.contains('bcom') || lp.contains('econom') || lp.contains('account') || lp.contains('finance') || lp.contains('management');
        } else if (normalizedCat == 'health') {
          return lp.contains('health') || lp.contains('medic') || lp.contains('nurs') || lp.contains('biomed') || lp.contains('psychol');
        } else if (normalizedCat == 'agriculture') {
          return lp.contains('agri') || lp.contains('crop') || lp.contains('soil') || lp.contains('farm') || lp.contains('animal') || lp.contains('horticulture');
        } else if (normalizedCat == 'education') {
          return lp.contains('education') || lp.contains('teach');
        }
        return false;
      });

      if (matchesProgram) return true;

      // 2. Check course code / unit name as fallback
      final code = r.unitCode.toLowerCase();
      final name = r.unitName.toLowerCase();
      final title = r.title.toLowerCase();

      if (normalizedCat == 'tech') {
        return code.startsWith('comp') || code.startsWith('dict') || name.contains('comput') || name.contains('digital') || name.contains('software') || name.contains('programming') || title.contains('comput') || title.contains('programming');
      } else if (normalizedCat == 'business') {
        return code.startsWith('bcom') || code.startsWith('econ') || code.startsWith('busm') || name.contains('business') || name.contains('econom') || name.contains('account') || name.contains('finance') || name.contains('management') || title.contains('business') || title.contains('accounting');
      } else if (normalizedCat == 'health') {
        return code.startsWith('nurs') || code.startsWith('biol') || name.contains('health') || name.contains('biolog') || name.contains('anatomy') || title.contains('health') || title.contains('biology');
      } else if (normalizedCat == 'agriculture') {
        return code.startsWith('agri') || name.contains('agri') || name.contains('crop') || name.contains('soil') || title.contains('agri') || title.contains('agriculture');
      } else if (normalizedCat == 'education') {
        return code.startsWith('edse') || code.startsWith('edfd') || code.startsWith('edci') || code.startsWith('epsy') || code.startsWith('edpy') || name.contains('education') || title.contains('education');
      }

      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final uiState = ref.watch(uiStateProvider);
    final isDark = themeMode == ThemeMode.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    // Listen to real-time resources from the provider
    final resourceService = ref.watch(resourceServiceProvider);
    final allResources = resourceService.allResources;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF070716) : Colors.white,
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
          child: Column(
            children: [
              _buildStaticHeader(context, textColor),
              _buildCategoryTabs(isDark, uiState),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _categories.length,
                  onPageChanged: (index) {
                    ref.read(uiStateProvider.notifier).setExploreCategory(_categories[index]);
                    _scrollToCategory(index);
                  },
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    final filtered = _filterResourcesByCategory(allResources, category);
                    return RefreshIndicator(
                      onRefresh: () async {
                        final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
                        if (userId.isNotEmpty) {
                          await ref.read(resourceServiceProvider).refresh(userId);
                        }
                      },
                      color: const Color(0xFF20C8FF),
                      child: _buildCategoryGrid(filtered, isDark),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStaticHeader(BuildContext context, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Explore',
            style: TextStyle(
              color: textColor,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
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
    );
  }

  Widget _buildCategoryTabs(bool isDark, UIState uiState) {
    const neonCyan = Color(0xFF00F2FF);
    return Container(
      height: 38,
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      child: ListView.builder(
        controller: _tabScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length + 1,
        itemBuilder: (context, index) {
          if (index == _categories.length) {
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const MoreOptionsScreen()),
                );
              },
              child: Container(
                width: 44,
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF181739) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                ),
                child: Center(
                  child: Icon(
                    Icons.menu_rounded,
                    color: isDark ? Colors.white70 : Colors.black54,
                    size: 20,
                  ),
                ),
              ),
            );
          }
          final category = _categories[index];
          final isSelected = uiState.exploreCategory == category;
          return GestureDetector(
            onTap: () => _onCategoryTap(category),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOutSine,
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isSelected 
                    ? neonCyan.withOpacity(0.9) 
                    : (isDark ? const Color(0xFF181739).withOpacity(0.3) : Colors.transparent),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? neonCyan : (isDark ? Colors.white10 : Colors.black12),
                  width: 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: neonCyan.withOpacity(0.6),
                          blurRadius: 15,
                          spreadRadius: 1,
                          offset: const Offset(0, 0),
                        )
                      ]
                    : [],
              ),
              child: Center(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeIn,
                  style: TextStyle(
                    color: isSelected ? Colors.black : (isDark ? Colors.white70 : Colors.black54),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                  ),
                  child: Text(category),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryGrid(List<Resource> resources, bool isDark) {
    if (resources.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 64,
              color: isDark ? Colors.white30 : Colors.black26,
            ),
            const SizedBox(height: 16),
            Text(
              'No resources found',
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to upload one!',
              style: TextStyle(
                color: isDark ? Colors.white30 : Colors.black38,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: resources.length,
      itemBuilder: (context, index) {
        final res = resources[index];
        return ResourceCard(
          resource: res,
          onLikeToggle: () => ref.read(resourceServiceProvider).toggleLike(res.id, res.isLiked),
          onViewIncrement: () => ref.read(resourceServiceProvider).incrementViews(res.id),
          showPin: false,
          onTap: () {},
        );
      },
    );
  }
}
