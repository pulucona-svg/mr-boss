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

  TrendingTopic({
    required this.id,
    required this.title,
    required this.icon,
    required this.gradientColors,
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
