import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/subscription_service.dart';
import '../services/connectivity_service.dart';

class InlineAdBanner extends StatefulWidget {
  const InlineAdBanner({super.key});

  @override
  State<InlineAdBanner> createState() => _InlineAdBannerState();
}

class _InlineAdBannerState extends State<InlineAdBanner> {
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
            if (mounted) {
              setState(() {
                _isAdLoaded = true;
              });
            }
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
            if (mounted) {
              setState(() {
                _isAdLoaded = false;
              });
            }
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

        if (isOffline || isSubscribed || !_isAdLoaded || _bannerAd == null) {
          return const SizedBox.shrink();
        }

        return Container(
          alignment: Alignment.center,
          width: double.infinity,
          height: _bannerAd!.size.height.toDouble(),
          margin: const EdgeInsets.symmetric(vertical: 12),
          child: AdWidget(ad: _bannerAd!),
        );
      },
    );
  }
}
