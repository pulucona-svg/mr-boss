import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

import 'screens/dashboard_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/library_screen.dart';
import 'screens/explore_screen.dart';
import 'screens/login_screen.dart';
import 'screens/academic_personalization_screen.dart';
import 'screens/email_verification_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/terms_and_conditions_screen.dart';
import 'screens/privacy_policy_screen.dart';

import 'services/connectivity_service.dart';
import 'services/course_service.dart';
import 'services/resource_service.dart';
import 'services/persistence_service.dart';
import 'services/subscription_service.dart';
import 'services/usage_service.dart';
import 'services/download_service.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'services/device_id_manager.dart';
import 'services/top_notification_service.dart';
import 'services/user_service.dart';
import 'services/offline_upload_queue_service.dart';
import 'services/interstitial_ad_service.dart';
import 'services/launch_ad_service.dart';
import 'services/app_open_ad_manager.dart';
import 'services/paystack_service.dart';
import 'services/notification_service.dart';
import 'services/manual_ad_view_tracker.dart';
import 'providers/providers.dart';

void main() async {
  final WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  try {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  } catch (_) {}

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await PersistenceService().init();

  try {
    await MobileAds.instance.initialize();
    AppOpenAdManager().markSdkInitialized();
    AppOpenAdManager().initialize();
    LaunchAdService().initialize();
  } catch (e) {
    debugPrint('Error initializing MobileAds or Ad services: $e');
  }

  _initServices();

  final bool isLoggedIn = PersistenceService().getSessionUserId() != null;
  if (isLoggedIn) {
    LaunchAdService().startParallelPreload();
  }

  runApp(
    ProviderScope(
      child: MirrorApp(isLoggedIn: isLoggedIn),
    ),
  );
}

Future<void> _initServices() async {
  try {
    ConnectivityService().initialize();
    await Future.wait([
      CourseService().init(),
      SubscriptionService().init(),
      UsageService().init(),
      OfflineUploadQueueService().initialize(),
      PaystackService().init(),
      NotificationService().init(),
      ManualAdViewTracker().initialize(),
    ]);

    InterstitialAdService().initialize();
    
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
  Widget _getInitialScreen() {
    if (!widget.isLoggedIn) {
      try {
        FlutterNativeSplash.remove();
      } catch (_) {}
      return const SignupScreen();
    }
    
    return const InitialSessionCheck();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'Mirror Digital',
      debugShowCheckedModeBanner: false,
      navigatorKey: InterstitialAdService.navigatorKey,
      scaffoldMessengerKey: ConnectivityService().messengerKey,
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF20C8FF),
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF20C8FF),
        scaffoldBackgroundColor: const Color(0xFF070716),
        useMaterial3: true,
      ),
      themeMode: themeMode,
      home: _getInitialScreen(),
      routes: {
        '/home': (context) => const MainNavigation(),
        '/login': (context) => const LoginScreen(),
        '/terms': (context) => const TermsAndConditionsScreen(),
        '/privacy': (context) => const PrivacyPolicyScreen(),
        '/personalization': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
          return AcademicPersonalizationScreen(
            email: args?['email'] ?? '',
            isOnboarding: args?['isOnboarding'] ?? false,
          );
        },
      },
    );
  }
}

class InitialSessionCheck extends ConsumerStatefulWidget {
  const InitialSessionCheck({super.key});

  @override
  ConsumerState<InitialSessionCheck> createState() => _InitialSessionCheckState();
}

class _InitialSessionCheckState extends ConsumerState<InitialSessionCheck> {
  late final DateTime _splashStartTime;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _splashStartTime = DateTime.now();
    // Use a post-frame callback to navigate immediately without blocking build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSession();
    });
  }

  Future<void> _proceedToHome() async {
    if (_isNavigating) {
      debugPrint('InitialSessionCheck: [GUARD] Already proceeding/navigating to home.');
      return;
    }
    _isNavigating = true;

    await LaunchAdService().handleAppLaunch(
      context: context,
      splashStartTime: _splashStartTime,
      onContinue: () {
        if (mounted) {
          debugPrint('InitialSessionCheck: [NAVIGATE] Navigating to /home');
          Navigator.pushReplacementNamed(context, '/home');
        }
      },
    );
  }

  void _checkSession() {
    final uid = PersistenceService().getSessionUserId();
    final localProfileJson = PersistenceService().getJson('user_profile');
    
    debugPrint('InitialSessionCheck: [DEBUG] session_user_id=$uid');
    
    if (uid != null) {
      if (localProfileJson != null) {
        final profile = UserProfile.fromJson(localProfileJson);
        debugPrint('InitialSessionCheck: [DEBUG] Local profile found. onboardingComplete=${profile.onboardingComplete}');
        
        if (profile.onboardingComplete) {
          debugPrint('InitialSessionCheck: [DEBUG] Proceeding to home via LaunchAdService...');
          _proceedToHome();
          return;
        }
      }
      
      // If we are here, it means we have a UID but either no local profile 
      // or onboarding is not complete. In this case, we might need a fetch,
      // but we should still handle it gracefully if offline.
      _performFullCheck(uid);
    } else {
      debugPrint('InitialSessionCheck: [DEBUG] No session found. Navigating to /login');
      try {
        FlutterNativeSplash.remove();
      } catch (_) {}
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> _performFullCheck(String uid) async {
    // This is the fallback path if local data is missing or incomplete
    try {
      final user = FirebaseAuth.instance.currentUser;
      await ref.read(userProfileProvider.notifier).fetchProfileFromFirestore(uid);
      final profile = ref.read(userProfileProvider);

      if (mounted) {
        if (profile.onboardingComplete) {
          _proceedToHome();
        } else {
          try {
            FlutterNativeSplash.remove();
          } catch (_) {}
          if (user != null && !user.emailVerified && user.providerData.any((p) => p.providerId == 'password')) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => EmailVerificationScreen(email: user.email ?? profile.email),
              ),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => AcademicPersonalizationScreen(
                  email: profile.email.isNotEmpty ? profile.email : (user?.email ?? ''),
                  isOnboarding: true,
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('InitialSessionCheck: [ERROR] Full check failed: $e');
      // If offline and check fails, we might be stuck, but if we have ANY profile data, 
      // let's try to let them in or show login
      try {
        FlutterNativeSplash.remove();
      } catch (_) {}
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Center(
            child: Image.asset(
              'assets/splash_logo.png',
              width: 160,
              height: 160,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const CircularProgressIndicator(color: Color(0xFF20C8FF)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: Image.asset(
              'assets/splash_branding.png',
              height: 38,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
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
  StreamSubscription<bool>? _sessionSubscription;
  late final String _deviceId;

  @override
  void initState() {
    super.initState();
    final uiState = ref.read(uiStateProvider);
    _pageController = PageController(initialPage: uiState.mainNavigationIndex);
    ConnectivityService().initialize();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _deviceId = await DeviceIdManager.getPersistentDeviceId();
      PersistenceService().setBool(LaunchAdService.kHasLaunchedAppKey, true);
      
      final userProfile = ref.read(userProfileProvider);
      final courseService = ref.read(courseServiceProvider);
      
      // Initialize ResourceService with real-time listeners
      ResourceService().initialize(userProfile.uid);
      ResourceService().synchronizeWithPool(courseService);

      // Start session monitoring
      _startSessionMonitoring();

      if (!mounted) return;
      final bool isFirstLogin = TopNotificationService.pendingWelcome;

      if (isFirstLogin) {
        TopNotificationService.pendingWelcome = false;
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) {
            TopNotificationService().showNotification(context, 'Welcome back to Mirror Laikipia');
            TopNotificationService().showNotification(context, 'Where should we start from today');
          }
        });
      }
    });
  }

  void _startSessionMonitoring() {
    final userProfile = ref.read(userProfileProvider);
    
    if (userProfile.uid.isNotEmpty) {
      debugPrint('MainNavigation: [DEBUG] Monitoring session status for UID: ${userProfile.uid}, Device: $_deviceId');
      
      // Listen to specific device session status (isActive)
      _sessionSubscription = UserService().streamSessionStatus(userProfile.uid, _deviceId).listen((isActive) {
        if (!isActive) {
          debugPrint('MainNavigation: [DEBUG] Session deactivated for this device!');
          _handleAutoLogout();
        }
      });
    }
  }

  void _handleAutoLogout() async {
    _sessionSubscription?.cancel();
    final authService = ref.read(authServiceProvider);
    await authService.signOut();
    await PersistenceService().clearSession();
    
    if (mounted) {
      TopNotificationService().showNotification(
        context, 
        'Logged out: Your account is being used on another device.'
      );
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
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
    final currentIndex = ref.read(uiStateProvider).mainNavigationIndex;
    if (currentIndex != index) {
      InterstitialAdService().maybeShowOnTransition(
        transitionPoint: 'main_nav_tab_${currentIndex}_to_$index',
      );
    }
    ref.read(uiStateProvider.notifier).setMainNavigationIndex(index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(uiStateProvider);
    final themeMode = ref.watch(themeProvider);
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
