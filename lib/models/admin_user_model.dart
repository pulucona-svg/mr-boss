// Data models for the Admin Console Users Management module.

class AdminUserSummary {
  final String uid;
  final String username;
  final String email;
  final String? photoURL;
  final String institution;
  final String program;
  final String programCode;
  final String year;
  final String semester;
  final String phone;
  final DateTime? createdAt;
  final DateTime? lastLogin;
  final bool emailVerified;
  final bool disabled;
  final bool isAdmin;
  final bool hasActiveSubscription;

  AdminUserSummary({
    required this.uid,
    required this.username,
    required this.email,
    this.photoURL,
    required this.institution,
    required this.program,
    required this.programCode,
    required this.year,
    required this.semester,
    required this.phone,
    this.createdAt,
    this.lastLogin,
    this.emailVerified = false,
    this.disabled = false,
    this.isAdmin = false,
    this.hasActiveSubscription = false,
  });

  factory AdminUserSummary.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    return AdminUserSummary(
      uid: json['uid'] as String? ?? '',
      username: json['username'] as String? ?? json['displayName'] as String? ?? 'User',
      email: json['email'] as String? ?? '',
      photoURL: json['photoURL'] as String? ?? json['photoUrl'] as String?,
      institution: json['institution'] as String? ?? '',
      program: json['program'] as String? ?? '',
      programCode: json['programCode'] as String? ?? '',
      year: json['year']?.toString() ?? '',
      semester: json['semester']?.toString() ?? '',
      phone: json['phone'] as String? ?? json['phoneNumber'] as String? ?? '',
      createdAt: parseDate(json['createdAt']),
      lastLogin: parseDate(json['lastLogin']),
      emailVerified: json['emailVerified'] as bool? ?? false,
      disabled: json['disabled'] as bool? ?? false,
      isAdmin: json['isAdmin'] as bool? ?? (json['role']?.toString().toLowerCase() == 'admin'),
      hasActiveSubscription: json['hasActiveSubscription'] as bool? ?? false,
    );
  }

  factory AdminUserSummary.fromMap(Map<String, dynamic> map) =>
      AdminUserSummary.fromJson(map);

  String get displayName => username;
  String get phoneOrEmpty => phone;

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'username': username,
        'email': email,
        'photoURL': photoURL,
        'institution': institution,
        'program': program,
        'programCode': programCode,
        'year': year,
        'semester': semester,
        'phone': phone,
        'createdAt': createdAt?.toIso8601String(),
        'lastLogin': lastLogin?.toIso8601String(),
        'emailVerified': emailVerified,
        'disabled': disabled,
        'isAdmin': isAdmin,
        'hasActiveSubscription': hasActiveSubscription,
      };

  Map<String, dynamic> toMap() => toJson();
}

class AdminUserDetail {
  final String uid;
  final String username;
  final String email;
  final String? photoURL;
  final String institution;
  final String universityLocation;
  final String program;
  final String programCode;
  final String year;
  final String semester;
  final String phone;
  final String authProvider;
  final bool emailVerified;
  final bool onboardingComplete;
  final bool disabled;
  final bool isAdmin;
  final DateTime? createdAt;
  final DateTime? joinDate;
  final DateTime? lastLogin;
  final String? activeDeviceId;

  AdminUserDetail({
    required this.uid,
    required this.username,
    required this.email,
    this.photoURL,
    required this.institution,
    required this.universityLocation,
    required this.program,
    required this.programCode,
    required this.year,
    required this.semester,
    required this.phone,
    required this.authProvider,
    this.emailVerified = false,
    this.onboardingComplete = false,
    this.disabled = false,
    this.isAdmin = false,
    this.createdAt,
    this.joinDate,
    this.lastLogin,
    this.activeDeviceId,
  });

  factory AdminUserDetail.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    return AdminUserDetail(
      uid: json['uid'] as String? ?? '',
      username: json['username'] as String? ?? 'User',
      email: json['email'] as String? ?? '',
      photoURL: json['photoURL'] as String?,
      institution: json['institution'] as String? ?? '',
      universityLocation: json['universityLocation'] as String? ?? '',
      program: json['program'] as String? ?? '',
      programCode: json['programCode'] as String? ?? '',
      year: json['year'] as String? ?? '',
      semester: json['semester'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      authProvider: json['authProvider'] as String? ?? 'email',
      emailVerified: json['emailVerified'] as bool? ?? false,
      onboardingComplete: json['onboardingComplete'] as bool? ?? false,
      disabled: json['disabled'] as bool? ?? false,
      isAdmin: json['isAdmin'] as bool? ?? false,
      createdAt: parseDate(json['createdAt']),
      joinDate: parseDate(json['joinDate']),
      lastLogin: parseDate(json['lastLogin']),
      activeDeviceId: json['activeDeviceId'] as String?,
    );
  }

  factory AdminUserDetail.fromMap(Map<String, dynamic> map) =>
      AdminUserDetail.fromJson(map);

  String get displayName => username;

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'username': username,
        'email': email,
        'photoURL': photoURL,
        'institution': institution,
        'universityLocation': universityLocation,
        'program': program,
        'programCode': programCode,
        'year': year,
        'semester': semester,
        'phone': phone,
        'authProvider': authProvider,
        'emailVerified': emailVerified,
        'onboardingComplete': onboardingComplete,
        'disabled': disabled,
        'isAdmin': isAdmin,
        'createdAt': createdAt?.toIso8601String(),
        'joinDate': joinDate?.toIso8601String(),
        'lastLogin': lastLogin?.toIso8601String(),
        'activeDeviceId': activeDeviceId,
      };

  Map<String, dynamic> toMap() => toJson();
}

class AdminUserSubscription {
  final String id;
  final String packageTitle;
  final double amount;
  final String transactionCode;
  final String? paystackReference;
  final String? paymentChannel;
  final String? operatorReceiptNumber;
  final DateTime? purchaseDate;
  final DateTime? activationDate;
  final DateTime? expiryDate;
  final String status;
  final int downloadCount;

  AdminUserSubscription({
    required this.id,
    required this.packageTitle,
    required this.amount,
    required this.transactionCode,
    this.paystackReference,
    this.paymentChannel,
    this.operatorReceiptNumber,
    this.purchaseDate,
    this.activationDate,
    this.expiryDate,
    required this.status,
    this.downloadCount = 0,
  });

  factory AdminUserSubscription.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    return AdminUserSubscription(
      id: json['id'] as String? ?? '',
      packageTitle: json['packageTitle'] as String? ?? 'Pass',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      transactionCode: json['transactionCode'] as String? ?? '',
      paystackReference: json['paystackReference'] as String?,
      paymentChannel: json['paymentChannel'] as String?,
      operatorReceiptNumber: json['operatorReceiptNumber'] as String?,
      purchaseDate: parseDate(json['purchaseDate']),
      activationDate: parseDate(json['activationDate']),
      expiryDate: parseDate(json['expiryDate']),
      status: json['status'] as String? ?? 'active',
      downloadCount: (json['downloadCount'] as num?)?.toInt() ?? 0,
    );
  }

  factory AdminUserSubscription.fromMap(Map<String, dynamic> map) =>
      AdminUserSubscription.fromJson(map);

  String get packageName => packageTitle;
  bool get isActive => status.toLowerCase() == 'active';

  Map<String, dynamic> toJson() => {
        'id': id,
        'packageTitle': packageTitle,
        'amount': amount,
        'transactionCode': transactionCode,
        'paystackReference': paystackReference,
        'paymentChannel': paymentChannel,
        'operatorReceiptNumber': operatorReceiptNumber,
        'purchaseDate': purchaseDate?.toIso8601String(),
        'activationDate': activationDate?.toIso8601String(),
        'expiryDate': expiryDate?.toIso8601String(),
        'status': status,
        'downloadCount': downloadCount,
      };

  Map<String, dynamic> toMap() => toJson();
}

class AdminUserPayment {
  final String reference;
  final String packageName;
  final double expectedAmountKes;
  final String paymentMethod;
  final String? phoneNumber;
  final String status;
  final bool fulfilled;
  final String? failureReason;
  final String? operatorReceiptNumber;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AdminUserPayment({
    required this.reference,
    required this.packageName,
    required this.expectedAmountKes,
    required this.paymentMethod,
    this.phoneNumber,
    required this.status,
    this.fulfilled = false,
    this.failureReason,
    this.operatorReceiptNumber,
    this.createdAt,
    this.updatedAt,
  });

  factory AdminUserPayment.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    return AdminUserPayment(
      reference: json['reference'] as String? ?? json['id'] as String? ?? '',
      packageName: json['packageName'] as String? ?? 'Subscription',
      expectedAmountKes: (json['expectedAmountKes'] as num?)?.toDouble() ??
          (json['amount'] as num?)?.toDouble() ??
          0.0,
      paymentMethod: json['paymentMethod'] as String? ?? json['channel'] as String? ?? 'mobile_money',
      phoneNumber: json['phoneNumber'] as String?,
      status: json['status'] as String? ?? 'pending',
      fulfilled: json['fulfilled'] as bool? ?? false,
      failureReason: json['failureReason'] as String?,
      operatorReceiptNumber: json['operatorReceiptNumber'] as String?,
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
    );
  }

  factory AdminUserPayment.fromMap(Map<String, dynamic> map) =>
      AdminUserPayment.fromJson(map);

  double get amount => expectedAmountKes;

  Map<String, dynamic> toJson() => {
        'reference': reference,
        'packageName': packageName,
        'expectedAmountKes': expectedAmountKes,
        'paymentMethod': paymentMethod,
        'phoneNumber': phoneNumber,
        'status': status,
        'fulfilled': fulfilled,
        'failureReason': failureReason,
        'operatorReceiptNumber': operatorReceiptNumber,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  Map<String, dynamic> toMap() => toJson();
}

class AdminUserMaterialSummary {
  final int totalUploads;
  final int approvedCount;
  final int pendingCount;
  final int rejectedCount;
  final int modifiedCount;
  final int archivedCount;
  final int totalViews;
  final int totalLikes;
  final int totalComments;

  AdminUserMaterialSummary({
    required this.totalUploads,
    required this.approvedCount,
    required this.pendingCount,
    required this.rejectedCount,
    required this.modifiedCount,
    required this.archivedCount,
    required this.totalViews,
    required this.totalLikes,
    required this.totalComments,
  });

  factory AdminUserMaterialSummary.fromJson(Map<String, dynamic> json) {
    return AdminUserMaterialSummary(
      totalUploads: (json['totalUploads'] as num?)?.toInt() ?? 0,
      approvedCount: (json['approvedCount'] as num?)?.toInt() ?? 0,
      pendingCount: (json['pendingCount'] as num?)?.toInt() ?? 0,
      rejectedCount: (json['rejectedCount'] as num?)?.toInt() ?? 0,
      modifiedCount: (json['modifiedCount'] as num?)?.toInt() ?? 0,
      archivedCount: (json['archivedCount'] as num?)?.toInt() ?? 0,
      totalViews: (json['totalViews'] as num?)?.toInt() ?? 0,
      totalLikes: (json['totalLikes'] as num?)?.toInt() ?? 0,
      totalComments: (json['totalComments'] as num?)?.toInt() ?? 0,
    );
  }

  factory AdminUserMaterialSummary.fromMap(Map<String, dynamic> map) =>
      AdminUserMaterialSummary.fromJson(map);

  int get totalCount => totalUploads;

  Map<String, dynamic> toJson() => {
        'totalUploads': totalUploads,
        'approvedCount': approvedCount,
        'pendingCount': pendingCount,
        'rejectedCount': rejectedCount,
        'modifiedCount': modifiedCount,
        'archivedCount': archivedCount,
        'totalViews': totalViews,
        'totalLikes': totalLikes,
        'totalComments': totalComments,
      };

  Map<String, dynamic> toMap() => toJson();
}

class AdminUserMaterialItem {
  final String id;
  final String title;
  final String fileName;
  final String type;
  final String unitName;
  final String unitCode;
  final String materialFormat;
  final DateTime? uploadDate;
  final String status;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;
  final String? declineReason;
  final List<String>? rejectionReasons;
  final String? adminRemark;
  final int views;
  final int likes;
  final int comments;
  final String? thumbnailUrl;
  final bool isAnonymous;

  AdminUserMaterialItem({
    required this.id,
    required this.title,
    required this.fileName,
    required this.type,
    required this.unitName,
    required this.unitCode,
    required this.materialFormat,
    this.uploadDate,
    required this.status,
    this.approvedAt,
    this.rejectedAt,
    this.declineReason,
    this.rejectionReasons,
    this.adminRemark,
    this.views = 0,
    this.likes = 0,
    this.comments = 0,
    this.thumbnailUrl,
    this.isAnonymous = false,
  });

  factory AdminUserMaterialItem.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    final rawRejections = json['rejectionReasons'];
    List<String>? parsedRejections;
    if (rawRejections is List) {
      parsedRejections = rawRejections.map((e) => e.toString()).toList();
    }

    return AdminUserMaterialItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Academic Resource',
      fileName: json['fileName'] as String? ?? '',
      type: json['type'] as String? ?? json['category'] as String? ?? 'Notes',
      unitName: json['unitName'] as String? ?? '',
      unitCode: json['unitCode'] as String? ?? '',
      materialFormat: json['materialFormat'] as String? ?? 'PDF',
      uploadDate: parseDate(json['uploadDate']),
      status: json['status'] as String? ?? 'pending',
      approvedAt: parseDate(json['approvedAt']),
      rejectedAt: parseDate(json['rejectedAt']),
      declineReason: json['declineReason'] as String?,
      rejectionReasons: parsedRejections,
      adminRemark: json['adminRemark'] as String?,
      views: (json['views'] as num?)?.toInt() ?? 0,
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      comments: (json['comments'] as num?)?.toInt() ?? (json['commentsCount'] as num?)?.toInt() ?? 0,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      isAnonymous: json['isAnonymous'] as bool? ?? false,
    );
  }

  factory AdminUserMaterialItem.fromMap(Map<String, dynamic> map) =>
      AdminUserMaterialItem.fromJson(map);

  String get category => type;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'fileName': fileName,
        'type': type,
        'unitName': unitName,
        'unitCode': unitCode,
        'materialFormat': materialFormat,
        'uploadDate': uploadDate?.toIso8601String(),
        'status': status,
        'approvedAt': approvedAt?.toIso8601String(),
        'rejectedAt': rejectedAt?.toIso8601String(),
        'declineReason': declineReason,
        'rejectionReasons': rejectionReasons,
        'adminRemark': adminRemark,
        'views': views,
        'likes': likes,
        'comments': comments,
        'thumbnailUrl': thumbnailUrl,
        'isAnonymous': isAnonymous,
      };

  Map<String, dynamic> toMap() => toJson();
}

class AdminUserSession {
  final String deviceId;
  final String platform;
  final bool isActive;
  final DateTime? lastLogin;

  AdminUserSession({
    required this.deviceId,
    required this.platform,
    required this.isActive,
    this.lastLogin,
  });

  factory AdminUserSession.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    return AdminUserSession(
      deviceId: json['deviceId'] as String? ?? '',
      platform: json['platform'] as String? ?? json['deviceModel'] as String? ?? 'Unknown',
      isActive: json['isActive'] as bool? ?? false,
      lastLogin: parseDate(json['lastLogin'] ?? json['lastLoginAt']),
    );
  }

  factory AdminUserSession.fromMap(Map<String, dynamic> map) =>
      AdminUserSession.fromJson(map);

  String get deviceModel => platform;
  DateTime? get lastLoginAt => lastLogin;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'platform': platform,
        'isActive': isActive,
        'lastLogin': lastLogin?.toIso8601String(),
      };

  Map<String, dynamic> toMap() => toJson();
}

class AdminUserFullProfile {
  final AdminUserDetail user;
  final List<AdminUserSession> sessions;
  final List<AdminUserSubscription> subscriptions;
  final List<AdminUserPayment> payments;
  final AdminUserMaterialSummary materialsSummary;
  final List<AdminUserMaterialItem> materials;

  AdminUserFullProfile({
    required this.user,
    required this.sessions,
    required this.subscriptions,
    required this.payments,
    required this.materialsSummary,
    required this.materials,
  });

  factory AdminUserFullProfile.fromJson(Map<String, dynamic> json) {
    final rawUser = Map<String, dynamic>.from(json['user'] as Map? ?? json['profile'] as Map? ?? {});
    final rawSessions = json['sessions'] as List<dynamic>? ?? [];
    final rawSubs = json['subscriptions'] as List<dynamic>? ?? [];
    final rawPayments = json['payments'] as List<dynamic>? ?? [];
    final rawMatSummary = Map<String, dynamic>.from(json['materialsSummary'] as Map? ?? {});
    final rawMaterials = json['materials'] as List<dynamic>? ?? [];

    return AdminUserFullProfile(
      user: AdminUserDetail.fromJson(rawUser),
      sessions: rawSessions.map((e) => AdminUserSession.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      subscriptions: rawSubs.map((e) => AdminUserSubscription.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      payments: rawPayments.map((e) => AdminUserPayment.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      materialsSummary: AdminUserMaterialSummary.fromJson(rawMatSummary),
      materials: rawMaterials.map((e) => AdminUserMaterialItem.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }

  factory AdminUserFullProfile.fromMap(Map<String, dynamic> map) =>
      AdminUserFullProfile.fromJson(map);

  AdminUserDetail get profile => user;
  String get userId => user.uid;
  bool get isDisabled => user.disabled;
  String get role => user.isAdmin ? 'admin' : 'student';
  bool get hasActiveSubscription => subscriptions.any((s) => s.isActive);

  Map<String, dynamic> toJson() => {
        'user': user.toJson(),
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'subscriptions': subscriptions.map((s) => s.toJson()).toList(),
        'payments': payments.map((p) => p.toJson()).toList(),
        'materialsSummary': materialsSummary.toJson(),
        'materials': materials.map((m) => m.toJson()).toList(),
      };

  Map<String, dynamic> toMap() => toJson();
}
