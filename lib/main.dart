import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/dashboard_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/placeholder_screen.dart';
import 'screens/library_screen.dart';
import 'screens/explore_screen.dart';
import 'screens/login_screen.dart';
import 'widgets/draggable_fab.dart';

import 'services/connectivity_service.dart';
import 'services/course_service.dart';
import 'services/resource_service.dart';
import 'providers/upload_provider.dart';
import 'providers/theme_provider.dart';
import 'services/download_service.dart';
import 'services/top_notification_service.dart';

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'services/persistence_service.dart';
import 'services/usage_service.dart';
import 'services/subscription_service.dart';
import 'providers/ui_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize persistence first as others might depend on it
  await PersistenceService().init();

  // Start heavy initialization in background without blocking runApp
  _initServices();

  final bool isLoggedIn = PersistenceService().getSessionUserId() != null;

  runApp(
    ProviderScope(
      child: MirrorApp(isLoggedIn: isLoggedIn),
    ),
  );
}

Future<void> _initServices() async {
  try {
    // Initialize in background to prevent splash screen freeze
    await Future.wait([
      MobileAds.instance.initialize(),
      CourseService().init(),
      SubscriptionService().init(),
      UsageService().init(),
    ]);
    
    // Run retention cleanup on launch
    DownloadService().performRetentionCleanup();
    
    debugPrint('All services initialized successfully');
  } catch (e) {
    debugPrint('Error during service initialization: $e');
  }
}
class MirrorApp extends ConsumerStatefulWidget {
  final bool isLoggedIn;
  const MirrorApp({super.key, required this.isLoggedIn});

  @override
  ConsumerState<MirrorApp> createState() => _MirrorAppState();
}

class _MirrorAppState extends ConsumerState<MirrorApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'Mirror Laikipia',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: ConnectivityService().messengerKey,
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF20C8FF),
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF20C8FF),
        scaffoldBackgroundColor: const Color(0xFF070716),
        useMaterial3: true,
      ),
      themeMode: themeMode,
      initialRoute: widget.isLoggedIn ? '/home' : '/',
      routes: {
        '/': (context) => const LoginScreen(),
        '/home': (context) => const MainNavigation(),
        '/login': (context) => const LoginScreen(),
      },
    );
  }
}

class MainNavigation extends ConsumerStatefulWidget {
  const MainNavigation({super.key});

  @override
  ConsumerState<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends ConsumerState<MainNavigation> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    final uiState = ref.read(uiStateProvider);
    _pageController = PageController(initialPage: uiState.mainNavigationIndex);
    ConnectivityService().initialize();

    // Synchronize resources with the course pool for accurate details
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final courseService = ref.read(courseServiceProvider);
      ResourceService().synchronizeWithPool(courseService);

      // Welcome messages trigger
      if (!mounted) return;
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      final bool isFirstLogin = (args != null && args['isFirstLogin'] == true) || TopNotificationService.pendingWelcome;

      if (isFirstLogin) {
        // Determine the customized welcome message based on navigation source
        String welcomeMessage = 'Welcome back to Mirror Laikipia';
        if (args != null) {
          if (args['source'] == 'signup') {
            welcomeMessage = 'Welcome to Mirror Laikipia — built to support your academic journey.';
          } else if (args['source'] == 'password_change') {
            welcomeMessage = 'Your account is now secure — enjoy learning with confidence.';
          }
        }

        // Clear the flags so they don't trigger again on rebuilds within this route
        if (args != null) {
          try {
            args['isFirstLogin'] = false;
          } catch (_) {
            // Arguments might be immutable
          }
        }
        TopNotificationService.pendingWelcome = false;

        // Slight delay to ensure screen is visible and stable
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) {
            TopNotificationService().showNotification(context, welcomeMessage);
            TopNotificationService().showNotification(context, 'Where should we start from today');
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    ConnectivityService().dispose();
    super.dispose();
  }

  final List<Widget> _screens = [
    const DashboardScreen(),
    const LibraryScreen(),
    const ExploreScreen(),
    const ProfileScreen(),
  ];

  void _onItemTapped(int index) {
    ref.read(uiStateProvider.notifier).setMainNavigationIndex(index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final uiState = ref.watch(uiStateProvider);
    final isDark = themeMode == ThemeMode.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF070716) : Colors.white,
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          ref.read(uiStateProvider.notifier).setMainNavigationIndex(index);
        },
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black12, width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: uiState.mainNavigationIndex,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
          backgroundColor: isDark ? const Color(0xFF070716) : Colors.white,
          selectedItemColor: const Color(0xFF20C8FF),
          unselectedItemColor: isDark ? Colors.white38 : Colors.black38,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_book_outlined),
              activeIcon: Icon(Icons.menu_book_rounded),
              label: 'Library',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.explore_outlined),
              activeIcon: Icon(Icons.explore_rounded),
              label: 'Explore',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

