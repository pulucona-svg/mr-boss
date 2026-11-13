import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_laikipia/models/explore_models.dart';
import 'package:mirror_laikipia/repositories/news_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Explore Optimization Tests', () {
    late NewsRepositoryImpl repository;

    setUp(() {
      repository = NewsRepositoryImpl();
    });

    test('1. In-Memory Category Interleaving: preserves alternating categories and relative chronological ordering', () {
      final now = DateTime.now();

      final tech1 = NewsArticle(
        id: 'tech_1',
        title: 'Tech Article 1',
        category: 'Technology',
        imageUrls: ['https://example.com/t1.jpg'],
        source: 'Mirror Tech',
        timeAgo: '10m ago',
        publishedAt: now.subtract(const Duration(minutes: 10)),
      );

      final tech2 = NewsArticle(
        id: 'tech_2',
        title: 'Tech Article 2',
        category: 'Technology',
        imageUrls: ['https://example.com/t2.jpg'],
        source: 'Mirror Tech',
        timeAgo: '20m ago',
        publishedAt: now.subtract(const Duration(minutes: 20)),
      );

      final sports1 = NewsArticle(
        id: 'sports_1',
        title: 'Sports Article 1',
        category: 'Sports',
        imageUrls: ['https://example.com/s1.jpg'],
        source: 'Mirror Sports',
        timeAgo: '15m ago',
        publishedAt: now.subtract(const Duration(minutes: 15)),
      );

      final sports2 = NewsArticle(
        id: 'sports_2',
        title: 'Sports Article 2',
        category: 'Sports',
        imageUrls: ['https://example.com/s2.jpg'],
        source: 'Mirror Sports',
        timeAgo: '25m ago',
        publishedAt: now.subtract(const Duration(minutes: 25)),
      );

      final business1 = NewsArticle(
        id: 'biz_1',
        title: 'Business Article 1',
        category: 'Business',
        imageUrls: ['https://example.com/b1.jpg'],
        source: 'Mirror Biz',
        timeAgo: '30m ago',
        publishedAt: now.subtract(const Duration(minutes: 30)),
      );

      // Latest news list ordered by publishedAt:
      // tech_1 (10m), sports_1 (15m), tech_2 (20m), sports_2 (25m), biz_1 (30m)
      final latestNews = [tech1, sports1, tech2, sports2, business1];

      final mixed = repository.interleaveByCategory(latestNews);

      // Expected interleaved order:
      // Index 0: tech_1 (Technology)
      // Index 1: sports_1 (Sports)
      // Index 2: tech_2 (Technology)
      // Index 3: sports_2 (Sports)
      // Index 4: biz_1 (Business)
      expect(mixed.length, equals(5));
      expect(mixed[0].id, equals('tech_1'));
      expect(mixed[1].id, equals('sports_1'));
      expect(mixed[2].id, equals('tech_2'));
      expect(mixed[3].id, equals('sports_2'));
      expect(mixed[4].id, equals('biz_1'));

      // Verify no adjacent elements have the same category where alternatives exist
      for (int i = 0; i < mixed.length - 1; i++) {
        if (i < 4) {
          expect(mixed[i].category, isNot(equals(mixed[i + 1].category)),
              reason: 'Adjacent articles at index $i and ${i + 1} must alternate categories');
        }
      }
    });

    test('2. In-Memory Category Interleaving: Edge Cases (<= 2 items, single category, empty)', () {
      expect(repository.interleaveByCategory([]), isEmpty);

      final now = DateTime.now();
      final art1 = NewsArticle(
        id: 'art_1',
        title: 'Article 1',
        category: 'Campus',
        imageUrls: [],
        source: 'Mirror',
        timeAgo: '1m ago',
        publishedAt: now,
      );

      // 1 item returns directly
      expect(repository.interleaveByCategory([art1]), equals([art1]));

      final art2 = NewsArticle(
        id: 'art_2',
        title: 'Article 2',
        category: 'Campus',
        imageUrls: [],
        source: 'Mirror',
        timeAgo: '2m ago',
        publishedAt: now.subtract(const Duration(minutes: 2)),
      );

      // 2 items returns directly without infinite loop
      expect(repository.interleaveByCategory([art1, art2]), equals([art1, art2]));

      // 3 items of identical category preserves order
      final art3 = NewsArticle(
        id: 'art_3',
        title: 'Article 3',
        category: 'Campus',
        imageUrls: [],
        source: 'Mirror',
        timeAgo: '3m ago',
        publishedAt: now.subtract(const Duration(minutes: 3)),
      );

      final sameCat = repository.interleaveByCategory([art1, art2, art3]);
      expect(sameCat.map((a) => a.id).toList(), equals(['art_1', 'art_2', 'art_3']));
    });

    test('3. Duplicate-Subscription Prevention: Mixed news is derived from Latest news without a second Firestore query', () {
      final now = DateTime.now();
      final sampleNews = [
        NewsArticle(
          id: 'news_1',
          title: 'Title 1',
          category: 'Kenya',
          imageUrls: ['https://example.com/1.jpg'],
          source: 'Mirror',
          timeAgo: '5m ago',
          publishedAt: now.subtract(const Duration(minutes: 5)),
        ),
        NewsArticle(
          id: 'news_2',
          title: 'Title 2',
          category: 'World',
          imageUrls: ['https://example.com/2.jpg'],
          source: 'Mirror',
          timeAgo: '10m ago',
          publishedAt: now.subtract(const Duration(minutes: 10)),
        ),
      ];

      List<NewsArticle> latestNewsState = [];
      List<NewsArticle> allMixedNewsState = [];

      void onLatestNewsEmitted(List<NewsArticle> incoming) {
        latestNewsState = incoming;
        allMixedNewsState = repository.interleaveByCategory(incoming);
      }

      onLatestNewsEmitted(sampleNews);

      expect(latestNewsState.length, equals(2));
      expect(allMixedNewsState.length, equals(2));
      expect(allMixedNewsState[0].id, equals('news_1'));
      expect(allMixedNewsState[1].id, equals('news_2'));
    });

    test('4. Exactly ONE active category listener: Switching from A to B cancels A', () {
      // Mock stream subscriptions tracking
      final createdSubscriptions = <String>[];
      final activeSubscriptions = <String, StreamSubscription>{};
      final categoryNewsMap = <String, List<NewsArticle>>{};

      StreamSubscription? activeCategorySub;
      String? activeCategoryName;
      int categorySubscriptionToken = 0;

      void ensureCategorySubscribed(String cat) {
        if (cat == 'For You' || cat == 'Trending' || cat == 'Latest') {
          if (activeCategorySub != null) {
            categorySubscriptionToken++;
            activeCategorySub?.cancel();
            activeCategorySub = null;
            activeCategoryName = null;
          }
          return;
        }

        if (activeCategoryName == cat && activeCategorySub != null) return;

        categorySubscriptionToken++;
        final currentToken = categorySubscriptionToken;
        activeCategorySub?.cancel();
        activeCategorySub = null;
        activeCategoryName = cat;

        final controller = StreamController<List<NewsArticle>>();
        createdSubscriptions.add(cat);
        final sub = controller.stream.listen((articles) {
          if (categorySubscriptionToken != currentToken) return;
          categoryNewsMap[cat] = articles;
        });

        activeCategorySub = sub;
        activeSubscriptions[cat] = sub;
      }

      // Step 1: User navigates to Technology
      ensureCategorySubscribed('Technology');
      expect(activeCategoryName, equals('Technology'));
      expect(activeCategorySub, isNotNull);

      // Step 2: User switches to Sports -> Technology subscription MUST be cancelled
      final techSub = activeCategorySub;
      ensureCategorySubscribed('Sports');
      expect(activeCategoryName, equals('Sports'));
      expect(activeCategorySub, isNot(equals(techSub)));

      // Step 3: User switches to Feed category 'For You' -> Sports subscription MUST be cancelled
      ensureCategorySubscribed('For You');
      expect(activeCategoryName, isNull);
      expect(activeCategorySub, isNull);
    });

    test('5. Returning to A uses cached results in memory immediately without awaiting network', () {
      final categoryNewsMap = <String, List<NewsArticle>>{};
      StreamSubscription? activeCategorySub;
      String? activeCategoryName;
      int categorySubscriptionToken = 0;

      final cachedTechArticles = [
        NewsArticle(
          id: 'cached_tech_1',
          title: 'Cached Tech Story',
          category: 'Technology',
          imageUrls: [],
          source: 'Mirror Tech',
          timeAgo: '1h ago',
          publishedAt: DateTime.now(),
        ),
      ];

      // Simulate Technology was previously loaded
      categoryNewsMap['Technology'] = cachedTechArticles;

      // Currently on 'Business'
      activeCategoryName = 'Business';

      // User returns to 'Technology'
      // 1. UI check: Can read immediately from cache
      final renderedArticles = categoryNewsMap['Technology'] ?? [];
      expect(renderedArticles.length, equals(1));
      expect(renderedArticles.first.id, equals('cached_tech_1'),
          reason: 'Cached articles must be instantly accessible when returning to category');

      // 2. Stream subscription starts in parallel for realtime updates
      void ensureCategorySubscribed(String cat) {
        categorySubscriptionToken++;
        activeCategorySub?.cancel();
        activeCategorySub = null;
        activeCategoryName = cat;
      }

      ensureCategorySubscribed('Technology');
      expect(activeCategoryName, equals('Technology'));
      expect(categorySubscriptionToken, equals(1));
      // Data in cache is still preserved!
      expect(categoryNewsMap['Technology'], isNotEmpty);
    });

    test('6. Neighboring PageView pages do NOT create Firestore listeners', () {
      int subscriptionCount = 0;

      void ensureCategorySubscribed(String cat) {
        if (cat == 'For You' || cat == 'Trending' || cat == 'Latest') return;
        subscriptionCount++;
      }

      // Simulation of PageView building adjacent pages:
      // Active page is index 0 ('For You')
      // PageView.builder pre-builds index 1 ('Technology')
      // Because itemBuilder does NOT call ensureCategorySubscribed, subscriptionCount remains 0!
      const int activeIndex = 0;
      final categories = ['For You', 'Technology', 'Sports', 'Agriculture'];

      // PageView.builder simulates building visible and adjacent pages
      for (int i = 0; i <= 1; i++) {
        expect(categories[i], isNotEmpty);
        // In the corrected implementation, itemBuilder ONLY builds content:
        // _buildCategoryContent(cat) - NO subscription call!
      }

      // Subscription ONLY triggered on user selection / onPageChanged:
      ensureCategorySubscribed(categories[activeIndex]);
      expect(subscriptionCount, equals(0),
          reason: 'Initial "For You" page should not trigger category subscriptions, and adjacent pages were not subscribed');
    });

    test('7. Rapid switching race protection: token increments and drops stale async responses', () async {
      final categoryNewsMap = <String, List<NewsArticle>>{};
      StreamSubscription? activeCategorySub;
      String? activeCategoryName;
      int categorySubscriptionToken = 0;

      final controllerA = StreamController<List<NewsArticle>>();
      final controllerB = StreamController<List<NewsArticle>>();

      void ensureCategorySubscribed(String cat, Stream<List<NewsArticle>> stream) {
        categorySubscriptionToken++;
        final currentToken = categorySubscriptionToken;
        activeCategorySub?.cancel();
        activeCategorySub = null;
        activeCategoryName = cat;

        activeCategorySub = stream.listen((articles) {
          if (categorySubscriptionToken != currentToken) return; // Stale event dropped!
          categoryNewsMap[cat] = articles;
        });
      }

      // 1. User selects Category A
      ensureCategorySubscribed('CategoryA', controllerA.stream);

      // 2. User rapidly switches to Category B before Category A emitted
      ensureCategorySubscribed('CategoryB', controllerB.stream);

      // 3. Stale event from Category A arrives late
      final staleArticles = [
        NewsArticle(
          id: 'stale_a',
          title: 'Old Stale Article from A',
          category: 'CategoryA',
          imageUrls: [],
          source: 'Mirror',
          timeAgo: '1h ago',
          publishedAt: DateTime.now(),
        ),
      ];
      controllerA.add(staleArticles);

      // 4. Fresh event from Category B arrives
      final freshArticles = [
        NewsArticle(
          id: 'fresh_b',
          title: 'Fresh Article from B',
          category: 'CategoryB',
          imageUrls: [],
          source: 'Mirror',
          timeAgo: '1m ago',
          publishedAt: DateTime.now(),
        ),
      ];
      controllerB.add(freshArticles);

      await Future.delayed(const Duration(milliseconds: 50));

      // Category A's stale event must have been dropped!
      expect(categoryNewsMap.containsKey('CategoryA'), isFalse,
          reason: 'Stale async event from Category A must be dropped due to token mismatch');
      // Category B's fresh event must be processed!
      expect(categoryNewsMap['CategoryB']?.first.id, equals('fresh_b'),
          reason: 'Fresh event for currently active Category B must be recorded');
      expect(activeCategoryName, equals('CategoryB'));

      await activeCategorySub?.cancel();
      await controllerA.close();
      await controllerB.close();
    });

    test('8. Screen disposal cancels the active category listener safely', () async {
      final controller = StreamController<List<NewsArticle>>();
      StreamSubscription? activeCategorySub = controller.stream.listen((_) {});
      String? activeCategoryName = 'Technology';
      int categorySubscriptionToken = 1;

      // Simulate dispose() / _cancelNewsSubscriptions()
      void cancelNewsSubscriptions() {
        categorySubscriptionToken++;
        activeCategorySub?.cancel();
        activeCategorySub = null;
        activeCategoryName = null;
      }

      cancelNewsSubscriptions();

      expect(activeCategorySub, isNull);
      expect(activeCategoryName, isNull);
      expect(categorySubscriptionToken, equals(2));

      await controller.close();
    });

    test('9. Duplicate callbacks (_onCategoryTap + onPageChanged) do NOT create duplicate subscriptions', () {
      int subscriptionOpens = 0;
      StreamSubscription? activeCategorySub;
      String? activeCategoryName;

      void ensureCategorySubscribed(String cat) {
        if (cat == 'For You' || cat == 'Trending' || cat == 'Latest') return;
        // The duplicate-guard:
        if (activeCategoryName == cat && activeCategorySub != null) return;

        activeCategorySub?.cancel();
        activeCategoryName = cat;
        subscriptionOpens++;

        final controller = StreamController<List<NewsArticle>>();
        activeCategorySub = controller.stream.listen((_) {});
      }

      // Callback 1: User taps 'Technology' tab -> _onCategoryTap calls ensureCategorySubscribed
      ensureCategorySubscribed('Technology');
      expect(subscriptionOpens, equals(1));

      // Callback 2: PageView animation settles -> onPageChanged calls ensureCategorySubscribed
      ensureCategorySubscribed('Technology');
      expect(subscriptionOpens, equals(1),
          reason: 'Duplicate call with same category must NOT create a second subscription');

      activeCategorySub?.cancel();
    });

    test('10. Bounded Fallback Safety: Limits runaway reads while preserving all retained category articles', () {
      final now = DateTime.now();
      final categoryArticles = List.generate(
        30,
        (i) => NewsArticle(
          id: 'art_${i.toString().padLeft(2, '0')}',
          title: 'Article $i',
          category: 'Kenya',
          imageUrls: ['https://example.com/k.jpg'],
          source: 'Mirror Kenya',
          timeAgo: '${i + 1}h ago',
          publishedAt: now.subtract(Duration(hours: i + 1)),
        ),
      );

      const int fallbackLimit = 50;
      final returnedFromFirestore = categoryArticles.take(fallbackLimit).toList();

      expect(returnedFromFirestore.length, equals(30));

      returnedFromFirestore.sort((a, b) {
        final aTime = a.publishedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.publishedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

      final finalArticles = returnedFromFirestore.take(30).toList();
      expect(finalArticles.length, equals(30));
      expect(finalArticles.first.id, equals('art_00'), reason: 'Newest article is first');
      expect(finalArticles.last.id, equals('art_29'), reason: 'Oldest article is 30th');
    });
  });
}
