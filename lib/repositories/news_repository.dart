import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/explore_models.dart';

/// Abstract News Repository defining real-time Stream-based data contract for news content.
abstract class NewsRepository {
  /// Watches top stories for the hero carousel in real-time
  Stream<List<TopStory>> watchTopStories();

  /// Watches trending topics in real-time
  Stream<List<TrendingTopic>> watchTrendingTopics();

  /// Watches news articles for a specific category in real-time
  Stream<List<NewsArticle>> watchCategoryNews(String category);

  /// Watches latest news articles in real-time
  Stream<List<NewsArticle>> watchLatestNews();

  /// Watches mixed news articles for the general feed in real-time
  Stream<List<NewsArticle>> watchAllMixedNews();

  /// Watches news categories list in real-time
  Stream<List<String>> watchCategories();

  /// Fetches a single news article by ID
  Future<NewsArticle?> getArticle(String id);
}

/// Concrete implementation of [NewsRepository].
/// Throws [UnimplementedError] for unimplemented methods until connected to Firestore.
class NewsRepositoryImpl implements NewsRepository {
  @override
  Stream<List<TopStory>> watchTopStories() {
    throw UnimplementedError('watchTopStories() is not implemented yet');
  }

  @override
  Stream<List<TrendingTopic>> watchTrendingTopics() {
    throw UnimplementedError('watchTrendingTopics() is not implemented yet');
  }

  @override
  Stream<List<NewsArticle>> watchCategoryNews(String category) {
    throw UnimplementedError('watchCategoryNews() is not implemented yet');
  }

  @override
  Stream<List<NewsArticle>> watchLatestNews() {
    throw UnimplementedError('watchLatestNews() is not implemented yet');
  }

  @override
  Stream<List<NewsArticle>> watchAllMixedNews() {
    throw UnimplementedError('watchAllMixedNews() is not implemented yet');
  }

  @override
  Stream<List<String>> watchCategories() {
    throw UnimplementedError('watchCategories() is not implemented yet');
  }

  @override
  Future<NewsArticle?> getArticle(String id) {
    throw UnimplementedError('getArticle() is not implemented yet');
  }
}

/// Provider for [NewsRepository]
final newsRepositoryProvider = Provider<NewsRepository>((ref) {
  return NewsRepositoryImpl();
});
