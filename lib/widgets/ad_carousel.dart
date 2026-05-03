import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

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

  @override
  void didUpdateWidget(AdCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ads != oldWidget.ads) {
      _setupAds();
      _cometController.duration = widget.interval;
      _cometController.forward(from: 0.0);
      _currentIndex = 0;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      _initVideo();
    }
  }

  void _setupAds() {
    _ads = widget.ads ?? [
      {
        'type': 'image',
        'isAsset': true,
        'title': 'Davy Cybers 💻',
        'subtitle': 'In need of professional cyber services? Worry no more, Davy Cybers we have got you.',
        'url': 'assets/ad_cyber.jpeg',
        'color': const Color(0xFF20C8FF),
      },
      {
        'type': 'image',
        'isAsset': true,
        'title': 'Manu Data 🌐',
        'subtitle': 'Tired of expensive data plans? Worry no more, Manu Data Solutions we have got you.',
        'url': 'assets/ad_data.jpeg',
        'color': const Color(0xFF00A85A),
      },
      {
        'type': 'image',
        'isAsset': true,
        'title': 'Snake Light 💡',
        'subtitle': 'In need of snake light? Say less, we got you with a discount.',
        'url': 'assets/ad_snake.jpeg',
        'color': const Color(0xFFFF8A00),
      },
      {
        'type': 'image',
        'title': 'Trending Now 🚀',
        'subtitle': 'End of Semester CATs are here! 📚 Get your revision materials now.',
        'url': 'https://images.unsplash.com/photo-1434030216411-0b793f4b4173?w=800',
        'color': const Color(0xFF7B5CFF),
      },
    ];
  }

  void _preCacheAll() async {
    for (var ad in _ads) {
      if (ad['type'] == 'image') {
        if (ad['isAsset'] == true) {
          precacheImage(AssetImage(ad['url']), context);
        } else {
          precacheImage(CachedNetworkImageProvider(ad['url']), context);
        }
      } else if (ad['type'] == 'video') {
        DefaultCacheManager().downloadFile(ad['url'], key: ad['url']);
      }
    }
  }

  void _initVideo() async {
    final ad = _ads[_currentIndex];
    if (ad['type'] == 'video') {
      _videoController?.dispose();
      
      // Try to get from cache first
      final fileInfo = await DefaultCacheManager().getFileFromCache(ad['url']);
      if (fileInfo != null) {
        _videoController = VideoPlayerController.file(fileInfo.file);
      } else {
        _videoController = VideoPlayerController.networkUrl(Uri.parse(ad['url']));
      }

      _videoController!.initialize().then((_) {
          if (mounted) {
            setState(() {});
            _videoController?.play();
            _videoController?.setLooping(true);
            _videoController?.setVolume(0);
          }
        });
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

  @override
  void dispose() {
    _pageController.dispose();
    _cometController.dispose();
    _videoController?.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            final color = ad['color'] as Color;

            return Stack(
              children: [
                if (ad['type'] == 'video' && 
                    _currentIndex == (index % _ads.length) &&
                    _videoController != null && 
                    _videoController!.value.isInitialized)
                  SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _videoController!.value.size.width,
                        height: _videoController!.value.size.height,
                        child: VideoPlayer(_videoController!),
                      ),
                    ),
                  )
                else if (ad['type'] == 'image')
                  SizedBox.expand(
                    child: ad['isAsset'] == true 
                      ? Image.asset(ad['url'], fit: BoxFit.cover)
                      : CachedNetworkImage(
                        imageUrl: ad['url'],
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: Colors.white10,
                          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.black26,
                          child: const Icon(Icons.broken_image, color: Colors.white24, size: 50),
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
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              (ad['title'] as String).toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.trending_up, color: Colors.white24, size: 20),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        ad['subtitle']!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(
                              color: Colors.black45,
                              offset: Offset(0, 2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
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
