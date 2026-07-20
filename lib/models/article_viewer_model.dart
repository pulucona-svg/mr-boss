class ContentBlock {
  final String type; // 'paragraph' | 'image' | 'heading'
  final String? text;
  final String? url;
  final String? caption;
  final int? level;

  ContentBlock({
    required this.type,
    this.text,
    this.url,
    this.caption,
    this.level,
  });

  factory ContentBlock.fromJson(Map<String, dynamic> json) {
    return ContentBlock(
      type: json['type'] as String? ?? 'paragraph',
      text: json['text'] as String?,
      url: json['url'] as String?,
      caption: json['caption'] as String?,
      level: json['level'] is int ? json['level'] as int : null,
    );
  }
}

class ViewerImage {
  final String url;
  final String? caption;

  ViewerImage({required this.url, this.caption});

  factory ViewerImage.fromJson(Map<String, dynamic> json) {
    return ViewerImage(
      url: json['url'] as String? ?? '',
      caption: json['caption'] as String?,
    );
  }
}

class ViewerSection {
  final String heading;
  final List<String> paragraphs;

  ViewerSection({required this.heading, required this.paragraphs});

  factory ViewerSection.fromJson(Map<String, dynamic> json) {
    final rawParagraphs = json['paragraphs'];
    List<String> list = [];
    if (rawParagraphs is List) {
      list = rawParagraphs.map((e) => e.toString()).toList();
    }
    return ViewerSection(
      heading: json['heading'] as String? ?? '',
      paragraphs: list,
    );
  }
}

class ArticleViewerDocument {
  final String articleId;
  final String title;
  final String? subtitle;
  final List<String> subtitles;
  final String category;
  final List<String> secondaryCategories;
  final String source;
  final String? author;
  final String? publishedAt;
  final int readingTime;
  final String? editorialSummary;
  final String? fullStory;
  final List<String> paragraphs;
  final List<ContentBlock> content;
  final List<ViewerImage> images;
  final List<ViewerSection> sections;
  final List<String> relatedArticles;
  final String? originalSourceUrl;

  ArticleViewerDocument({
    required this.articleId,
    required this.title,
    this.subtitle,
    this.subtitles = const [],
    required this.category,
    this.secondaryCategories = const [],
    required this.source,
    this.author,
    this.publishedAt,
    this.readingTime = 1,
    this.editorialSummary,
    this.fullStory,
    this.paragraphs = const [],
    this.content = const [],
    this.images = const [],
    this.sections = const [],
    this.relatedArticles = const [],
    this.originalSourceUrl,
  });

  factory ArticleViewerDocument.fromJson(Map<String, dynamic> json) {
    List<String> parseStringList(dynamic raw) {
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      return [];
    }

    List<ContentBlock> parseContent(dynamic raw) {
      if (raw is List) {
        return raw
            .whereType<Map<String, dynamic>>()
            .map((item) => ContentBlock.fromJson(item))
            .toList();
      }
      return [];
    }

    List<ViewerImage> parseImages(dynamic raw) {
      if (raw is List) {
        return raw
            .whereType<Map<String, dynamic>>()
            .map((item) => ViewerImage.fromJson(item))
            .toList();
      }
      return [];
    }

    List<ViewerSection> parseSections(dynamic raw) {
      if (raw is List) {
        return raw
            .whereType<Map<String, dynamic>>()
            .map((item) => ViewerSection.fromJson(item))
            .toList();
      }
      return [];
    }

    return ArticleViewerDocument(
      articleId: json['articleId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String?,
      subtitles: parseStringList(json['subtitles']),
      category: json['category'] as String? ?? 'General',
      secondaryCategories: parseStringList(json['secondaryCategories']),
      source: json['source'] as String? ?? '',
      author: json['author'] as String?,
      publishedAt: json['publishedAt'] as String?,
      readingTime: json['readingTime'] is int ? json['readingTime'] as int : 1,
      editorialSummary: json['editorialSummary'] as String?,
      fullStory: json['fullStory'] as String?,
      paragraphs: parseStringList(json['paragraphs']),
      content: parseContent(json['content']),
      images: parseImages(json['images']),
      sections: parseSections(json['sections']),
      relatedArticles: parseStringList(json['relatedArticles']),
      originalSourceUrl: json['originalSourceUrl'] as String?,
    );
  }
}
