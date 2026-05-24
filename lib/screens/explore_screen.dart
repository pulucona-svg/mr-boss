import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/explore_models.dart';
import '../providers/theme_provider.dart';
import '../services/notification_service.dart';
import '../providers/chat_provider.dart';
import '../widgets/notification_modal.dart';
import '../screens/help_support_screen.dart';
import '../widgets/skeleton.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  String _selectedCategory = 'For You';
  bool _isLoading = true;

  final List<String> _categories = [
    'For You',
    'Trending',
    'Kenya',
    'World',
    'Sports',
    'Tech',
    'Business',
    'Health',
    'Agriculture',
    'Entertainment',
  ];

  late List<TopStory> _topStories;
  late List<TrendingTopic> _trendingTopics;
  late List<NewsArticle> _latestNews;

  @override
  void initState() {
    super.initState();
    _loadMockData();
  }

  void _loadMockData() async {
    // Simulate loading
    await Future.delayed(const Duration(milliseconds: 1500));
    
    _topStories = [
      TopStory(
        id: '1',
        title: 'Ruto: Kenya to Create 2M Jobs by 2027',
        summary: 'The President says the government is focused on economic growth and youth empowerment.',
        imageUrl: 'https://images.unsplash.com/photo-1597058811219-41b497f4d2bb?q=80&w=2000&auto=format&fit=crop',
        source: 'Citizen Digital',
        timeAgo: '2h ago',
        category: 'TOP STORY',
      ),
      TopStory(
        id: '2',
        title: 'Tech Giants Announce New AI Hub in Nairobi',
        summary: 'Major investment aimed at boosting digital infrastructure in East Africa.',
        imageUrl: 'https://images.unsplash.com/photo-1518770660439-4636190af475?q=80&w=2000&auto=format&fit=crop',
        source: 'TechCrunch',
        timeAgo: '4h ago',
        category: 'TOP STORY',
      ),
    ];

    _trendingTopics = [
      TrendingTopic(
        id: '1',
        title: '#FinanceBill2024',
        icon: Icons.trending_up_rounded,
        gradientColors: [const Color(0xFF20C8FF), const Color(0xFF287BFF)],
      ),
      TrendingTopic(
        id: '2',
        title: 'Raila Odinga',
        icon: Icons.person_rounded,
        gradientColors: [const Color(0xFF00A85A), const Color(0xFF00D1FF)],
      ),
      TrendingTopic(
        id: '3',
        title: 'Premier League',
        icon: Icons.sports_soccer_rounded,
        gradientColors: [const Color(0xFF7B5CFF), const Color(0xFFFF4667)],
      ),
      TrendingTopic(
        id: '4',
        title: 'Olympics 2024',
        icon: Icons.emoji_events_rounded,
        gradientColors: [const Color(0xFFFF8A00), const Color(0xFFFFD600)],
      ),
      TrendingTopic(
        id: '5',
        title: 'Trending Kenya',
        icon: Icons.whatshot_rounded,
        gradientColors: [const Color(0xFFFF4667), const Color(0xFF7B5CFF)],
      ),
    ];

    _latestNews = [
      NewsArticle(
        id: '1',
        title: 'Fuel Prices Expected to Drop Next Month - EPRA',
        category: 'KENYA',
        imageUrls: [
          'https://images.unsplash.com/photo-1526628953301-3e589a6a8b74?q=80&w=800&auto=format&fit=crop',
          'https://images.unsplash.com/photo-15206304640581-d334cdbbf45e?q=80&w=800&auto=format&fit=crop',
        ],
        source: 'Nation Africa',
        timeAgo: '1h ago',
        content: 'The Energy and Petroleum Regulatory Authority (EPRA) has indicated a potential drop in fuel prices starting next month, following a decrease in landed costs of petroleum products.',
        details: {
          'What\'s New?': 'Projected price reduction across all petroleum products.',
          'Who Benefits?': 'Motorists, public transport operators, and general consumers.',
          'Key Date': 'New prices to be announced on the 14th of next month.',
          'Stay Informed': 'Follow EPRA official channels for the final price review.'
        },
      ),
      NewsArticle(
        id: '2',
        title: 'Gaza Ceasefire Talks Resume in Cairo',
        category: 'WORLD',
        imageUrls: [
          'https://images.unsplash.com/photo-1547721064-36202335dddb?q=80&w=800&auto=format&fit=crop',
          'https://images.unsplash.com/photo-1518091043644-c1d4457512c6?q=80&w=800&auto=format&fit=crop',
        ],
        source: 'Al Jazeera',
        timeAgo: '2h ago',
        content: 'Diplomatic efforts to secure a ceasefire in Gaza have gained momentum as mediators resume high-level talks in Cairo aiming to end the months-long conflict.',
        details: {
          'What\'s New?': 'New compromise proposals being discussed by all parties.',
          'Who Benefits?': 'Civilians in conflict zones and regional stability.',
          'Key Date': 'Talks expected to continue throughout the week.',
          'Stay Informed': 'Live updates available on Al Jazeera and global news outlets.'
        },
      ),
      NewsArticle(
        id: '3',
        title: 'Arsenal Beat Man United 2-1 in Thrilling Clash',
        category: 'SPORTS',
        imageUrls: [
          'https://images.unsplash.com/photo-1518091043644-c1d4457512c6?q=80&w=800&auto=format&fit=crop',
          'https://images.unsplash.com/photo-1574629810360-7efbbe195018?q=80&w=800&auto=format&fit=crop',
        ],
        source: 'BBC Sport',
        timeAgo: '3h ago',
        content: 'Arsenal secured a crucial victory in their title chase with a hard-fought 2-1 win over Manchester United at the Emirates Stadium.',
        details: {
          'What\'s New?': 'Late winner from Bukayo Saka seals the three points.',
          'Who Benefits?': 'Arsenal title hopes remain alive; fans celebrate.',
          'Key Date': 'Next match scheduled for this coming Sunday.',
          'Stay Informed': 'Full match analysis and highlights on BBC Sport.'
        },
      ),
      NewsArticle(
        id: '4',
        title: 'Apple Announces iPhone 16 Series With AI Features',
        category: 'TECH',
        imageUrls: [
          'https://images.unsplash.com/photo-1616348436168-de43ad0db179?q=80&w=800&auto=format&fit=crop',
          'https://images.unsplash.com/photo-1510557880182-3d4d3cba3f21?q=80&w=800&auto=format&fit=crop',
        ],
        source: 'TechCrunch',
        timeAgo: '4h ago',
        content: 'Apple has officially unveiled the iPhone 16 series, featuring advanced Apple Intelligence and a dedicated Camera Control button across all models.',
        details: {
          'What\'s New?': 'Apple Intelligence integration and faster A18 chips.',
          'Who Benefits?': 'Tech enthusiasts and current iPhone users looking to upgrade.',
          'Key Date': 'Pre-orders start this Friday; available next week.',
          'Stay Informed': 'Detailed reviews and specs on TechCrunch.'
        },
      ),
      NewsArticle(
        id: '5',
        title: 'Nairobi Expressway to Undergo Major Maintenance',
        category: 'KENYA',
        imageUrls: [
          'https://images.unsplash.com/photo-1519494026892-80bbd2d6fd0d?q=80&w=800&auto=format&fit=crop',
          'https://images.unsplash.com/photo-1545143333-11bb24019bca?q=80&w=800&auto=format&fit=crop',
        ],
        source: 'The Standard',
        timeAgo: '5h ago',
        content: 'Commuters in Nairobi have been advised of potential traffic disruptions as sections of the Nairobi Expressway undergo scheduled structural maintenance.',
        details: {
          'What\'s New?': 'Phased closure of specific toll exit ramps for repairs.',
          'Who Benefits?': 'Long-term safety and efficiency for all road users.',
          'Key Date': 'Maintenance work begins at midnight tonight.',
          'Stay Informed': 'Check MOJA Expressway app for real-time traffic alerts.'
        },
      ),
      NewsArticle(
        id: '6',
        title: 'New Health Insurance Model to Begin in July',
        category: 'HEALTH',
        imageUrls: [
          'https://images.unsplash.com/photo-1505751172177-51ad1857f032?q=80&w=800&auto=format&fit=crop',
          'https://images.unsplash.com/photo-1576091160550-2173dba999ef?q=80&w=800&auto=format&fit=crop',
        ],
        source: 'Kenyans.co.ke',
        timeAgo: '6h ago',
        content: 'The new health insurance model, set to begin in July, will be implemented at AFya House and aims to make quality healthcare more accessible, affordable, and inclusive for all.',
        details: {
          'What\'s New?': 'The model introduces improved coverage, lower out-of-pocket costs, and simplified enrollment for individuals and families.',
          'Who Benefits?': 'Families, individuals, and vulnerable groups will have greater access to essential health services.',
          'Key Date': 'Implementation begins in July at AFya House.',
          'Stay Informed': 'Follow official updates for more details on registration and benefits.'
        },
      ),
      NewsArticle(
        id: '7',
        title: 'Global Markets Rally Amid Inflation Hopes',
        category: 'BUSINESS',
        imageUrls: [
          'https://images.unsplash.com/photo-1611974717483-360099195d43?q=80&w=800&auto=format&fit=crop',
          'https://images.unsplash.com/photo-1526628953301-3e589a6a8b74?q=80&w=800&auto=format&fit=crop',
        ],
        source: 'Reuters',
        timeAgo: '7h ago',
        content: 'Stock markets around the world saw significant gains today as new data suggests inflation may be cooling faster than previously anticipated by central banks.',
        details: {
          'What\'s New?': 'Global indices up 2% on average after positive CPI data.',
          'Who Benefits?': 'Investors and businesses looking for lower borrowing costs.',
          'Key Date': 'Next Fed meeting in two weeks will be closely watched.',
          'Stay Informed': 'Market analysis available on Reuters Business.'
        },
      ),
      NewsArticle(
        id: '8',
        title: 'Central Bank Maintains Key Interest Rate',
        category: 'BUSINESS',
        imageUrls: [
          'https://images.unsplash.com/photo-1526304640581-d334cdbbf45e?q=80&w=800&auto=format&fit=crop',
          'https://images.unsplash.com/photo-1454165833767-027ffea9e78b?q=80&w=800&auto=format&fit=crop',
        ],
        source: 'Business Daily',
        timeAgo: '8h ago',
        content: 'The Monetary Policy Committee has decided to keep the benchmark lending rate unchanged, citing the need to further stabilize the local currency and anchor inflation expectations.',
        details: {
          'What\'s New?': 'MPC keeps base rate at 13.0% after its latest session.',
          'Who Benefits?': 'Borrowers who were fearing another hike in loan repayments.',
          'Key Date': 'Rate will be reviewed again in sixty days.',
          'Stay Informed': 'Read the full MPC statement on Business Daily.'
        },
      ),
      NewsArticle(
        id: '9',
        title: 'Safaricom to Expand 5G Network to More Counties',
        category: 'TECH',
        imageUrls: [
          'https://images.unsplash.com/photo-1511497584788-876760111969?q=80&w=800&auto=format&fit=crop',
          'https://images.unsplash.com/photo-1563986768609-322da13575f3?q=80&w=800&auto=format&fit=crop',
        ],
        source: 'CIO Africa',
        timeAgo: '9h ago',
        content: 'Kenya\'s leading telecommunications provider is set to roll out its ultra-fast 5G network to twenty additional counties by the end of this year.',
        details: {
          'What\'s New?': 'Installation of 500 new 5G sites across regional hubs.',
          'Who Benefits?': 'SMEs and tech-savvy consumers in newly covered areas.',
          'Key Date': 'Phase 1 of expansion concludes next month.',
          'Stay Informed': 'Coverage maps available on Safaricom website.'
        },
      ),
      NewsArticle(
        id: '10',
        title: 'Tourism Sector Sees Recovery in Q1 2024',
        category: 'BUSINESS',
        imageUrls: [
          'https://images.unsplash.com/photo-1469854523086-cc02fe5d8800?q=80&w=800&auto=format&fit=crop',
          'https://images.unsplash.com/photo-1501785888041-af3ef285b470?q=80&w=800&auto=format&fit=crop',
        ],
        source: 'Tourism Weekly',
        timeAgo: '10h ago',
        content: 'International visitor arrivals have reached pre-pandemic levels in the first quarter, signaling a full recovery for the country\'s tourism industry.',
        details: {
          'What\'s New?': '30% increase in arrivals compared to Q1 2023.',
          'Who Benefits?': 'Hoteliers, tour operators, and the national economy.',
          'Key Date': 'Peak season expected to start in June.',
          'Stay Informed': 'Quarterly report available on Tourism Board site.'
        },
      ),
    ];

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
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

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    
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
          child: RefreshIndicator(
            onRefresh: () async {
              setState(() => _isLoading = true);
              _loadMockData();
            },
            color: const Color(0xFF20C8FF),
            child: CustomScrollView(
              slivers: [
                _buildHeader(context, textColor),
                _buildCategoryTabs(isDark),
                if (_isLoading)
                  const SliverFillRemaining(
                    child: ExploreSkeleton(),
                  )
                else ...[
                  _buildTopStoryHero(),
                  _buildTrendingNowSection(isDark, textColor),
                  _buildLatestNewsSection(isDark, textColor),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Color textColor) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverToBoxAdapter(
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
      ),
    );
  }

  Widget _buildCategoryTabs(bool isDark) {
    const neonCyan = Color(0xFF00F2FF);
    return SliverToBoxAdapter(
      child: Container(
        height: 38,
        margin: const EdgeInsets.only(top: 4, bottom: 8),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _categories.length + 1,
          itemBuilder: (context, index) {
            if (index == _categories.length) {
              return Container(
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
              );
            }
            final category = _categories[index];
            final isSelected = _selectedCategory == category;
            return GestureDetector(
              onTap: () => setState(() => _selectedCategory = category),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(
                          colors: [neonCyan, neonCyan.withOpacity(0.8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isSelected ? null : (isDark ? const Color(0xFF181739).withOpacity(0.5) : Colors.transparent),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? neonCyan : (isDark ? Colors.white10 : Colors.black12),
                    width: 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: neonCyan.withOpacity(0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ]
                      : [],
                ),
                child: Center(
                  child: Text(
                    category,
                    style: TextStyle(
                      color: isSelected ? Colors.black : (isDark ? Colors.white70 : Colors.black54),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopStoryHero() {
    return SliverToBoxAdapter(
      child: Container(
        height: 220,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: PageView.builder(
          itemCount: _topStories.length,
          itemBuilder: (context, index) {
            final story = _topStories[index];
            return Container(
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
                          return Container(
                            width: i == index ? 16 : 6,
                            height: 3,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: i == index ? const Color(0xFF20C8FF) : Colors.white38,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTrendingNowSection(bool isDark, Color textColor) {
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
                  onPressed: () {},
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
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _trendingTopics.length,
              itemBuilder: (context, index) {
                final topic = _trendingTopics[index];
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: topic.gradientColors.map((c) => c.withOpacity(0.15)).toList(),
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: topic.gradientColors[0].withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(topic.icon, color: topic.gradientColors[0], size: 16),
                      const SizedBox(width: 6),
                      Text(
                        topic.title.startsWith('#') ? topic.title : '#${topic.title.replaceAll(' ', '')}',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
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

  Widget _buildLatestNewsSection(bool isDark, Color textColor) {
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
                      'Latest News',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: () {},
                      child: const Text('See all', style: TextStyle(color: Color(0xFF20C8FF))),
                    ),
                  ],
                ),
              );
            }
            final article = _latestNews[index - 1];
            return _buildNewsCard(article, isDark, textColor);
          },
          childCount: _latestNews.length + 1,
        ),
      ),
    );
  }

  Widget _buildNewsCard(NewsArticle article, bool isDark, Color textColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
                Text(
                  article.category,
                  style: const TextStyle(
                    color: Color(0xFF20C8FF),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${article.source} • ${article.timeAgo}',
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
    );
  }
}

class FadingImageThumbnail extends StatefulWidget {
  final List<String> imageUrls;
  const FadingImageThumbnail({super.key, required this.imageUrls});

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
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NewsDetailScreen(
              article: (context.findAncestorWidgetOfExactType<ExploreScreen>() != null) 
                  ? (context.findAncestorStateOfType<_ExploreScreenState>()!._latestNews.firstWhere((a) => a.imageUrls == widget.imageUrls))
                  : NewsArticle(id: '', title: '', category: '', imageUrls: widget.imageUrls, source: '', timeAgo: ''), // Fallback
              initialImageIndex: _currentIndex,
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 100,
          height: 100,
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
              width: 100,
              height: 100,
              fit: BoxFit.cover,
              placeholder: (context, url) => const Skeleton(borderRadius: 12),
              errorWidget: (context, url, error) => Container(
                width: 100,
                height: 100,
                color: Colors.grey.shade900,
                child: const Icon(Icons.error, color: Colors.white38),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NewsDetailScreen extends StatelessWidget {
  final NewsArticle article;
  final int initialImageIndex;

  const NewsDetailScreen({
    super.key,
    required this.article,
    required this.initialImageIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070716),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 450,
            pinned: true,
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
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: article.imageUrls[initialImageIndex],
                    fit: BoxFit.cover,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          const Color(0xFF070716).withOpacity(0.8),
                          const Color(0xFF070716),
                        ],
                        stops: const [0.6, 0.9, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 40,
                    left: 20,
                    right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          article.category,
                          style: const TextStyle(
                            color: Color(0xFF20C8FF),
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          article.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'More Information',
                    style: TextStyle(
                      color: Color(0xFF20C8FF),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    article.content,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ...article.details.entries.map((entry) {
                    IconData icon;
                    switch (entry.key) {
                      case 'What\'s New?':
                        icon = Icons.group_outlined;
                        break;
                      case 'Who Benefits?':
                        icon = Icons.shield_outlined;
                        break;
                      case 'Key Date':
                        icon = Icons.calendar_today_outlined;
                        break;
                      case 'Stay Informed':
                        icon = Icons.info_outline;
                        break;
                      default:
                        icon = Icons.info_outline;
                    }
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
                            child: Icon(icon, color: const Color(0xFF20C8FF), size: 20),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Media, links, and docs',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            '14',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.5), size: 20),
                        ],
                      ),
                    ],
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
