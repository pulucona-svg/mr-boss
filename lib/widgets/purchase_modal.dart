import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/subscription_model.dart';
import '../providers/service_providers.dart';
import '../services/connectivity_service.dart';
import '../services/interstitial_ad_service.dart';
import '../services/paystack_service.dart';

class PurchaseModal extends ConsumerStatefulWidget {
  final SubscriptionPackage package;
  final String phoneNumber;
  final VoidCallback onSuccess;

  const PurchaseModal({
    super.key,
    required this.package,
    required this.phoneNumber,
    required this.onSuccess,
  });

  @override
  ConsumerState<PurchaseModal> createState() => _PurchaseModalState();
}

class _PurchaseModalState extends ConsumerState<PurchaseModal> {
  String _buttonText = 'Purchase';
  String? _statusMessage;
  bool _isLoading = false;
  bool _isSuccess = false;

  // Selected payment method (defaults to M-PESA)
  PaystackPaymentMethod _selectedMethod = PaystackPaymentMethod.mpesa;

  // Phone number controller & focus node
  late TextEditingController _phoneController;
  final FocusNode _phoneFocusNode = FocusNode();

  // Card details controllers
  final TextEditingController _cardHolderController = TextEditingController();
  final TextEditingController _cardNumberController = TextEditingController();
  final TextEditingController _cardExpiryController = TextEditingController();
  final TextEditingController _cardCvvController = TextEditingController();

  @override
  void initState() {
    super.initState();
    InterstitialAdService.isFullScreenAdShowing = true;

    // Prefill phone: Prefer last successful M-PESA number if available,
    // otherwise format profile phone number to local Kenyan format (07XXXXXXXX / 01XXXXXXXX)
    final lastMpesa = PaystackService().getLastSuccessfulPhone(PaystackPaymentMethod.mpesa);
    final profileLocal = PaystackService.formatToLocalKenyaPhone(widget.phoneNumber);
    final initialPhone = (lastMpesa != null && lastMpesa.isNotEmpty)
        ? lastMpesa
        : profileLocal;

    _phoneController = TextEditingController(text: initialPhone);
    _phoneController.addListener(_onPhoneChanged);

    // Keep cursor at the end when the phone field receives focus
    _phoneFocusNode.addListener(_handlePhoneFocusChange);
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

  @override
  void dispose() {
    InterstitialAdService.isFullScreenAdShowing = false;
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
        widget.package.price < PaystackService.minCardAmount) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text('Card payment does not support payments below Ksh.100.'),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFC62828),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }

    // Switch method and load method defaults
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
    if (_selectedMethod == PaystackPaymentMethod.mastercard) {
      if (widget.package.price < PaystackService.minCardAmount) return false;
      return true;
    }
    return PaystackService.isValidKenyaPhone(_phoneController.text.trim());
  }

  Future<void> _handlePurchase() async {
    if (_isLoading || _isSuccess) return;

    // 1. Guard check for Mastercard below KES 100
    if (_selectedMethod == PaystackPaymentMethod.mastercard &&
        widget.package.price < PaystackService.minCardAmount) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text('Card payment does not support payments below Ksh.100.'),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFC62828),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    // 2. Validate mobile money phone number
    final phone = _phoneController.text.trim();
    if (_selectedMethod == PaystackPaymentMethod.mpesa ||
        _selectedMethod == PaystackPaymentMethod.airtelMoney) {
      if (!PaystackService.isValidKenyaPhone(phone)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid 10-digit phone number (07XXXXXXXX or 01XXXXXXXX).'),
          ),
        );
        return;
      }
    }

    // 3. Validate card fields if Mastercard selected
    if (_selectedMethod == PaystackPaymentMethod.mastercard) {
      final numCleaned = _cardNumberController.text.replaceAll(' ', '').trim();
      if (numCleaned.length < 16) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid 16-digit card number.')),
        );
        return;
      }
      if (!_cardExpiryController.text.contains('/') || _cardExpiryController.text.trim().length < 4) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid expiration date (MM/YY).')),
        );
        return;
      }
      if (_cardCvvController.text.trim().length < 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid 3-digit CVV.')),
        );
        return;
      }
    }

    // 4. Connectivity check
    if (ConnectivityService().isOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are currently offline. Please check your internet connection.'),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _buttonText = 'Waiting...';
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

      final result = await PaystackService().processPayment(
        package: widget.package,
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
            _buttonText = 'Purchase';
            _statusMessage = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.message ?? 'Payment failed. Please try again.')),
          );
        }
        return;
      }

      final reference = result.reference!;

      // Persist pending Paystack transaction reference locally immediately
      await PaystackService().saveUnresolvedPayment(
        reference: reference,
        packageId: widget.package.id,
        method: _selectedMethod,
        phoneNumber: phone,
      );

      if (mounted) {
        setState(() {
          _buttonText = 'Waiting for payment confirmation...';
          _statusMessage = result.displayText ?? 'Please complete the authorization on your phone.';
        });
      }

      // Safe verification polling loop (up to 180 seconds per Paystack Kenya mobile-money documentation)
      const int maxPollSeconds = 180;
      const int pollIntervalSeconds = 3;
      final int maxAttempts = maxPollSeconds ~/ pollIntervalSeconds;

      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        if (!mounted) return;

        await Future.delayed(const Duration(seconds: pollIntervalSeconds));
        if (!mounted) return;

        // Check if connection was lost while awaiting authorization
        if (ConnectivityService().isOffline) {
          if (mounted) {
            setState(() {
              _statusMessage = 'Payment confirmation is pending. We will verify your payment when connectivity returns.';
            });
          }
          // Do not falsely report failure; continue waiting or allow background sync
          continue;
        }

        final verifyResult = await PaystackService().verifyPayment(reference);

        if (verifyResult.success || verifyResult.alreadyFulfilled) {
          // Success confirmed! Save successful phone number locally and clean up unresolved reference
          if (_selectedMethod == PaystackPaymentMethod.mpesa ||
              _selectedMethod == PaystackPaymentMethod.airtelMoney) {
            await PaystackService().saveLastSuccessfulPhone(_selectedMethod, phone);
          } else if (_selectedMethod == PaystackPaymentMethod.mastercard) {
            final cardNum = _cardNumberController.text.replaceAll(' ', '');
            if (cardNum.length >= 4) {
              await PaystackService().saveLastCardMetadata(
                brand: 'Mastercard',
                last4: cardNum.substring(cardNum.length - 4),
              );
            }
          }

          await PaystackService().removeUnresolvedPayment(reference);

          if (mounted) {
            setState(() {
              _isLoading = false;
              _isSuccess = true;
              _buttonText = 'Successful';
              _statusMessage = 'Payment confirmed! Activating subscription...';
            });

            await Future.delayed(const Duration(seconds: 1));
            if (mounted) {
              Navigator.pop(context);
              widget.onSuccess();
            }
          }
          return;
        } else if (verifyResult.status == 'failed') {
          // Terminal failure: Provider or PIN error
          await PaystackService().removeUnresolvedPayment(reference);
          if (mounted) {
            setState(() {
              _isLoading = false;
              _buttonText = 'Purchase';
              _statusMessage = null;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(verifyResult.message)),
            );
          }
          return;
        } else if (verifyResult.status == 'abandoned') {
          await PaystackService().removeUnresolvedPayment(reference);
          if (mounted) {
            setState(() {
              _isLoading = false;
              _buttonText = 'Purchase';
              _statusMessage = null;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Payment was not completed or expired. Please try again.'),
              ),
            );
          }
          return;
        } else if (verifyResult.status == 'reversed') {
          await PaystackService().removeUnresolvedPayment(reference);
          if (mounted) {
            setState(() {
              _isLoading = false;
              _buttonText = 'Purchase';
              _statusMessage = null;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Payment was reversed.')),
            );
          }
          return;
        } else {
          // Status is still pending, ongoing, or pay_offline
          if (verifyResult.displayText != null && mounted) {
            setState(() {
              _statusMessage = verifyResult.displayText;
            });
          }
        }
      }

      // Polling reached 180s without final resolution
      if (mounted) {
        setState(() {
          _isLoading = false;
          _buttonText = 'Purchase';
          _statusMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Payment confirmation timed out. If you already authorized on your phone, your subscription will activate automatically once confirmed.',
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _buttonText = 'Purchase';
          _statusMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment error: ${e.toString()}')),
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

    return PopScope(
      canPop: false,
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              constraints: const BoxConstraints(maxWidth: 350),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 22),
                      const Text(
                        'CONFIRM PAYMENT',
                        style: TextStyle(
                          color: Color(0xFF7B5CFF),
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        height: 1,
                        width: double.infinity,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _infoRow('Package', widget.package.title),
                            _infoRow('Amount', 'Ksh.${widget.package.price.toInt()}'),

                            // 1. EDITABLE HORIZONTAL PHONE NUMBER FIELD
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
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    errorBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none,
                                    hintText: '07XXXXXXXX',
                                    hintStyle: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.35),
                                      fontSize: 12,
                                    ),
                                  ),
                                  onTap: () {
                                    _phoneController.selection = TextSelection.fromPosition(
                                      TextPosition(offset: _phoneController.text.length),
                                    );
                                  },
                                ),
                              ),
                            ),

                            const SizedBox(height: 14),

                            // 2. INSTRUCTION TEXT DIRECTLY ABOVE BUTTONS
                            const Text(
                              'Please select your preferred method of payment',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),

                            const SizedBox(height: 12),

                            // 3. THREE HORIZONTAL PAYMENT-METHOD BUTTONS
                            Row(
                              children: [
                                Expanded(
                                  child: _paymentMethodButton(
                                    method: PaystackPaymentMethod.mpesa,
                                    title: 'M-PESA',
                                    brandColor: const Color(0xFF00A85A),
                                    logoWidget: const _MpesaLogoBadge(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _paymentMethodButton(
                                    method: PaystackPaymentMethod.airtelMoney,
                                    title: 'Airtel Money',
                                    brandColor: const Color(0xFFED1C24),
                                    logoWidget: const _AirtelLogoBadge(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _paymentMethodButton(
                                    method: PaystackPaymentMethod.mastercard,
                                    title: 'Mastercard',
                                    brandColor: const Color(0xFFF79E1B),
                                    logoWidget: const _MastercardLogoBadge(),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 18),

                            // DYNAMIC SECTION BASED ON METHOD
                            _buildPaymentMethodDetailsSection(),

                            const SizedBox(height: 24),

                            // SINGLE PURCHASE BUTTON
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: (_isLoading || _isSuccess || !isFormValid)
                                    ? null
                                    : _handlePurchase,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isSuccess
                                      ? const Color(0xFF00A85A)
                                      : const Color(0xFF7B5CFF),
                                  disabledBackgroundColor: const Color(0xFF7B5CFF).withValues(alpha: 0.35),
                                  foregroundColor: Colors.white,
                                  disabledForegroundColor: Colors.white38,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 0,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (_isLoading)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 12),
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    Flexible(
                                      child: Text(
                                        _buttonText,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
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
                            const SizedBox(height: 12),
                          ],
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

  Widget _paymentMethodButton({
    required PaystackPaymentMethod method,
    required String title,
    required Color brandColor,
    required Widget logoWidget,
  }) {
    final isSelected = _selectedMethod == method;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onMethodSelected(method),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? brandColor.withValues(alpha: 0.16)
                : const Color(0xFF16162E).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? brandColor : Colors.white.withValues(alpha: 0.12),
              width: isSelected ? 1.8 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: brandColor.withValues(alpha: 0.25),
                      blurRadius: 8,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 22, child: Center(child: logoWidget)),
              const SizedBox(height: 4),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white60,
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethodDetailsSection() {
    if (_isLoading && _statusMessage != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF7B5CFF).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF7B5CFF).withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF7B5CFF),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _statusMessage!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    switch (_selectedMethod) {
      case PaystackPaymentMethod.mpesa:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF00A85A).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF00A85A).withValues(alpha: 0.3)),
          ),
          child: Text(
            'You will receive an M-Pesa prompt requesting payment of Ksh.${widget.package.price.toInt()}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF43B02A),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        );

      case PaystackPaymentMethod.airtelMoney:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFED1C24).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFED1C24).withValues(alpha: 0.3)),
          ),
          child: Text(
            'You will receive an Airtel Money prompt requesting payment of Ksh.${widget.package.price.toInt()}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFFF6B6B),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        );

      case PaystackPaymentMethod.mastercard:
        // Package below KES 100 restriction
        if (widget.package.price < PaystackService.minCardAmount) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.35)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Color(0xFFFFB74D), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Card payment does not support payments below Ksh.100.',
                    style: TextStyle(
                      color: Color(0xFFFFB74D),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Amount >= KES 100: Modern Card Form
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'CARD DETAILS',
                    style: TextStyle(
                      color: Color(0xFFF79E1B),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  _MastercardLogoBadge(),
                ],
              ),
              const SizedBox(height: 12),
              _cardInputField(
                controller: _cardHolderController,
                hintText: 'Cardholder Name',
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 10),
              _cardInputField(
                controller: _cardNumberController,
                hintText: '0000 0000 0000 0000',
                icon: Icons.credit_card,
                keyboardType: TextInputType.number,
                maxLength: 19,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _cardInputField(
                      controller: _cardExpiryController,
                      hintText: 'MM/YY',
                      icon: Icons.date_range,
                      keyboardType: TextInputType.datetime,
                      maxLength: 5,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _cardInputField(
                      controller: _cardCvvController,
                      hintText: 'CVV',
                      icon: Icons.lock_outline,
                      keyboardType: TextInputType.number,
                      maxLength: 3,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
    }
  }

  Widget _cardInputField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
  }) {
    return Container(
      height: 40,
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

  Widget _infoRow(String label, String value, {Widget? customValueWidget}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF7B5CFF),
              fontSize: 14,
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
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }
}

/// Official Safaricom M-PESA Logo Badge
class _MpesaLogoBadge extends StatelessWidget {
  const _MpesaLogoBadge();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/payment/mpesa.svg',
      width: 44,
      height: 18,
      fit: BoxFit.contain,
      placeholderBuilder: (_) => _fallback(),
    );
  }

  Widget _fallback() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF00A85A),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'M-PESA',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 9.5,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Official Airtel Money Logo Badge
class _AirtelLogoBadge extends StatelessWidget {
  const _AirtelLogoBadge();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/payment/airtel.svg',
      width: 44,
      height: 18,
      fit: BoxFit.contain,
      placeholderBuilder: (_) => _fallback(),
    );
  }

  Widget _fallback() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFED1C24),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'airtel money',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 8.5,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Official Mastercard Logo Badge (Red & Yellow Interlocking Circles)
class _MastercardLogoBadge extends StatelessWidget {
  const _MastercardLogoBadge();

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/payment/mastercard.svg',
      width: 32,
      height: 18,
      fit: BoxFit.contain,
      placeholderBuilder: (_) => _fallback(),
    );
  }

  Widget _fallback() {
    return SizedBox(
      width: 28,
      height: 16,
      child: CustomPaint(
        painter: _MastercardPainter(),
      ),
    );
  }
}

class _MastercardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.height * 0.44;
    final centerY = size.height / 2;

    final leftCenter = Offset(size.width * 0.38, centerY);
    final rightCenter = Offset(size.width * 0.62, centerY);

    final redPaint = Paint()..color = const Color(0xFFEB001B);
    final yellowPaint = Paint()..color = const Color(0xFFF79E1B);

    canvas.drawCircle(leftCenter, radius, redPaint);

    final pathLeft = Path()..addOval(Rect.fromCircle(center: leftCenter, radius: radius));
    final pathRight = Path()..addOval(Rect.fromCircle(center: rightCenter, radius: radius));

    canvas.save();
    canvas.clipPath(pathLeft);
    canvas.drawCircle(rightCenter, radius, Paint()..color = const Color(0xFFFF5F00));
    canvas.restore();

    canvas.save();
    canvas.clipPath(Path.combine(PathOperation.difference, pathRight, pathLeft));
    canvas.drawCircle(rightCenter, radius, yellowPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
