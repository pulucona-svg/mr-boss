import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/subscription_model.dart';
import '../services/subscription_service.dart';
import '../widgets/purchase_modal.dart';
import '../providers/user_provider.dart';
import '../widgets/countdown_timer.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  final List<SubscriptionPackage> _packages = const [
    SubscriptionPackage(id: 'daily', title: 'Daily Pass', price: 5, duration: Duration(days: 1)),
    SubscriptionPackage(id: 'weekly', title: 'Weekly Pass', price: 30, duration: Duration(days: 7)),
    SubscriptionPackage(id: 'monthly', title: 'Monthly Pass', price: 100, duration: Duration(days: 30)),
    SubscriptionPackage(id: 'semester', title: 'Semester Pass', price: 300, duration: Duration(days: 120)),
    SubscriptionPackage(id: 'yearly', title: 'Yearly Pass', price: 500, duration: Duration(days: 365)),
  ];

  void _showPurchaseModal(SubscriptionPackage package) {
    final userProfile = ref.read(userProfileProvider);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PurchaseModal(
        package: package,
        phoneNumber: userProfile.phone,
        onSuccess: () {
          _showSuccessMessage();
          setState(() {});
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
                'Subscription successful. Enjoy ad-free access!',
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

  void _confirmTermination(SubscriptionHistory sub) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A3F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Terminate Package?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'Terminating this package does not provide any refund. Are you sure you want to proceed?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () {
              SubscriptionService().terminateSubscription(sub.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Package terminated successfully.')),
              );
            },
            child: const Text('Terminate', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
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
          final service = SubscriptionService();
          final activeSub = service.activeSubscription;
          final queuedSubs = service.queuedSubscriptions;
          final history = service.history.where((s) => 
              s.status == SubscriptionStatus.expired || 
              s.status == SubscriptionStatus.terminated).toList();
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (activeSub != null) ...[
                  const Text(
                    'ACTIVE PACKAGE',
                    style: TextStyle(
                      color: Color(0xFF7B5CFF),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _activePackageCard(activeSub),
                  const SizedBox(height: 30),
                ],

                if (queuedSubs.isNotEmpty) ...[
                  const Text(
                    'QUEUED PACKAGES',
                    style: TextStyle(
                      color: Color(0xFF20C8FF),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...queuedSubs.map((s) => _queuedPackageCard(s)),
                  const SizedBox(height: 30),
                ],

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

  Widget _activePackageCard(SubscriptionHistory sub) {
    final dateFormat = DateFormat('MMM d, yyyy • HH:mm');

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B5CFF), Color(0xFF5C3DFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B5CFF).withOpacity(0.3),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sub.packageTitle,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const Text('Currently Active', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                    IconButton(
                      onPressed: () => _confirmTermination(sub),
                      icon: const Icon(Icons.cancel_outlined, color: Colors.white70),
                      tooltip: 'Terminate Package',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _infoColumn('Activated On', dateFormat.format(sub.activationDate)),
                    _infoColumn('Expires On', dateFormat.format(sub.expiryDate)),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined, color: Colors.white, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CountdownTimer(
                          expiryDate: sub.expiryDate,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _queuedPackageCard(SubscriptionHistory sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF20C8FF).withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF20C8FF).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF20C8FF).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.queue_play_next, color: Color(0xFF20C8FF), size: 18),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sub.packageTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const Text('Waiting in Queue', style: TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _confirmTermination(sub),
            child: const Text('Cancel', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _infoColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
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
                    color: const Color(0xFF7B5CFF).withOpacity(0.1),
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
    final isTerminated = history.status == SubscriptionStatus.terminated;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
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
                  color: isTerminated 
                      ? Colors.red.withOpacity(0.1) 
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isTerminated ? 'TERMINATED' : 'EXPIRED',
                  style: TextStyle(
                    color: isTerminated ? Colors.redAccent : Colors.white38,
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
          if (!isTerminated) _historyRow('Expired', dateFormat.format(history.expiryDate))
          else _historyRow('Terminated', dateFormat.format(DateTime.now())), // Ideally use actual termination date
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
          Text(label, style: const TextStyle(color: Color(0xFF7B5CFF), fontSize: 11, fontWeight: FontWeight.bold)),
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
        color: Colors.white.withOpacity(0.02),
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
