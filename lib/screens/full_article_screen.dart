import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/article_viewer_model.dart';
import '../models/explore_models.dart';
import '../widgets/skeleton.dart';
import '../services/interstitial_ad_service.dart';


class FullArticleScreen extends StatefulWidget {
  final NewsArticle? article;
  final String? viewerUrl;

  const FullArticleScreen({
    super.key,
    this.article,
    this.viewerUrl,
  });

  @override
  State<FullArticleScreen> createState() => _FullArticleScreenState();
}

class _FullArticleScreenState extends State<FullArticleScreen> {
  late final Dio _dio;
  late final ScrollController _scrollController;
  Timer? _minuteTickerTimer;
  bool _isLoading = false;
  String? _errorMessage;
  ArticleViewerDocument? _viewerDoc;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));

    _minuteTickerTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });

    if (_resolvedViewerUrl != null && widget.article == null) {
      _fetchViewerDocument();
    }
  }

  @override
  void dispose() {
    _minuteTickerTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  String? get _resolvedViewerUrl {
    if (widget.viewerUrl != null && widget.viewerUrl!.isNotEmpty) {
      return widget.viewerUrl;
    }
    if (widget.article?.viewerUrl != null && widget.article!.viewerUrl!.isNotEmpty) {
      return widget.article!.viewerUrl;
    }
    return null;
  }

  Future<void> _fetchViewerDocument() async {
    final url = _resolvedViewerUrl;
    if (url == null || url.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );

      if (response.statusCode == 200 && response.data != null) {
        final Map<String, dynamic> jsonData = json.decode(response.data!);
        final doc = ArticleViewerDocument.fromJson(jsonData);

        if (mounted) {
          setState(() {
            _viewerDoc = doc;
            _isLoading = false;
          });
        }
      } else {
        throw Exception('HTTP Error ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _launchSourceUrl(String? urlStr) async {
    if (urlStr == null || urlStr.trim().isEmpty) return;
    final Uri? uri = Uri.tryParse(urlStr.trim());
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF070716) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final secondaryTextColor = isDark ? Colors.white70 : const Color(0xFF334155);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
          onPressed: () {
            Navigator.pop(context);
            InterstitialAdService().maybeShowOnTransition(
              transitionPoint: 'full_article_screen_exit',
            );
          },
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.bookmark_border_rounded, color: textColor, size: 22),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(Icons.share_outlined, color: textColor, size: 22),
            onPressed: () {},
          ),
        ],
      ),
      body: _buildBody(context, isDark, textColor, secondaryTextColor),
    );
  }

  Widget _buildBody(BuildContext context, bool isDark, Color textColor, Color secondaryTextColor) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF20C8FF)),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading article...',
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.article != null) {
      return _buildArticleContent(context, widget.article!, isDark, textColor, secondaryTextColor);
    }

    if (_viewerDoc != null) {
      final docArt = NewsArticle(
        id: _viewerDoc!.articleId,
        title: _viewerDoc!.title,
        category: _viewerDoc!.category,
        imageUrls: _viewerDoc!.content
            .where((b) => b.type == 'image' && b.url != null)
            .map((b) => b.url!)
            .toList(),
        source: _viewerDoc!.source,
        timeAgo: _viewerDoc!.publishedAt ?? 'Recently',
        content: _viewerDoc!.fullStory ?? _viewerDoc!.paragraphs.join('\n\n'),
        summary: _viewerDoc!.paragraphs.isNotEmpty ? _viewerDoc!.paragraphs.first : '',
        sourceUrl: _viewerDoc!.originalSourceUrl,
      );
      return _buildArticleContent(context, docArt, isDark, textColor, secondaryTextColor);
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article_outlined, size: 64, color: isDark ? Colors.white24 : Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Article Unavailable',
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'The requested article could not be loaded.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArticleContent(
    BuildContext context,
    NewsArticle article,
    bool isDark,
    Color textColor,
    Color secondaryTextColor,
  ) {
    final widgets = _parseArticleBlocks(article, isDark, textColor, secondaryTextColor);

    return SingleChildScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category Pill & Reading Time Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF20C8FF).withAlpha(38),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF20C8FF).withAlpha(102),
                  ),
                ),
                child: Text(
                  article.category.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF20C8FF),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(Icons.access_time_rounded, size: 13, color: isDark ? Colors.white70 : Colors.black54),
                    const SizedBox(width: 4),
                    Text(
                      '${article.readingTimeMinutes} min read',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Article Headline
          Text(
            article.title,
            style: TextStyle(
              color: textColor,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),

          const SizedBox(height: 12),

          // Source & Dynamic Time Ago Row
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFF20C8FF).withAlpha(51),
                child: Text(
                  article.source.isNotEmpty ? article.source[0].toUpperCase() : 'M',
                  style: const TextStyle(
                    color: Color(0xFF20C8FF),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.source,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      article.dynamicTimeAgo,
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black45,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const Divider(height: 28, color: Colors.white10),

          // Main Article Body with Inline Distributed Images
          ...widgets,

          const SizedBox(height: 24),

          // Source Link Button
          if (article.sourceUrl != null && article.sourceUrl!.trim().isNotEmpty)
            Center(
              child: OutlinedButton.icon(
                onPressed: () => _launchSourceUrl(article.sourceUrl),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text('Read Original Source on ${article.source}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF20C8FF),
                  side: const BorderSide(color: Color(0xFF20C8FF)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  List<Widget> _parseArticleBlocks(
    NewsArticle article,
    bool isDark,
    Color textColor,
    Color secondaryTextColor,
  ) {
    final List<Widget> widgets = [];
    final rawContent = article.content.trim().isNotEmpty ? article.content : article.summary;

    // Collect available images and captions from metadata
    final List<Map<String, String>> imagesMeta = [];
    for (final item in article.imagesData) {
      final url = item['imageUrl']?.toString() ?? '';
      final cap = item['caption']?.toString() ?? '';
      if (url.isNotEmpty) {
        imagesMeta.add({'url': url, 'caption': cap});
      }
    }
    if (imagesMeta.isEmpty) {
      for (final url in article.imageUrls) {
        if (url.isNotEmpty) {
          imagesMeta.add({'url': url, 'caption': article.title});
        }
      }
    }
    if (imagesMeta.isEmpty && article.coverImage != null && article.coverImage!.isNotEmpty) {
      imagesMeta.add({'url': article.coverImage!, 'caption': article.title});
    }

    int fallbackImageIdx = 0;

    // Check if rawContent contains markdown image tags ![caption](url)
    final imgRegex = RegExp(r'!\[(.*?)\]\((.*?)\)');
    final lines = rawContent.split('\n');

    final List<String> currentParagraphLines = [];

    void flushParagraph() {
      if (currentParagraphLines.isEmpty) return;
      final text = currentParagraphLines.join(' ').trim();
      currentParagraphLines.clear();
      if (text.isEmpty) return;

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Text(
            text,
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 16,
              height: 1.65,
            ),
          ),
        ),
      );

      // If markdown didn't have embedded images, interleave fallback images every 2 paragraphs
      if (!rawContent.contains('![') && fallbackImageIdx < imagesMeta.length) {
        final img = imagesMeta[fallbackImageIdx++];
        widgets.add(_buildInlineImage(img['url']!, img['caption'] ?? '', isDark, textColor));
      }
    }

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) {
        flushParagraph();
        continue;
      }

      // Check Markdown Image ![caption](url)
      final match = imgRegex.firstMatch(line);
      if (match != null) {
        flushParagraph();
        final caption = match.group(1) ?? '';
        final url = match.group(2) ?? '';
        if (url.isNotEmpty) {
          widgets.add(_buildInlineImage(url, caption, isDark, textColor));
        }
        continue;
      }

      // Check italic caption line following an image: *caption*
      if (line.startsWith('*') && line.endsWith('*') && line.length > 2) {
        continue;
      }

      // Check Headings: #, ##, ###
      if (line.startsWith('#')) {
        flushParagraph();
        final headingText = line.replaceAll(RegExp(r'^#+\s*'), '').trim();
        if (headingText.toLowerCase() == article.title.toLowerCase()) continue;

        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 14.0, bottom: 10.0),
            child: Text(
              headingText,
              style: TextStyle(
                color: const Color(0xFF20C8FF),
                fontSize: line.startsWith('###') ? 17 : (line.startsWith('##') ? 19 : 21),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
        continue;
      }

      currentParagraphLines.add(line);
    }

    flushParagraph();

    return widgets;
  }

  Widget _buildInlineImage(String url, String caption, bool isDark, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CachedNetworkImage(
              imageUrl: url,
              width: double.infinity,
              height: 220,
              fit: BoxFit.cover,
              placeholder: (context, _) => const Skeleton(height: 220, borderRadius: 16),
              errorWidget: (context, url, error) => Container(
                height: 200,
                color: Colors.grey.shade900,
                child: const Center(
                  child: Icon(Icons.image_not_supported_rounded, color: Colors.white38, size: 36),
                ),
              ),
            ),
          ),
          if (caption.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.photo_camera_outlined, size: 14, color: Color(0xFF20C8FF)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      caption.trim(),
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontSize: 12.5,
                        fontStyle: FontStyle.italic,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
