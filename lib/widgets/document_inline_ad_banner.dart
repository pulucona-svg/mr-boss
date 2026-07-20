import 'package:flutter/material.dart';
import '../services/subscription_service.dart';
import 'smart_ad_banner.dart';

class DocumentInlineAdBanner extends StatefulWidget {
  final ValueChanged<double>? onHeightChanged;
  final double fallbackHeight;

  const DocumentInlineAdBanner({
    super.key,
    this.onHeightChanged,
    this.fallbackHeight = 100.0,
  });

  @override
  State<DocumentInlineAdBanner> createState() => _DocumentInlineAdBannerState();
}

class _DocumentInlineAdBannerState extends State<DocumentInlineAdBanner> {
  late double _bannerHeight;

  @override
  void initState() {
    super.initState();
    _bannerHeight = widget.fallbackHeight;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SubscriptionService(),
      builder: (context, child) {
        if (SubscriptionService().isSubscribed) {
          return const SizedBox.shrink();
        }

        return AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 2, bottom: 14),
            child: Center(
              child: SmartAdBanner(
                fallbackHeight: widget.fallbackHeight,
                onSizeChanged: (size) {
                  if (_bannerHeight != size.height) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _bannerHeight != size.height) {
                        setState(() {
                          _bannerHeight = size.height;
                        });
                        final totalBlockHeight = 16.0 + size.height;
                        widget.onHeightChanged?.call(totalBlockHeight);
                      }
                    });
                  }
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
