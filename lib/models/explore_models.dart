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

  NewsArticle({
    required this.id,
    required this.title,
    required this.category,
    required this.imageUrls,
    required this.source,
    required this.timeAgo,
    this.content = '',
    this.details = const {},
  });
}
