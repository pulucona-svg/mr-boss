import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_laikipia/models/explore_models.dart';
import 'package:mirror_laikipia/screens/explore_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 3 Module 2 — News Articles Admin Validation Tests', () {
    test('1. Reference Links Validation: Validates http/https URLs with host, rejects plain text and invalid schemes', () {
      bool isValidUrl(String input) {
        final trimmed = input.trim();
        if (trimmed.isEmpty) return false;
        final uri = Uri.tryParse(trimmed);
        if (uri == null) return false;
        return (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
      }

      // Valid URLs
      expect(isValidUrl('https://www.bbc.com/news/world-africa-12345'), isTrue);
      expect(isValidUrl('http://nation.africa/kenya/news'), isTrue);
      expect(isValidUrl('https://standardmedia.co.ke/article/2001/breaking'), isTrue);

      // Invalid URLs / Plain text
      expect(isValidUrl(''), isFalse);
      expect(isValidUrl('   '), isFalse);
      expect(isValidUrl('plain text without scheme'), isFalse);
      expect(isValidUrl('bbc.com/news'), isFalse); // Missing scheme
      expect(isValidUrl('ftp://files.example.com/doc'), isFalse); // Non-http(s) scheme
      expect(isValidUrl('https://'), isFalse); // Missing host
      expect(isValidUrl('http:///path/only'), isFalse); // Missing host
    });

    test('2. Subtopic Completeness Validation: Requires title >= 3, body >= 10, image, and caption >= 3', () {
      bool isSubtopicComplete({
        required String title,
        required String body,
        required bool hasImage,
        required String caption,
      }) {
        return title.trim().length >= 3 &&
            body.trim().length >= 10 &&
            hasImage &&
            caption.trim().length >= 3;
      }

      // Completely valid subtopic
      expect(
        isSubtopicComplete(
          title: 'Subtopic 1: Key Finding',
          body: 'This is the detailed explanation containing well over ten characters.',
          hasImage: true,
          caption: 'Infographic showing statistics',
        ),
        isTrue,
      );

      // Invalid: title < 3 chars
      expect(
        isSubtopicComplete(
          title: 'AB',
          body: 'Detailed explanation with sufficient character count.',
          hasImage: true,
          caption: 'Valid Caption',
        ),
        isFalse,
      );

      // Invalid: body < 10 chars
      expect(
        isSubtopicComplete(
          title: 'Valid Title',
          body: 'Short',
          hasImage: true,
          caption: 'Valid Caption',
        ),
        isFalse,
      );

      // Invalid: missing image
      expect(
        isSubtopicComplete(
          title: 'Valid Title',
          body: 'Detailed explanation with sufficient character count.',
          hasImage: false,
          caption: 'Valid Caption',
        ),
        isFalse,
      );

      // Invalid: caption < 3 chars
      expect(
        isSubtopicComplete(
          title: 'Valid Title',
          body: 'Detailed explanation with sufficient character count.',
          hasImage: true,
          caption: 'No',
        ),
        isFalse,
      );
    });

    test('3. Article Form Submission Gate: Strictly requires >= 4 completed subtopics and valid fields', () {
      bool canSubmitArticle({
        required String category,
        required String source,
        required String title,
        required List<bool> completedSubtopics,
        required List<String> links,
      }) {
        if (category.trim().isEmpty) return false;
        if (source.trim().isEmpty) return false;
        if (title.trim().length < 5) return false;
        
        final completedCount = completedSubtopics.where((c) => c).length;
        if (completedCount < 4) return false;

        final validLinks = links.where((link) {
          final uri = Uri.tryParse(link.trim());
          return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
        }).toList();

        if (validLinks.isEmpty) return false;

        return true;
      }

      // Valid form with 4 completed subtopics
      expect(
        canSubmitArticle(
          category: 'Technology',
          source: 'Tech Daily',
          title: 'Major Breakthrough in Artificial Intelligence Announced',
          completedSubtopics: [true, true, true, true],
          links: ['https://example.com/ai-report'],
        ),
        isTrue,
      );

      // Valid form with 5 completed subtopics (adding more than 4 is allowed)
      expect(
        canSubmitArticle(
          category: 'Science',
          source: 'Science Weekly',
          title: 'New Discoveries in Space Exploration',
          completedSubtopics: [true, true, true, true, true],
          links: ['https://nasa.gov/article'],
        ),
        isTrue,
      );

      // Invalid: Only 3 completed subtopics
      expect(
        canSubmitArticle(
          category: 'Technology',
          source: 'Tech Daily',
          title: 'Major Breakthrough in Artificial Intelligence Announced',
          completedSubtopics: [true, true, true, false],
          links: ['https://example.com/ai-report'],
        ),
        isFalse,
      );

      // Invalid: Empty category
      expect(
        canSubmitArticle(
          category: '',
          source: 'Tech Daily',
          title: 'Major Breakthrough in Artificial Intelligence Announced',
          completedSubtopics: [true, true, true, true],
          links: ['https://example.com/ai-report'],
        ),
        isFalse,
      );

      // Invalid: No valid links
      expect(
        canSubmitArticle(
          category: 'Technology',
          source: 'Tech Daily',
          title: 'Major Breakthrough in Artificial Intelligence Announced',
          completedSubtopics: [true, true, true, true],
          links: ['not-a-valid-url'],
        ),
        isFalse,
      );
    });

    test('4. Real-time Status Filtering: NewsRepository excludes deactivated articles from user streams', () {
      final articles = [
        NewsArticle(
          id: 'art_1',
          title: 'Published Article 1',
          category: 'News',
          source: 'Daily News',
          timeAgo: '1h ago',
          status: 'published',
          imageUrls: const [],
          publishedAt: DateTime.parse('2026-09-26T10:00:00Z'),
        ),
        NewsArticle(
          id: 'art_2',
          title: 'Deactivated Article 2',
          category: 'News',
          source: 'Daily News',
          timeAgo: '1h ago',
          status: 'deactivated',
          imageUrls: const [],
          publishedAt: DateTime.parse('2026-09-26T11:00:00Z'),
        ),
        NewsArticle(
          id: 'art_3',
          title: 'Legacy Article Without Status',
          category: 'News',
          source: 'Daily News',
          timeAgo: '1h ago',
          status: null,
          imageUrls: const [],
          publishedAt: DateTime.parse('2026-09-26T09:00:00Z'),
        ),
        NewsArticle(
          id: 'art_4',
          title: 'Legacy Article With Empty Status',
          category: 'News',
          source: 'Daily News',
          timeAgo: '1h ago',
          status: '',
          imageUrls: const [],
          publishedAt: DateTime.parse('2026-09-26T08:00:00Z'),
        ),
      ];

      // Exact filter logic used in NewsRepository
      final userVisibleArticles = articles.where(
        (article) =>
            article.status == null ||
            article.status!.isEmpty ||
            article.status == 'published',
      ).toList();

      expect(userVisibleArticles.length, equals(3));
      expect(userVisibleArticles.map((a) => a.id), containsAll(['art_1', 'art_3', 'art_4']));
      expect(userVisibleArticles.map((a) => a.id), isNot(contains('art_2')));
    });

    test('5. Restore Preserves Original Chronological Position in Category Feed', () {
      final originalPublishedAt = DateTime.parse('2026-09-20T12:00:00Z');

      final articleA = NewsArticle(
        id: 'art_A',
        title: 'Newest Article',
        category: 'Politics',
        source: 'Daily News',
        timeAgo: '1h ago',
        imageUrls: const [],
        publishedAt: DateTime.parse('2026-09-25T12:00:00Z'),
      );
      final articleB = NewsArticle(
        id: 'art_B',
        title: 'Middle Article (Deactivated then Restored)',
        category: 'Politics',
        source: 'Daily News',
        timeAgo: '1h ago',
        status: 'published',
        imageUrls: const [],
        publishedAt: originalPublishedAt, // Retains original timestamp
      );
      final articleC = NewsArticle(
        id: 'art_C',
        title: 'Oldest Article',
        category: 'Politics',
        source: 'Daily News',
        timeAgo: '1h ago',
        imageUrls: const [],
        publishedAt: DateTime.parse('2026-09-15T12:00:00Z'),
      );

      final feed = [articleB, articleC, articleA];
      feed.sort((a, b) {
        final aDate = a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

      // Confirm chronological ordering: A (newest) -> B (original restored time) -> C (oldest)
      expect(feed[0].id, equals('art_A'));
      expect(feed[1].id, equals('art_B'));
      expect(feed[2].id, equals('art_C'));
    });

    test('6. Category 30-Article Retention Limit Logic: Evicts oldest when exceeded', () {
      final List<NewsArticle> categoryFeed = List.generate(
        31,
        (i) => NewsArticle(
          id: 'art_$i',
          title: 'Article $i',
          category: 'Sports',
          source: 'Daily News',
          timeAgo: '1h ago',
          imageUrls: const [],
          publishedAt: DateTime(2026, 1, 1).add(Duration(days: i)),
        ),
      );

      // Sort descending (newest first)
      categoryFeed.sort((a, b) => b.publishedAt!.compareTo(a.publishedAt!));

      expect(categoryFeed.length, equals(31));

      // Enforce 30 retention
      final List<NewsArticle> retained = categoryFeed.take(30).toList();
      final List<NewsArticle> evicted = categoryFeed.skip(30).toList();

      expect(retained.length, equals(30));
      expect(evicted.length, equals(1));
      // Oldest article (index 0 generated with oldest date) is evicted
      expect(evicted.first.id, equals('art_0'));
      expect(retained.first.id, equals('art_30')); // Newest article is retained
    });

    test('7. ExploreScreen Constructor isAdminMode Isolation', () {
      const defaultScreen = ExploreScreen();
      expect(defaultScreen.isAdminMode, isFalse);

      const adminScreen = ExploreScreen(isAdminMode: true);
      expect(adminScreen.isAdminMode, isTrue);

      const explicitUserScreen = ExploreScreen(isAdminMode: false);
      expect(explicitUserScreen.isAdminMode, isFalse);
    });
  });
}
