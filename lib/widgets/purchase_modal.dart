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
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 30),
          decoration: BoxDecoration(
            color: const Color(0xFF181739),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white12, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Text(
                  'CONFIRM PAYMENT',
                  style: TextStyle(
                    color: Color(0xFF7B5CFF),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Divider(color: Colors.white10, height: 30),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    _infoRow('Package', widget.package.title),
                    _infoRow('Amount', 'Ksh.${widget.package.price.toInt()}'),
                    _infoRow('Phone', widget.phoneNumber),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'You will receive an M-Pesa prompt requesting payment of Ksh.${widget.package.price.toInt()}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF20C8FF),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _handlePurchase,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isSuccess ? const Color(0xFF00A85A) : const Color(0xFF7B5CFF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
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
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            Text(
                              _buttonText,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!_isLoading && !_isSuccess)
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
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
