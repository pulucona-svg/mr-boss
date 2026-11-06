import 'dart:async';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/service_providers.dart';
import '../services/connectivity_service.dart';
import '../services/interstitial_ad_service.dart';
import '../services/paystack_service.dart';
import '../services/top_notification_service.dart';

class DonationModal extends ConsumerStatefulWidget {
  final String phoneNumber;
  final VoidCallback? onSuccess;

  const DonationModal({
    super.key,
    required this.phoneNumber,
    this.onSuccess,
  });

  @override
  ConsumerState<DonationModal> createState() => _DonationModalState();
}

class _DonationModalState extends ConsumerState<DonationModal> {
  String _buttonText = 'Donate';
  String? _statusMessage;
  bool _isLoading = false;
  bool _isSuccess = false;

  // Background verification tracking
  String? _activeReference;
  PaystackVerificationListener? _verificationListener;

  // Selected payment method (defaults to M-PESA)
  PaystackPaymentMethod _selectedMethod = PaystackPaymentMethod.mpesa;

  // Amount controller & focus node
  late TextEditingController _amountController;
  final FocusNode _amountFocusNode = FocusNode();

  // Phone number controller & focus node
  late TextEditingController _phoneController;
  final FocusNode _phoneFocusNode = FocusNode();

  // Card details controllers
  final TextEditingController _cardHolderController = TextEditingController();
  final TextEditingController _cardNumberController = TextEditingController();
  final TextEditingController _cardExpiryController = TextEditingController();
  final TextEditingController _cardCvvController = TextEditingController();

  int get _currentAmount {
    return int.tryParse(_amountController.text.trim()) ?? 0;
  }

  int get _expectedXp {
    return _currentAmount * 10;
  }

  @override
  void initState() {
    super.initState();
    InterstitialAdService.isFullScreenAdShowing = true;

    _amountController = TextEditingController(text: '100');
    _amountController.addListener(_onAmountChanged);

    // Prefill phone: Prefer last successful M-PESA number if available,
    // otherwise format profile phone number to local Kenyan format (07XXXXXXXX / 01XXXXXXXX)
    final lastMpesa = PaystackService().getLastSuccessfulPhone(PaystackPaymentMethod.mpesa);
    final profileLocal = PaystackService.formatToLocalKenyaPhone(widget.phoneNumber);
    final initialPhone = (lastMpesa != null && lastMpesa.isNotEmpty)
        ? lastMpesa
        : profileLocal;

    _phoneController = TextEditingController(text: initialPhone);
    _phoneController.addListener(_onPhoneChanged);

    _phoneFocusNode.addListener(_handlePhoneFocusChange);
  }

  void _onAmountChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onPhoneChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handlePhoneFocusChange() {
    if (_phoneFocusNode.hasFocus) {
      _phoneController.selection = TextSelection.fromPosition(
        TextPosition(offset: _phoneController.text.length),
      );
    }
  }

  void _attachToActiveVerification(String reference, int amount) {
    _activeReference = reference;
    _verificationListener = PaystackVerificationListener(
      onStatusUpdate: (message) {
        if (mounted) {
          setState(() {
            _statusMessage = message;
          });
        }
      },
      onSuccess: () async {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isSuccess = true;
            _buttonText = 'Successful (+${amount * 10} XP)';
            _statusMessage = 'Donation confirmed! +${amount * 10} XP awarded to your balance!';
          });

          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            unawaited(ref.read(userProfileProvider.notifier).fetchProfileFromFirestore(user.uid));
          }

          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.pop(context);
            widget.onSuccess?.call();
          }
        }
      },
      onFailure: (errorMessage) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _buttonText = 'Donate';
            _statusMessage = null;
          });
          TopNotificationService().showNotification(
            context,
            errorMessage,
          );
        }
      },
    );
    PaystackService().addVerificationListener(reference, _verificationListener!);
  }

  @override
  void dispose() {
    InterstitialAdService.isFullScreenAdShowing = false;
    if (_activeReference != null && _verificationListener != null) {
      PaystackService().removeVerificationListener(_activeReference!, _verificationListener!);
    }
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _amountFocusNode.dispose();
    _phoneController.removeListener(_onPhoneChanged);
    _phoneFocusNode.removeListener(_handlePhoneFocusChange);
    _phoneFocusNode.dispose();
    _phoneController.dispose();
    _cardHolderController.dispose();
    _cardNumberController.dispose();
    _cardExpiryController.dispose();
    _cardCvvController.dispose();
    super.dispose();
  }

  void _onMethodSelected(PaystackPaymentMethod method) {
    if (_isLoading || _isSuccess) return;

    if (method == PaystackPaymentMethod.mastercard &&
        _currentAmount < PaystackService.minCardAmount) {
      TopNotificationService().showNotification(
        context,
        'Card payment does not support donations below Ksh.100.',
      );
    }

    setState(() {
      _selectedMethod = method;
      if (method == PaystackPaymentMethod.mpesa) {
        final lastMpesa = PaystackService().getLastSuccessfulPhone(PaystackPaymentMethod.mpesa);
        if (lastMpesa != null && lastMpesa.isNotEmpty) {
          _phoneController.text = lastMpesa;
        }
      } else if (method == PaystackPaymentMethod.airtelMoney) {
        final lastAirtel = PaystackService().getLastSuccessfulPhone(PaystackPaymentMethod.airtelMoney);
        if (lastAirtel != null && lastAirtel.isNotEmpty) {
          _phoneController.text = lastAirtel;
        }
      }
    });
  }

  bool _isCurrentInputValid() {
    if (_currentAmount < 3) return false;

    if (_selectedMethod == PaystackPaymentMethod.mastercard) {
      if (_currentAmount < PaystackService.minCardAmount) return false;
      return true;
    }
    return PaystackService.isValidKenyaPhone(_phoneController.text.trim());
  }

  Future<void> _handleDonate() async {
    if (_isLoading || _isSuccess) return;

    final amount = _currentAmount;
    if (amount < 3) {
      TopNotificationService().showNotification(
        context,
        'Minimum donation amount is Ksh.3.',
      );
      return;
    }

    if (_selectedMethod == PaystackPaymentMethod.mastercard &&
        amount < PaystackService.minCardAmount) {
      TopNotificationService().showNotification(
        context,
        'Card payment does not support donations below Ksh.100.',
      );
      return;
    }

    final phone = _phoneController.text.trim();
    if (_selectedMethod == PaystackPaymentMethod.mpesa ||
        _selectedMethod == PaystackPaymentMethod.airtelMoney) {
      if (!PaystackService.isValidKenyaPhone(phone)) {
        TopNotificationService().showNotification(
          context,
          'Please enter a valid 10-digit phone number (07XXXXXXXX or 01XXXXXXXX).',
        );
        return;
      }
    }

    if (_selectedMethod == PaystackPaymentMethod.mastercard) {
      final numCleaned = _cardNumberController.text.replaceAll(' ', '').trim();
      if (numCleaned.length < 16) {
        TopNotificationService().showNotification(
          context,
          'Please enter a valid 16-digit card number.',
        );
        return;
      }
      if (!_cardExpiryController.text.contains('/') || _cardExpiryController.text.trim().length < 4) {
        TopNotificationService().showNotification(
          context,
          'Please enter a valid expiration date (MM/YY).',
        );
        return;
      }
      if (_cardCvvController.text.trim().length < 3) {
        TopNotificationService().showNotification(
          context,
          'Please enter a valid 3-digit CVV.',
        );
        return;
      }
    }

    if (ConnectivityService().isOffline) {
      TopNotificationService().showNotification(
        context,
        'You are currently offline. Please check your internet connection.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _buttonText = 'Waiting';
      _statusMessage = 'Please complete the authorization on your phone.';
    });

    try {
      final userProfile = ref.read(userProfileProvider);
      final authEmail = FirebaseAuth.instance.currentUser?.email;
      final email = userProfile.email.trim().isNotEmpty
          ? userProfile.email.trim()
          : (authEmail != null && authEmail.trim().isNotEmpty
              ? authEmail.trim()
              : 'customer@mirrorlaikipia.app');

      final result = await PaystackService().processDonation(
        amountKes: amount,
        method: _selectedMethod,
        phoneNumber: phone,
        email: email,
        cardHolderName: _cardHolderController.text.trim(),
        cardNumber: _cardNumberController.text.trim(),
        expiryDate: _cardExpiryController.text.trim(),
        cvv: _cardCvvController.text.trim(),
      );

      if (!result.success || result.reference == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _buttonText = 'Donate';
            _statusMessage = null;
          });
          TopNotificationService().showNotification(
            context,
            result.message ?? 'Donation initialization failed. Please try again.',
          );
        }
        return;
      }

      final reference = result.reference!;

      await PaystackService().saveUnresolvedPayment(
        reference: reference,
        packageId: 'donation_$amount',
        method: _selectedMethod,
        phoneNumber: phone,
      );

      if (mounted) {
        setState(() {
          _buttonText = 'Waiting';
          _statusMessage = result.displayText ?? 'Please complete the authorization on your phone.';
        });
      }

      _attachToActiveVerification(reference, amount);

      unawaited(PaystackService().startBackgroundVerification(
        reference: reference,
        packageId: 'donation_$amount',
        method: _selectedMethod,
        phoneNumber: phone,
        cardNumber: _cardNumberController.text.trim(),
      ));
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _buttonText = 'Donate';
          _statusMessage = null;
        });
        TopNotificationService().showNotification(
          context,
          'Donation error: ${e.toString()}',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final phoneText = _phoneController.text.trim();
    final isPhoneValid = PaystackService.isValidKenyaPhone(phoneText);
    final phoneTextColor = (phoneText.isEmpty || isPhoneValid) ? Colors.white : Colors.redAccent;
    final isFormValid = _isCurrentInputValid();
    final amount = _currentAmount;

    return PopScope(
      canPop: true,
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              constraints: const BoxConstraints(maxWidth: 360),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 30,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF1E1E3A).withValues(alpha: 0.95),
                        const Color(0xFF101025).withValues(alpha: 0.98),
                      ],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 22),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.volunteer_activism_rounded, color: Color(0xFF20C8FF), size: 20),
                              SizedBox(width: 8),
                              Text(
                                'DONATE & EARN XP',
                                style: TextStyle(
                                  color: Color(0xFF20C8FF),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Container(
                            height: 1,
                            width: double.infinity,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 1. EDITABLE DONATION AMOUNT FIELD
                                _infoRow(
                                  'Amount (KES)',
                                  '',
                                  customValueWidget: Container(
                                    width: 140,
                                    height: 38,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: (amount > 0 && amount < 3)
                                            ? Colors.redAccent
                                            : const Color(0xFF20C8FF).withValues(alpha: 0.5),
                                        width: 1.2,
                                      ),
                                    ),
                                    alignment: Alignment.centerRight,
                                    child: TextField(
                                      controller: _amountController,
                                      focusNode: _amountFocusNode,
                                      textAlign: TextAlign.right,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(6),
                                      ],
                                      style: TextStyle(
                                        color: (amount > 0 && amount < 3) ? Colors.redAccent : Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        counterText: '',
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.zero,
                                        prefixText: 'Ksh. ',
                                        prefixStyle: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.5),
                                          fontSize: 13,
                                        ),
                                        hintText: '100',
                                        hintStyle: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.35),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                // Preset Amount Chips
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [10, 50, 100, 250, 500].map((preset) {
                                      final isSelected = amount == preset;
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 6, bottom: 12),
                                        child: InkWell(
                                          onTap: () {
                                            _amountController.text = preset.toString();
                                          },
                                          borderRadius: BorderRadius.circular(8),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? const Color(0xFF20C8FF).withValues(alpha: 0.25)
                                                  : Colors.white.withValues(alpha: 0.05),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: isSelected ? const Color(0xFF20C8FF) : Colors.white12,
                                              ),
                                            ),
                                            child: Text(
                                              'Ksh.$preset',
                                              style: TextStyle(
                                                color: isSelected ? const Color(0xFF20C8FF) : Colors.white70,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),

                                // XP Calculation Preview Row
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF20C8FF).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFF20C8FF).withValues(alpha: 0.25)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(Icons.stars_rounded, color: Colors.amber, size: 16),
                                          SizedBox(width: 6),
                                          Text(
                                            'Reward Earned:',
                                            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        '+$_expectedXp XP (10 XP / KSh)',
                                        style: const TextStyle(
                                          color: Color(0xFF20C8FF),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // 2. EDITABLE PHONE NUMBER FIELD
                                _infoRow(
                                  'Phone',
                                  '',
                                  customValueWidget: Container(
                                    width: 155,
                                    height: 36,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: (phoneText.isNotEmpty && !isPhoneValid)
                                            ? Colors.redAccent
                                            : const Color(0xFF7B5CFF).withValues(alpha: 0.4),
                                        width: 1.2,
                                      ),
                                    ),
                                    alignment: Alignment.centerRight,
                                    child: TextField(
                                      controller: _phoneController,
                                      focusNode: _phoneFocusNode,
                                      textAlign: TextAlign.right,
                                      keyboardType: TextInputType.phone,
                                      maxLength: 10,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(10),
                                      ],
                                      style: TextStyle(
                                        color: phoneTextColor,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        counterText: '',
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.zero,
                                        hintText: '07XXXXXXXX',
                                        hintStyle: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.35),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 12),
                                const Text(
                                  'Preferred Payment Method',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 10),

                                // PAYMENT METHOD SELECTOR
                                Row(
                                  children: [
                                    Expanded(
                                      child: _paymentMethodButton(
                                        method: PaystackPaymentMethod.mpesa,
                                        title: 'M-PESA',
                                        brandColor: const Color(0xFF00A85A),
                                        logoWidget: const _MpesaBadge(),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _paymentMethodButton(
                                        method: PaystackPaymentMethod.airtelMoney,
                                        title: 'Airtel Money',
                                        brandColor: const Color(0xFFED1C24),
                                        logoWidget: const _AirtelBadge(),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _paymentMethodButton(
                                        method: PaystackPaymentMethod.mastercard,
                                        title: 'Mastercard',
                                        brandColor: const Color(0xFFF79E1B),
                                        logoWidget: const _MastercardBadge(),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 16),
                                _buildMethodSpecificFields(),

                                if (_statusMessage != null) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: _isSuccess
                                          ? Colors.green.withValues(alpha: 0.15)
                                          : Colors.blue.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: _isSuccess ? Colors.green : Colors.blueAccent,
                                      ),
                                    ),
                                    child: Text(
                                      _statusMessage!,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: _isSuccess ? Colors.greenAccent : Colors.white,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 20),

                                // DONATE BUTTON
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: (_isLoading || _isSuccess || !isFormValid)
                                        ? null
                                        : _handleDonate,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _isSuccess
                                          ? const Color(0xFF00A85A)
                                          : const Color(0xFF20C8FF),
                                      disabledBackgroundColor: const Color(0xFF20C8FF).withValues(alpha: 0.35),
                                      foregroundColor: Colors.white,
                                      disabledForegroundColor: Colors.white38,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: Text(
                                      _isLoading
                                          ? _buttonText
                                          : (_isSuccess ? _buttonText : 'Donate Ksh.$amount (+$_expectedXp XP)'),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (!_isLoading && !_isSuccess)
                                  Center(
                                    child: TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: Text(
                                        'Cancel',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.5),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        top: 10,
                        right: 12,
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          tooltip: 'Close',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMethodSpecificFields() {
    if (_selectedMethod == PaystackPaymentMethod.mastercard) {
      final amount = _currentAmount;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (amount < 100)
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
              ),
              child: const Text(
                'Note: Card payments require a minimum donation of Ksh.100.',
                style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          _cardInput(controller: _cardNumberController, hintText: 'Card Number (16 digits)', icon: Icons.credit_card, keyboardType: TextInputType.number, maxLength: 19),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _cardInput(controller: _cardExpiryController, hintText: 'MM/YY', icon: Icons.date_range, keyboardType: TextInputType.datetime, maxLength: 5),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _cardInput(controller: _cardCvvController, hintText: 'CVV', icon: Icons.lock_outline, keyboardType: TextInputType.number, maxLength: 4),
              ),
            ],
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _cardInput({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required TextInputType keyboardType,
    int? maxLength,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF13132B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLength: maxLength,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          counterText: '',
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: InputBorder.none,
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
          prefixIcon: Icon(icon, color: Colors.white54, size: 16),
          prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 16),
        ),
      ),
    );
  }

  Widget _paymentMethodButton({
    required PaystackPaymentMethod method,
    required String title,
    required Color brandColor,
    required Widget logoWidget,
  }) {
    final isSelected = _selectedMethod == method;
    return InkWell(
      onTap: () => _onMethodSelected(method),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? brandColor.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? brandColor : Colors.white10,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            logoWidget,
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {Widget? customValueWidget}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF20C8FF),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (customValueWidget != null)
            customValueWidget
          else
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }
}

class _MpesaBadge extends StatelessWidget {
  const _MpesaBadge();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/payment/mpesa.svg',
      width: 38,
      height: 16,
      fit: BoxFit.contain,
      placeholderBuilder: (_) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(color: const Color(0xFF00A85A), borderRadius: BorderRadius.circular(3)),
        child: const Text('M-PESA', style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _AirtelBadge extends StatelessWidget {
  const _AirtelBadge();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/payment/airtel.svg',
      width: 38,
      height: 16,
      fit: BoxFit.contain,
      placeholderBuilder: (_) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(color: const Color(0xFFED1C24), borderRadius: BorderRadius.circular(3)),
        child: const Text('Airtel', style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _MastercardBadge extends StatelessWidget {
  const _MastercardBadge();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/payment/mastercard.svg',
      width: 32,
      height: 16,
      fit: BoxFit.contain,
      placeholderBuilder: (_) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(color: const Color(0xFFF79E1B), borderRadius: BorderRadius.circular(3)),
        child: const Text('Card', style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
