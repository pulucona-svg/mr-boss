import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/subscription_model.dart';
import '../services/subscription_service.dart';
import '../widgets/purchase_modal.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final List<SubscriptionPackage> _packages = const [
    SubscriptionPackage(id: 'daily', title: 'Daily Pass', price: 5, duration: Duration(days: 1)),
    SubscriptionPackage(id: 'weekly', title: 'Weekly Pass', price: 30, duration: Duration(days: 7)),
    SubscriptionPackage(id: 'monthly', title: 'Monthly Pass', price: 100, duration: Duration(days: 30)),
    SubscriptionPackage(id: 'semester', title: 'Semester Pass', price: 300, duration: Duration(days: 120)),
    SubscriptionPackage(id: 'yearly', title: 'Yearly Pass', price: 500, duration: Duration(days: 365)),
  ];

  void _showPurchaseModal(SubscriptionPackage package) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PurchaseModal(
        package: package,
        phoneNumber: '0712345678', // This could be fetched from user provider
        onSuccess: () {
          _showSuccessMessage();
          setState(() {}); // Refresh list
        },
      ),
    );
  }

  void _showSuccessMessage() {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'You can now access materials without ads. Go back to download.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF00A85A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070716),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Premium Subscription',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListenableBuilder(
        listenable: SubscriptionService(),
        builder: (context, child) {
          final history = SubscriptionService().history;
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SELECT A PACKAGE',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                ..._packages.map((p) => _packageCard(p)),
                
                const SizedBox(height: 40),
                const Text(
                  'SUBSCRIPTION HISTORY',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                if (history.isEmpty)
                  _emptyHistory()
                else
                  ...history.map((h) => _historyCard(h)),
                
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _packageCard(SubscriptionPackage package) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF181739), Color(0xFF1D1B4D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12, width: 0.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showPurchaseModal(package),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B5CFF).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.star_rounded, color: Color(0xFF7B5CFF)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        package.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Full access for ${package.duration.inDays} days',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Ksh.${package.price.toInt()}',
                  style: const TextStyle(
                    color: Color(0xFF20C8FF),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _historyCard(SubscriptionHistory history) {
    final dateFormat = DateFormat('MMM d, yyyy • HH:mm');
    final isExpired = history.expiryDate.isBefore(DateTime.now());
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                history.packageTitle,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isExpired 
                      ? Colors.red.withValues(alpha: 0.1) 
                      : const Color(0xFF00A85A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isExpired ? 'EXPIRED' : 'ACTIVE',
                  style: TextStyle(
                    color: isExpired ? Colors.red : const Color(0xFF00A85A),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _historyRow('Transaction', history.transactionCode),
          _historyRow('Amount', 'Ksh.${history.amount.toInt()}'),
          _historyRow('Purchase', dateFormat.format(history.purchaseDate)),
          _historyRow('Expires', dateFormat.format(history.expiryDate)),
        ],
      ),
    );
  }

  Widget _historyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          Text(value, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _emptyHistory() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10, width: 0.5),
      ),
      child: const Column(
        children: [
          Icon(Icons.history, color: Colors.white12, size: 48),
          SizedBox(height: 12),
          Text(
            'No subscription history found',
            style: TextStyle(color: Colors.white24),
          ),
        ],
      ),
    );
  }
}
