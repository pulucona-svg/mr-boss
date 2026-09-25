import 'dart:math';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Full-screen offline manual interstitial ad dialog.
/// Displays bundled offline asset ads (e.g. Davy Cybers, Manu Data, Snake Light)
/// when the user is offline or when Google Mobile Ads is unavailable.
class ManualInterstitialAdDialog extends StatefulWidget {
  final VoidCallback onDismissed;
  final Map<String, dynamic>? adData;

  const ManualInterstitialAdDialog({
    super.key,
    required this.onDismissed,
    this.adData,
  });

  /// Offline/manual ads bundled with local image assets for zero-network reliability.
  static const List<Map<String, dynamic>> defaultOfflineAds = [
    {
      'title': 'Davy Cybers 💻',
      'subtitle': 'In need of professional cyber services? Worry no more, Davy Cybers we have got you covered.',
      'url': 'assets/ad_cyber.jpeg',
      'color': Color(0xFF20C8FF),
      'contactUrl': 'https://wa.me/254108462492',
    },
    {
      'title': 'Manu Data 🌐',
      'subtitle': 'Tired of expensive data plans? Worry no more, Manu Data Solutions we have got you covered.',
      'url': 'assets/ad_data.jpeg',
      'color': Color(0xFF00A85A),
      'contactUrl': 'https://wa.me/254108462492',
    },
    {
      'title': 'Snake Light 💡',
      'subtitle': 'In need of snake light? Say less, we got you with an exclusive student discount.',
      'url': 'assets/ad_snake.jpeg',
      'color': Color(0xFFFF8A00),
      'contactUrl': 'https://wa.me/254108462492',
    },
  ];

  @override
  State<ManualInterstitialAdDialog> createState() => _ManualInterstitialAdDialogState();
}

class _ManualInterstitialAdDialogState extends State<ManualInterstitialAdDialog> {
  late final Map<String, dynamic> _ad;
  bool _isDismissed = false;

  @override
  void initState() {
    super.initState();
    if (widget.adData != null) {
      _ad = widget.adData!;
    } else {
      final rand = Random();
      _ad = ManualInterstitialAdDialog.defaultOfflineAds[
          rand.nextInt(ManualInterstitialAdDialog.defaultOfflineAds.length)];
    }
  }

  void _dismiss() {
    if (_isDismissed) return;
    _isDismissed = true;
    widget.onDismissed();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _launchContact(String? urlStr) async {
    if (urlStr == null || urlStr.trim().isEmpty) return;
    final uri = Uri.tryParse(urlStr.trim());
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = _ad['color'] as Color? ?? const Color(0xFF20C8FF);
    final title = _ad['title'] as String? ?? 'Sponsored';
    final subtitle = _ad['subtitle'] as String? ?? '';
    final imageUrl = _ad['url'] as String? ?? 'assets/ad_cyber.jpeg';
    final contactUrl = _ad['contactUrl'] as String?;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && !_isDismissed) {
          _isDismissed = true;
          widget.onDismissed();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF070716),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Header Row with Badge & Dismiss Icon
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.campaign_outlined, size: 14, color: Colors.white70),
                          SizedBox(width: 5),
                          Text(
                            'SPONSORED',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                        child: const Icon(Icons.close_rounded, size: 18, color: Colors.white),
                      ),
                      onPressed: _dismiss,
                      tooltip: 'Close Ad',
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Main Ad Content
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Ad Image Card
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(maxHeight: 340),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                            boxShadow: [
                              BoxShadow(
                                color: themeColor.withValues(alpha: 0.2),
                                blurRadius: 24,
                                spreadRadius: 2,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.asset(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              height: 200,
                              color: Colors.white10,
                              child: const Center(
                                child: Icon(Icons.broken_image_rounded, color: Colors.white38, size: 48),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Title
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Subtitle
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 15,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Bottom Call to Action Buttons
                if (contactUrl != null) ...[
                  ElevatedButton(
                    onPressed: () {
                      _launchContact(contactUrl);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A85A), // WhatsApp Green
                      foregroundColor: Colors.white,
                      elevation: 4,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FaIcon(FontAwesomeIcons.whatsapp, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Contact via WhatsApp',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                TextButton(
                  onPressed: _dismiss,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white60,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Return to App',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
