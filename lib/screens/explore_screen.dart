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
    'Latest',
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
        imageUrl: 'https://images.unsplash.com/photo-1591115765373-5056e382d512?q=80&w=2000&auto=format&fit=crop',
        source: 'Citizen Digital',
        timeAgo: '2h ago',
        category: 'TOP STORY',
      ),
      TopStory(
        id: '2',
        title: 'Tech Giants Announce New AI Hub in Nairobi',
        summary: 'Major investment aimed at boosting digital infrastructure in East Africa.',
        imageUrl: 'https://images.unsplash.com/photo-1485827404703-89b55fcc595e?q=80&w=2000&auto=format&fit=crop',
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
        imageUrls: ['https://images.unsplash.com/photo-1526304640581-d334cdbbf45e?q=80&w=800&auto=format&fit=crop'],
        source: 'KBC News',
        timeAgo: '1h ago',
        description: 'Nationwide debates intensify as citizens and lawmakers dissect the proposed fiscal measures aimed at economic recovery.',
      ),
      TrendingTopic(
        id: '2',
        title: 'Raila Odinga',
        icon: Icons.person_rounded,
        gradientColors: [const Color(0xFF00A85A), const Color(0xFF00D1FF)],
        imageUrls: ['https://images.unsplash.com/photo-1591115765373-5056e382d512?q=80&w=800&auto=format&fit=crop'],
        source: 'Citizen Digital',
        timeAgo: '2h ago',
        description: 'The veteran politician makes a bold statement on national unity, sparking fresh conversations about the country\'s political future.',
      ),
      TrendingTopic(
        id: '3',
        title: 'Premier League',
        icon: Icons.sports_soccer_rounded,
        gradientColors: [const Color(0xFF7B5CFF), const Color(0xFFFF4667)],
        imageUrls: ['https://images.unsplash.com/photo-1508098682722-e99c43a406b2?q=80&w=800&auto=format&fit=crop'],
        source: 'Sky Sports',
        timeAgo: '3h ago',
        description: 'A thrilling weekend of football as the title race heats up with unexpected upsets and masterclass performances.',
      ),
      TrendingTopic(
        id: '4',
        title: 'Olympics 2024',
        icon: Icons.emoji_events_rounded,
        gradientColors: [const Color(0xFFFF8A00), const Color(0xFFFFD600)],
        imageUrls: ['https://images.unsplash.com/photo-1569517282132-25d22f4573e6?q=80&w=800&auto=format&fit=crop'],
        source: 'BBC News',
        timeAgo: '4h ago',
        description: 'World records tumble as elite athletes gather for the ultimate display of sporting excellence and human spirit.',
      ),
      TrendingTopic(
        id: '5',
        title: 'Trending Kenya',
        icon: Icons.whatshot_rounded,
        gradientColors: [const Color(0xFFFF4667), const Color(0xFF7B5CFF)],
        imageUrls: ['https://images.unsplash.com/photo-1489392191049-fc10c97e64b6?q=80&w=800&auto=format&fit=crop'],
        source: 'Standard News',
        timeAgo: '5h ago',
        description: 'From viral challenges to cultural milestones, discover what has captured the collective imagination of the Kenyan digital space.',
      ),
      TrendingTopic(
        id: '6',
        title: 'World Cup 2026',
        icon: Icons.emoji_events_rounded,
        gradientColors: [const Color(0xFF20C8FF), const Color(0xFF7B5CFF)],
        imageUrls: ['https://images.unsplash.com/photo-1551244072-5d12893278ab?q=80&w=800&auto=format&fit=crop'],
        source: 'FIFA',
        timeAgo: '6h ago',
        description: 'Host cities prepare for a global football extravaganza that promises to be the largest and most inclusive tournament ever.',
      ),
      TrendingTopic(
        id: '7',
        title: 'Bitcoin Surge',
        icon: Icons.currency_bitcoin_rounded,
        gradientColors: [const Color(0xFFFF9900), const Color(0xFFFFCC00)],
        imageUrls: ['https://images.unsplash.com/photo-1518546305927-5a555bb7020d?q=80&w=800&auto=format&fit=crop'],
        source: 'CoinDesk',
        timeAgo: '7h ago',
        description: 'Digital gold reaches new heights as institutional adoption and market optimism drive the cryptocurrency to record peaks.',
      ),
      TrendingTopic(
        id: '8',
        title: 'SpaceX Launch',
        icon: Icons.rocket_launch_rounded,
        gradientColors: [const Color(0xFF005288), const Color(0xFF00A0E3)],
        imageUrls: ['https://images.unsplash.com/photo-1517976487492-5750f3195933?q=80&w=800&auto=format&fit=crop'],
        source: 'SpaceX',
        timeAgo: '8h ago',
        description: 'Pushing the boundaries of interstellar travel as another successful mission paves the way for future lunar and Mars expeditions.',
      ),
      TrendingTopic(
        id: '9',
        title: 'AI Revolution',
        icon: Icons.psychology_rounded,
        gradientColors: [const Color(0xFF00F2FF), const Color(0xFF0061FF)],
        imageUrls: ['https://images.unsplash.com/photo-1677442136019-21780ecad995?q=80&w=800&auto=format&fit=crop'],
        source: 'Wired',
        timeAgo: '9h ago',
        description: 'Artificial intelligence transforms industries overnight, raising profound questions about the future of work and human creativity.',
      ),
      TrendingTopic(
        id: '10',
        title: 'Climate Action',
        icon: Icons.eco_rounded,
        gradientColors: [const Color(0xFF00D1FF), const Color(0xFF00A85A)],
        imageUrls: ['https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?q=80&w=800&auto=format&fit=crop'],
        source: 'National Geographic',
        timeAgo: '10h ago',
        description: 'Global leaders and activists unite in a critical race against time to implement sustainable solutions for a greener planet.',
      ),
      TrendingTopic(
        id: '11',
        title: 'Tech Expo 2024',
        icon: Icons.devices_rounded,
        gradientColors: [const Color(0xFF7B5CFF), const Color(0xFF00D1FF)],
        imageUrls: ['https://images.unsplash.com/photo-1505740420928-5e560c06d30e?q=80&w=800&auto=format&fit=crop'],
        source: 'TechCrunch',
        timeAgo: '11h ago',
        description: 'A glimpse into the future as cutting-edge gadgets and innovative software solutions take center stage at the annual tech showcase.',
      ),
      TrendingTopic(
        id: '12',
        title: 'Global Health',
        icon: Icons.health_and_safety_rounded,
        gradientColors: [const Color(0xFFFF4667), const Color(0xFFFF8A00)],
        imageUrls: ['https://images.unsplash.com/photo-1505751172107-573966a09905?q=80&w=800&auto=format&fit=crop'],
        source: 'WHO',
        timeAgo: '12h ago',
        description: 'International health agencies coordinate efforts to combat emerging challenges and ensure equitable access to medical care.',
      ),
      TrendingTopic(
        id: '13',
        title: 'Art & Design',
        icon: Icons.palette_rounded,
        gradientColors: [const Color(0xFFFFD600), const Color(0xFFFF8A00)],
        imageUrls: ['https://images.unsplash.com/photo-1513364776144-60967b0f800f?q=80&w=800&auto=format&fit=crop'],
        source: 'Behance',
        timeAgo: '13h ago',
        description: 'Exploring the intersection of aesthetics and functionality as visionary artists redefine the visual language of the modern era.',
      ),
      TrendingTopic(
        id: '14',
        title: 'Formula 1',
        icon: Icons.speed_rounded,
        gradientColors: [const Color(0xFFFF0000), const Color(0xFF000000)],
        imageUrls: ['https://images.unsplash.com/photo-1503376780353-7e6692767b70?q=80&w=800&auto=format&fit=crop'],
        source: 'F1 Official',
        timeAgo: '14h ago',
        description: 'High-speed drama on the track as legendary drivers battle for podium finishes in the world\'s most prestigious racing circuit.',
      ),
      TrendingTopic(
        id: '15',
        title: 'Electric Vehicles',
        icon: Icons.electric_car_rounded,
        gradientColors: [const Color(0xFF00FF00), const Color(0xFF0000FF)],
        imageUrls: ['https://images.unsplash.com/photo-1593941707882-a5bba14938c7?q=80&w=800&auto=format&fit=crop'],
        source: 'Tesla',
        timeAgo: '15h ago',
        description: 'The automotive industry accelerates towards a zero-emission future with groundbreaking battery tech and sustainable manufacturing.',
      ),
    ];

    _latestNews = [
      NewsArticle(
        id: '1',
        title: 'Fuel Prices Expected to Drop Next Month - EPRA',
        category: 'KENYA',
        imageUrls: [
          'https://images.unsplash.com/photo-1542224566-6e85f2e6772f?q=80&w=800&auto=format&fit=crop',
          'https://images.unsplash.com/photo-1613665813446-82a78c44b8fe?q=80&w=800&auto=format&fit=crop',
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
          'https://images.unsplash.com/photo-1534067783941-51c9c23ecefd?q=80&w=800&auto=format&fit=crop',
          'https://images.unsplash.com/photo-1444723121867-7a241cacace9?q=80&w=800&auto=format&fit=crop',
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
          'https://images.unsplash.com/photo-1508098682722-e99c43a406b2?q=80&w=800&auto=format&fit=crop',
          'https://images.unsplash.com/photo-1518091043644-c1d4457512c6?q=80&w=800&auto=format&fit=crop',
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
          'https://images.unsplash.com/photo-1510557880182-3d4d3cba3f21?q=80&w=800&auto=format&fit=crop',
          'https://images.unsplash.com/photo-1556656793-062ff987850c?q=80&w=800&auto=format&fit=crop',
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
          'https://images.unsplash.com/photo-1449824913935-59a10b8d2000?q=80&w=800&auto=format&fit=crop',
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
          'https://images.unsplash.com/photo-1538108149393-fdfd81895907?q=80&w=800&auto=format&fit=crop',
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
              onTap: () {
                if (category == 'Trending') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TrendingSeeAllScreen(topics: _trendingTopics),
                    ),
                  );
                } else if (category == 'Latest') {
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) => LatestNewsSeeAllScreen(articles: _latestNews),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                        const begin = Offset(0.0, 1.0);
                        const end = Offset.zero;
                        const curve = Curves.easeOutCubic;
                        var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                        return SlideTransition(
                          position: animation.drive(tween),
                          child: child,
                        );
                      },
                      transitionDuration: const Duration(milliseconds: 600),
                    ),
                  );
                } else if (category != 'For You') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CategoryNewsScreen(
                        category: category,
                        articles: _generateCategoryNews(category),
                      ),
                    ),
                  );
                } else {
                  setState(() => _selectedCategory = category);
                }
              },
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
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TrendingSeeAllScreen(topics: _trendingTopics),
                      ),
                    );
                  },
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
                            topic.title,
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
                      onPressed: () {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => LatestNewsSeeAllScreen(articles: _latestNews),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              const begin = Offset(0.0, 1.0);
                              const end = Offset.zero;
                              const curve = Curves.easeOutCubic;
                              var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                              return SlideTransition(
                                position: animation.drive(tween),
                                child: child,
                              );
                            },
                            transitionDuration: const Duration(milliseconds: 600),
                          ),
                        );
                      },
                      child: const Text('See all', style: TextStyle(color: Color(0xFF20C8FF))),
                    ),
                  ],
                ),
              );
            }
            final article = _latestNews[index - 1];
            final isStretched = (index - 1) % 7 == 0;
            return _buildNewsCard(context, article, isDark, textColor, isStretched: isStretched);
          },
          childCount: _latestNews.length + 1,
        ),
      ),
    );
  }

}

Widget _buildNewsCard(BuildContext context, NewsArticle article, bool isDark, Color textColor, {bool isStretched = false}) {
  if (isStretched) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NewsDetailScreen(
              article: article,
              initialImageIndex: 0,
            ),
          ),
        );
      },
      child: Container(
        height: 220,
        margin: const EdgeInsets.only(bottom: 16),
        child: Stack(
          children: [
            FadingImageThumbnail(
              imageUrls: article.imageUrls,
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
                      color: const Color(0xFF20C8FF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      article.category,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: MediaQuery.of(context).size.width * 0.6,
                    child: Text(
                      article.title,
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
                      article.content,
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
                        '${article.source} • ${article.timeAgo}',
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
          builder: (context) => NewsDetailScreen(
            article: article,
            initialImageIndex: 0,
          ),
        ),
      );
    },
    child: Container(
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.transparent, // Ensure it's tappable
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
                const SizedBox(height: 4),
                Text(
                  article.content,
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
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialImageIndex;
    _pageController = PageController(initialPage: widget.initialImageIndex);
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
            expandedHeight: 400, // Increased height for better "fully open" feel
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
                    itemCount: widget.article.imageUrls.length,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      return CachedNetworkImage(
                        imageUrl: widget.article.imageUrls[index],
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
                  if (widget.article.imageUrls.length > 1)
                    Positioned(
                      bottom: 20,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          widget.article.imageUrls.length,
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
                  Text(
                    widget.article.category,
                    style: const TextStyle(
                      color: Color(0xFF20C8FF),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.article.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
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
                    widget.article.content,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ...widget.article.details.entries.map((entry) {
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
                        onPressed: () {},
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
                        onPressed: () {},
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

class TrendingSeeAllScreen extends ConsumerWidget {
  final List<TrendingTopic> topics;

  const TrendingSeeAllScreen({super.key, required this.topics});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF070716) : Colors.white,
      appBar: AppBar(
        title: const Text('Trending Now', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textColor,
      ),
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
                  colors: [Colors.white, Colors.blue.shade50],
                ),
        ),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: topics.length,
          itemBuilder: (context, index) {
            final topic = topics[index];
            return _buildTrendingCard(context, topic, isDark, textColor, isStretched: true);
          },
        ),
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

List<NewsArticle> _generateCategoryNews(String category) {
  return List.generate(15, (index) {
    return NewsArticle(
      id: '${category.toLowerCase()}_$index',
      title: index == 0 
          ? 'Major $category Milestone Achieved This Week'
          : 'Latest Updates in $category: What You Need to Know',
      category: category.toUpperCase(),
      imageUrls: [
        'https://images.unsplash.com/photo-1511497584788-876760111969?q=80&w=800&auto=format&fit=crop',
        'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?q=80&w=800&auto=format&fit=crop',
      ],
      source: 'Global News Network',
      timeAgo: '${index + 1}h ago',
      content: 'In-depth analysis of the current trends affecting the $category sector, with insights from industry leaders and experts on the ground.',
      details: {
        'Analysis': 'Strategic shift observed across the entire $category landscape.',
        'Impact': 'Broad reach across multiple demographics and international markets.',
      },
    );
  });
}

class CategoryNewsScreen extends ConsumerWidget {
  final String category;
  final List<NewsArticle> articles;

  const CategoryNewsScreen({super.key, required this.category, required this.articles});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF070716) : Colors.white,
      appBar: AppBar(
        title: Text(category, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textColor,
      ),
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
                  colors: [Colors.white, Colors.blue.shade50],
                ),
        ),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: articles.length,
          itemBuilder: (context, index) {
            final article = articles[index];
            // Only the first card is horizontal (stretched), others are compact
            return _buildNewsCard(context, article, isDark, textColor, isStretched: index == 0);
          },
        ),
      ),
    );
  }
}

class LatestNewsSeeAllScreen extends ConsumerWidget {
  final List<NewsArticle> articles;

  const LatestNewsSeeAllScreen({super.key, required this.articles});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF070716) : Colors.white,
      appBar: AppBar(
        title: const Text('Latest News', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textColor,
      ),
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
                  colors: [Colors.white, Colors.blue.shade50],
                ),
        ),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: articles.length,
          itemBuilder: (context, index) {
            final article = articles[index];
            return _buildNewsCard(context, article, isDark, textColor, isStretched: true);
          },
        ),
      ),
    );
  }
}


