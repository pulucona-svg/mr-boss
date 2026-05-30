enum SubscriptionStatus {
  active,
  queued,
  expired,
  terminated,
}

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
  final DateTime activationDate;
  final DateTime expiryDate;
  final SubscriptionStatus status;
  final int downloadCount;

  SubscriptionHistory({
    required this.id,
    required this.packageTitle,
    required this.amount,
    required this.transactionCode,
    required this.purchaseDate,
    required this.activationDate,
    required this.expiryDate,
    required this.status,
    this.downloadCount = 0,
  });

  SubscriptionHistory copyWith({
    SubscriptionStatus? status,
    DateTime? activationDate,
    DateTime? expiryDate,
    int? downloadCount,
  }) {
    return SubscriptionHistory(
      id: id,
      packageTitle: packageTitle,
      amount: amount,
      transactionCode: transactionCode,
      purchaseDate: purchaseDate,
      activationDate: activationDate ?? this.activationDate,
      expiryDate: expiryDate ?? this.expiryDate,
      status: status ?? this.status,
      downloadCount: downloadCount ?? this.downloadCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'packageTitle': packageTitle,
    'amount': amount,
    'transactionCode': transactionCode,
    'purchaseDate': purchaseDate.toIso8601String(),
    'activationDate': activationDate.toIso8601String(),
    'expiryDate': expiryDate.toIso8601String(),
    'status': status.name,
    'downloadCount': downloadCount,
  };

  factory SubscriptionHistory.fromJson(Map<String, dynamic> json) => SubscriptionHistory(
    id: json['id'],
    packageTitle: json['packageTitle'],
    amount: json['amount'],
    transactionCode: json['transactionCode'],
    purchaseDate: DateTime.parse(json['purchaseDate']),
    activationDate: DateTime.parse(json['activationDate']),
    expiryDate: DateTime.parse(json['expiryDate']),
    status: SubscriptionStatus.values.byName(json['status'] ?? 'active'),
    downloadCount: json['downloadCount'] ?? 0,
  );
}
