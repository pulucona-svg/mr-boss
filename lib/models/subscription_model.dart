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
  final int? paystackTransactionId;
  final String? paystackReference;
  final String? paymentChannel;
  final String? operatorReceiptNumber;
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
    this.paystackTransactionId,
    this.paystackReference,
    this.paymentChannel,
    this.operatorReceiptNumber,
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
    int? paystackTransactionId,
    String? paystackReference,
    String? paymentChannel,
    String? operatorReceiptNumber,
  }) {
    return SubscriptionHistory(
      id: id,
      packageTitle: packageTitle,
      amount: amount,
      transactionCode: transactionCode,
      paystackTransactionId: paystackTransactionId ?? this.paystackTransactionId,
      paystackReference: paystackReference ?? this.paystackReference,
      paymentChannel: paymentChannel ?? this.paymentChannel,
      operatorReceiptNumber: operatorReceiptNumber ?? this.operatorReceiptNumber,
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
    if (paystackTransactionId != null) 'paystackTransactionId': paystackTransactionId,
    if (paystackReference != null) 'paystackReference': paystackReference,
    if (paymentChannel != null) 'paymentChannel': paymentChannel,
    if (operatorReceiptNumber != null) 'operatorReceiptNumber': operatorReceiptNumber,
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
    paystackTransactionId: json['paystackTransactionId'] as int?,
    paystackReference: json['paystackReference'] as String?,
    paymentChannel: json['paymentChannel'] as String?,
    operatorReceiptNumber: json['operatorReceiptNumber'] as String?,
    purchaseDate: DateTime.parse(json['purchaseDate']),
    activationDate: DateTime.parse(json['activationDate']),
    expiryDate: DateTime.parse(json['expiryDate']),
    status: SubscriptionStatus.values.byName(json['status'] ?? 'active'),
    downloadCount: json['downloadCount'] ?? 0,
  );

  Map<String, dynamic> toFirestore() => toJson();

  factory SubscriptionHistory.fromFirestore(Map<String, dynamic> json, String id) {
    return SubscriptionHistory(
      id: id,
      packageTitle: json['packageTitle'] ?? '',
      amount: (json['amount'] ?? 0.0).toDouble(),
      transactionCode: json['transactionCode'] ?? '',
      paystackTransactionId: json['paystackTransactionId'] as int?,
      paystackReference: json['paystackReference'] as String?,
      paymentChannel: json['paymentChannel'] as String?,
      operatorReceiptNumber: json['operatorReceiptNumber'] as String?,
      purchaseDate: json['purchaseDate'] is String 
          ? DateTime.parse(json['purchaseDate']) 
          : (json['purchaseDate'] as dynamic).toDate(),
      activationDate: json['activationDate'] is String 
          ? DateTime.parse(json['activationDate']) 
          : (json['activationDate'] as dynamic).toDate(),
      expiryDate: json['expiryDate'] is String 
          ? DateTime.parse(json['expiryDate']) 
          : (json['expiryDate'] as dynamic).toDate(),
      status: SubscriptionStatus.values.firstWhere(
        (e) => e.name == (json['status'] ?? 'active'),
        orElse: () => SubscriptionStatus.active,
      ),
      downloadCount: json['downloadCount'] ?? 0,
    );
  }
}
