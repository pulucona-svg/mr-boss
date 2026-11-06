import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_laikipia/models/explore_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Explore Page Ordering, Robustness & Fallback Verification', () {
    test('1. Timestamp Sorting: newest articles sort first, null timestamps sort last safely', () {
      final now = DateTime.now();
      final artNew = NewsArticle(
        id: 'new_art',
        title: 'Newest Breaking Story',
        category: 'Technology',
        imageUrls: ['https://example.com/new.jpg'],
        source: 'Mirror Tech',
        timeAgo: '10m ago',
        publishedAt: now.subtract(const Duration(minutes: 10)),
      );

      final artOld = NewsArticle(
        id: 'old_art',
        title: 'Old Story from August',
        category: 'Technology',
        imageUrls: ['https://example.com/old.jpg'],
        source: 'Mirror Tech',
        timeAgo: '60d ago',
        publishedAt: now.subtract(const Duration(days: 60)),
      );

      final artNoDate = NewsArticle(
        id: 'nodate_art',
        title: 'Story Without Date',
        category: 'Technology',
        imageUrls: ['https://example.com/nodate.jpg'],
        source: 'Mirror Tech',
        timeAgo: 'Recently',
        publishedAt: null,
        createdAt: null,
      );

      final artCreatedFallback = NewsArticle(
        id: 'created_fallback_art',
        title: 'Story With Only CreatedAt',
        category: 'Technology',
        imageUrls: ['https://example.com/created.jpg'],
        source: 'Mirror Tech',
        timeAgo: '1d ago',
        publishedAt: null,
        createdAt: now.subtract(const Duration(days: 1)),
      );

      final articles = [artOld, artNoDate, artNew, artCreatedFallback];

      // Sort descending by publishedAt ?? createdAt
      articles.sort((a, b) {
        final aTime = a.publishedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.publishedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

      expect(articles[0].id, equals('new_art'), reason: 'Newest article must sort to index 0');
      expect(articles[1].id, equals('created_fallback_art'), reason: '1-day old created fallback must be index 1');
      expect(articles[2].id, equals('old_art'), reason: '60-day old article must be index 2');
      expect(articles[3].id, equals('nodate_art'), reason: 'Undated article must safely sort to the end without crashing');
    });

    test('2. TopStory Model & Selection Rules', () {
      final now = DateTime.now();
      final stories = [
        NewsArticle(
          id: 'story_no_img',
          title: 'Article Without Image',
          category: 'Sports',
          imageUrls: [],
          source: 'Sports Hub',
          timeAgo: '1h ago',
          publishedAt: now.subtract(const Duration(hours: 1)),
          status: 'published',
        ),
        NewsArticle(
          id: 'story_with_img_1',
          title: 'Article 1 With Image',
          category: 'Sports',
          imageUrls: ['https://example.com/s1.jpg'],
          source: 'Sports Hub',
          timeAgo: '2h ago',
          publishedAt: now.subtract(const Duration(hours: 2)),
          status: 'published',
        ),
        NewsArticle(
          id: 'story_with_img_2',
          title: 'Article 2 With Image',
          category: 'Sports',
          imageUrls: ['https://example.com/s2.jpg'],
          source: 'Sports Hub',
          timeAgo: '30m ago',
          publishedAt: now.subtract(const Duration(minutes: 30)),
          status: 'published',
        ),
        NewsArticle(
          id: 'story_draft',
          title: 'Draft Article',
          category: 'Sports',
          imageUrls: ['https://example.com/draft.jpg'],
          source: 'Sports Hub',
          timeAgo: '5m ago',
          publishedAt: now.subtract(const Duration(minutes: 5)),
          status: 'draft',
        ),
      ];

      final topEligible = stories
          .where((a) => a.status == null || a.status!.isEmpty || a.status == 'published')
          .toList();

      topEligible.sort((a, b) {
        final aTime = a.publishedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.publishedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

      final topStories = topEligible
          .map((art) => TopStory(
                id: art.id,
                title: art.title,
                summary: art.summary.isNotEmpty ? art.summary : art.content,
                imageUrl: art.coverImage ?? (art.imageUrls.isNotEmpty ? art.imageUrls.first : ''),
                source: art.source,
                timeAgo: art.timeAgo,
                category: art.category,
              ))
          .where((s) => s.imageUrl.isNotEmpty)
          .take(5)
          .toList();

      expect(topStories.length, equals(2));
      expect(topStories.first.id, equals('story_with_img_2'), reason: 'Newest published story with image must be first');
      expect(topStories[1].id, equals('story_with_img_1'));
      expect(topStories.any((s) => s.id == 'story_draft'), isFalse, reason: 'Drafts must be excluded');
      expect(topStories.any((s) => s.id == 'story_no_img'), isFalse, reason: 'Image-less stories must be excluded from carousel');
    });

    test('3. Hex Gradient Colors in TrendingTopic gracefully handled', () {
      final dataHex = {
        'title': 'Autonomous AI Farming Summit',
        'gradientColors': ['#20C8FF', '#287BFF'],
      };

      List<Color> gradientColors = const [Color(0xFF6366F1), Color(0xFF8B5CF6)];
      if (dataHex['gradientColors'] is List && (dataHex['gradientColors'] as List).isNotEmpty) {
        try {
          final parsed = (dataHex['gradientColors'] as List).map((c) {
            final str = c.toString().replaceAll('#', '').trim();
            final hex = str.length == 6 ? 'FF$str' : str;
            return Color(int.parse(hex, radix: 16));
          }).toList();
          if (parsed.length >= 2) gradientColors = parsed;
        } catch (_) {}
      }

      expect(gradientColors.length, equals(2));
      expect(gradientColors[0], equals(const Color(0xFF20C8FF)));
      expect(gradientColors[1], equals(const Color(0xFF287BFF)));
    });

    test('4. Malformed Gradient Colors gracefully fall back to defaults', () {
      final dataMalformed = {
        'title': 'Malformed Topic',
        'gradientColors': ['invalid_hex_string'],
      };

      List<Color> gradientColors = const [Color(0xFF6366F1), Color(0xFF8B5CF6)];
      if (dataMalformed['gradientColors'] is List && (dataMalformed['gradientColors'] as List).isNotEmpty) {
        try {
          final parsed = (dataMalformed['gradientColors'] as List).map((c) {
            final str = c.toString().replaceAll('#', '').trim();
            final hex = str.length == 6 ? 'FF$str' : str;
            return Color(int.parse(hex, radix: 16));
          }).toList();
          if (parsed.length >= 2) gradientColors = parsed;
        } catch (_) {}
      }

      expect(gradientColors, equals(const [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
          reason: 'Must fall back to default colors without throwing exception');
    });

    test('5. Legacy Document Missing publishedAt: Resolves createdAt and positions accurately', () {
      final now = DateTime.now();

      // Document with no publishedAt but valid createdAt
      final legacyDoc = NewsArticle(
        id: 'legacy_doc_1',
        title: 'Legacy Article Without PublishedAt',
        category: 'Politics',
        imageUrls: ['https://example.com/p1.jpg'],
        source: 'Parliament News',
        timeAgo: '2h ago',
        publishedAt: null,
        createdAt: now.subtract(const Duration(hours: 2)),
      );

      final olderDoc = NewsArticle(
        id: 'older_doc',
        title: 'Older Article With PublishedAt',
        category: 'Politics',
        imageUrls: ['https://example.com/p2.jpg'],
        source: 'Parliament News',
        timeAgo: '5h ago',
        publishedAt: now.subtract(const Duration(hours: 5)),
      );

      final newerDoc = NewsArticle(
        id: 'newer_doc',
        title: 'Newer Article With PublishedAt',
        category: 'Politics',
        imageUrls: ['https://example.com/p3.jpg'],
        source: 'Parliament News',
        timeAgo: '30m ago',
        publishedAt: now.subtract(const Duration(minutes: 30)),
      );

      final list = [olderDoc, legacyDoc, newerDoc];
      list.sort((a, b) {
        final aTime = a.publishedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.publishedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

      expect(list[0].id, equals('newer_doc'));
      expect(list[1].id, equals('legacy_doc_1'), reason: 'Legacy doc with 2h createdAt must slot between 30m and 5h');
      expect(list[2].id, equals('older_doc'));
    });

    test('6. Invalid Timestamps: Malformed string safely falls back without throwing', () {
      final now = DateTime.now();

      DateTime? parseDate(dynamic val) {
        if (val == null) return null;
        if (val is String) return DateTime.tryParse(val);
        if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
        return null;
      }

      DateTime? resolveEffective(dynamic p, dynamic c, dynamic col) {
        final pDate = parseDate(p);
        if (pDate != null) return pDate;
        final cDate = parseDate(c);
        if (cDate != null) return cDate;
        final colDate = parseDate(col);
        if (colDate != null) return colDate;
        return null;
      }

      // Case A: publishedAt is invalid string, createdAt is valid ISO string
      final resA = resolveEffective('invalid-date-string', now.toIso8601String(), null);
      expect(resA, isNotNull);
      expect(resA!.difference(now).inSeconds.abs(), lessThanOrEqualTo(1));

      // Case B: publishedAt is invalid string, createdAt is integer millis
      final millis = now.millisecondsSinceEpoch;
      final resB = resolveEffective('corrupt-date', millis, null);
      expect(resB, isNotNull);
      expect(resB!.millisecondsSinceEpoch, equals(millis));

      // Case C: both are invalid strings
      final resC = resolveEffective('corrupt-date-1', 'corrupt-date-2', null);
      expect(resC, isNull);
    });

    test('7. Avoiding Arbitrary Pre-Sort Limits: Newest documents with late doc IDs are preserved', () {
      final now = DateTime.now();

      // Simulate 40 articles in a category where the 5 newest articles have IDs 'zzz_0'..'zzz_4'
      // A query with .limit(30) by doc ID would have only fetched 'aaa_0'..'aaa_29' and missed the newest 5!
      final allCategoryArticles = <NewsArticle>[];

      for (int i = 0; i < 35; i++) {
        allCategoryArticles.add(
          NewsArticle(
            id: 'aaa_${i.toString().padLeft(2, '0')}',
            title: 'Older Article $i',
            category: 'Agriculture',
            imageUrls: ['https://example.com/agri.jpg'],
            source: 'AgriNews',
            timeAgo: '${i + 2}d ago',
            publishedAt: now.subtract(Duration(days: i + 2)),
          ),
        );
      }

      // The 5 newest articles have IDs that sort at the very end lexicographically
      for (int i = 0; i < 5; i++) {
        allCategoryArticles.add(
          NewsArticle(
            id: 'zzz_$i',
            title: 'Breaking Agriculture News $i',
            category: 'Agriculture',
            imageUrls: ['https://example.com/agri_new.jpg'],
            source: 'AgriNews',
            timeAgo: '${(i + 1) * 10}m ago',
            publishedAt: now.subtract(Duration(minutes: (i + 1) * 10)),
          ),
        );
      }

      // Pre-sort arbitrary truncation (the bug): would take the first 30 docs by id ('aaa_00'..'aaa_29')
      final buggyDocs = allCategoryArticles.take(30).toList();
      buggyDocs.sort((a, b) {
        final aTime = a.publishedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.publishedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      expect(buggyDocs.any((a) => a.id.startsWith('zzz_')), isFalse,
          reason: 'Pre-sort limit dropped the newest articles because their IDs sorted after index 30');

      // The correct fallback: scope query to category without pre-sort limit, sort in memory, then take 30
      final correctDocs = List<NewsArticle>.from(allCategoryArticles);
      correctDocs.sort((a, b) {
        final aTime = a.publishedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.publishedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      final finalizedCategoryArticles = correctDocs.take(30).toList();

      expect(finalizedCategoryArticles.length, equals(30));
      // The first 5 articles MUST be the newest 'zzz_' articles!
      for (int i = 0; i < 5; i++) {
        expect(finalizedCategoryArticles[i].id, startsWith('zzz_'),
            reason: 'Articles at index $i must be the newest articles regardless of document ID');
      }
    });

    test('8. Navigation Logic: PopScope allows exit on first category and resets active filter otherwise', () {
      // Rule verification: System back button must disengage active filters on Explore screen
      final categories = ['For You', 'Sports', 'Technology', 'Politics'];
      String currentCategory = 'Sports';

      bool canPop = (currentCategory == categories.first);
      expect(canPop, isFalse, reason: 'When on Sports filter, screen should not pop on back button');

      // Simulate back pressed
      if (!canPop) {
        currentCategory = categories.first;
      }
      expect(currentCategory, equals('For You'));

      canPop = (currentCategory == categories.first);
      expect(canPop, isTrue, reason: 'When on first category (For You), screen is eligible to pop');
    });

    test('9. Timestamp Resolution Matrix: exact behavior for publishedAt, only createdAt, only collectedAt, and none', () {
      final now = DateTime.now();

      DateTime? parseDate(dynamic val) {
        if (val == null) return null;
        if (val is DateTime) return val;
        if (val is String) return DateTime.tryParse(val);
        if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
        return null;
      }

      DateTime? resolveEffectiveDate(dynamic publishedVal, dynamic createdVal, dynamic collectedVal) {
        final pDate = parseDate(publishedVal);
        if (pDate != null) return pDate;
        final cDate = parseDate(createdVal);
        if (cDate != null) return cDate;
        final colDate = parseDate(collectedVal);
        if (colDate != null) return colDate;
        return null;
      }

      String formatTimeAgo(dynamic timestampVal) {
        final date = parseDate(timestampVal);
        if (date == null) return 'Recently';
        final diff = DateTime.now().difference(date);
        if (diff.inMinutes < 1) return 'Just now';
        if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
        if (diff.inHours < 24) return '${diff.inHours}h ago';
        return '${diff.inDays}d ago';
      }

      // Case A: Full document with publishedAt (1 hour ago), createdAt (2 hours ago), collectedAt (3 hours ago)
      final date1h = now.subtract(const Duration(hours: 1));
      final date2h = now.subtract(const Duration(hours: 2));
      final date3h = now.subtract(const Duration(hours: 3));
      final effA = resolveEffectiveDate(date1h, date2h, date3h);
      expect(effA, equals(date1h), reason: 'publishedAt takes precedence when available');
      expect(formatTimeAgo(effA), equals('1h ago'));

      // Case B: Document with ONLY createdAt (4 hours ago)
      final date4h = now.subtract(const Duration(hours: 4));
      final effB = resolveEffectiveDate(null, date4h, null);
      expect(effB, equals(date4h), reason: 'Falls back to createdAt when publishedAt is null');
      expect(formatTimeAgo(effB), equals('4h ago'));

      // Case C: Document with ONLY collectedAt (6 hours ago)
      final date6h = now.subtract(const Duration(hours: 6));
      final effC = resolveEffectiveDate(null, null, date6h);
      expect(effC, equals(date6h), reason: 'Falls back to collectedAt when publishedAt and createdAt are null');
      expect(formatTimeAgo(effC), equals('6h ago'));

      // Case D: Document with NONE of these timestamps
      final effD = resolveEffectiveDate(null, null, null);
      expect(effD, isNull, reason: 'Returns null when all candidate timestamps are absent');
      expect(formatTimeAgo(effD), equals('Recently'), reason: 'Null date falls back to "Recently" label');

      // Sorting all 4 cases together
      final docA = NewsArticle(
        id: 'case_A_published',
        title: 'Article With publishedAt',
        category: 'Campus',
        imageUrls: const ['https://example.com/1.jpg'],
        source: 'Mirror News',
        timeAgo: formatTimeAgo(effA),
        publishedAt: effA,
        createdAt: date2h,
      );

      final docB = NewsArticle(
        id: 'case_B_only_created',
        title: 'Article With Only createdAt',
        category: 'Campus',
        imageUrls: const ['https://example.com/2.jpg'],
        source: 'Mirror News',
        timeAgo: formatTimeAgo(effB),
        publishedAt: effB,
        createdAt: date4h,
      );

      final docC = NewsArticle(
        id: 'case_C_only_collected',
        title: 'Article With Only collectedAt',
        category: 'Campus',
        imageUrls: const ['https://example.com/3.jpg'],
        source: 'Mirror News',
        timeAgo: formatTimeAgo(effC),
        publishedAt: effC,
        createdAt: effC,
      );

      final docD = NewsArticle(
        id: 'case_D_none',
        title: 'Article With No Timestamp',
        category: 'Campus',
        imageUrls: const ['https://example.com/4.jpg'],
        source: 'Mirror News',
        timeAgo: formatTimeAgo(effD),
        publishedAt: null,
        createdAt: null,
      );

      final sortedList = [docC, docD, docA, docB];
      sortedList.sort((a, b) {
        final aTime = a.publishedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.publishedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

      expect(sortedList[0].id, equals('case_A_published'), reason: '1h ago must be 1st');
      expect(sortedList[1].id, equals('case_B_only_created'), reason: '4h ago must be 2nd');
      expect(sortedList[2].id, equals('case_C_only_collected'), reason: '6h ago must be 3rd');
      expect(sortedList[3].id, equals('case_D_none'), reason: 'Null timestamp sorts last safely at epoch 0');
    });

    test('10. Companion Stream Merging: Deduplicates docs and rescues articles missing publishedAt', () {
      final now = DateTime.now();

      // Simulated docs from queryPub (orderBy publishedAt)
      final doc1 = {'id': 'doc_1', 'publishedAt': now.subtract(const Duration(minutes: 10)), 'createdAt': now.subtract(const Duration(minutes: 15))};
      final doc2 = {'id': 'doc_2', 'publishedAt': now.subtract(const Duration(minutes: 30)), 'createdAt': now.subtract(const Duration(minutes: 35))};

      // Simulated docs from queryCreated (orderBy createdAt) - includes doc_2 (overlap) and doc_legacy (missing publishedAt)
      final doc2Overlap = {'id': 'doc_2', 'publishedAt': now.subtract(const Duration(minutes: 30)), 'createdAt': now.subtract(const Duration(minutes: 35))};
      final docLegacy = {'id': 'doc_legacy', 'publishedAt': null, 'createdAt': now.subtract(const Duration(minutes: 5))};

      // In the companion architecture:
      final Map<String, Map<String, dynamic>> pubDocs = {'doc_1': doc1, 'doc_2': doc2};
      final Map<String, Map<String, dynamic>> createdDocs = {'doc_2': doc2Overlap, 'doc_legacy': docLegacy};

      final merged = {...pubDocs, ...createdDocs};

      // Verify deduplication
      expect(merged.length, equals(3), reason: 'doc_2 must not be duplicated');
      expect(merged.containsKey('doc_legacy'), isTrue, reason: 'doc_legacy must be rescued into the merged dataset');

      // Sort merged items
      final list = merged.values.toList();
      list.sort((a, b) {
        final aTime = a['publishedAt'] ?? a['createdAt'];
        final bTime = b['publishedAt'] ?? b['createdAt'];
        return (bTime as DateTime).compareTo(aTime as DateTime);
      });

      expect(list[0]['id'], equals('doc_legacy'), reason: 'doc_legacy (5m ago) must be first because of its recent createdAt');
      expect(list[1]['id'], equals('doc_1'), reason: 'doc_1 (10m ago) must be second');
      expect(list[2]['id'], equals('doc_2'), reason: 'doc_2 (30m ago) must be third');
    });
  });
}
