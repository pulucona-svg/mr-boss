enum SubscriptionStatus {
  active,
  queued,
  expired,
  terminated,
  unknown,
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

  /// Explicit temporal entitlement evaluation rule:
  /// activationDate <= time < expiryDate.
  /// Expired, terminated, and unknown statuses fail closed.
  bool isEffectiveAt(DateTime time) {
    if (status == SubscriptionStatus.expired ||
        status == SubscriptionStatus.terminated ||
        status == SubscriptionStatus.unknown) {
      return false;
    }
    return !time.isBefore(activationDate) && time.isBefore(expiryDate);
  }

  /// Explicit temporal entitlement evaluation rule for the current instant.
  bool get isEffectiveNow => isEffectiveAt(DateTime.now());

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
    status: SubscriptionStatus.values.firstWhere(
      (e) => e.name == (json['status'] ?? ''),
      orElse: () => SubscriptionStatus.unknown,
    ),
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
        (e) => e.name == (json['status'] ?? ''),
        orElse: () => SubscriptionStatus.unknown,
      ),
      downloadCount: json['downloadCount'] ?? 0,
    );
  }
}

class PromotionalStageInfo {
  final int stageNumber;
  final String title;
  final String durationDescription;
  final int claimedCount;
  final int maxClaims;
  final int remainingClaims;
  final DateTime deadlineUtc;

  const PromotionalStageInfo({
    required this.stageNumber,
    required this.title,
    required this.durationDescription,
    required this.claimedCount,
    required this.maxClaims,
    required this.remainingClaims,
    required this.deadlineUtc,
  });

  factory PromotionalStageInfo.fromMap(Map<dynamic, dynamic> map) {
    return PromotionalStageInfo(
      stageNumber: (map['stageNumber'] as num?)?.toInt() ?? 1,
      title: map['title'] as String? ?? '',
      durationDescription: map['durationDescription'] as String? ?? '',
      claimedCount: (map['claimedCount'] as num?)?.toInt() ?? 0,
      maxClaims: (map['maxClaims'] as num?)?.toInt() ?? 0,
      remainingClaims: (map['remainingClaims'] as num?)?.toInt() ?? 0,
      deadlineUtc: DateTime.tryParse(map['deadlineUtc'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class PromotionalCampaignState {
  final bool campaignActive;
  final PromotionalStageInfo? activeStage;
  final bool isEligible;
  final bool hasClaimed;
  final String? ineligibilityReason;
  final DateTime? latestPaidExpiry;

  const PromotionalCampaignState({
    required this.campaignActive,
    this.activeStage,
    required this.isEligible,
    required this.hasClaimed,
    this.ineligibilityReason,
    this.latestPaidExpiry,
  });

  factory PromotionalCampaignState.fromMap(Map<dynamic, dynamic> map) {
    final activeStageMap = map['activeStage'] as Map<dynamic, dynamic>?;
    final userStatusMap = map['userStatus'] as Map<dynamic, dynamic>?;
    final expiryStr = userStatusMap?['latestPaidExpiry'] as String?;

    return PromotionalCampaignState(
      campaignActive: map['campaignActive'] as bool? ?? false,
      activeStage: activeStageMap != null ? PromotionalStageInfo.fromMap(activeStageMap) : null,
      isEligible: userStatusMap?['isEligible'] as bool? ?? false,
      hasClaimed: userStatusMap?['hasClaimed'] as bool? ?? false,
      ineligibilityReason: userStatusMap?['ineligibilityReason'] as String?,
      latestPaidExpiry: expiryStr != null ? DateTime.tryParse(expiryStr) : null,
    );
  }
}
