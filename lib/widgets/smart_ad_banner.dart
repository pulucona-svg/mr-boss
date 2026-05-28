import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/subscription_service.dart';
import '../services/connectivity_service.dart';
import 'ad_carousel.dart';

class SmartAdBanner extends StatefulWidget {
  const SmartAdBanner({super.key});

  @override
  State<SmartAdBanner> createState() => _SmartAdBannerState();
}

class _SmartAdBannerState extends State<SmartAdBanner> {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
  }

  void _loadBannerAd() {
    // Only load AdMob if online and NOT subscribed
    if (!ConnectivityService().isOffline && !SubscriptionService().isSubscribed) {
      _bannerAd = BannerAd(
        adUnitId: 'ca-app-pub-3940256099942544/6300978111', // Test ID
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            setState(() {
              _isAdLoaded = true;
            });
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
            _isAdLoaded = false;
          },
        ),
      )..load();
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([SubscriptionService(), ConnectivityService()]),
      builder: (context, child) {
        final isSubscribed = SubscriptionService().isSubscribed;
        final isOffline = ConnectivityService().isOffline;

        // Requirement:
        // Offline -> Manual asset ads
        // Online + no package -> AdMob banner ads
        // Active package -> Manual asset ads (REVERTED TO ASSET ADS)

        // 1. If Online and NOT subscribed, try AdMob
        if (!isOffline && !isSubscribed) {
          if (_isAdLoaded && _bannerAd != null) {
            return Container(
              alignment: Alignment.center,
              width: double.infinity,
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            );
          }
          // Fallback to manual ads while loading or if AdMob fails
          return const AdCarousel();
        }

        // 2. If Offline OR Active Package, show ONLY manual asset ads
        return const AdCarousel();
      },
    );
  }
}
