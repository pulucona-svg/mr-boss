import 'package:flutter/material.dart';

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
    this.imageUrls = const [
      'https://images.unsplash.com/photo-1504711434969-e33886168f5c?q=80&w=2000&auto=format&fit=crop',
      'https://images.unsplash.com/photo-1495020689067-958852a7765e?q=80&w=2000&auto=format&fit=crop',
    ],
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
}

List<String> getFourRelevantImages(List<String> existing, String category, String title) {
  final Set<String> images = {};
  for (final url in existing) {
    if (url.isNotEmpty && !images.contains(url)) {
      images.add(url);
    }
  }

  final String catLower = category.toLowerCase();
  final List<String> fallbackPool;
  if (catLower.contains('kenya') || catLower.contains('africa')) {
    fallbackPool = [
      'https://images.unsplash.com/photo-1547471080-7cc2caa01a7e?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1516426122078-c23e76319801?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1523805009345-7448845a9e53?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1489749798305-4fea3ae63d43?w=800&auto=format&fit=crop&q=80',
    ];
  } else if (catLower.contains('tech') || catLower.contains('science')) {
    fallbackPool = [
      'https://images.unsplash.com/photo-1518770660439-4636190af475?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1451187580459-43490279c0fa?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1526374965328-7f61d4dc18c5?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1507413245164-6160d8298b31?w=800&auto=format&fit=crop&q=80',
    ];
  } else if (catLower.contains('business') || catLower.contains('politics')) {
    fallbackPool = [
      'https://images.unsplash.com/photo-1486406146926-c627a92ad1ab?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1590283603385-17ffb3a7f29f?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1521791136064-7986c2920216?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1541872703-74c5e44368f9?w=800&auto=format&fit=crop&q=80',
    ];
  } else if (catLower.contains('sports')) {
    fallbackPool = [
      'https://images.unsplash.com/photo-1508098682722-e99c43a406b2?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1461896836934-ffe607ba8211?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1517649763962-0c623266010b?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1579952363873-27f3bade9f55?w=800&auto=format&fit=crop&q=80',
    ];
  } else if (catLower.contains('nature') || catLower.contains('environment')) {
    fallbackPool = [
      'https://images.unsplash.com/photo-1448375240586-882707db888b?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=800&auto=format&fit=crop&q=80',
    ];
  } else if (catLower.contains('health')) {
    fallbackPool = [
      'https://images.unsplash.com/photo-1505751172876-fa1923c5c528?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1576091160399-112ba8d25d1d?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1532938911079-1b06ac7ceec7?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1584515979956-d9f6e5d09982?w=800&auto=format&fit=crop&q=80',
    ];
  } else {
    fallbackPool = [
      'https://images.unsplash.com/photo-1504711434969-e33886168f5c?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1495020689067-958852a7765e?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1585829365295-ab7cd400c167?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1488190211105-8b0e65b80b4e?w=800&auto=format&fit=crop&q=80',
    ];
  }

  int idx = 0;
  while (images.length < 4 && idx < fallbackPool.length) {
    images.add(fallbackPool[idx]);
    idx++;
  }

  return images.toList();
}
