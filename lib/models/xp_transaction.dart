import 'package:cloud_firestore/cloud_firestore.dart';

class XPTransaction {
  final String id;
  final String userId;
  final String type; // 'donation' | 'rewarded_ad'
  final String title;
  final String description;
  final int xpAmount;
  final int? kesAmount;
  final String? paymentMethod;
  final String? paystackReference;
  final String? operatorReceiptNumber;
  final String status;
  final DateTime createdAt;

  XPTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.description,
    required this.xpAmount,
    this.kesAmount,
    this.paymentMethod,
    this.paystackReference,
    this.operatorReceiptNumber,
    required this.status,
    required this.createdAt,
  });

  bool get isDonation => type == 'donation';
  bool get isAdReward => type == 'rewarded_ad' || type == 'rewarded_video' || type == 'rewarded_interstitial';

  factory XPTransaction.fromFirestore(Map<String, dynamic> data, String docId) {
    DateTime parsedDate;
    final created = data['createdAt'];
    if (created is Timestamp) {
      parsedDate = created.toDate();
    } else if (created is String) {
      parsedDate = DateTime.tryParse(created) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return XPTransaction(
      id: docId,
      userId: data['userId'] ?? '',
      type: data['type'] ?? 'unknown',
      title: data['title'] ?? (data['type'] == 'donation' ? 'Direct Donation' : 'Rewarded Ad'),
      description: data['description'] ?? '',
      xpAmount: (data['xpAmount'] as num?)?.toInt() ?? 0,
      kesAmount: (data['kesAmount'] as num?)?.toInt(),
      paymentMethod: data['paymentMethod'],
      paystackReference: data['paystackReference'],
      operatorReceiptNumber: data['operatorReceiptNumber'],
      status: data['status'] ?? 'success',
      createdAt: parsedDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'type': type,
      'title': title,
      'description': description,
      'xpAmount': xpAmount,
      'kesAmount': kesAmount,
      'paymentMethod': paymentMethod,
      'paystackReference': paystackReference,
      'operatorReceiptNumber': operatorReceiptNumber,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
