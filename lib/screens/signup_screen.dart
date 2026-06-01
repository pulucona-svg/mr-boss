import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'academic_personalization_screen.dart';
import 'verification_password_screen.dart';
import 'email_verification_screen.dart';
import '../services/top_notification_service.dart';
import '../providers/firebase_auth_provider.dart';
import '../providers/user_provider.dart';
import '../services/persistence_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  bool _agreeToEmails = true;
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;

  static const String _googleSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" width="48px" height="48px"><path fill="#fbc02d" d="M43.611,20.083H42V20H24v8h11.303c-1.649,4.657-6.08,8-11.303,8c-6.627,0-12-5.373-12-12	s5.373-12,12-12c3.059,0,5.842,1.154,7.961,3.039l5.657-5.657C34.046,6.053,29.268,4,24,4C12.955,4,4,12.955,4,24s8.955,20,20,20	s20-8.955,20-20C44,22.659,43.862,21.35,43.611,20.083z"/><path fill="#e53935" d="M6.306,14.691l6.571,4.819C14.655,15.108,18.961,12,24,12c3.059,0,5.842,1.154,7.961,3.039	l5.657-5.657C34.046,6.053,29.268,4,24,4C16.318,4,9.656,8.337,6.306,14.691z"/><path fill="#4caf50" d="M24,44c5.166,0,9.86-1.977,13.409-5.192l-6.19-5.238C29.211,35.091,26.715,36,24,36	c-5.202,0-9.619-3.317-11.283-7.946l-6.522,5.025C9.505,39.556,16.227,44,24,44z"/><path fill="#1565c0" d="M43.611,20.083L43.595,20L42,20H24v8h11.303c-0.792,2.237-2.231,4.166-4.087,5.571	c0.001-0.001,0.002-0.001,0.002-0.002l6.19,5.238C36.971,39.205,44,34,44,24C44,22.659,43.862,21.35,43.611,20.083z"/></svg>
''';

  void _handleGoogleSignup() async {
    debugPrint('SignupScreen: [DEBUG] Google Signup button pressed.');
    try {
      setState(() => _isLoading = true);

      final authService = ref.read(authServiceProvider);
      debugPrint('SignupScreen: [DEBUG] Calling authService.signInWithGoogle()...');
      final userCredential = await authService.signInWithGoogle();

      if (userCredential != null && mounted) {
        final user = userCredential.user!;
        debugPrint('SignupScreen: [DEBUG] Google Sign-In success. UID: ${user.uid}');
        
        debugPrint('SignupScreen: [DEBUG] Saving session to persistence...');
        await PersistenceService().saveSession(user.uid);
        
        // Sync profile to Firestore
        debugPrint('SignupScreen: [DEBUG] Fetching profile from Firestore to check existence...');
        await ref
            .read(userProfileProvider.notifier)
            .fetchProfileFromFirestore(user.uid);
            
        final profile = ref.read(userProfileProvider);
        debugPrint('SignupScreen: [DEBUG] Profile state after fetch: onboardingComplete=${profile.onboardingComplete}');

        // Update local profile with Google info
        debugPrint('SignupScreen: [DEBUG] Updating local profile with Google info...');
        ref.read(userProfileProvider.notifier).updateProfile(
          uid: user.uid,
          email: user.email ?? '',
          username: user.displayName ?? '',
          photoURL: user.photoURL,
        );

        if (profile.onboardingComplete) {
          debugPrint('SignupScreen: [DEBUG] Navigating to /home');
          Navigator.pushReplacementNamed(context, '/home');
        } else {
          debugPrint('SignupScreen: [DEBUG] Navigating to AcademicPersonalizationScreen');
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
      } else {
        debugPrint('SignupScreen: [DEBUG] Google Sign-In returned null (user cancelled).');
      }
    } catch (e) {
      debugPrint('SignupScreen: [FATAL ERROR] Google Sign-In failed in catch block: $e');
      if (mounted) {
        TopNotificationService().showNotification(context, "Google Sign-In failed: $e");
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showEmailModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 32,
          left: 24,
          right: 24,
          top: 32,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF14142B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your email',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Email address',
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () async {
                  final email = _emailController.text.trim();
                  if (!email.contains('@')) {
                    TopNotificationService().showNotification(context, "Please enter a valid email");
                    return;
                  }

                  setState(() => _isLoading = true);
                  
                  debugPrint('SignupScreen: [DEBUG] Starting signup flow for $email');
                  try {
                    final authService = ref.read(authServiceProvider);
                    
                    // Create account with a temporary password
                    const dummyPassword = "TemporaryPassword123!";
                    
                    debugPrint('SignupScreen: [DEBUG] Calling registerWithEmailAndPassword...');
                    final userCredential = await authService.registerWithEmailAndPassword(email, dummyPassword);
                    debugPrint('SignupScreen: [DEBUG] Account creation successful.');
                    
                    if (userCredential != null) {
                      await PersistenceService().saveSession(userCredential.user!.uid);
                      debugPrint('SignupScreen: [DEBUG] Session saved: ${userCredential.user!.uid}');
                    }

                    debugPrint('SignupScreen: [DEBUG] Calling sendEmailVerification...');
                    await authService.sendEmailVerification();
                    debugPrint('SignupScreen: [DEBUG] Verification email sent successfully.');

                    if (mounted) {
                      debugPrint('SignupScreen: [DEBUG] Navigating to EmailVerificationScreen');
                      // Close the modal before navigating
                      Navigator.pop(context);
                      
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EmailVerificationScreen(
                            email: email,
                          ),
                        ),
                      );
                    }
                  } on FirebaseAuthException catch (e) {
                    debugPrint('SignupScreen: [DEBUG] FirebaseAuthException: Code=${e.code}, Message=${e.message}');
                    String message = e.message ?? 'An error occurred during signup';
                    if (e.code == 'email-already-in-use') {
                      message = 'This email is already registered. Please login instead.';
                    } else if (e.code == 'invalid-email') {
                      message = 'The email address is invalid.';
                    } else if (e.code == 'weak-password') {
                      message = 'The password is too weak.';
                    }
                    
                    if (mounted) {
                      TopNotificationService().showNotification(context, message);
                    }
                  } catch (e) {
                    debugPrint('SignupScreen: [DEBUG] Unknown error: $e');
                    if (mounted) {
                      TopNotificationService().showNotification(context, "Signup failed: ${e.toString()}");
                    }
                  } finally {
                    if (mounted) setState(() => _isLoading = false);
                  }
                },
                child: const Text('CONTINUE'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/login_bg.jpeg',
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.2),
            ),
          ),

          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.3),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Back Button Row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  // LOGO
                  Center(
                    child: Container(
                      height: 110,
                      width: 110,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        image: DecorationImage(
                          image: AssetImage('assets/icon.png'),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    'Join Mirror Laikipia',
                    style: TextStyle(
                      color: Colors.purpleAccent,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 10),

                  const Text(
                    'Access notes, exams & academic resources',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),

                  const SizedBox(height: 40),

                  // GOOGLE BUTTON
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _buildGoogleButton(),
                  ),

                  const SizedBox(height: 16),

                  // APPLE BUTTON
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _buildSocialButton(
                      icon: const FaIcon(FontAwesomeIcons.apple, size: 24),
                      label: "Continue with Apple",
                      onPressed: () {
                        TopNotificationService().showNotification(context, "Apple Sign-In coming soon");
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  // EMAIL BUTTON
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _buildSocialButton(
                      icon: const Icon(Icons.email_outlined, size: 24),
                      label: "Continue with Email",
                      onPressed: _showEmailModal,
                    ),
                  ),

                  const SizedBox(height: 30),

                  // TERMS
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text(
                          "By continuing you agree to our terms",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Checkbox(
                              value: _agreeToEmails,
                              onChanged: (v) =>
                                  setState(() => _agreeToEmails = v ?? false),
                            ),
                            const Text(
                              "I agree to receive updates",
                              style: TextStyle(color: Colors.white),
                            )
                          ],
                        )
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // FOOTER
                  const Column(
                    children: [
                      Text(
                        'Copyright © 2026 - MIRROR Softwares',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'International',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black45,
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFF20C8FF)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleGoogleSignup,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
                style: TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialButton({
    required Widget icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
