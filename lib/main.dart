import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/dashboard_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/placeholder_screen.dart';
import 'screens/library_screen.dart';
import 'widgets/draggable_fab.dart';

import 'services/connectivity_service.dart';
import 'services/course_service.dart';
import 'services/resource_service.dart';
import 'providers/upload_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final courseService = CourseService();
  await courseService.init();

  runApp(
    ProviderScope(
      overrides: [
        courseServiceProvider.overrideWithValue(courseService),
      ],
      child: const MirrorApp(),
    ),
  );
}

class MirrorApp extends StatelessWidget {
  const MirrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mirror Laikipia',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: ConnectivityService().messengerKey,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF20C8FF),
        scaffoldBackgroundColor: const Color(0xFF070716),
        useMaterial3: true,
      ),
      home: const MainNavigation(),
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
    const PlaceholderScreen(title: 'Explore'),
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
    return Scaffold(
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
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
          backgroundColor: const Color(0xFF070716),
          selectedItemColor: const Color(0xFF20C8FF),
          unselectedItemColor: Colors.white38,
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
