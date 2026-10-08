import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../services/deletion_service.dart';
import '../services/persistence_service.dart';
import '../services/top_notification_service.dart';
import 'login_screen.dart';

class AccountDeletionScreen extends ConsumerStatefulWidget {
  const AccountDeletionScreen({super.key});

  @override
  ConsumerState<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends ConsumerState<AccountDeletionScreen> {
  bool _isSubmitting = false;

  // Optional questionnaire responses
  String? _q1Reason;
  final TextEditingController _q2ImprovementsController = TextEditingController();
  final TextEditingController _q3DisappointedFeatureController = TextEditingController();
  String? _q4EaseOfUse;
  String? _q5AcademicValue;
  String? _q6FoundMaterials;
  String? _q7AdExperience;
  String? _q8PaymentExperience;
  String? _q9ReturnIntent;
  final TextEditingController _q10CommentsController = TextEditingController();

  final List<String> _q1Options = const [
    'Found an alternative service',
    'Completed studies / graduating',
    'Technical difficulties / bugs',
    'Privacy concerns',
    'Content / materials not relevant',
    'Cost / subscription concerns',
    'Other reason',
  ];

  final List<String> _q4Options = const [
    'Very Easy',
    'Easy',
    'Neutral',
    'Difficult',
    'Very Difficult',
  ];

  final List<String> _q5Options = const [
    'Extremely valuable',
    'Very valuable',
    'Somewhat valuable',
    'Not valuable',
  ];

  final List<String> _q6Options = const [
    'Always',
    'Most of the time',
    'Sometimes',
    'Rarely',
    'Never',
  ];

  final List<String> _q7Options = const [
    'Non-intrusive',
    'Acceptable',
    'Too frequent',
    'Distracting',
  ];

  final List<String> _q8Options = const [
    'Seamless',
    'Good',
    'Neutral',
    'Confusing',
    'Never subscribed',
  ];

  final List<String> _q9Options = const [
    'Definitely yes',
    'Maybe in the future',
    'Unlikely',
    'No',
  ];

  @override
  void dispose() {
    _q2ImprovementsController.dispose();
    _q3DisappointedFeatureController.dispose();
    _q10CommentsController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _collectFeedback() {
    final Map<String, dynamic> feedback = {};
    if (_q1Reason != null) feedback['reason'] = _q1Reason;
    if (_q2ImprovementsController.text.trim().isNotEmpty) {
      feedback['improvements'] = _q2ImprovementsController.text.trim();
    }
    if (_q3DisappointedFeatureController.text.trim().isNotEmpty) {
      feedback['disappointedFeature'] = _q3DisappointedFeatureController.text.trim();
    }
    if (_q4EaseOfUse != null) feedback['easeOfUse'] = _q4EaseOfUse;
    if (_q5AcademicValue != null) feedback['academicValue'] = _q5AcademicValue;
    if (_q6FoundMaterials != null) feedback['foundMaterials'] = _q6FoundMaterials;
    if (_q7AdExperience != null) feedback['adExperience'] = _q7AdExperience;
    if (_q8PaymentExperience != null) feedback['paymentExperience'] = _q8PaymentExperience;
    if (_q9ReturnIntent != null) feedback['returnIntent'] = _q9ReturnIntent;
    if (_q10CommentsController.text.trim().isNotEmpty) {
      feedback['additionalComments'] = _q10CommentsController.text.trim();
    }
    return feedback;
  }

  Future<void> _confirmAndRequestDeletion() async {
    if (_isSubmitting) return;

    final themeMode = ref.read(themeProvider);
    final isDark = themeMode == ThemeMode.dark;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: !_isSubmitting,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Confirm Account Deletion',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Your account will enter a 30-day grace period. You can sign in anytime within the next 30 days to restore your account.\n\nAre you sure you want to proceed?',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text(
              'Keep Account',
              style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text(
              'Yes, Request Deletion',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);

    try {
      final feedback = _collectFeedback();
      final result = await DeletionService().requestAccountDeletion(
        feedback: feedback.isNotEmpty ? feedback : null,
      );

      if (!mounted) return;

      if (result.success) {
        ref.read(userProfileProvider.notifier).setDeletionStatus(
          status: 'pending',
          requestedAt: result.deletionRequestedAt,
          scheduledAt: result.deletionScheduledAt,
        );

        final authService = ref.read(authServiceProvider);
        await authService.signOut();
        await PersistenceService().clearSession();

        if (mounted) {
          TopNotificationService().showNotification(
            context,
            'Account deletion requested. You have a 30-day grace period to restore your account.',
            type: TopNotificationType.info,
          );

          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      } else {
        setState(() => _isSubmitting = false);
        final errorMsg = result.errorMessage ??
            "Request can't be completed. Please check your internet connection.";
        TopNotificationService().showNotification(
          context,
          errorMsg,
          type: TopNotificationType.error,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        TopNotificationService().showNotification(
          context,
          "Request can't be completed. Please check your internet connection.",
          type: TopNotificationType.error,
        );
      }
    }
  }

  Widget _buildSectionCard({
    required bool isDark,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF13132B) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
        ),
      ),
      child: child,
    );
  }

  Widget _buildChoiceChips({
    required List<String> options,
    required String? selectedValue,
    required ValueChanged<String?> onSelected,
    required bool isDark,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final isSelected = opt == selectedValue;
        return ChoiceChip(
          label: Text(
            opt,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected
                  ? Colors.white
                  : (isDark ? Colors.white70 : Colors.black87),
            ),
          ),
          selected: isSelected,
          selectedColor: Colors.blueAccent,
          backgroundColor: isDark ? const Color(0xFF1F1F3D) : Colors.grey.shade200,
          onSelected: (selected) {
            onSelected(selected ? opt : null);
          },
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF090914) : Colors.white,
      appBar: AppBar(
        title: const Text('Delete account'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textColor,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  // Information & Grace Period Card
                  _buildSectionCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.blueAccent, size: 24),
                            const SizedBox(width: 8),
                            Text(
                              'How Account Deletion Works',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '• Requesting deletion starts a 30-day grace period.\n'
                          '• Your account will not be permanently deleted immediately.\n'
                          '• You can restore your account anytime during these 30 days simply by signing in.\n'
                          '• After the 30-day grace period expires, permanent deletion and anonymization occur.\n'
                          '• Academic materials you contributed may remain available to students, but will no longer identify you.\n'
                          '• Discussion comments and replies remain for context, attributed to "Anonymous User".\n'
                          '• Your private profile information, credentials, and sessions will be permanently removed.\n'
                          '• Once the grace period expires, deletion is irreversible.',
                          style: TextStyle(
                            color: subTextColor,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Optional Feedback Title
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      'Feedback (Optional)',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    'Help us improve Mirror Digital. All questions below are completely optional.',
                    style: TextStyle(
                      color: subTextColor,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Question 1
                  _buildSectionCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '1. What is the main reason you are leaving Mirror Digital?',
                          style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        _buildChoiceChips(
                          options: _q1Options,
                          selectedValue: _q1Reason,
                          onSelected: (val) => setState(() => _q1Reason = val),
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),

                  // Question 2
                  _buildSectionCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '2. What changes or improvements would you like to see?',
                          style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _q2ImprovementsController,
                          maxLines: 2,
                          style: TextStyle(color: textColor, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Share your ideas or suggestions...',
                            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF1F1F3D) : Colors.grey.shade100,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Question 3
                  _buildSectionCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '3. Was there a feature that disappointed you?',
                          style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _q3DisappointedFeatureController,
                          maxLines: 2,
                          style: TextStyle(color: textColor, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Tell us what did not meet your expectations...',
                            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF1F1F3D) : Colors.grey.shade100,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Question 4
                  _buildSectionCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '4. How easy was Mirror Digital to use?',
                          style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        _buildChoiceChips(
                          options: _q4Options,
                          selectedValue: _q4EaseOfUse,
                          onSelected: (val) => setState(() => _q4EaseOfUse = val),
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),

                  // Question 5
                  _buildSectionCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '5. How valuable was Mirror Digital for your academic work?',
                          style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        _buildChoiceChips(
                          options: _q5Options,
                          selectedValue: _q5AcademicValue,
                          onSelected: (val) => setState(() => _q5AcademicValue = val),
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),

                  // Question 6
                  _buildSectionCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '6. Did you find the academic materials you needed?',
                          style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        _buildChoiceChips(
                          options: _q6Options,
                          selectedValue: _q6FoundMaterials,
                          onSelected: (val) => setState(() => _q6FoundMaterials = val),
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),

                  // Question 7
                  _buildSectionCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '7. How would you rate the advertisements?',
                          style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        _buildChoiceChips(
                          options: _q7Options,
                          selectedValue: _q7AdExperience,
                          onSelected: (val) => setState(() => _q7AdExperience = val),
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),

                  // Question 8
                  _buildSectionCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '8. How would you rate the payment/subscription experience?',
                          style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        _buildChoiceChips(
                          options: _q8Options,
                          selectedValue: _q8PaymentExperience,
                          onSelected: (val) => setState(() => _q8PaymentExperience = val),
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),

                  // Question 9
                  _buildSectionCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '9. Would you consider returning to Mirror Digital?',
                          style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        _buildChoiceChips(
                          options: _q9Options,
                          selectedValue: _q9ReturnIntent,
                          onSelected: (val) => setState(() => _q9ReturnIntent = val),
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),

                  // Question 10
                  _buildSectionCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '10. Do you have any other comments or suggestions?',
                          style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _q10CommentsController,
                          maxLines: 3,
                          style: TextStyle(color: textColor, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Any thoughts, praise, or critique...',
                            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF1F1F3D) : Colors.grey.shade100,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Actions: Cancel (Blue) / Delete Account (Red)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0D0D1A) : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Cancel (Blue)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blueAccent,
                        side: const BorderSide(color: Colors.blueAccent, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Delete Account (Red)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _confirmAndRequestDeletion,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Delete Account',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
