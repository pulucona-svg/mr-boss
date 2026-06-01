import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'signup_screen.dart';
import 'reset_password_screen.dart';
import 'academic_personalization_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../providers/auth_provider.dart';
import '../providers/firebase_auth_provider.dart';
import '../providers/user_provider.dart';
import '../services/persistence_service.dart';
import '../services/top_notification_service.dart';

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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 2500),
              curve: Curves.linear,
            );
          }
        });
      }
    });
  }

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

        // Update sessionId in Firestore for single session enforcement
        final sessionId = ref.read(userProfileProvider.notifier).instanceSessionId;
        await UserService().updateSessionId(user.uid, sessionId);
        
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google Login failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleLogin() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;

    if (identifier.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both identifier and password')),
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
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Username not found')),
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

        // Update sessionId in Firestore for single session enforcement
        final sessionId = ref.read(userProfileProvider.notifier).instanceSessionId;
        await UserService().updateSessionId(user.uid, sessionId);

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
      if (e.code == 'user-not-found') {
        message = 'No user found with this identifier';
      } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = 'Incorrect password';
      } else if (e.code == 'invalid-email') {
        message = 'Invalid email address';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
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
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
            prefixIcon: icon != null ? Icon(icon, color: Colors.white) : null,
            suffixIcon: toggle != null
                ? IconButton(
                    icon: Icon(
                      obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: Colors.white,
                    ),
                    onPressed: toggle,
                  )
                : null,
            filled: true,
            fillColor: Colors.black.withOpacity(0.3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
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
          Positioned.fill(
            child: Image.asset('assets/login_bg.jpeg', fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.3),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const SizedBox(height: 80),

                    const Text(
                      'Hi, welcome back',
                      style: TextStyle(
                        color: Color(0xFF9C27B0),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 32),

                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF000066),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blueAccent),
                      ),
                      child: Column(
                        children: [
                          _buildTextField(
                            controller: _identifierController,
                            label: "Identifier",
                            hint: "Username / Email",
                            obscure: false,
                            toggle: null,
                            icon: Icons.person,
                          ),
                          const SizedBox(height: 16),

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
                              Row(
                                children: [
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Checkbox(
                                      value: _rememberMe,
                                      onChanged: (v) =>
                                          setState(() => _rememberMe = v ?? false),
                                      activeColor: const Color(0xFF20C8FF),
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text("Remember me",
                                      style: TextStyle(color: Colors.white, fontSize: 13)),
                                ],
                              ),
                              Flexible(
                                child: TextButton(
                                  onPressed: () async {
                                    final identifier = _identifierController.text.trim();
                                    if (identifier.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Please enter your email or username first')),
                                      );
                                      return;
                                    }

                                    setState(() => _isLoading = true);
                                    try {
                                      final authService = ref.read(authServiceProvider);
                                      String email = identifier;
                                      if (!identifier.contains('@')) {
                                        final resolvedEmail = await authService.resolveEmailFromUsername(identifier);
                                        if (resolvedEmail == null) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Username not found')),
                                            );
                                          }
                                          setState(() => _isLoading = false);
                                          return;
                                        }
                                        email = resolvedEmail;
                                      }

                                      await authService.sendPasswordResetEmail(email);
                                      
                                      if (mounted) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => ResetPasswordScreen(
                                              email: email,
                                              showInitialSuccess: true,
                                            ),
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Error: ${e.toString()}')),
                                        );
                                      }
                                    } finally {
                                      if (mounted) setState(() => _isLoading = false);
                                    }
                                  },
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    "Forgot Password?",
                                    style: TextStyle(
                                      color: Color(0xFF20C8FF),
                                      fontSize: 13,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed:
                                  _isLoading ? null : _handleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF20C8FF),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: _isLoading
                                  ? const CircularProgressIndicator(
                                      color: Colors.white)
                                  : const Text(
                                      "Login",
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white),
                                    ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          Row(
                            children: [
                              Expanded(
                                  child: Divider(
                                      color: Colors.white.withOpacity(0.3))),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  "OR",
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              Expanded(
                                  child: Divider(
                                      color: Colors.white.withOpacity(0.3))),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // GOOGLE BUTTON
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: OutlinedButton(
                              onPressed: _isLoading ? null : _handleGoogleLogin,
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white24),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SvgPicture.string(
                                    _googleSvg,
                                    width: 24,
                                    height: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  const Flexible(
                                    child: Text(
                                      "Continue with Google",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // APPLE BUTTON
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: OutlinedButton(
                              onPressed: () {
                                TopNotificationService().showNotification(context, "Apple Sign-In coming soon");
                              },
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white24),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const FaIcon(
                                    FontAwesomeIcons.apple,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  const Flexible(
                                    child: Text(
                                      "Continue with Apple",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
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

                    const SizedBox(height: 32),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Don't have an account? ",
                            style: TextStyle(color: Colors.white70)),
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
                              color: Color(0xFFE31E24),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 48),

                    const Column(
                      children: [
                        Text(
                          'Copyright © 2026- MIRROR Softwares',
                          style: TextStyle(
                            color: Color(0xFFE31E24),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'International',
                          style: TextStyle(
                            color: Color(0xFFE31E24),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
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
