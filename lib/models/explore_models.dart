import 'package:flutter/material.dart';

class ExploreCategory {
  final String id;
  final String name;
  final int displayOrder;
  final bool enabled;
  final String? icon;
  final String? color;
  final String? description;
  final int? targetArticles;

  ExploreCategory({
    required this.id,
    required this.name,
    required this.displayOrder,
    this.enabled = true,
    this.icon,
    this.color,
    this.description,
    this.targetArticles,
  });

  factory ExploreCategory.fromMap(String id, Map<String, dynamic> data) {
    return ExploreCategory(
      id: id,
      name: (data['name'] as String?)?.trim() ?? id,
      displayOrder: (data['displayOrder'] as num?)?.toInt() ?? 999,
      enabled: data['enabled'] as bool? ?? true,
      icon: data['icon'] as String?,
      color: data['color'] as String?,
      description: data['description'] as String?,
      targetArticles: (data['targetArticles'] as num?)?.toInt(),
    );
  }
}

class TopStory {
  final String id;
  final String title;
  final String summary;
  final String imageUrl;
  final String source;
  final String timeAgo;
  final String category;

  TopStory({
    required this.id,
    required this.title,
    required this.summary,
    required this.imageUrl,
    required this.source,
    required this.timeAgo,
    required this.category,
  });
}

class TrendingTopic {
  final String id;
  final String title;
  final IconData icon;
  final List<Color> gradientColors;
  final List<String> imageUrls;
  final String description;
  final Map<String, String> details;
  final String source;
  final String timeAgo;

  TrendingTopic({
    required this.id,
    required this.title,
    required this.icon,
    required this.gradientColors,
    this.imageUrls = const [],
    this.description = 'Stay updated with the latest developments on this trending topic. We bring you real-time insights and comprehensive coverage as events unfold.',
    this.details = const {
      'Why it\'s Trending': 'High engagement across social platforms and major news outlets.',
      'Recent Activity': 'Increased discussion and news coverage in the last 24 hours.',
      'Key Figures': 'Multiple industry leaders and influencers are weighing in.',
      'Impact': 'This topic is shaping regional and global conversations.'
    },
    this.source = 'Trending Now',
    this.timeAgo = 'Just now',
  });
}

class NewsArticle {
  final String id;
  final String title;
  final String category;
  final List<String> imageUrls;
  final String source;
  final String timeAgo;
  final String content;
  final String summary;
  final String? provider;
  final DateTime? publishedAt;
  final List<Map<String, dynamic>> imagesData;
  final Map<String, String> details;

  // Optional fields for automated news backend & article viewer integration
  final String? slug;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final DateTime? updatedAt;
  final String? viewerDocumentId;
  final String? viewerUrl;
  final String? coverImage;
  final String? status;
  final int? priority;
  final String? sourceUrl;

  NewsArticle({
    required this.id,
    required this.title,
    required this.category,
    required this.imageUrls,
    required this.source,
    required this.timeAgo,
    this.content = '',
    this.summary = '',
    this.provider,
    this.publishedAt,
    this.imagesData = const [],
    this.details = const {},
    this.slug,
    this.createdAt,
    this.expiresAt,
    this.updatedAt,
    this.viewerDocumentId,
    this.viewerUrl,
    this.coverImage,
    this.status,
    this.priority,
    this.sourceUrl,
  });

  String get dynamicTimeAgo {
    final date = publishedAt ?? createdAt;
    if (date == null) return timeAgo.isNotEmpty ? timeAgo : 'Recently';
    final diff = DateTime.now().difference(date);
    if (diff.isNegative || diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }

  int get readingTimeMinutes {
    final text = '$title $summary $content';
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final mins = (words / 200).ceil();
    return mins < 1 ? 1 : mins;
  }
}


List<String> getFourRelevantImages(List<String> existing, String category, String title) {
  final Set<String> images = {};
  for (final url in existing) {
    if (url.isNotEmpty && !images.contains(url)) {
      images.add(url);
    }
  }
  return images.toList();
}
