import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/subscription_model.dart';
import '../services/subscription_service.dart';

class PurchaseModal extends StatefulWidget {
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
  State<PurchaseModal> createState() => _PurchaseModalState();
}

class _PurchaseModalState extends State<PurchaseModal> {
  String _buttonText = 'Purchase';
  bool _isLoading = false;
  bool _isSuccess = false;
  late TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.phoneNumber);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handlePurchase() async {
    if (_isLoading || _isSuccess) return;

    setState(() {
      _isLoading = true;
      _buttonText = 'Waiting...';
    });

    try {
      await SubscriptionService().addSubscription(widget.package);
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSuccess = true;
          _buttonText = 'Successful';
        });

        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.pop(context);
          widget.onSuccess();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _buttonText = 'Purchase';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment failed. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 30),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
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
                      const Color(0xFF1E1E3A).withValues(alpha: 0.8),
                      const Color(0xFF101025).withValues(alpha: 0.9),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 24),
                    const Text(
                      'CONFIRM PAYMENT',
                      style: TextStyle(
                        color: Color(0xFF7B5CFF),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      height: 1,
                      width: double.infinity,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          _infoRow('Package', widget.package.title),
                          _infoRow('Amount', 'Ksh.${widget.package.price.toInt()}'),
                          _infoRow(
                            'Phone', 
                            '', 
                            customValueWidget: SizedBox(
                              width: 120,
                              height: 30,
                              child: TextField(
                                controller: _phoneController,
                                textAlign: TextAlign.right,
                                keyboardType: TextInputType.phone,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  // This prevents weird yellow lines/errors in some contexts
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  errorBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF20C8FF).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF20C8FF).withValues(alpha: 0.2)),
                            ),
                            child: Text(
                              'You will receive an M-Pesa prompt requesting payment of Ksh.${widget.package.price.toInt()}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF20C8FF),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _handlePurchase,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isSuccess ? const Color(0xFF00A85A) : const Color(0xFF7B5CFF),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 18),
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
                                  Text(
                                    _buttonText,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (!_isLoading && !_isSuccess)
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          const SizedBox(height: 20),
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
    );
  }

  Widget _infoRow(String label, String value, {Widget? customValueWidget}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
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
