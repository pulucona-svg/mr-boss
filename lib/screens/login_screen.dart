import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'signup_screen.dart';
import 'reset_password_screen.dart';
import 'academic_personalization_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/providers.dart';
import '../services/persistence_service.dart';
import '../services/top_notification_service.dart';
import '../services/connectivity_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false;

  static const String _googleSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" width="48px" height="48px"><path fill="#fbc02d" d="M43.611,20.083H42V20H24v8h11.303c-1.649,4.657-6.08,8-11.303,8c-6.627,0-12-5.373-12-12	s5.373-12,12-12c3.059,0,5.842,1.154,7.961,3.039l5.657-5.657C34.046,6.053,29.268,4,24,4C12.955,4,4,12.955,4,24s8.955,20,20,20	s20-8.955,20-20C44,22.659,43.862,21.35,43.611,20.083z"/><path fill="#e53935" d="M6.306,14.691l6.571,4.819C14.655,15.108,18.961,12,24,12c3.059,0,5.842,1.154,7.961,3.039	l5.657-5.657C34.046,6.053,29.268,4,24,4C16.318,4,9.656,8.337,6.306,14.691z"/><path fill="#4caf50" d="M24,44c5.166,0,9.86-1.977,13.409-5.192l-6.19-5.238C29.211,35.091,26.715,36,24,36	c-5.202,0-9.619-3.317-11.283-7.946l-6.522,5.025C9.505,39.556,16.227,44,24,44z"/><path fill="#1565c0" d="M43.611,20.083L43.595,20L42,20H24v8h11.303c-0.792,2.237-2.231,4.166-4.087,5.571	c0.001-0.001,0.002-0.001,0.002-0.002l6.19,5.238C36.971,39.205,44,34,44,24C44,22.659,43.862,21.35,43.611,20.083z"/></svg>
''';

  @override
  void dispose() {
    _scrollController.dispose();
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleGoogleLogin() async {
    debugPrint('LoginScreen: [DEBUG] Google Sign-In button pressed.');
    setState(() => _isLoading = true);
    try {
      final authService = ref.read(authServiceProvider);
      debugPrint('LoginScreen: [DEBUG] Calling authService.signInWithGoogle()...');
      final userCredential = await authService.signInWithGoogle();

      if (userCredential != null && mounted) {
        final user = userCredential.user!;
        debugPrint('LoginScreen: [DEBUG] Google Sign-In success. UID: ${user.uid}');
        
        await PersistenceService().saveSession(user.uid);
        
        await ref
            .read(userProfileProvider.notifier)
            .fetchProfileFromFirestore(user.uid);

        final profile = ref.read(userProfileProvider);

        if (profile.onboardingComplete) {
          Navigator.pushReplacementNamed(context, '/home');
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => AcademicPersonalizationScreen(
                email: user.email ?? '',
                isOnboarding: true,
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('LoginScreen: [FATAL ERROR] Google Sign-In failed: $e');
      if (mounted) {
        final message = ConnectivityService.isNetworkError(e)
            ? 'Login failed. Please check your internet connection and try again.'
            : 'Google Login failed: $e';
        TopNotificationService().showNotification(context, message);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleLogin() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;

    if (identifier.isEmpty || password.isEmpty) {
      TopNotificationService().showNotification(
        context,
        'Please enter both identifier and password',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = ref.read(authServiceProvider);
      String email = identifier;

      // If it doesn't look like an email, treat as username
      if (!identifier.contains('@')) {
        final resolvedEmail = await authService.resolveEmailFromUsername(identifier);
        if (resolvedEmail == null) {
          if (ConnectivityService.isNetworkError(null)) {
            if (mounted) {
              TopNotificationService().showNotification(
                context,
                'Login failed. Please check your internet connection and try again.',
              );
            }
            setState(() => _isLoading = false);
            return;
          }
          if (mounted) {
            TopNotificationService().showNotification(
              context,
              'Username not found',
            );
          }
          setState(() => _isLoading = false);
          return;
        }
        email = resolvedEmail;
      }

      final userCredential =
          await authService.signInWithEmailAndPassword(email, password);

      if (userCredential != null && mounted) {
        final user = userCredential.user!;

        await PersistenceService().saveSession(user.uid);

        await ref
            .read(userProfileProvider.notifier)
            .fetchProfileFromFirestore(user.uid);

        final profile = ref.read(userProfileProvider);

        TopNotificationService()
            .showNotification(context, 'Login successful');
        TopNotificationService.pendingWelcome = true;

        Future.delayed(const Duration(milliseconds: 1000), () {
          if (!mounted) return;

          if (profile.onboardingComplete) {
            Navigator.pushReplacementNamed(context, '/home');
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => AcademicPersonalizationScreen(
                  email: user.email ?? email,
                  isOnboarding: true,
                ),
              ),
            );
          }
        });
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Login failed';
      if (ConnectivityService.isNetworkError(e)) {
        message = 'Login failed. Please check your internet connection and try again.';
      } else if (e.code == 'user-not-found') {
        message = 'No user found with this identifier';
      } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = 'Incorrect password';
      } else if (e.code == 'invalid-email') {
        message = 'Invalid email address';
      } else if (e.code == 'user-disabled') {
        message = 'This account has been disabled';
      } else if (e.code == 'too-many-requests') {
        message = 'Too many attempts. Please try again later.';
      }
      if (mounted) {
        TopNotificationService().showNotification(context, message);
      }
    } catch (e) {
      if (mounted) {
        final message = ConnectivityService.isNetworkError(e)
            ? 'Login failed. Please check your internet connection and try again.'
            : 'Error: ${e.toString()}';
        TopNotificationService().showNotification(context, message);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool obscure,
    required VoidCallback? toggle,
    IconData? icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon == Icons.person
                    ? Icons.person_rounded
                    : Icons.lock_rounded,
                size: 14,
                color: Colors.white70,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.16),
              width: 1,
            ),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            cursorColor: const Color(0xFF20C8FF),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 14,
              ),
              prefixIcon: icon != null
                  ? Icon(
                      icon == Icons.person
                          ? Icons.person_outline_rounded
                          : Icons.lock_outline_rounded,
                      color: Colors.white60,
                      size: 20,
                    )
                  : null,
              suffixIcon: toggle != null
                  ? IconButton(
                      icon: Icon(
                        obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: Colors.white60,
                        size: 20,
                      ),
                      onPressed: toggle,
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Campus photograph background (fully preserved)
          Positioned.fill(
            child: Image.asset(
              'assets/login_bg.jpeg',
              fit: BoxFit.cover,
            ),
          ),

          // 2. Subtle dark overlay over photograph (keeps natural sunset/building colors visible)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.28),
            ),
          ),

          // 3. Responsive Safe Content Area
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),

                    // MIRROR LAIKIPIA Branding
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/splash_logo.png',
                            height: 44,
                            width: 44,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'MIRROR',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.8,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.school,
                                    color: Color(0xFF20C8FF),
                                    size: 18,
                                  ),
                                ],
                              ),
                              const Text(
                                'LAIKIPIA',
                                style: TextStyle(
                                  color: Color(0xFF20C8FF),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 3.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(width: 14, height: 1, color: Colors.white38),
                          const SizedBox(width: 6),
                          const Text(
                            'Learn  ·  Access  ·  Grow',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              letterSpacing: 0.8,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(width: 14, height: 1, color: Colors.white38),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Glassmorphism Login Card
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: const Color(0xFF20C8FF).withValues(alpha: 0.06),
                            blurRadius: 20,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A1128).withValues(alpha: 0.58),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
                                width: 1.2,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildTextField(
                                  controller: _identifierController,
                                  label: "Username / Email",
                                  hint: "Username / Email",
                                  obscure: false,
                                  toggle: null,
                                  icon: Icons.person,
                                ),
                                const SizedBox(height: 14),

                                _buildTextField(
                                  controller: _passwordController,
                                  label: "Password",
                                  hint: "Enter password",
                                  obscure: _obscurePassword,
                                  toggle: () => setState(
                                      () => _obscurePassword = !_obscurePassword),
                                  icon: Icons.lock,
                                ),

                                const SizedBox(height: 8),

                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Flexible(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: Checkbox(
                                              value: _rememberMe,
                                              onChanged: (v) =>
                                                  setState(() => _rememberMe = v ?? false),
                                              activeColor: const Color(0xFF20C8FF),
                                              checkColor: Colors.white,
                                              side: BorderSide(
                                                color: Colors.white.withValues(alpha: 0.5),
                                                width: 1.5,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize.shrinkWrap,
                                              visualDensity: VisualDensity.compact,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          const Flexible(
                                            child: Text(
                                              "Remember me",
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Flexible(
                                      child: TextButton(
                                        onPressed: () async {
                                          final identifier =
                                              _identifierController.text.trim();
                                          if (identifier.isEmpty) {
                                            TopNotificationService().showNotification(
                                              context,
                                              'Please enter your email or username first',
                                            );
                                            return;
                                          }

                                          setState(() => _isLoading = true);
                                          try {
                                            final authService =
                                                ref.read(authServiceProvider);
                                            String email = identifier;
                                            if (!identifier.contains('@')) {
                                              final resolvedEmail = await authService
                                                  .resolveEmailFromUsername(identifier);
                                              if (resolvedEmail == null) {
                                                if (ConnectivityService.isNetworkError(null)) {
                                                  if (context.mounted) {
                                                    TopNotificationService().showNotification(
                                                      context,
                                                      'Password reset failed. Please check your internet connection and try again.',
                                                    );
                                                  }
                                                  if (mounted) setState(() => _isLoading = false);
                                                  return;
                                                }
                                                if (context.mounted) {
                                                  TopNotificationService().showNotification(
                                                    context,
                                                    'Username not found',
                                                  );
                                                }
                                                if (mounted) setState(() => _isLoading = false);
                                                return;
                                              }
                                              email = resolvedEmail;
                                            }

                                            await authService
                                                .sendPasswordResetEmail(email);

                                            if (context.mounted) {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      ResetPasswordScreen(
                                                    email: email,
                                                    showInitialSuccess: true,
                                                  ),
                                                ),
                                              );
                                            }
                                          } on FirebaseAuthException catch (e) {
                                            String message = 'Password reset failed';
                                            if (ConnectivityService.isNetworkError(e)) {
                                              message =
                                                  'Password reset failed. Please check your internet connection and try again.';
                                            } else if (e.code == 'user-not-found') {
                                              message = 'No user found with this email';
                                            } else if (e.code == 'invalid-email') {
                                              message = 'Invalid email address';
                                            } else if (e.code == 'too-many-requests') {
                                              message = 'Too many attempts. Please try again later.';
                                            } else {
                                              message = e.message ?? 'Password reset failed';
                                            }
                                            if (context.mounted) {
                                              TopNotificationService().showNotification(context, message);
                                            }
                                          } catch (e) {
                                            if (context.mounted) {
                                              final message = ConnectivityService.isNetworkError(e)
                                                  ? 'Password reset failed. Please check your internet connection and try again.'
                                                  : 'Error: ${e.toString()}';
                                              TopNotificationService().showNotification(context, message);
                                            }
                                          } finally {
                                            if (mounted) {
                                              setState(() => _isLoading = false);
                                            }
                                          }
                                        },
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text(
                                          "Forgot Password?",
                                          style: TextStyle(
                                            color: Color(0xFF20C8FF),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 18),

                                // PRIMARY LOGIN BUTTON
                                Container(
                                  width: double.infinity,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF0284C7), Color(0xFF20C8FF)],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF20C8FF)
                                            .withValues(alpha: 0.35),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _handleLogin,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2.5,
                                            ),
                                          )
                                        : const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                "Login",
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                              Icon(
                                                Icons.arrow_forward_rounded,
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                            ],
                                          ),
                                  ),
                                ),

                                const SizedBox(height: 14),

                                // OR DIVIDER
                                Row(
                                  children: [
                                    Expanded(
                                      child: Divider(
                                        color: Colors.white.withValues(alpha: 0.20),
                                        thickness: 1,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14),
                                      child: Text(
                                        "OR",
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.50),
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Divider(
                                        color: Colors.white.withValues(alpha: 0.20),
                                        thickness: 1,
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 14),

                                // GOOGLE BUTTON
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: OutlinedButton(
                                    onPressed: _isLoading ? null : _handleGoogleLogin,
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFF20C8FF).withValues(alpha: 0.08),
                                      side: BorderSide(
                                        color: const Color(0xFF20C8FF).withValues(alpha: 0.35),
                                        width: 1.2,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        SvgPicture.string(
                                          _googleSvg,
                                          width: 22,
                                          height: 22,
                                        ),
                                        const SizedBox(width: 12),
                                        const Flexible(
                                          child: Text(
                                            "Continue with Google",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 10),

                                // APPLE BUTTON
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: OutlinedButton(
                                    onPressed: () {
                                      TopNotificationService().showNotification(
                                          context, "Apple Sign-In coming soon");
                                    },
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFF20C8FF).withValues(alpha: 0.08),
                                      side: BorderSide(
                                        color: const Color(0xFF20C8FF).withValues(alpha: 0.35),
                                        width: 1.2,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        FaIcon(
                                          FontAwesomeIcons.apple,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                        SizedBox(width: 12),
                                        Flexible(
                                          child: Text(
                                            "Continue with Apple",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // CREATE ACCOUNT (Retaining existing RED accent)
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          "Don't have an account? ",
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SignupScreen(),
                            ),
                          ),
                          child: const Text(
                            "Create Account",
                            style: TextStyle(
                              color: Color(0xFFE31E24), // Explicitly retained red accent
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // COPYRIGHT (Preserved as BLUE)
                    Column(
                      children: [
                        const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Copyright © 2026- MIRROR Softwares',
                            style: TextStyle(
                              color: Color(0xFF20C8FF), // Explicitly BLUE
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 20,
                                height: 1,
                                color: const Color(0xFF20C8FF).withValues(alpha: 0.4),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'International',
                                style: TextStyle(
                                  color: Color(0xFF20C8FF), // Explicitly BLUE
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 20,
                                height: 1,
                                color: const Color(0xFF20C8FF).withValues(alpha: 0.4),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
