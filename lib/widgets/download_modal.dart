import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../screens/subscription_screen.dart';
import '../providers/upload_provider.dart';
import '../providers/service_providers.dart';

enum AccessActionType { download, read }

class DownloadModal extends ConsumerWidget {
  final String resourceTitle;
  final AccessActionType actionType;

  const DownloadModal({
    super.key,
    required this.resourceTitle,
    this.actionType = AccessActionType.download,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // We listen to the provider to handle external state changes (like ad rewards)
    // but we handle the subscription return flow explicitly in the button handler.
    ref.listen(subscriptionServiceProvider, (previous, next) {
      final bool isUnlocked = next.isResourceUnlocked(resourceTitle);
      // Only auto-pop if unlocked via ad (since that happens while modal is "active")
      // Subscription pops are handled by the 'await' in the button handler below.
      if (isUnlocked) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context, true);
        }
      }
    });

    final String actionText = actionType == AccessActionType.download ? 'downloading' : 'accessing';
    final String message = 'Subscribe to packages and enjoy $actionText materials without watching ads.';

    return PopScope(
      canPop: false,
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 30),
            decoration: BoxDecoration(
              color: const Color(0xFF181739),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white12, width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 24),
                      const Text(
                        'MIRROR LAIKIPIA',
                        style: TextStyle(
                          color: Color(0xFF7B5CFF),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white54),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),

                const Divider(color: Colors.white10),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    children: [
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Package Preview List
                      _packageItem('Daily Pass', 'Ksh.5/='),
                      _packageItem('Weekly Pass', 'Ksh.30/='),
                      _packageItem('Monthly Pass', 'Ksh.100/='),
                      
                      const SizedBox(height: 30),

                      // Buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                await ref.read(subscriptionServiceProvider).showRewardedAd(
                                  onRewardEarned: () {
                                    ref.read(subscriptionServiceProvider).unlockResource(resourceTitle);
                                    // The ref.listen above will handle popping the modal
                                  },
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7B5CFF),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Watch Ad',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                // Wait for user to come back from Subscription Screen
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const SubscriptionScreen()),
                                );
                                
                                // Once we are back, check if they successfully subscribed
                                if (context.mounted) {
                                  final subService = ref.read(subscriptionServiceProvider);
                                  if (subService.isSubscribed) {
                                    // Pop the modal with true to trigger auto-resume in the caller
                                    if (Navigator.canPop(context)) {
                                      Navigator.pop(context, true);
                                    }
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00A85A),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Subscribe',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _packageItem(String title, String price) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10, width: 0.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            price,
            style: const TextStyle(
              color: Color(0xFF20C8FF),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
