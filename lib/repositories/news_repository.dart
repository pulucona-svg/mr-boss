import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/explore_models.dart';

/// Abstract News Repository defining real-time Stream-based data contract for news content.
abstract class NewsRepository {
  /// Watches top stories for the hero carousel in real-time
  Stream<List<TopStory>> watchTopStories();

  /// Watches trending topics in real-time
  Stream<List<TrendingTopic>> watchTrendingTopics();

  /// Watches news articles for a specific category in real-time from Firestore explore_news
  Stream<List<NewsArticle>> watchCategoryNews(String category);

  /// Watches latest news articles in real-time from Firestore explore_news
  Stream<List<NewsArticle>> watchLatestNews();

  /// Watches mixed news articles for the general feed in real-time
  Stream<List<NewsArticle>> watchAllMixedNews();

  /// Watches news categories list in real-time
  Stream<List<String>> watchCategories();

  /// Watches full ExploreCategory models from categoryNews collection
  Stream<List<ExploreCategory>> watchExploreCategories();

  /// Fetches a single news article by ID
  Future<NewsArticle?> getArticle(String id);

  /// Triggers backend Explore article generation Cloud Function (generateExploreArticle)
  Future<bool> triggerExploreArticleGeneration(String category, {String? query});
}

/// Concrete production implementation of [NewsRepository] connected to Cloud Firestore.
class NewsRepositoryImpl implements NewsRepository {
  final FirebaseFirestore? _customFirestore;

  NewsRepositoryImpl({FirebaseFirestore? firestore})
      : _customFirestore = firestore;

  FirebaseFirestore get _firestore =>
      _customFirestore ?? FirebaseFirestore.instance;

  static final Set<String> _triggeredCategories = {};

  void _triggerBackgroundArticleGeneration(String category) {
    final catKey = category.toLowerCase().trim();
    if (_triggeredCategories.contains(catKey)) return;
    _triggeredCategories.add(catKey);
    triggerExploreArticleGeneration(category).catchError((_) => false);
  }

  @override
  Stream<List<TopStory>> watchTopStories() {
    return _firestore
        .collection('topStories')
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      final list = snapshot.docs
          .where((doc) => !_isExpired(doc.data()['expiresAt'], now))
          .map((doc) => _mapDocToTopStory(doc))
          .toList();
      return list.isNotEmpty ? list : _defaultTopStories;
    });
  }

  @override
  Stream<List<TrendingTopic>> watchTrendingTopics() {
    return _firestore
        .collection('trendingTopics')
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => _mapDocToTrendingTopic(doc))
          .toList();
      return list.isNotEmpty ? list : _defaultTrendingTopics;
    });
  }

  @override
  Stream<List<NewsArticle>> watchCategoryNews(String category) {
    final catLower = category.toLowerCase().trim();
    if (catLower == 'all' || catLower.isEmpty) {
      return watchLatestNews();
    }

    return _firestore
        .collection('explore_news')
        .snapshots()
        .asyncMap((snapshot) async {
      final Map<String, NewsArticle> articleMap = {};

      for (final doc in snapshot.docs) {
        final article = _mapDocToNewsArticle(doc);
        final artCat = article.category.toLowerCase().trim();
        if (artCat == catLower || artCat.contains(catLower) || catLower.contains(artCat)) {
          articleMap[article.id] = article;
        }
      }

      // Also check categoryNews/{category}/articles or latestNews if present
      try {
        final catSubSnap = await _firestore
            .collection('categoryNews')
            .doc(category)
            .collection('articles')
            .get();
        for (final doc in catSubSnap.docs) {
          if (!articleMap.containsKey(doc.id)) {
            articleMap[doc.id] = _mapDocToNewsArticle(doc);
          }
        }
      } catch (_) {}

      final articles = articleMap.values.toList();
      articles.sort((a, b) {
        final dateA = a.publishedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = b.publishedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });

      if (articles.isNotEmpty) {
        return articles;
      }

      _triggerBackgroundArticleGeneration(category);
      return _getDefaultArticlesForCategory(category);
    });
  }

  @override
  Stream<List<NewsArticle>> watchLatestNews() {
    return _firestore
        .collection('explore_news')
        .snapshots()
        .asyncMap((snapshot) async {
      final Map<String, NewsArticle> articleMap = {};

      for (final doc in snapshot.docs) {
        final article = _mapDocToNewsArticle(doc);
        articleMap[article.id] = article;
      }

      try {
        final latestSnap = await _firestore.collection('latestNews').get();
        for (final doc in latestSnap.docs) {
          if (!articleMap.containsKey(doc.id)) {
            articleMap[doc.id] = _mapDocToNewsArticle(doc);
          }
        }
      } catch (_) {}

      final articles = articleMap.values.toList();
      articles.sort((a, b) {
        final dateA = a.publishedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = b.publishedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });

      if (articles.isNotEmpty) {
        return articles;
      }

      _triggerBackgroundArticleGeneration('General');
      return _defaultArticles;
    });
  }

  @override
  Stream<List<NewsArticle>> watchAllMixedNews() {
    return watchLatestNews().asyncMap((latestArticles) async {
      try {
        final topSnap = await _firestore.collection('topStories').get();
        final now = DateTime.now();
        final topArticles = topSnap.docs
            .where((doc) => !_isExpired(doc.data()['expiresAt'], now))
            .map((doc) => _mapDocToNewsArticle(doc))
            .toList();

        final Map<String, NewsArticle> articleMap = {};
        for (final art in latestArticles) {
          articleMap[art.id] = art;
        }
        for (final art in topArticles) {
          if (!articleMap.containsKey(art.id)) {
            articleMap[art.id] = art;
          }
        }

        final mergedList = articleMap.values.toList();
        mergedList.sort((a, b) {
          final dateA = a.publishedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final dateB = b.publishedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return dateB.compareTo(dateA);
        });

        return _interleaveByCategory(mergedList);
      } catch (_) {
        return _interleaveByCategory(latestArticles);
      }
    });
  }

  List<NewsArticle> _interleaveByCategory(List<NewsArticle> articles) {
    if (articles.length <= 2) return articles;

    final List<NewsArticle> result = [];
    final List<NewsArticle> remaining = List.from(articles);

    while (remaining.isNotEmpty) {
      final first = remaining.removeAt(0);
      result.add(first);

      if (remaining.isEmpty) break;

      final lastCategory = first.category;
      int nextIdx = remaining.indexWhere((art) => art.category != lastCategory);

      if (nextIdx != -1) {
        result.add(remaining.removeAt(nextIdx));
      } else {
        result.add(remaining.removeAt(0));
      }
    }

    return result;
  }

  @override
  Stream<List<ExploreCategory>> watchExploreCategories() {
    return _firestore.collection('categoryNews').snapshots().map((snapshot) {
      final List<ExploreCategory> list = [];
      final Set<String> seenNames = {};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final cat = ExploreCategory.fromMap(doc.id, data);

        if (!cat.enabled) continue;

        final normName = cat.name.toLowerCase();
        if (normName == 'dummy' || normName.startsWith('dummy') || cat.id.toLowerCase() == 'dummy') continue;
        if (seenNames.contains(normName)) continue;
        seenNames.add(normName);

        list.add(cat);
      }

      if (list.isEmpty) {
        const defaultNames = [
          'For You',
          'General',
          'Technology',
          'Campus',
          'Environment',
          'Sports',
          'Entertainment',
          'Science',
          'Business',
          'Health',
        ];
        for (int i = 0; i < defaultNames.length; i++) {
          final name = defaultNames[i];
          list.add(ExploreCategory(
            id: name.toLowerCase().replaceAll(' ', '_'),
            name: name,
            displayOrder: i,
            enabled: true,
          ));
        }
      } else {
        list.sort((a, b) {
          final orderComp = a.displayOrder.compareTo(b.displayOrder);
          if (orderComp != 0) return orderComp;
          return a.name.compareTo(b.name);
        });
      }

      return list;
    });
  }

  @override
  Stream<List<String>> watchCategories() {
    return watchExploreCategories().map((categories) {
      return categories.map((c) => c.name).toList();
    });
  }

  @override
  Future<NewsArticle?> getArticle(String id) async {
    try {
      final doc = await _firestore.collection('explore_news').doc(id).get();
      if (doc.exists) {
        return _mapDocToNewsArticle(doc);
      }

      // Legacy fallback
      final legacyDoc = await _firestore.collection('latestNews').doc(id).get();
      if (legacyDoc.exists) {
        return _mapDocToNewsArticle(legacyDoc);
      }
    } catch (_) {}

    return _defaultArticles.firstWhere(
      (a) => a.id == id,
      orElse: () => _defaultArticles.first,
    );
  }

  @override
  Future<bool> triggerExploreArticleGeneration(String category, {String? query}) async {
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('generateExploreArticle');
      final response = await callable.call({
        'query': query ?? category,
        'category': category,
      });
      final data = response.data;
      if (data == null) return false;
      if (data is Map) {
        return data['success'] == true || data['status'] == 'success' || data['articleId'] != null;
      }
      return true;
    } catch (e) {
      debugPrint('[NEWS_REPOSITORY] Cloud function trigger failed: $e');
      return false;
    }
  }

  List<NewsArticle> _getDefaultArticlesForCategory(String category) {
    final catLower = category.toLowerCase().trim();
    final filtered = _defaultArticles.where((a) => a.category.toLowerCase().trim() == catLower).toList();
    return filtered.isNotEmpty ? filtered : _defaultArticles;
  }

  // --- Fallback Instant Articles ---

  static final List<TopStory> _defaultTopStories = [
    TopStory(
      id: 'default_top_1',
      title: 'Laikipia University Launches Cutting-Edge AI & Agritech Innovation Hub',
      summary: 'Laikipia University has officially commissioned a state-of-the-art AI laboratory dedicated to smart farming, weather prediction, and student tech incubation in Kenya.',
      imageUrl: 'https://images.unsplash.com/photo-1523240795612-9a054b0db644?q=80&w=1200&auto=format&fit=crop',
      source: 'Laikipia News',
      timeAgo: '1h ago',
      category: 'Campus',
    ),
    TopStory(
      id: 'default_top_2',
      title: 'Global Leaders Gather in Nairobi for the Pan-African Tech Summit 2026',
      summary: 'Innovators, software engineers, and digital policy architects across Africa have converged in Nairobi to discuss cloud infrastructure, mobile engineering, and youth employment.',
      imageUrl: 'https://images.unsplash.com/photo-1531482615713-2afd69097998?q=80&w=1200&auto=format&fit=crop',
      source: 'Tech Africa Review',
      timeAgo: '2h ago',
      category: 'Technology',
    ),
    TopStory(
      id: 'default_top_3',
      title: 'Major Solar Energy Expansion Powers Educational Institutions in Laikipia',
      summary: 'A transformative green energy initiative brings off-grid clean solar power to university facilities, schools, and rural community centers across the region.',
      imageUrl: 'https://images.unsplash.com/photo-1509391365360-2e959784a276?q=80&w=1200&auto=format&fit=crop',
      source: 'Environment Watch',
      timeAgo: '4h ago',
      category: 'Environment',
    ),
  ];

  static final List<TrendingTopic> _defaultTrendingTopics = [
    TrendingTopic(
      id: 'default_trend_1',
      title: 'AI Education & University Curriculum Reform',
      icon: Icons.trending_up_rounded,
      gradientColors: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
      imageUrls: const [
        'https://images.unsplash.com/photo-1516321318423-f06f85e504b3?q=80&w=1200&auto=format&fit=crop',
      ],
      description: 'Higher education institutions across East Africa are integrating generative AI and data analytics modules into undergraduate degree programs.',
      details: const {
        'Why it\'s Trending': 'Widespread adoption of AI tools by university students and faculty.',
        'Recent Activity': 'New curriculum guidelines announced by higher education boards.',
        'Impact': 'Empowering students with industry-relevant technology skills.'
      },
      source: 'Trending Now',
      timeAgo: '30m ago',
    ),
    TrendingTopic(
      id: 'default_trend_2',
      title: 'Rhino & Wildlife Conservation Technology in Laikipia',
      icon: Icons.eco_rounded,
      gradientColors: const [Color(0xFF10B981), Color(0xFF059669)],
      imageUrls: const [
        'https://images.unsplash.com/photo-1534567153574-2b12153a87f0?q=80&w=1200&auto=format&fit=crop',
      ],
      description: 'Advanced satellite tracking collars and AI surveillance drones are successfully safeguarding endangered wildlife in the Laikipia plateau.',
      details: const {
        'Why it\'s Trending': 'Zero poaching incidents recorded over the past 12 consecutive months.',
        'Key Partners': 'Laikipia Wildlife Conservancies Association & Kenya Wildlife Service.',
        'Global Recognition': 'Featured as a international benchmark in smart conservation.'
      },
      source: 'Eco Insights',
      timeAgo: '1h ago',
    ),
    TrendingTopic(
      id: 'default_trend_3',
      title: 'East Africa University Athletics Championships 2026',
      icon: Icons.directions_run_rounded,
      gradientColors: const [Color(0xFFF59E0B), Color(0xFFD97706)],
      imageUrls: const [
        'https://images.unsplash.com/photo-1461896836934-ffe607ba8211?q=80&w=1200&auto=format&fit=crop',
      ],
      description: 'Student athletes compete across track, field, and cross-country events, breaking long-standing regional records.',
      details: const {
        'Why it\'s Trending': 'Record turnout of varsity teams competing for national titles.',
        'Highlights': 'Top performers qualify for international world university trials.',
      },
      source: 'Sports Central',
      timeAgo: '3h ago',
    ),
  ];

  static final List<NewsArticle> _defaultArticles = [
    NewsArticle(
      id: 'default_art_1',
      title: 'Laikipia University Opens Modern Digital Library and E-Learning Hub',
      category: 'Campus',
      imageUrls: const [
        'https://images.unsplash.com/photo-1521587760476-6c12a4b040da?q=80&w=1200&auto=format&fit=crop',
        'https://images.unsplash.com/photo-1481627834876-b7833e8f5570?q=80&w=1200&auto=format&fit=crop',
      ],
      source: 'Laikipia Campus Press',
      timeAgo: '30m ago',
      summary: 'The new high-tech facility offers 24/7 high-speed fiber internet, digital research repositories, and quiet study zones for thousands of university students.',
      content: 'Laikipia University has officially commissioned its ultra-modern Digital Resource Center and E-Learning Library hub. The facility is equipped with high-speed optical fiber connectivity, dedicated research workstations, digital catalog search terminals, and collaborative project rooms.\n\nSpeaking during the opening ceremony, the university administration highlighted that the new resource hub will enable students to access over 100,000 academic journals, scientific databases, and open-access course materials.\n\nStudents have praised the initiative, noting that the round-the-clock availability of digital learning tools will significantly bolster research, innovation, and exam preparation across all faculties.',
      publishedAt: DateTime.now().subtract(const Duration(minutes: 30)),
      details: const {
        'Location': 'Main Campus, Laikipia University',
        'Key Feature': '24/7 High-speed Internet & Academic Databases',
      },
    ),
    NewsArticle(
      id: 'default_art_2',
      title: 'Next-Generation Flutter 3.41 Framework Accelerates Cross-Platform Mobile Apps',
      category: 'Technology',
      imageUrls: const [
        'https://images.unsplash.com/photo-1555066931-4365d14bab8c?q=80&w=1200&auto=format&fit=crop',
        'https://images.unsplash.com/photo-1526374965328-7f61d4dc18c5?q=80&w=1200&auto=format&fit=crop',
      ],
      source: 'Developer Tech Hub',
      timeAgo: '1h ago',
      summary: 'The latest release of Flutter introduces groundbreaking UI rendering optimizations, improved Dart compilation speeds, and seamless cross-platform widget fidelity.',
      content: 'Google\'s open-source UI toolkit Flutter has released version 3.41, introducing enhanced graphics pipeline performance, precise color space handling, and faster hot-reload capabilities.\n\nDevelopers worldwide are taking advantage of Flutter\'s rich widget library and high-performance Impeller rendering engine to build fluid, native-quality experiences across Android, iOS, Web, and Desktop platforms.\n\nIndustry benchmarks demonstrate a 25% reduction in app startup latency and optimized memory utilization for complex animation-heavy mobile applications.',
      publishedAt: DateTime.now().subtract(const Duration(hours: 1)),
      details: const {
        'SDK Version': 'Flutter 3.41 / Dart 3.11',
        'Platform Support': 'Android, iOS, Web, Desktop',
      },
    ),
    NewsArticle(
      id: 'default_art_3',
      title: 'Reforestation Drive Plants 50,000 Indigenous Trees in Laikipia County',
      category: 'Environment',
      imageUrls: const [
        'https://images.unsplash.com/photo-1542601906990-b4d3fb778b09?q=80&w=1200&auto=format&fit=crop',
        'https://images.unsplash.com/photo-1448375240586-882707db888b?q=80&w=1200&auto=format&fit=crop',
      ],
      source: 'Green Earth Kenya',
      timeAgo: '2h ago',
      summary: 'Community groups, university volunteers, and environmental agencies joined forces to restore degraded forest cover and protect local water catchments.',
      content: 'A massive environmental conservation campaign led by local youth, student organizations, and environmental experts has successfully planted 50,000 indigenous tree seedlings across Laikipia County.\n\nThe exercise aims to restore vital river basins, mitigate soil erosion, and combat regional climate change impacts. Local authorities pledged continuous monitoring and protection of the newly forested areas to ensure high survival rates.',
      publishedAt: DateTime.now().subtract(const Duration(hours: 2)),
      details: const {
        'Seedlings Planted': '50,000 Indigenous Species',
        'Target Area': 'Laikipia Forest Reserve & River Basins',
      },
    ),
    NewsArticle(
      id: 'default_art_4',
      title: 'Varsity Athletics Team Triumphs at Regional Inter-University Games',
      category: 'Sports',
      imageUrls: const [
        'https://images.unsplash.com/photo-1517649763962-0c623266010b?q=80&w=1200&auto=format&fit=crop',
      ],
      source: 'Sports Campus Express',
      timeAgo: '3h ago',
      summary: 'Student athletes secured 12 gold medals in track events, football, and volleyball during the weekend regional university tournament.',
      content: 'The university sports delegation delivered an outstanding performance at the 2026 Inter-University Games, clinching 12 gold, 8 silver, and 5 bronze medals across multiple disciplines.\n\nThe track and field team dominated the 5,000m and 10,000m long-distance races, while the varsity volleyball squad triumphed in a dramatic five-set final against rival contenders.',
      publishedAt: DateTime.now().subtract(const Duration(hours: 3)),
      details: const {
        'Medals Won': '12 Gold, 8 Silver, 5 Bronze',
        'Top Events': '5,000m Track, Volleyball, Soccer',
      },
    ),
    NewsArticle(
      id: 'default_art_5',
      title: 'Kenyan FinTech Startups Secure \$150M in Regional Growth Capital',
      category: 'Business',
      imageUrls: const [
        'https://images.unsplash.com/photo-1460925895917-afdab827c52f?q=80&w=1200&auto=format&fit=crop',
      ],
      source: 'African Business Chronicle',
      timeAgo: '4h ago',
      summary: 'Venture capital funding into East African digital payments, micro-lending, and agri-finance startups experiences robust Q2 expansion.',
      content: 'East Africa\'s technology ecosystem continues to attract international venture capital, with Kenyan financial technology firms raising over \$150 million in Series A and B funding rounds this quarter.\n\nInvestors pointed to high smartphone penetration, mobile money interoperability, and innovative credit-scoring algorithms as key growth drivers for the region\'s expanding digital economy.',
      publishedAt: DateTime.now().subtract(const Duration(hours: 4)),
      details: const {
        'Total Funding': '\$150 Million USD',
        'Focus Sectors': 'Digital Payments, Agri-Finance, Micro-Credit',
      },
    ),
    NewsArticle(
      id: 'default_art_6',
      title: 'Annual Cultural Festival Celebrates Diverse African Music and Arts',
      category: 'Entertainment',
      imageUrls: const [
        'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?q=80&w=1200&auto=format&fit=crop',
      ],
      source: 'Culture & Life',
      timeAgo: '5h ago',
      summary: 'Thousands of attendees gathered to witness vibrant cultural dances, live acoustic performances, fashion displays, and art exhibitions.',
      content: 'The annual Laikipia Cultural Festival lit up the weekend with a showcase of traditional music, contemporary Afrobeat performances, spoken word poetry, and indigenous art displays.\n\nThe festival brought together artists from across the country, celebrating heritage while providing a platform for emerging campus talents to showcase their creative works to a broad audience.',
      publishedAt: DateTime.now().subtract(const Duration(hours: 5)),
      details: const {
        'Event': 'Laikipia Annual Cultural Festival',
        'Attendance': 'Over 5,000 Guests & Students',
      },
    ),
    NewsArticle(
      id: 'default_art_7',
      title: 'Breakthrough Study Advances Solar Cell Efficiency to Record 32%',
      category: 'Science',
      imageUrls: const [
        'https://images.unsplash.com/photo-1507668077129-56e32842fceb?q=80&w=1200&auto=format&fit=crop',
      ],
      source: 'Global Science Digest',
      timeAgo: '6h ago',
      summary: 'Researchers have developed a tandem perovskite-silicon solar cell that achieves unprecedented light conversion rates.',
      content: 'A international team of materials scientists has announced a milestone in photovoltaic technology, engineering a tandem perovskite-silicon solar cell capable of converting 32% of sunlight directly into electricity.\n\nThis breakthrough promises to drastically lower solar panel manufacturing costs and increase clean energy output for commercial and residential power grids worldwide.',
      publishedAt: DateTime.now().subtract(const Duration(hours: 6)),
      details: const {
        'Efficiency Rate': '32.4% Sunlight Conversion',
        'Technology': 'Perovskite-Silicon Tandem Cells',
      },
    ),
    NewsArticle(
      id: 'default_art_8',
      title: 'Student Wellness Initiative Promotes Mental Health Awareness & Fitness',
      category: 'Health',
      imageUrls: const [
        'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?q=80&w=1200&auto=format&fit=crop',
      ],
      source: 'Health & Wellbeing',
      timeAgo: '7h ago',
      summary: 'Campus health services launch free counseling sessions, mindfulness workshops, and daily morning yoga routines for students.',
      content: 'Laikipia University Health Services has launched a holistic student wellness campaign focused on stress management, balanced nutrition, and peer mental health support.\n\nThe program includes confidential counseling resources, weekly group therapy circles, and guided morning fitness sessions aimed at fostering a healthy academic lifestyle.',
      publishedAt: DateTime.now().subtract(const Duration(hours: 7)),
      details: const {
        'Program': 'Mind & Body Campus Wellness',
        'Services': 'Free Counseling, Yoga, Peer Support',
      },
    ),
    NewsArticle(
      id: 'default_art_9',
      title: 'Laikipia County Administration Announces New Youth Innovation Fund',
      category: 'General',
      imageUrls: const [
        'https://images.unsplash.com/photo-1531497865144-0464ef8fb9a9?q=80&w=1200&auto=format&fit=crop',
      ],
      source: 'County News Service',
      timeAgo: '8h ago',
      summary: 'A new enterprise grant program will award funding to promising youth-led business ventures and technological solutions.',
      content: 'The Laikipia County Executive Committee has approved a KES 50 Million Youth Enterprise and Innovation Fund designed to support young entrepreneurs, campus incubators, and community startups.\n\nEligible applicants can submit business plans across agriculture, technology, renewable energy, and creative arts to receive seed capital, mentorship, and business registration support.',
      publishedAt: DateTime.now().subtract(const Duration(hours: 8)),
      details: const {
        'Fund Capacity': 'KES 50 Million',
        'Target Beneficiaries': 'Youth Entrepreneurs & Campus Startups',
      },
    ),
  ];

  // --- Helper Mapping Methods ---

  bool _isExpired(dynamic expiresAtVal, DateTime now) {
    if (expiresAtVal == null) return false;
    final expiry = _parseDateTime(expiresAtVal);
    if (expiry == null) return false;
    return now.isAfter(expiry);
  }

  DateTime? _parseDateTime(dynamic val) {
    if (val == null) return null;
    if (val is Timestamp) return val.toDate();
    if (val is String) return DateTime.tryParse(val);
    if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
    return null;
  }

  String _formatTimeAgo(dynamic timestampVal) {
    final date = _parseDateTime(timestampVal);
    if (date == null) return 'Recently';

    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  TopStory _mapDocToTopStory(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final id = doc.id;
    final title = data['title'] as String? ?? '';
    final summary =
        data['editorialSummary'] as String? ?? data['summary'] as String? ?? '';
    final imageUrl = data['thumbnailUrl'] as String? ??
        data['imageKitUrl'] as String? ??
        '';
    final source = data['source'] as String? ?? '';
    final category = data['category'] as String? ?? 'General';
    final timeAgo = _formatTimeAgo(data['publishedAt'] ?? data['collectedAt']);

    return TopStory(
      id: id,
      title: title,
      summary: summary,
      imageUrl: imageUrl,
      source: source,
      timeAgo: timeAgo,
      category: category,
    );
  }

  TrendingTopic _mapDocToTrendingTopic(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final id = doc.id;
    final title = data['title'] as String? ?? data['topicTitle'] as String? ?? '';
    final description = data['description'] as String? ??
        data['summary'] as String? ??
        'Stay updated with the latest developments on this trending topic.';
    final source = data['source'] as String? ?? 'Trending Now';
    final timeAgo = _formatTimeAgo(data['publishedAt'] ?? data['createdAt']);

    List<String> imageUrls = [];
    if (data['imageUrls'] is List) {
      imageUrls = (data['imageUrls'] as List).map((e) => e.toString()).toList();
    } else if (data['thumbnailUrl'] is String &&
        (data['thumbnailUrl'] as String).isNotEmpty) {
      imageUrls = [data['thumbnailUrl'] as String];
    }

    Map<String, String> detailsMap = {};
    if (data['details'] is Map) {
      (data['details'] as Map).forEach((k, v) => detailsMap[k.toString()] = v.toString());
    }

    return TrendingTopic(
      id: id,
      title: title,
      icon: Icons.trending_up_rounded,
      gradientColors: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
      imageUrls: imageUrls.isNotEmpty
          ? imageUrls
          : const [
              'https://images.unsplash.com/photo-1504711434969-e33886168f5c?q=80&w=2000&auto=format&fit=crop',
            ],
      description: description,
      details: detailsMap.isNotEmpty
          ? detailsMap
          : const {
              'Why it\'s Trending':
                  'High engagement across social platforms and major news outlets.',
              'Recent Activity':
                  'Increased discussion and news coverage in the last 24 hours.',
            },
      source: source,
      timeAgo: timeAgo,
    );
  }

  NewsArticle _mapDocToNewsArticle(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final id = doc.id;
    final title = data['title'] as String? ?? '';
    final category = data['category'] as String? ?? 'General';
    final summary = data['summary'] as String? ?? data['editorialSummary'] as String? ?? '';
    final content = data['content'] as String? ?? summary;
    final provider = data['provider'] as String? ?? data['assignedWorker'] as String?;
    final source = data['source'] as String? ?? provider?.toUpperCase() ?? 'Mirror Explore';
    final publishedAt = _parseDateTime(data['publishedAt'] ?? data['createdAt']);
    final timeAgo = _formatTimeAgo(publishedAt);

    List<Map<String, dynamic>> imagesData = [];
    List<String> imageUrls = [];

    if (data['images'] is List) {
      for (final item in (data['images'] as List)) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          imagesData.add(map);
          if (map['imageUrl'] != null && map['imageUrl'].toString().isNotEmpty) {
            imageUrls.add(map['imageUrl'].toString());
          }
        }
      }
    }

    if (imageUrls.isEmpty) {
      if (data['imageUrls'] is List) {
        imageUrls = (data['imageUrls'] as List).map((e) => e.toString()).toList();
      } else if (data['thumbnailUrl'] is String && (data['thumbnailUrl'] as String).isNotEmpty) {
        imageUrls = [data['thumbnailUrl'] as String];
      }
    }

    final coverImage = imageUrls.isNotEmpty
        ? imageUrls.first
        : (data['thumbnailUrl'] as String? ?? data['coverImage'] as String?);

    Map<String, String> details = {};
    if (data['details'] is Map) {
      (data['details'] as Map).forEach((k, v) => details[k.toString()] = v.toString());
    }

    return NewsArticle(
      id: id,
      title: title,
      category: category,
      imageUrls: imageUrls,
      source: source,
      timeAgo: timeAgo,
      content: content,
      summary: summary,
      provider: provider,
      publishedAt: publishedAt,
      imagesData: imagesData,
      details: details,
      slug: data['slug'] as String?,
      createdAt: _parseDateTime(data['collectedAt'] ?? data['createdAt']),
      expiresAt: _parseDateTime(data['expiresAt']),
      updatedAt: _parseDateTime(data['updatedAt']),
      viewerDocumentId: data['viewerDocumentId'] as String?,
      viewerUrl: data['viewerDocumentUrl'] as String? ?? data['viewerUrl'] as String?,
      coverImage: coverImage,
      status: data['status'] as String? ?? 'published',
      priority: data['priority'] is int ? data['priority'] as int : null,
      sourceUrl: data['originalSourceUrl'] as String? ?? data['originalUrl'] as String?,
    );
  }
}

/// Provider for [NewsRepository]
final newsRepositoryProvider = Provider<NewsRepository>((ref) {
  return NewsRepositoryImpl();
});

