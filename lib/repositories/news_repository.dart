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

  /// Watches full ExploreCategory models from categories collection
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

  @override
  Stream<List<TopStory>> watchTopStories() {
    return _firestore
        .collection('topStories')
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      return snapshot.docs
          .where((doc) => !_isExpired(doc.data()['expiresAt'], now))
          .map((doc) => _mapDocToTopStory(doc))
          .toList();
    });
  }

  @override
  Stream<List<TrendingTopic>> watchTrendingTopics() {
    return _firestore
        .collection('trendingTopics')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => _mapDocToTrendingTopic(doc))
          .toList();
    });
  }

  @override
  Stream<List<NewsArticle>> watchCategoryNews(String category) {
    final catLower = category.toLowerCase().trim();
    if (catLower == 'all' || catLower == 'general' || catLower.isEmpty) {
      return watchLatestNews();
    }

    return _firestore
        .collection('explore_news')
        .where('category', isEqualTo: category)
        .snapshots()
        .map((snapshot) {
      final articles = snapshot.docs
          .map((doc) => _mapDocToNewsArticle(doc))
          .toList();

      articles.sort((a, b) {
        final dateA = a.publishedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = b.publishedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });

      return articles;
    });
  }

  @override
  Stream<List<NewsArticle>> watchLatestNews() {
    return _firestore
        .collection('explore_news')
        .snapshots()
        .map((snapshot) {
      final articles = snapshot.docs
          .map((doc) => _mapDocToNewsArticle(doc))
          .toList();

      articles.sort((a, b) {
        final dateA = a.publishedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = b.publishedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });

      return articles;
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
    return _firestore.collection('categories').snapshots().map((snapshot) {
      final List<ExploreCategory> list = [];
      final Set<String> seenNames = {};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final cat = ExploreCategory.fromMap(doc.id, data);

        if (!cat.enabled) continue;

        final normName = cat.name.toLowerCase();
        if (seenNames.contains(normName)) continue;
        seenNames.add(normName);

        list.add(cat);
      }

      list.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
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

      return null;
    } catch (_) {
      return null;
    }
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
