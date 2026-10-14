import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/persistence_service.dart';
import '../services/user_service.dart';
import '../services/resource_service.dart';

import 'package:uuid/uuid.dart';

class UserProfile {
  final String uid;
  final String username;
  final String? profileImagePath;
  final String? photoURL; 
  final String institution;
  final String universityLocation;
  final String program;
  final String programCode;
  final String year;
  final String semester;
  final String phone;
  final String email;
  final DateTime? joinDate;
  final bool onboardingComplete;
  final String? sessionId;
  final String? termsVersionAccepted;
  final DateTime? termsAcceptedAt;
  final String? privacyPolicyVersionAccepted;
  final DateTime? privacyPolicyAcceptedAt;
  final String deletionStatus;
  final DateTime? deletionRequestedAt;
  final DateTime? deletionScheduledAt;

  UserProfile({
    required this.uid,
    required this.username,
    this.profileImagePath,
    this.photoURL,
    required this.institution,
    required this.universityLocation,
    required this.program,
    required this.programCode,
    required this.year,
    required this.semester,
    required this.phone,
    required this.email,
    this.joinDate,
    this.onboardingComplete = false,
    this.sessionId,
    this.termsVersionAccepted,
    this.termsAcceptedAt,
    this.privacyPolicyVersionAccepted,
    this.privacyPolicyAcceptedAt,
    this.deletionStatus = 'none',
    this.deletionRequestedAt,
    this.deletionScheduledAt,
  });

  bool get isPendingDeletion => deletionStatus == 'pending';
  bool get isPermanentlyDeleted => deletionStatus == 'permanently_deleted';

  UserProfile copyWith({
    String? uid,
    String? username,
    String? profileImagePath,
    String? photoURL,
    String? institution,
    String? universityLocation,
    String? program,
    String? programCode,
    String? year,
    String? semester,
    String? phone,
    String? email,
    DateTime? joinDate,
    bool? onboardingComplete,
    String? sessionId,
    String? termsVersionAccepted,
    DateTime? termsAcceptedAt,
    String? privacyPolicyVersionAccepted,
    DateTime? privacyPolicyAcceptedAt,
    String? deletionStatus,
    DateTime? deletionRequestedAt,
    DateTime? deletionScheduledAt,
    bool clearImagePath = false,
    bool clearDeletion = false,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      username: username ?? this.username,
      profileImagePath: clearImagePath ? null : (profileImagePath ?? this.profileImagePath),
      photoURL: photoURL ?? this.photoURL,
      institution: institution ?? this.institution,
      universityLocation: universityLocation ?? this.universityLocation,
      program: program ?? this.program,
      programCode: programCode ?? this.programCode,
      year: year ?? this.year,
      semester: semester ?? this.semester,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      joinDate: joinDate ?? this.joinDate,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      sessionId: sessionId ?? this.sessionId,
      termsVersionAccepted: termsVersionAccepted ?? this.termsVersionAccepted,
      termsAcceptedAt: termsAcceptedAt ?? this.termsAcceptedAt,
      privacyPolicyVersionAccepted: privacyPolicyVersionAccepted ?? this.privacyPolicyVersionAccepted,
      privacyPolicyAcceptedAt: privacyPolicyAcceptedAt ?? this.privacyPolicyAcceptedAt,
      deletionStatus: clearDeletion ? 'none' : (deletionStatus ?? this.deletionStatus),
      deletionRequestedAt: clearDeletion ? null : (deletionRequestedAt ?? this.deletionRequestedAt),
      deletionScheduledAt: clearDeletion ? null : (deletionScheduledAt ?? this.deletionScheduledAt),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'username': username,
      'profileImagePath': profileImagePath,
      'photoURL': photoURL,
      'institution': institution,
      'universityLocation': universityLocation,
      'program': program,
      'programCode': programCode,
      'year': year,
      'semester': semester,
      'phone': phone,
      'email': email,
      'joinDate': joinDate?.toIso8601String(),
      'onboardingComplete': onboardingComplete,
      'sessionId': sessionId,
      'termsVersionAccepted': termsVersionAccepted,
      'termsAcceptedAt': termsAcceptedAt?.toIso8601String(),
      'privacyPolicyVersionAccepted': privacyPolicyVersionAccepted,
      'privacyPolicyAcceptedAt': privacyPolicyAcceptedAt?.toIso8601String(),
      'deletionStatus': deletionStatus,
      'deletionRequestedAt': deletionRequestedAt?.toIso8601String(),
      'deletionScheduledAt': deletionScheduledAt?.toIso8601String(),
    };
  }

  /// Returns a sanitized map containing only the allowed profile fields for Firestore.
  /// Server-controlled deletion lifecycle fields and local device paths are excluded.
  Map<String, dynamic> toFirestoreMap() {
    final map = <String, dynamic>{
      'uid': uid,
      'username': username,
      'institution': institution,
      'universityLocation': universityLocation,
      'program': program,
      'programCode': programCode,
      'year': year,
      'semester': semester,
      'phone': phone,
      'email': email,
      'onboardingComplete': onboardingComplete,
    };
    if (photoURL != null && photoURL!.isNotEmpty) {
      map['photoURL'] = photoURL;
    }
    if (joinDate != null) {
      map['joinDate'] = joinDate!.toIso8601String();
    }
    if (termsVersionAccepted != null) {
      map['termsVersionAccepted'] = termsVersionAccepted;
    }
    if (termsAcceptedAt != null) {
      map['termsAcceptedAt'] = termsAcceptedAt!.toIso8601String();
    }
    if (privacyPolicyVersionAccepted != null) {
      map['privacyPolicyVersionAccepted'] = privacyPolicyVersionAccepted;
    }
    if (privacyPolicyAcceptedAt != null) {
      map['privacyPolicyAcceptedAt'] = privacyPolicyAcceptedAt!.toIso8601String();
    }
    return map;
  }

  static DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    if (val is String) return DateTime.tryParse(val);
    try {
      return (val as dynamic).toDate();
    } catch (_) {
      return null;
    }
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      uid: json['uid'] ?? '',
      username: json['username'] ?? '',
      profileImagePath: json['profileImagePath'],
      photoURL: json['photoURL'],
      institution: json['institution'] ?? '',
      universityLocation: json['universityLocation'] ?? 'Main Campus',
      program: json['program'] ?? '',
      programCode: json['programCode'] ?? 'C001',
      year: json['year'] ?? 'Year 1',
      semester: json['semester'] ?? 'Sem 1',
      phone: json['phone'] ?? '',
      email: json['email'] ?? '',
      joinDate: _parseDate(json['joinDate']),
      onboardingComplete: json['onboardingComplete'] ?? false,
      sessionId: json['sessionId'],
      termsVersionAccepted: json['termsVersionAccepted'] as String?,
      termsAcceptedAt: _parseDate(json['termsAcceptedAt']),
      privacyPolicyVersionAccepted: json['privacyPolicyVersionAccepted'] as String?,
      privacyPolicyAcceptedAt: _parseDate(json['privacyPolicyAcceptedAt']),
      deletionStatus: json['deletionStatus'] as String? ?? 'none',
      deletionRequestedAt: _parseDate(json['deletionRequestedAt']),
      deletionScheduledAt: _parseDate(json['deletionScheduledAt']),
    );
  }
}

class UserProfileNotifier extends StateNotifier<UserProfile> {
  final String _instanceSessionId = const Uuid().v4();

  UserProfileNotifier()
      : super(UserProfile(
          uid: '',
          username: '',
          institution: '',
          universityLocation: '',
          program: '',
          programCode: '',
          year: 'Year 1',
          semester: 'Sem 1',
          phone: '',
          email: '',
          onboardingComplete: false,
        )) {
    _restoreProfile();
  }

  String get instanceSessionId => _instanceSessionId;

  Future<void> _restoreProfile() async {
    final json = PersistenceService().getJson('user_profile');
    if (json != null) {
      state = UserProfile.fromJson(json);
    }
    
    final userId = PersistenceService().getSessionUserId();
    if (userId != null) {
      ResourceService().initialize(userId);
      await fetchProfileFromFirestore(userId);
    }
    
    _autoUpdateAcademicDetails();
  }

  Future<void> fetchProfileFromFirestore(String uid) async {
    debugPrint('UserProfileNotifier: [DEBUG] Fetching profile from Firestore for UID: $uid');
    final Map<String, dynamic>? data = await UserService().getUserProfile(uid);
    if (data != null) {
      debugPrint('UserProfileNotifier: [DEBUG] Profile data received. Updating state...');
      state = UserProfile.fromJson(data);
      await _saveProfile();
      debugPrint('UserProfileNotifier: [DEBUG] Local state updated and saved to persistence.');
    } else {
      debugPrint('UserProfileNotifier: [DEBUG] No profile data received from Firestore (data is null).');
    }
  }

  Future<void> _saveProfile() async {
    await PersistenceService().setJson('user_profile', state.toJson());
  }

  void _autoUpdateAcademicDetails() {
    final now = DateTime.now();
    final month = now.month;
    
    String calculatedSemester = (month >= 8 && month <= 12) ? 'Sem 1' : 'Sem 2';
    
    if (state.joinDate != null) {
      int yearsPassed = now.year - state.joinDate!.year;
      if (month >= 8 && state.joinDate!.month < 8) {
        yearsPassed += 1;
      } else if (month < 8 && state.joinDate!.month >= 8) {
        yearsPassed -= 1;
      }
      
      int currentYearInt = int.tryParse(state.year.replaceAll('Year ', '')) ?? 1;
      int newYearInt = currentYearInt + (yearsPassed > 0 ? yearsPassed : 0);
      if (newYearInt > 4) newYearInt = 4;

      state = state.copyWith(
        year: 'Year $newYearInt',
        semester: calculatedSemester,
      );
      _saveProfile();
    }
  }

  void updateProfile({
    String? uid,
    String? username,
    String? profileImagePath,
    String? photoURL,
    String? institution,
    String? universityLocation,
    String? program,
    String? programCode,
    String? year,
    String? semester,
    String? phone,
    String? email,
    bool? onboardingComplete,
  }) {
    state = state.copyWith(
      uid: uid,
      username: username,
      profileImagePath: profileImagePath,
      photoURL: photoURL,
      institution: institution,
      universityLocation: universityLocation,
      program: program,
      programCode: programCode,
      year: year,
      semester: semester,
      phone: phone,
      email: email,
      onboardingComplete: onboardingComplete,
    );
    _saveProfile();
  }

  Future<void> setProfileImage(String path) async {
    state = state.copyWith(profileImagePath: path);
    await _saveProfile();
    
    if (state.uid.isNotEmpty) {
      final downloadUrl = await UserService().uploadProfilePicture(state.uid, path);
      if (downloadUrl != null) {
        // Clear local path and use download URL to ensure consistency
        state = state.copyWith(photoURL: downloadUrl, clearImagePath: true);
        await _saveProfile();
        debugPrint('UserProfileNotifier: [DEBUG] Profile image synced. Local path cleared, using photoURL: $downloadUrl');
      }
    }
  }

  void clearProfileImage() {
    state = state.copyWith(clearImagePath: true);
    _saveProfile();
  }

  void setDeletionStatus({
    required String status,
    DateTime? requestedAt,
    DateTime? scheduledAt,
  }) {
    state = state.copyWith(
      deletionStatus: status,
      deletionRequestedAt: requestedAt,
      deletionScheduledAt: scheduledAt,
      clearDeletion: status == 'none',
    );
    _saveProfile();
  }
}

final userProfileProvider = StateNotifierProvider<UserProfileNotifier, UserProfile>((ref) {
  return UserProfileNotifier();
});
