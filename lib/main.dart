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
import 'services/top_notification_service.dart';

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'services/subscription_service.dart';
import 'services/usage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Start heavy initialization in background without blocking runApp
  _initServices();

  runApp(
    const ProviderScope(
      child: MirrorApp(),
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
    debugPrint('All services initialized successfully');
  } catch (e) {
    debugPrint('Error during service initialization: $e');
  }
}

class MirrorApp extends ConsumerStatefulWidget {
  const MirrorApp({super.key});

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
      initialRoute: '/',
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
  int _selectedIndex = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
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
        // Clear the flags so they don't trigger again on rebuilds within this route
        if (args != null) args['isFirstLogin'] = false;
        TopNotificationService.pendingWelcome = false;
        
        // Slight delay to ensure screen is visible and stable
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) {
            TopNotificationService().showNotification(context, 'Welcome back to Mirror Laikipia');
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
    setState(() {
      _selectedIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF070716) : Colors.white,
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black12, width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
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
