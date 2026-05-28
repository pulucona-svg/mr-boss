class SubscriptionPackage {
  final String id;
  final String title;
  final double price;
  final Duration duration;

  const SubscriptionPackage({
    required this.id,
    required this.title,
    required this.price,
    required this.duration,
  });
}

class SubscriptionHistory {
  final String id;
  final String packageTitle;
  final double amount;
  final String transactionCode;
  final DateTime purchaseDate;
  final DateTime expiryDate;
  final bool isActive;

  SubscriptionHistory({
    required this.id,
    required this.packageTitle,
    required this.amount,
    required this.transactionCode,
    required this.purchaseDate,
    required this.expiryDate,
    this.isActive = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'packageTitle': packageTitle,
    'amount': amount,
    'transactionCode': transactionCode,
    'purchaseDate': purchaseDate.toIso8601String(),
    'expiryDate': expiryDate.toIso8601String(),
    'isActive': isActive,
  };

  factory SubscriptionHistory.fromJson(Map<String, dynamic> json) => SubscriptionHistory(
    id: json['id'],
    packageTitle: json['packageTitle'],
    amount: json['amount'],
    transactionCode: json['transactionCode'],
    purchaseDate: DateTime.parse(json['purchaseDate']),
    expiryDate: DateTime.parse(json['expiryDate']),
    isActive: json['isActive'] ?? true,
  );
}
