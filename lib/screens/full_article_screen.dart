import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/article_viewer_model.dart';
import '../models/explore_models.dart';

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
  bool _isLoading = true;
  String? _errorMessage;
  ArticleViewerDocument? _viewerDoc;

  @override
  void initState() {
    super.initState();
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));
    _fetchViewerDocument();
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

    if (url == null || url.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = null; // Fallback to NewsArticle metadata if available
      });
      return;
    }

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
          // If network download fails, fallback to rendering existing article metadata gracefully
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _launchSourceUrl(String? urlStr) async {
    if (urlStr == null || urlStr.isEmpty) return;
    final Uri? uri = Uri.tryParse(urlStr);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF070716) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black87;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.share_outlined, color: textColor, size: 22),
            onPressed: () {},
          ),
        ],
      ),
      body: _buildBody(context, isDark, textColor, secondaryTextColor),
    );
  }

  Widget _buildBody(
      BuildContext context, bool isDark, Color textColor, Color secondaryTextColor) {
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
              'Loading full article...',
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // Render from downloaded ArticleViewerDocument if present
    if (_viewerDoc != null) {
      return _buildViewerDocumentContent(
          context, _viewerDoc!, isDark, textColor, secondaryTextColor);
    }

    // Fallback: Render from NewsArticle metadata if viewer JSON failed or is unavailable
    if (widget.article != null) {
      return _buildFallbackArticleContent(
          context, widget.article!, isDark, textColor, secondaryTextColor);
    }

    // Network / Missing document error screen with Retry button
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article_outlined,
                size: 64, color: isDark ? Colors.white24 : Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Unable to Load Article Viewer',
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'The article document is unavailable or removed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchViewerDocument,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF20C8FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewerDocumentContent(
      BuildContext context,
      ArticleViewerDocument doc,
      bool isDark,
      Color textColor,
      Color secondaryTextColor) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category & Reading Time Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF20C8FF).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF20C8FF).withOpacity(0.4),
                  ),
                ),
                child: Text(
                  doc.category.toUpperCase(),
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
                    Icon(Icons.access_time_rounded,
                        size: 13, color: isDark ? Colors.white70 : Colors.black54),
                    const SizedBox(width: 4),
                    Text(
                      '${doc.readingTime} min read',
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

          const SizedBox(height: 16),

          // Article Title
          Text(
            doc.title,
            style: TextStyle(
              color: textColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              height: 1.35,
            ),
          ),

          const SizedBox(height: 12),

          // Author & Publication Info Row
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFF20C8FF).withOpacity(0.2),
                child: Text(
                  doc.source.isNotEmpty ? doc.source[0].toUpperCase() : 'N',
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
                      doc.author != null && doc.author!.isNotEmpty
                          ? doc.author!
                          : doc.source,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (doc.publishedAt != null)
                      Text(
                        doc.publishedAt!,
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black45,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          const Divider(height: 32, color: Colors.white10),

          // Main Interspaced Content Blocks
          if (doc.content.isNotEmpty) ...[
            ...doc.content.map((block) => _buildContentBlock(
                block, isDark, textColor, secondaryTextColor)),
          ] else if (doc.paragraphs.isNotEmpty) ...[
            ...doc.paragraphs.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    p,
                    style: TextStyle(
                      color: secondaryTextColor,
                      fontSize: 15,
                      height: 1.6,
                    ),
                  ),
                )),
          ] else if (doc.fullStory != null) ...[
            Text(
              doc.fullStory!,
              style: TextStyle(
                color: secondaryTextColor,
                fontSize: 15,
                height: 1.6,
              ),
            ),
          ],

          // Structured Sections
          if (doc.sections.isNotEmpty) ...[
            const SizedBox(height: 24),
            ...doc.sections.map((section) => _buildSection(
                section, isDark, textColor, secondaryTextColor)),
          ],

          const SizedBox(height: 32),

          // Original Source Action Button
          if (doc.originalSourceUrl != null && doc.originalSourceUrl!.isNotEmpty)
            Center(
              child: OutlinedButton.icon(
                onPressed: () => _launchSourceUrl(doc.originalSourceUrl),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text('Read Original on ${doc.source}'),
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

  Widget _buildContentBlock(
      ContentBlock block, bool isDark, Color textColor, Color secondaryTextColor) {
    if (block.type == 'paragraph' && block.text != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: Text(
          block.text!,
          style: TextStyle(
            color: secondaryTextColor,
            fontSize: 15,
            height: 1.65,
          ),
        ),
      );
    }

    if (block.type == 'image' && block.url != null && block.url!.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8.0, bottom: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: block.url!,
                fit: BoxFit.cover,
                width: double.infinity,
                placeholder: (context, url) => Container(
                  height: 200,
                  color: isDark ? const Color(0xFF181739) : Colors.grey.shade200,
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF20C8FF)),
                    ),
                  ),
                ),
                errorWidget: (context, url, err) => const SizedBox.shrink(),
              ),
            ),
            if (block.caption != null && block.caption!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6.0, left: 4.0),
                child: Text(
                  block.caption!,
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black45,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    if (block.type == 'heading' && block.text != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 20.0, bottom: 12.0),
        child: Text(
          block.text!,
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildSection(ViewerSection section, bool isDark, Color textColor,
      Color secondaryTextColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF12122A) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.heading.isNotEmpty)
            Text(
              section.heading,
              style: const TextStyle(
                color: Color(0xFF20C8FF),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          if (section.heading.isNotEmpty) const SizedBox(height: 10),
          ...section.paragraphs.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                p,
                style: TextStyle(
                  color: secondaryTextColor,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackArticleContent(BuildContext context, NewsArticle article,
      bool isDark, Color textColor, Color secondaryTextColor) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            article.category,
            style: const TextStyle(
              color: Color(0xFF20C8FF),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            article.title,
            style: TextStyle(
              color: textColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (article.coverImage != null || article.imageUrls.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: article.coverImage ?? article.imageUrls.first,
                width: double.infinity,
                height: 220,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(height: 20),
          Text(
            article.content,
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 15,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
