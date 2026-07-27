import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/explore_models.dart';
import '../repositories/news_repository.dart';
import '../providers/theme_provider.dart';
import '../services/notification_service.dart';
import '../providers/chat_provider.dart';
import '../widgets/notification_modal.dart';
import '../screens/help_support_screen.dart';
import '../widgets/skeleton.dart';
import '../widgets/inline_ad_banner.dart';
import '../services/subscription_service.dart';
import '../services/connectivity_service.dart';
import '../providers/ui_provider.dart';
import 'more_options_screen.dart';
import 'full_article_screen.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  bool _isLoading = true;
  late PageController _pageController;
  late PageController _topStoryPageController;
  late ScrollController _tabScrollController;
  Timer? _topStoriesTimer;

  StreamSubscription<List<TopStory>>? _topStoriesSub;
  StreamSubscription<List<TrendingTopic>>? _trendingTopicsSub;
  StreamSubscription<List<NewsArticle>>? _latestNewsSub;
  StreamSubscription<List<NewsArticle>>? _allMixedNewsSub;
  StreamSubscription<List<String>>? _categoriesSub;
  final Map<String, StreamSubscription<List<NewsArticle>>> _categorySubs = {};

  List<String> _categories = [];

  late List<TopStory> _topStories;
  late List<TrendingTopic> _trendingTopics;
  late List<NewsArticle> _latestNews;
  late List<NewsArticle> _allMixedNews;
  final Map<String, List<NewsArticle>> _categoryNewsMap = {};

  @override
  void initState() {
    super.initState();
    _topStories = [];
    _trendingTopics = [];
    _latestNews = [];
    _allMixedNews = [];

    final uiState = ref.read(uiStateProvider);
    final initialIndex = _categories.indexOf(uiState.exploreCategory);
    final validInitialIndex = initialIndex != -1 ? initialIndex : 0;
    
    _pageController = PageController(initialPage: validInitialIndex);
    _topStoryPageController = PageController(initialPage: 1000);
    _tabScrollController = ScrollController();
    
    _subscribeToNewsStreams();

    // Initial scroll sync
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCategory(validInitialIndex);
    });
  }

  @override
  void dispose() {
    _topStoriesTimer?.cancel();
    _cancelNewsSubscriptions();
    _pageController.dispose();
    _topStoryPageController.dispose();
    _tabScrollController.dispose();
    super.dispose();
  }

  void _startTopStoriesTimer() {
    _topStoriesTimer?.cancel();
    if (_topStories.length >= 2) {
      _topStoriesTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (mounted && _topStoryPageController.hasClients && _topStories.isNotEmpty) {
          final currentPage = _topStoryPageController.page?.round() ?? 1000;
          _topStoryPageController.animateToPage(
            currentPage + 1,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  void _cancelNewsSubscriptions() {
    _topStoriesSub?.cancel();
    _trendingTopicsSub?.cancel();
    _latestNewsSub?.cancel();
    _allMixedNewsSub?.cancel();
    _categoriesSub?.cancel();
    for (var sub in _categorySubs.values) {
      sub.cancel();
    }
    _categorySubs.clear();
  }

  void _scrollToCategory(int index) {
    if (!_tabScrollController.hasClients) return;

    // Estimate button width (padding + text + margin)
    // Most buttons are around 80-120px wide
    const double approxButtonWidth = 100.0;
    final double screenWidth = MediaQuery.of(context).size.width;
    
    // Target position to center the button
    final double targetScroll = (index * approxButtonWidth) - (screenWidth / 2) + (approxButtonWidth / 2);
    
    // Clamp the scroll position
    final double maxScroll = _tabScrollController.position.maxScrollExtent;
    final double clampedScroll = targetScroll.clamp(0.0, maxScroll);

    _tabScrollController.animateTo(
      clampedScroll,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _subscribeToNewsStreams() {
    if (!mounted) return;
    _cancelNewsSubscriptions();

    final repository = ref.read(newsRepositoryProvider);

    try {
      _categoriesSub = repository.watchCategories().listen(
        (categories) {
          if (mounted) {
            setState(() {
              _categories = categories;
            });
            if (categories.isNotEmpty) {
              final uiState = ref.read(uiStateProvider);
              if (uiState.exploreCategory.isEmpty || !categories.contains(uiState.exploreCategory)) {
                ref.read(uiStateProvider.notifier).setExploreCategory(categories.first);
              }
            }
          }
        },
        onError: (_) {},
      );
    } catch (_) {}

    try {
      _topStoriesSub = repository.watchTopStories().listen(
        (stories) {
          if (mounted) {
            final Map<String, TopStory> uniqueMap = {};
            for (final s in stories) {
              if (!uniqueMap.containsKey(s.id)) {
                uniqueMap[s.id] = s;
              }
            }
            setState(() {
              _topStories = uniqueMap.values.toList();
            });
            _startTopStoriesTimer();
          }
        },
        onError: (_) {
          if (mounted) setState(() => _topStories = []);
        },
      );
    } catch (_) {
      _topStories = [];
    }

    try {
      _trendingTopicsSub = repository.watchTrendingTopics().listen(
        (topics) {
          if (mounted) setState(() => _trendingTopics = topics);
        },
        onError: (_) {
          if (mounted) setState(() => _trendingTopics = []);
        },
      );
    } catch (_) {
      _trendingTopics = [];
    }

    try {
      _latestNewsSub = repository.watchLatestNews().listen(
        (news) {
          if (mounted) setState(() => _latestNews = news);
        },
        onError: (_) {
          if (mounted) setState(() => _latestNews = []);
        },
      );
    } catch (_) {
      _latestNews = [];
    }

    try {
      _allMixedNewsSub = repository.watchAllMixedNews().listen(
        (news) {
          if (mounted) setState(() => _allMixedNews = news);
        },
        onError: (_) {
          if (mounted) setState(() => _allMixedNews = []);
        },
      );
    } catch (_) {
      _allMixedNews = [];
    }

    final otherCategories = _categories
        .where((c) => c != 'For You' && c != 'Trending' && c != 'Latest')
        .toList();

    for (var cat in otherCategories) {
      try {
        _categorySubs[cat] = repository.watchCategoryNews(cat).listen(
          (articles) {
            if (mounted) {
              setState(() {
                _categoryNewsMap[cat] = articles;
              });
            }
          },
          onError: (_) {
            if (mounted) {
              setState(() {
                _categoryNewsMap[cat] = [];
              });
            }
          },
        );
      } catch (_) {
        _categoryNewsMap[cat] = [];
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _getShortTrendingTitle(String title) {
    final clean = title.trim();
    if (clean.length <= 20) return clean;

    final lower = clean.toLowerCase();
    if (lower.contains('manchester united') || lower.contains('man united')) {
      return 'Man United';
    }
    if (lower.contains('rhino') || lower.contains('conservation')) {
      return 'Rhino Conservation';
    }
    if (lower.contains('university') || lower.contains('funding')) {
      return 'University Funding';
    }

    String t = clean.replaceAll(RegExp(r'^(Government|Kenya|Ministry|Official|Breaking|Update|New|Report|Launches|Announces|Unveils)\s+', caseSensitive: false), '');
    final words = t.split(RegExp(r'\s+'));
    if (words.length <= 3) return words.join(' ');

    String shortStr = '${words[0]} ${words[1]}';
    if (words.length > 2 && (shortStr.length + words[2].length + 1) <= 20) {
      shortStr += ' ${words[2]}';
    }

    return shortStr;
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String message,
    required bool isDark,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: isDark ? Colors.white30 : Colors.black26,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black45,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final uiState = ref.watch(uiStateProvider);
    final isDark = themeMode == ThemeMode.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final isOffline = ConnectivityService().isOffline;

    final firstCat = _categories.isNotEmpty ? _categories.first : 'For You';
    final canPopScreen = uiState.exploreCategory == firstCat;

    return PopScope(
      canPop: canPopScreen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_categories.isNotEmpty) {
          _onCategoryTap(_categories.first);
        }
      },
      child: Scaffold(
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
                if (isOffline)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    color: Colors.amber.shade900.withAlpha(230),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Offline Mode — Displaying cached Explore articles',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                _buildStaticHeader(context, textColor),
                _buildCategoryTabs(isDark, uiState),
                Expanded(
                  child: _categories.isEmpty
                      ? Center(
                          child: _buildEmptyState(
                            icon: Icons.newspaper_rounded,
                            message: 'No news categories available',
                            isDark: isDark,
                          ),
                        )
                      : PageView.builder(
                          controller: _pageController,
                          itemCount: _categories.length,
                          onPageChanged: (index) {
                            final cat = _categories[index];
                            ref.read(uiStateProvider.notifier).setExploreCategory(cat);
                            _scrollToCategory(index);
                          },
                          itemBuilder: (context, index) {
                            final category = _categories[index];
                            if (_isLoading) {
                              return const ExploreSkeleton();
                            }
                            return _buildCategoryContent(category, isDark, textColor);
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStaticHeader(BuildContext context, Color textColor) {
// ... rest of method ...
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

  Widget _buildCategoryContent(String category, bool isDark, Color textColor) {
    // Determine the content to display
    final Widget content;
    
    final isFirstCategory = _categories.isNotEmpty && _categories.first == category;
    final catLower = category.toLowerCase();
    
    if (isFirstCategory || catLower == 'for you') {
      if (_topStories.isEmpty && _trendingTopics.isEmpty && _allMixedNews.isEmpty) {
        content = CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: _buildEmptyState(
                  icon: Icons.newspaper_rounded,
                  message: 'No news or trending updates available',
                  isDark: isDark,
                ),
              ),
            ),
          ],
        );
      } else {
        content = CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            _buildTopStoryHero(),
            _buildTrendingNowSection(isDark, textColor),
            _buildAllFeedSection(isDark, textColor),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        );
      }
    } else if (catLower == 'trending') {
      if (_trendingTopics.isEmpty) {
        content = _buildEmptyState(
          icon: Icons.trending_up_rounded,
          message: 'No trending topics available',
          isDark: isDark,
        );
      } else {
        content = ListView.builder(
          padding: const EdgeInsets.all(16),
          physics: const BouncingScrollPhysics(),
          itemCount: _trendingTopics.length + (_trendingTopics.length ~/ 5),
          itemBuilder: (context, index) {
            if (index > 0 && index % 6 == 5) {
              if (SubscriptionService().isSubscribed) return const SizedBox.shrink();
              return InlineAdBanner();
            }
            final actualIndex = index - (index ~/ 6);
            final isStretched = actualIndex % 7 == 0;
            return _buildTrendingCard(context, _trendingTopics[actualIndex], isDark, textColor, isStretched: isStretched);
          },
        );
      }
    } else if (catLower == 'latest') {
      if (_latestNews.isEmpty) {
        content = _buildEmptyState(
          icon: Icons.newspaper_rounded,
          message: 'No latest news available',
          isDark: isDark,
        );
      } else {
        content = ListView.builder(
          padding: const EdgeInsets.all(16),
          physics: const BouncingScrollPhysics(),
          itemCount: _latestNews.length + (_latestNews.length ~/ 5),
          itemBuilder: (context, index) {
            if (index > 0 && index % 6 == 5) {
              if (SubscriptionService().isSubscribed) return const SizedBox.shrink();
              return InlineAdBanner();
            }
            final actualIndex = index - (index ~/ 6);
            final isStretched = actualIndex % 7 == 0;
            return _buildNewsCard(context, _latestNews[actualIndex], isDark, textColor, isStretched: isStretched);
          },
        );
      }
    } else {
      final articles = _categoryNewsMap[category] ?? [];
      if (articles.isEmpty) {
        content = _buildEmptyState(
          icon: Icons.article_outlined,
          message: 'No articles available in $category',
          isDark: isDark,
        );
      } else {
        content = ListView.builder(
          padding: const EdgeInsets.all(16),
          physics: const BouncingScrollPhysics(),
          itemCount: articles.length + (articles.length ~/ 5),
          itemBuilder: (context, index) {
            if (index > 0 && index % 6 == 5) {
              if (SubscriptionService().isSubscribed) return const SizedBox.shrink();
              return InlineAdBanner();
            }
            final actualIndex = index - (index ~/ 6);
            final isStretched = actualIndex % 7 == 0;
            return _buildNewsCard(context, articles[actualIndex], isDark, textColor, isStretched: isStretched, displayedCategory: category);
          },
        );
      }
    }

    return RefreshIndicator(
      onRefresh: () async {
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
                backgroundColor: Colors.redAccent.withAlpha(230),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return;
        }

        _subscribeToNewsStreams();
        await Future.delayed(const Duration(milliseconds: 500));
      },
      color: const Color(0xFF20C8FF),
      child: content,
    );
  }

  Widget _buildTopStoryHero() {
    if (_topStories.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Container(
        height: 220,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: PageView.builder(
          controller: _topStoryPageController,
          itemCount: 10000,
          itemBuilder: (context, index) {
            final realIndex = index % _topStories.length;
            final story = _topStories[realIndex];
            return GestureDetector(
              onTap: () async {
                final repository = ref.read(newsRepositoryProvider);
                NewsArticle? article = await repository.getArticle(story.id);
                article ??= NewsArticle(
                  id: story.id,
                  title: story.title,
                  category: story.category,
                  imageUrls: story.imageUrl.isNotEmpty ? [story.imageUrl] : [],
                  source: story.source,
                  timeAgo: story.timeAgo,
                  content: story.summary,
                  coverImage: story.imageUrl,
                );
                if (context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => NewsDetailScreen(
                        article: article!,
                        initialImageIndex: 0,
                      ),
                    ),
                  );
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    children: [
                      CachedNetworkImage(
                        imageUrl: story.imageUrl,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const Skeleton(borderRadius: 24),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey.shade900,
                          child: const Icon(Icons.error, color: Colors.white38),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.85),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF20C8FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            children: [
                              Text(
                                'TOP STORY',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(Icons.auto_awesome, color: Colors.white, size: 10),
                            ],
                          ),
                        ),
                      ),
                      const Positioned(
                        top: 12,
                        right: 12,
                        child: Icon(Icons.more_vert, color: Colors.white, size: 20),
                      ),
                      Positioned(
                        bottom: 20,
                        left: 16,
                        right: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              story.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${story.source} • ${story.timeAgo}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_topStories.length, (i) {
                            final isSelected = i == realIndex;
                            return Container(
                              width: isSelected ? 16 : 6,
                              height: 3,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF20C8FF) : Colors.white38,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTrendingNowSection(bool isDark, Color textColor) {
    if (_trendingTopics.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Trending Now',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () => _onCategoryTap('Trending'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Row(
                    children: [
                      Text('See all', style: TextStyle(color: Color(0xFF20C8FF), fontSize: 13)),
                      Icon(Icons.chevron_right, color: Color(0xFF20C8FF), size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 42,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _trendingTopics.length,
              itemBuilder: (context, index) {
                final topic = _trendingTopics[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => TrendingDetailScreen(topic: topic),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: topic.gradientColors[0].withOpacity(0.5),
                          width: 1.5,
                        ),
                        color: isDark ? const Color(0xFF181739) : Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: topic.gradientColors[0].withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(topic.icon, color: topic.gradientColors[0], size: 16),
                          const SizedBox(width: 8),
                          Text(
                            _getShortTrendingTitle(topic.title),
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildAllFeedSection(bool isDark, Color textColor) {
    if (_allMixedNews.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'All',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox.shrink(), // No "See all" for "All" feed
                  ],
                ),
              );
            }
            
            final adjustedIndex = index - 1;
            
            // Inline ad logic: every 5 items (index 5, 11, 17...)
            if (adjustedIndex > 0 && adjustedIndex % 6 == 5) {
              if (SubscriptionService().isSubscribed) return const SizedBox.shrink();
              return InlineAdBanner();
            }
            
            final actualDataIndex = adjustedIndex - (adjustedIndex ~/ 6);
            if (actualDataIndex >= _allMixedNews.length) return null;
            
            final article = _allMixedNews[actualDataIndex];
            final isStretched = actualDataIndex % 7 == 0;
            return _buildNewsCard(context, article, isDark, textColor, isStretched: isStretched);
          },
          childCount: _allMixedNews.length + (_allMixedNews.length ~/ 5) + 1,
        ),
      ),
    );
  }
}

Widget _buildNewsCard(BuildContext context, NewsArticle article, bool isDark, Color textColor, {bool isStretched = false, String? displayedCategory}) {
  final categoryBadgeText = displayedCategory ?? article.category;
  final providerBadgeText = article.provider != null && article.provider!.isNotEmpty ? article.provider!.toUpperCase() : null;
  final readingTimeText = '${article.readingTimeMinutes} min read';
  final summaryText = article.summary.isNotEmpty ? article.summary : article.content;

  if (isStretched) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FullArticleScreen(
              article: article,
            ),
          ),
        );
      },
      child: Container(
        height: 230,
        margin: const EdgeInsets.only(bottom: 16),
        child: Stack(
          children: [
            FadingImageThumbnail(
              imageUrls: article.imageUrls,
              width: double.infinity,
              height: 230,
              borderRadius: 20,
            ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withAlpha(153),
                    Colors.black.withAlpha(242),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF20C8FF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          categoryBadgeText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      if (providerBadgeText != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            providerBadgeText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    article.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    summaryText,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '${article.source} • ${article.timeAgo} • $readingTimeText',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Color(0xFF20C8FF),
                        size: 14,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  return GestureDetector(
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullArticleScreen(
            article: article,
          ),
        ),
      );
    },
    child: Container(
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadingImageThumbnail(imageUrls: article.imageUrls),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      categoryBadgeText,
                      style: const TextStyle(
                        color: Color(0xFF20C8FF),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    if (providerBadgeText != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E1E3F) : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          providerBadgeText,
                          style: TextStyle(
                            color: isDark ? const Color(0xFF20C8FF) : Colors.blue.shade700,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  article.title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  summaryText,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${article.source} • ${article.timeAgo} • $readingTimeText',
                        style: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black38,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.more_vert,
                      color: isDark ? Colors.white38 : Colors.black38,
                      size: 18,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class FadingImageThumbnail extends StatefulWidget {
  final List<String> imageUrls;
  final double width;
  final double height;
  final double borderRadius;

  const FadingImageThumbnail({
    super.key,
    required this.imageUrls,
    this.width = 100,
    this.height = 100,
    this.borderRadius = 12,
  });

  @override
  State<FadingImageThumbnail> createState() => _FadingImageThumbnailState();
}

class _FadingImageThumbnailState extends State<FadingImageThumbnail> {
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.imageUrls.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 4), (timer) {
        if (mounted) {
          setState(() {
            _currentIndex = (_currentIndex + 1) % widget.imageUrls.length;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 1500),
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          child: CachedNetworkImage(
            key: ValueKey<int>(_currentIndex),
            imageUrl: widget.imageUrls[_currentIndex],
            width: widget.width,
            height: widget.height,
            fit: BoxFit.cover,
            placeholder: (context, url) => Skeleton(borderRadius: widget.borderRadius),
            errorWidget: (context, url, error) => Container(
              width: widget.width,
              height: widget.height,
              color: Colors.grey.shade900,
              child: const Icon(Icons.error, color: Colors.white38),
            ),
          ),
        ),
      ),
    );
  }
}

class NewsDetailScreen extends StatefulWidget {
  final NewsArticle article;
  final int initialImageIndex;

  const NewsDetailScreen({
    super.key,
    required this.article,
    required this.initialImageIndex,
  });

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  late PageController _pageController;
  late ScrollController _scrollController;
  late int _currentPage;
  bool _hasAutoScrolled = false;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialImageIndex;
    _pageController = PageController(initialPage: widget.initialImageIndex);
    _scrollController = ScrollController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasAutoScrolled && mounted) {
        _hasAutoScrolled = true;
        Future.delayed(const Duration(milliseconds: 300), () {
          if (_scrollController.hasClients && mounted) {
            final maxScroll = _scrollController.position.maxScrollExtent;
            _scrollController.animateTo(
              maxScroll,
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOut,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final galleryImages = getFourRelevantImages(
      widget.article.imageUrls,
      widget.article.category,
      widget.article.title,
    );

    final Map<String, String> infoCards = {};
    if (widget.article.details.containsKey("What's New?")) {
      infoCards["What's New?"] = widget.article.details["What's New?"]!;
    } else {
      infoCards["What's New?"] = "Key highlights and latest developments surrounding ${widget.article.title}.";
    }

    if (widget.article.details.containsKey("Key Impact & Context")) {
      infoCards["Key Impact & Context"] = widget.article.details["Key Impact & Context"]!;
    } else if (widget.article.details.containsKey("Who Benefits?")) {
      infoCards["Key Impact & Context"] = widget.article.details["Who Benefits?"]!;
    } else {
      infoCards["Key Impact & Context"] = "Broader economic, social, and policy implications for ${widget.article.category} stakeholders.";
    }

    if (widget.article.details.containsKey("Detailed Coverage")) {
      infoCards["Detailed Coverage"] = widget.article.details["Detailed Coverage"]!;
    } else if (widget.article.details.containsKey("Stay Informed")) {
      infoCards["Detailed Coverage"] = widget.article.details["Stay Informed"]!;
    } else {
      infoCards["Detailed Coverage"] = "Comprehensive analysis, verified sources, and real-time updates provided by ${widget.article.source}.";
    }

    return Scaffold(
      backgroundColor: const Color(0xFF070716),
      body: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 400,
            pinned: true,
            stretch: true,
            backgroundColor: const Color(0xFF070716),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.grid_view_rounded, color: Colors.white),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: () {},
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [
                StretchMode.zoomBackground,
                StretchMode.blurBackground,
              ],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _pageController,
                    itemCount: galleryImages.length,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      return CachedNetworkImage(
                        imageUrl: galleryImages[index],
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const Skeleton(),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey.shade900,
                          child: const Icon(Icons.error, color: Colors.white38),
                        ),
                      );
                    },
                  ),
                  IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            const Color(0xFF070716).withAlpha(128),
                            const Color(0xFF070716),
                          ],
                          stops: const [0.7, 0.9, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        galleryImages.length,
                        (index) => Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _currentPage == index
                                ? const Color(0xFF20C8FF)
                                : Colors.white.withAlpha(102),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Headline
                  Text(
                    widget.article.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 2. Category
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF20C8FF).withAlpha(38),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF20C8FF).withAlpha(102),
                      ),
                    ),
                    child: Text(
                      widget.article.category.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF20C8FF),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 3. Source & Time
                  Row(
                    children: [
                      const Icon(Icons.newspaper_rounded, color: Colors.white70, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        '${widget.article.source} • ${widget.article.timeAgo}',
                        style: TextStyle(
                          color: Colors.white.withAlpha(179),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 4. Article Preview Summary
                  Text(
                    widget.article.content,
                    style: TextStyle(
                      color: Colors.white.withAlpha(230),
                      fontSize: 15,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 5. Information Cards (What's New?, Key Impact & Context, Detailed Coverage)
                  const Divider(color: Colors.white10, height: 32),
                  ...infoCards.entries.map((entry) {
                    IconData icon;
                    if (entry.key == "What's New?") {
                      icon = Icons.auto_awesome_rounded;
                    } else if (entry.key == "Key Impact & Context") {
                      icon = Icons.insights_rounded;
                    } else {
                      icon = Icons.library_books_rounded;
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF12122A),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF181739),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF20C8FF).withAlpha(77)),
                              ),
                              child: Icon(icon, color: const Color(0xFF20C8FF), size: 20),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.key,
                                    style: const TextStyle(
                                      color: Color(0xFF20C8FF),
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    entry.value,
                                    style: TextStyle(
                                      color: Colors.white.withAlpha(204),
                                      fontSize: 13,
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 16),

                  // 6. Read Article Button
                  Center(
                    child: Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF20C8FF), Color(0xFF287BFF)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF20C8FF).withAlpha(77),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => FullArticleScreen(
                                article: widget.article,
                                viewerUrl: widget.article.viewerUrl,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Read Article',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TrendingDetailScreen extends StatefulWidget {
  final TrendingTopic topic;

  const TrendingDetailScreen({super.key, required this.topic});

  @override
  State<TrendingDetailScreen> createState() => _TrendingDetailScreenState();
}

class _TrendingDetailScreenState extends State<TrendingDetailScreen> {
  late PageController _pageController;
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _currentPage = 0;
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070716),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 400,
            pinned: true,
            stretch: true,
            backgroundColor: const Color(0xFF070716),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [
                StretchMode.zoomBackground,
                StretchMode.blurBackground,
              ],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _pageController,
                    itemCount: widget.topic.imageUrls.length,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      return CachedNetworkImage(
                        imageUrl: widget.topic.imageUrls[index],
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const Skeleton(),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey.shade900,
                          child: const Icon(Icons.error, color: Colors.white38),
                        ),
                      );
                    },
                  ),
                  IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            const Color(0xFF070716).withOpacity(0.5),
                            const Color(0xFF070716),
                          ],
                          stops: const [0.7, 0.9, 1.0],
                        ),
                      ),
                    ),
                  ),
                  if (widget.topic.imageUrls.length > 1)
                    Positioned(
                      bottom: 20,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          widget.topic.imageUrls.length,
                          (index) => Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _currentPage == index
                                  ? const Color(0xFF20C8FF)
                                  : Colors.white.withOpacity(0.4),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(widget.topic.icon, color: widget.topic.gradientColors[0], size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.topic.title,
                          style: const TextStyle(
                            color: Color(0xFF20C8FF),
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Trending Insight',
                    style: TextStyle(
                      color: Color(0xFF20C8FF),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.topic.description,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ...widget.topic.details.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF181739),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Icon(widget.topic.icon, color: widget.topic.gradientColors[0], size: 20),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.key,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  entry.value,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(color: Colors.white10, height: 40),
                  Center(
                    child: Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF20C8FF), Color(0xFF287BFF)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF20C8FF).withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => FullArticleScreen(
                                viewerUrl: null,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Read Article...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildTrendingCard(BuildContext context, TrendingTopic topic, bool isDark, Color textColor, {bool isStretched = false}) {
  if (isStretched) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TrendingDetailScreen(topic: topic),
          ),
        );
      },
      child: Container(
        height: 220,
        margin: const EdgeInsets.only(bottom: 16),
        child: Stack(
          children: [
            FadingImageThumbnail(
              imageUrls: topic.imageUrls,
              width: double.infinity,
              height: 220,
              borderRadius: 20,
            ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withOpacity(0.9),
                    Colors.black.withOpacity(0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: topic.gradientColors[0],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(topic.icon, color: Colors.white, size: 10),
                        const SizedBox(width: 4),
                        const Text(
                          'TRENDING',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: MediaQuery.of(context).size.width * 0.6,
                    child: Text(
                      topic.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: MediaQuery.of(context).size.width * 0.7,
                    child: Text(
                      topic.description,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        '${topic.source} • ${topic.timeAgo}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: topic.gradientColors[0],
                        size: 14,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  return GestureDetector(
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TrendingDetailScreen(topic: topic),
        ),
      );
    },
    child: Container(
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadingImageThumbnail(imageUrls: topic.imageUrls),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(topic.icon, color: topic.gradientColors[0], size: 12),
                    const SizedBox(width: 4),
                    Text(
                      'TRENDING',
                      style: TextStyle(
                        color: topic.gradientColors[0],
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  topic.title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  topic.description,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${topic.source} • ${topic.timeAgo}',
                        style: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black38,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.more_vert,
                      color: isDark ? Colors.white38 : Colors.black38,
                      size: 18,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
