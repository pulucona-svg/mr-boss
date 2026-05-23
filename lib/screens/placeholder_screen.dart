import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notification_service.dart';
import '../widgets/notification_modal.dart';
import '../widgets/skeleton.dart';
import '../providers/theme_provider.dart';
import '../providers/chat_provider.dart';
import 'help_support_screen.dart';

class PlaceholderScreen extends ConsumerStatefulWidget {
  const PlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  ConsumerState<PlaceholderScreen> createState() => _PlaceholderScreenState();
}

class _PlaceholderScreenState extends ConsumerState<PlaceholderScreen> {
  static final Set<String> _loadedTitles = {};
  late bool _isLoading;

  @override
  void initState() {
    super.initState();
    _isLoading = !_loadedTitles.contains(widget.title);
    if (_isLoading) {
      _simulateLoading();
    }
  }

  void _simulateLoading() async {
    await Future.delayed(const Duration(milliseconds: 1500));
    _loadedTitles.add(widget.title);
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showNotifications(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NotificationModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF070716) : Colors.white,
        body: const ExploreSkeleton(),
      );
    }

    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF140C37), Color(0xFF070716)],
                )
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.blue.shade50, Colors.white],
                ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Row(
                      children: [
                        ListenableBuilder(
                          listenable: ref.watch(chatServiceProvider),
                          builder: (context, child) {
                            final unreadMessages = ref.read(chatServiceProvider).unreadCount;
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                IconButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const HelpSupportScreen()),
                                    );
                                  },
                                  icon: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      const Icon(
                                        Icons.chat_bubble_rounded,
                                        color: Color(0xFF00B2FF),
                                        size: 28,
                                      ),
                                      const Positioned(
                                        top: 5,
                                        child: Icon(
                                          Icons.bolt_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (unreadMessages > 0)
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                      child: Text(
                                        unreadMessages > 9 ? '9+' : unreadMessages.toString(),
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                        ListenableBuilder(
                          listenable: NotificationService(),
                          builder: (context, child) {
                            final unreadCount = NotificationService().unreadCount;
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                IconButton(
                                  onPressed: () => _showNotifications(context),
                                  icon: const Text('🔔', style: TextStyle(fontSize: 24)),
                                ),
                                if (unreadCount > 0)
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                      child: Text(
                                        unreadCount > 9 ? '9+' : unreadCount.toString(),
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${widget.title} Coming Soon',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
