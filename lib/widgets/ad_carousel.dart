import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/interstitial_ad_service.dart';

class AdCarousel extends StatefulWidget {
  final List<Map<String, dynamic>>? ads;
  final Duration interval;
  final double height;

  const AdCarousel({
    super.key,
    this.ads,
    this.interval = const Duration(seconds: 10),
    this.height = 180,
  });

  @override
  State<AdCarousel> createState() => _AdCarouselState();
}

class _AdCarouselState extends State<AdCarousel> with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  int _currentIndex = 0;
  late AnimationController _cometController;
  VideoPlayerController? _videoController;
  Timer? _timer;

  late List<Map<String, dynamic>> _ads;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _setupAds();
    InterstitialAdService().addListener(_onAdServiceChanged);

    _cometController = AnimationController(
      vsync: this,
      duration: widget.interval,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _nextAd();
          _cometController.forward(from: 0.0);
        }
      });
    _cometController.forward();
    _initVideo();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _preCacheAll();
    });
  }

  void _onAdServiceChanged() {
    if (!mounted) return;
    if (widget.ads == null) {
      setState(() {
        _setupAds();
        _currentIndex = 0;
        if (_pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
        _initVideo();
        _preCacheAll();
      });
    }
  }

  @override
  void didUpdateWidget(AdCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool changed = false;
    final oldAds = oldWidget.ads;
    final newAds = widget.ads;
    if (oldAds == null && newAds != null) {
      changed = true;
    } else if (oldAds != null && newAds == null) {
      changed = true;
    } else if (oldAds != null && newAds != null) {
      if (oldAds.length != newAds.length) {
        changed = true;
      } else {
        for (int i = 0; i < oldAds.length; i++) {
          if (oldAds[i]['id'] != newAds[i]['id'] ||
              oldAds[i]['url'] != newAds[i]['url'] ||
              oldAds[i]['title'] != newAds[i]['title'] ||
              oldAds[i]['isActive'] != newAds[i]['isActive']) {
            changed = true;
            break;
          }
        }
      }
    }

    if (changed || widget.interval != oldWidget.interval) {
      setState(() {
        _setupAds();
        _cometController.duration = widget.interval;
        _cometController.forward(from: 0.0);
        _currentIndex = 0;
        if (_pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
        _initVideo();
        _preCacheAll();
      });
    }
  }

  void _setupAds() {
    if (widget.ads != null && widget.ads!.isNotEmpty) {
      _ads = List<Map<String, dynamic>>.from(widget.ads!);
      return;
    }

    final pool = InterstitialAdService().activeCarouselAds;
    if (pool.isNotEmpty) {
      _ads = List<Map<String, dynamic>>.from(pool);
      return;
    }

    _ads = [];
  }

  void _preCacheAll() async {
    for (var ad in _ads) {
      final url = (ad['url'] as String?) ?? (ad['imageUrl'] as String?) ?? '';
      if (url.isEmpty) continue;
      if (ad['type'] == 'image') {
        if (ad['isAsset'] == true) {
          precacheImage(AssetImage(url), context);
        } else if (url.startsWith('http')) {
          precacheImage(CachedNetworkImageProvider(url), context);
        }
      } else if (ad['type'] == 'video') {
        if (url.startsWith('http')) {
          unawaited(() async {
            try {
              await DefaultCacheManager().downloadFile(url, key: url);
            } catch (_) {}
          }());
        }
      }
    }
  }

  void _initVideo() async {
    if (_ads.isEmpty) return;
    final ad = _ads[_currentIndex % _ads.length];
    final String url = (ad['url'] as String?) ?? (ad['imageUrl'] as String?) ?? '';
    if (ad['type'] == 'video' && url.isNotEmpty) {
      _videoController?.dispose();
      _videoController = null;

      try {
        final fileInfo = await DefaultCacheManager().getFileFromCache(url);
        if (fileInfo != null) {
          _videoController = VideoPlayerController.file(fileInfo.file);
        } else if (url.startsWith('http')) {
          _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
          unawaited(() async {
            try {
              await DefaultCacheManager().downloadFile(url, key: url);
            } catch (_) {}
          }());
        } else {
          _videoController = VideoPlayerController.asset(url);
        }

        await _videoController!.initialize();
        if (mounted) {
          setState(() {});
          _videoController?.play();
          _videoController?.setLooping(true);
          _videoController?.setVolume(0);
        }
      } catch (e) {
        debugPrint('AdCarousel: [VIDEO_ERROR] Failed to load carousel video ad: $e');
        if (mounted) {
          setState(() {
            _videoController = null;
          });
        }
      }
    } else {
      _videoController?.dispose();
      _videoController = null;
    }
  }

  void _nextAd() {
    if (mounted && _pageController.hasClients) {
      _currentIndex = (_currentIndex + 1) % _ads.length;
      _pageController.animateToPage(
        _currentIndex,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _launchContactUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    InterstitialAdService().removeListener(_onAdServiceChanged);
    _pageController.dispose();
    _cometController.dispose();
    _videoController?.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ads.isEmpty) {
      return const SizedBox.shrink();
    }

    return CustomPaint(
      painter: CometPainter(
        progress: _cometController.value,
        color: _ads[_currentIndex]['color'] as Color,
      ),
      child: Container(
        width: double.infinity,
        height: widget.height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
        ),
        child: PageView.builder(
          controller: _pageController,
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index % _ads.length;
              _initVideo();
              _cometController.forward(from: 0.0);
            });
          },
          itemBuilder: (context, index) {
            final ad = _ads[index % _ads.length];
            final dynamic rawColor = ad['color'] ?? ad['colorValue'];
            final Color color = rawColor is Color
                ? rawColor
                : (rawColor is int ? Color(rawColor) : const Color(0xFF20C8FF));
            final String mediaUrl = (ad['url'] as String?) ?? (ad['imageUrl'] as String?) ?? '';

            final isCompact = widget.height < 140;

            return Stack(
              children: [
                // Dark background base layer for letterboxing / pillarboxing
                const Positioned.fill(
                  child: ColoredBox(color: Color(0xFF0A0A18)),
                ),
                if (ad['type'] == 'video' && 
                    _currentIndex == (index % _ads.length) &&
                    _videoController != null && 
                    _videoController!.value.isInitialized)
                  Positioned.fill(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: _videoController!.value.size.width,
                          height: _videoController!.value.size.height,
                          child: VideoPlayer(_videoController!),
                        ),
                      ),
                    ),
                  )
                else if (ad['type'] == 'image')
                  Positioned.fill(
                    child: Center(
                      child: ad['isAsset'] == true 
                        ? Image.asset(
                            mediaUrl,
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                          )
                        : CachedNetworkImage(
                          imageUrl: mediaUrl,
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          placeholder: (context, url) => Container(
                            color: Colors.white10,
                            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.black26,
                            child: const Icon(Icons.broken_image, color: Colors.white24, size: 50),
                          ),
                        ),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          color.withValues(alpha: 0.15),
                          color.withValues(alpha: 0.05),
                        ],
                      ),
                    ),
                  ),

                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.7),
                        Colors.transparent,
                      ],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                  ),
                ),

                Padding(
                  padding: isCompact ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8) : const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: isCompact 
                                ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2) 
                                : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              (ad['title'] as String).toUpperCase(),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isCompact ? 9 : 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Icon(Icons.trending_up, color: Colors.white24, size: isCompact ? 16 : 20),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              ad['subtitle']!,
                              maxLines: isCompact ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isCompact ? 13 : 18,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black45,
                                    offset: Offset(0, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (ad['contactUrl'] != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: ElevatedButton(
                                onPressed: () => _launchContactUrl(ad['contactUrl']),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: isCompact
                                      ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                                      : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    FaIcon(FontAwesomeIcons.whatsapp, size: isCompact ? 12 : 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Contact Us',
                                      style: TextStyle(
                                        fontSize: isCompact ? 11 : 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class CometPainter extends CustomPainter {
  final double progress;
  final Color color;

  CometPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final RRect rrect = RRect.fromRectAndRadius(rect, const Radius.circular(20));
    
    final paint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawRRect(rrect, paint);

    final path = Path()..addRRect(rrect);
    final pathMetrics = path.computeMetrics();
    final metric = pathMetrics.first;

    final double extractStart = metric.length * progress;
    final double cometLength = metric.length * 0.15;
    
    final cometPath = Path();
    
    if (extractStart + cometLength <= metric.length) {
      cometPath.addPath(
        metric.extractPath(extractStart, extractStart + cometLength),
        Offset.zero,
      );
    } else {
      cometPath.addPath(
        metric.extractPath(extractStart, metric.length),
        Offset.zero,
      );
      cometPath.addPath(
        metric.extractPath(0, cometLength - (metric.length - extractStart)),
        Offset.zero,
      );
    }

    final cometPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0),
          color,
        ],
        stops: const [0.7, 1.0],
        transform: GradientRotation(2 * 3.14159 * progress - 0.5),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(cometPath, cometPaint..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawPath(cometPath, cometPaint..maskFilter = null);
  }

  @override
  bool shouldRepaint(covariant CometPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
