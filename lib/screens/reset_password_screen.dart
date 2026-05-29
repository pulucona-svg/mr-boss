import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';
import '../providers/auth_provider.dart';
import '../services/top_notification_service.dart';
import '../services/persistence_service.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  final bool showInitialSuccess;
  final String email;
  final bool isSignup;

  const ResetPasswordScreen({
    super.key, 
    this.showInitialSuccess = false,
    required this.email,
    this.isSignup = false,
  });

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Validation checks
  bool _hasMinLength = false;
  bool _hasLetter = false;
  bool _hasNumber = false;
  bool _passwordsMatch = false;
  bool _isOtpValid = false;

  @override
  void initState() {
    super.initState();
    
    _codeController.addListener(_onFieldChanged);
    _passwordController.addListener(_onFieldChanged);
    _confirmPasswordController.addListener(_onFieldChanged);

    // Move provider initialization to post-frame to avoid build cycle issues
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      final authState = ref.read(authStateProvider);
      
      // If it's a new email or OTP hasn't been sent yet, start timer and show notification
      if (authState.lastSentEmail != widget.email || !authState.otpSent) {
        ref.read(authStateProvider.notifier).startTimer(widget.email);
        
        if (widget.showInitialSuccess) {
          TopNotificationService().showNotification(
            context, 
            widget.isSignup 
              ? 'Signup code sent to ${widget.email}' 
              : 'Password reset code sent to ${widget.email}'
          );
        }
      }
    });
  }

  void _onFieldChanged() {
    final code = _codeController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;
    
    setState(() {
      _isOtpValid = code.length == 6;
      _hasMinLength = password.length > 6;
      _hasLetter = password.contains(RegExp(r'[a-zA-Z]'));
      _hasNumber = password.contains(RegExp(r'[0-9]'));
      _passwordsMatch = password.isNotEmpty && password == confirm;
    });
  }

  @override
  void dispose() {
    _codeController.removeListener(_onFieldChanged);
    _passwordController.removeListener(_onFieldChanged);
    _confirmPasswordController.removeListener(_onFieldChanged);
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleResendCode() {
    ref.read(authStateProvider.notifier).startTimer(widget.email);
    
    // Clear relevant fields on resend
    _codeController.clear();
    _passwordController.clear();
    _confirmPasswordController.clear();
    
    TopNotificationService().showNotification(
      context, 
      widget.isSignup 
        ? 'Signup code resent successfully' 
        : 'Password reset code resent successfully'
    );
  }

  void _handleReset() {
    if (_codeController.text.trim().length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 6-digit code')),
      );
      return;
    }

    if (!_hasMinLength || !_hasLetter || !_hasNumber) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please satisfy all password validation requirements')),
      );
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }

    // Success simulation
    TopNotificationService().showNotification(
      context, 
      widget.isSignup ? 'Account created successfully' : 'Password changed successfully'
    );
    TopNotificationService.pendingWelcome = true;
    
    // Clear auth state on success
    ref.read(authStateProvider.notifier).reset();
    
    // Save session so user is logged in automatically next time
    PersistenceService().saveSession('user_12345');
    
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context, 
          '/home', 
          (route) => false,
          arguments: {
            'isFirstLogin': true,
            'source': widget.isSignup ? 'signup' : 'password_change',
          },
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final authState = ref.watch(authStateProvider);
    
    final isDark = themeMode == ThemeMode.dark;
    final textColor = Colors.white; // Using white for better contrast on background image
    final subTextColor = Colors.white70;
    final bgColor = const Color(0xFF070716);
    final fieldBgColor = Colors.white.withOpacity(0.05);

    final isFormValid = _isOtpValid && _hasMinLength && _hasLetter && _hasNumber && _passwordsMatch;

    return Scaffold(
      body: Stack(
        children: [
          // Background Image (Matched with SignupScreen)
          Positioned.fill(
            child: Image.asset(
              'assets/login_bg.jpeg',
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.2),
            ),
          ),
          
          // Gradient Overlay (Matched with SignupScreen)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.4, 0.7, 1.0],
                  colors: [
                    Colors.black.withOpacity(0.02),
                    Colors.black.withOpacity(0.05),
                    Colors.black.withOpacity(0.2),
                    Colors.black.withOpacity(0.4),
                  ],
                ),
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              children: [
                // Top Navigation / Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF20C8FF)),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          widget.isSignup ? 'Set Password' : 'Reset Password',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          // Glass-like container for content
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: const Color(0xFF14142B).withOpacity(0.9),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              children: [
                                const SizedBox(height: 8),
                                Text(
                                  'We have sent a code to ${widget.email}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  widget.isSignup 
                                    ? 'Enter it below to set your account password.'
                                    : 'Enter it below along with your new password.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: subTextColor,
                                    fontSize: 14,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 40),
                                
                                // Reset Code Field
                                _buildTextField(
                                  controller: _codeController,
                                  hint: widget.isSignup ? 'Verification Code (6 digits)' : 'Reset Code (6 digits)',
                                  icon: Icons.tag,
                                  keyboardType: TextInputType.number,
                                  isDark: true,
                                  fieldBgColor: fieldBgColor,
                                  maxLength: 6,
                                  suffixWidget: Container(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: TextButton(
                                      onPressed: authState.canResend ? _handleResendCode : null,
                                      style: TextButton.styleFrom(
                                        backgroundColor: authState.canResend ? Colors.green.withOpacity(0.1) : Colors.transparent,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                      ),
                                      child: Text(
                                        authState.canResend ? 'Resend Code' : '${authState.remainingSeconds}s',
                                        style: TextStyle(
                                          color: authState.canResend ? Colors.green : Colors.grey,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                
                                // OTP Code Validation Tracker
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                  child: _buildRuleRow(
                                    _isOtpValid ? 'Valid verification code' : 'Enter 6-digit verification code',
                                    _isOtpValid,
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // New Password Field
                                _buildTextField(
                                  controller: _passwordController,
                                  hint: widget.isSignup ? 'Password' : 'New Password',
                                  icon: Icons.lock_outline,
                                  isPassword: true,
                                  obscureText: _obscurePassword,
                                  onToggleVisibility: () => setState(() => _obscurePassword = !_obscurePassword),
                                  isDark: true,
                                  fieldBgColor: fieldBgColor,
                                  disableCopyPaste: true,
                                ),
                                const SizedBox(height: 12),

                                // Live Password Rule Tracker
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                  child: Column(
                                    children: [
                                      _buildRuleRow('More than 6 characters', _hasMinLength),
                                      const SizedBox(height: 4),
                                      _buildRuleRow('Contains a letter', _hasLetter),
                                      const SizedBox(height: 4),
                                      _buildRuleRow('Contains a number', _hasNumber),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // Confirm Password Field
                                _buildTextField(
                                  controller: _confirmPasswordController,
                                  hint: 'Confirm Password',
                                  icon: Icons.lock_outline,
                                  isPassword: true,
                                  obscureText: _obscureConfirmPassword,
                                  onToggleVisibility: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                                  isDark: true,
                                  fieldBgColor: fieldBgColor,
                                  disableCopyPaste: true,
                                ),
                                const SizedBox(height: 12),

                                // Confirm Password Match Tracker
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                  child: _buildRuleRow(
                                    _passwordsMatch ? 'Passwords match' : 'Passwords do not match',
                                    _passwordsMatch,
                                  ),
                                ),
                                const SizedBox(height: 40),

                                // Reset Button
                                SizedBox(
                                  width: double.infinity,
                                  height: 55,
                                  child: ElevatedButton(
                                    onPressed: isFormValid ? _handleReset : null,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isFormValid ? const Color(0xFF20C8FF) : Colors.grey,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: Text(
                                      widget.isSignup ? 'SET PASSWORD' : 'RESET PASSWORD',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 48),
                          
                          // Copyright Info (Matched with SignupScreen)
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
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleRow(String text, bool isSatisfied) {
    return Row(
      children: [
        Text(
          isSatisfied ? '✓' : '✗',
          style: TextStyle(
            color: isSatisfied ? Colors.green : Colors.redAccent.withOpacity(0.8),
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: isSatisfied ? Colors.green : Colors.grey,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
    TextInputType? keyboardType,
    required bool isDark,
    required Color fieldBgColor,
    Widget? suffixWidget,
    bool disableCopyPaste = false,
    int? maxLength,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: fieldBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade300,
        ),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        maxLength: maxLength,
        enableInteractiveSelection: !disableCopyPaste,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
          prefixIcon: Icon(icon, color: Colors.grey, size: 22),
          counterText: '', // Hide default counter
          suffixIcon: suffixWidget ?? (isPassword
              ? IconButton(
                  icon: Icon(
                    obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: Colors.grey,
                    size: 20,
                  ),
                  onPressed: onToggleVisibility,
                )
              : null),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        ),
      ),
    );
  }
}
