import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/subscription_service.dart';
import '../services/connectivity_service.dart';
import 'ad_carousel.dart';

class SmartAdBanner extends StatefulWidget {
  final double fallbackHeight;
  final ValueChanged<Size>? onSizeChanged;

  const SmartAdBanner({
    super.key,
    this.fallbackHeight = 100,
    this.onSizeChanged,
  });

  @override
  State<SmartAdBanner> createState() => _SmartAdBannerState();
}

class _SmartAdBannerState extends State<SmartAdBanner> {
  BannerAd? _bannerAd;
  AdSize? _loadedAdSize;
  bool _isAdLoaded = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadBannerAd();
      }
    });
  }

  Future<void> _loadBannerAd() async {
    if (_isLoading) return;
    if (ConnectivityService().isOffline || SubscriptionService().isSubscribed) {
      if (mounted) {
        widget.onSizeChanged?.call(Size(double.infinity, widget.fallbackHeight));
      }
      return;
    }

    _isLoading = true;
    final double widthDouble = context.size?.width ?? (MediaQuery.maybeOf(context)?.size.width ?? 360.0);
    final int width = widthDouble.truncate().clamp(1, 10000);

    AdSize? adaptiveSize;
    try {
      adaptiveSize = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
    } catch (e) {
      debugPrint('SmartAdBanner: [DEBUG] Failed to get adaptive banner size: $e');
    }
    if (!mounted) return;
    final adSize = adaptiveSize ?? AdSize.banner;

    try {
      _bannerAd = BannerAd(
        adUnitId: 'ca-app-pub-3940256099942544/6300978111', // Test ID
        size: adSize,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (mounted) {
              final loadedBanner = ad as BannerAd;
              final size = Size(
                loadedBanner.size.width.toDouble(),
                loadedBanner.size.height.toDouble(),
              );
              setState(() {
                _loadedAdSize = loadedBanner.size;
                _isAdLoaded = true;
                _isLoading = false;
              });
              widget.onSizeChanged?.call(size);
            }
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
            if (mounted) {
              setState(() {
                _isAdLoaded = false;
                _bannerAd = null;
                _isLoading = false;
              });
              widget.onSizeChanged?.call(Size(widthDouble, widget.fallbackHeight));
            }
          },
        ),
      );
      await _bannerAd!.load();
    } catch (e) {
      debugPrint('SmartAdBanner: [DEBUG] Failed to load AdMob banner: $e');
      if (mounted) {
        setState(() {
          _isAdLoaded = false;
          _isLoading = false;
        });
        widget.onSizeChanged?.call(Size(widthDouble, widget.fallbackHeight));
      }
    }
  }

  @override
  void dispose() {
    try {
      _bannerAd?.dispose().catchError((_) {});
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([SubscriptionService(), ConnectivityService()]),
      builder: (context, child) {
        final isSubscribed = SubscriptionService().isSubscribed;
        final isOffline = ConnectivityService().isOffline;

        if (isSubscribed) {
          return const SizedBox.shrink();
        }

        if (!isOffline && _isAdLoaded && _bannerAd != null && _loadedAdSize != null) {
          return Center(
            child: SizedBox(
              width: _loadedAdSize!.width.toDouble(),
              height: _loadedAdSize!.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
          );
        }

        return Center(
          child: AdCarousel(height: widget.fallbackHeight),
        );
      },
    );
  }
}
