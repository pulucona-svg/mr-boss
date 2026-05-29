import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/persistence_service.dart';

class UserProfile {
  final String uid;
  final String username;
  final String? profileImagePath;
  final String institution;
  final String universityLocation;
  final String program;
  final String programCode;
  final String year;
  final String semester;
  final String phone;
  final String email;
  final DateTime? joinDate;

  UserProfile({
    required this.uid,
    required this.username,
    this.profileImagePath,
    required this.institution,
    required this.universityLocation,
    required this.program,
    required this.programCode,
    required this.year,
    required this.semester,
    required this.phone,
    required this.email,
    this.joinDate,
  });

  UserProfile copyWith({
    String? uid,
    String? username,
    String? profileImagePath,
    String? institution,
    String? universityLocation,
    String? program,
    String? programCode,
    String? year,
    String? semester,
    String? phone,
    String? email,
    DateTime? joinDate,
    bool clearImagePath = false,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      username: username ?? this.username,
      profileImagePath: clearImagePath ? null : (profileImagePath ?? this.profileImagePath),
      institution: institution ?? this.institution,
      universityLocation: universityLocation ?? this.universityLocation,
      program: program ?? this.program,
      programCode: programCode ?? this.programCode,
      year: year ?? this.year,
      semester: semester ?? this.semester,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      joinDate: joinDate ?? this.joinDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'username': username,
      'profileImagePath': profileImagePath,
      'institution': institution,
      'universityLocation': universityLocation,
      'program': program,
      'programCode': programCode,
      'year': year,
      'semester': semester,
      'phone': phone,
      'email': email,
      'joinDate': joinDate?.toIso8601String(),
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      uid: json['uid'],
      username: json['username'],
      profileImagePath: json['profileImagePath'],
      institution: json['institution'],
      universityLocation: json['universityLocation'] ?? 'Main Campus',
      program: json['program'],
      programCode: json['programCode'] ?? 'C001',
      year: json['year'],
      semester: json['semester'],
      phone: json['phone'],
      email: json['email'],
      joinDate: json['joinDate'] != null ? DateTime.parse(json['joinDate']) : null,
    );
  }
}

class UserProfileNotifier extends StateNotifier<UserProfile> {
  UserProfileNotifier()
      : super(UserProfile(
          uid: 'user_12345',
          username: 'Cona Pulu',
          institution: 'University of Nairobi',
          universityLocation: 'Main Campus',
          program: 'Bachelor of Computer Science',
          programCode: 'COM_CS_2024',
          year: 'Year 1',
          semester: 'Sem 1',
          phone: '0714072724',
          email: 'pulucona@gmail.com',
          joinDate: DateTime(2025, 1, 1),
        )) {
    _restoreProfile();
  }

  Future<void> _restoreProfile() async {
    final json = PersistenceService().getJson('user_profile');
    if (json != null) {
      state = UserProfile.fromJson(json);
    }
    _autoUpdateAcademicDetails();
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
    String? username,
    String? profileImagePath,
    String? institution,
    String? universityLocation,
    String? program,
    String? programCode,
    String? year,
    String? semester,
    String? phone,
    String? email,
  }) {
    state = state.copyWith(
      username: username,
      profileImagePath: profileImagePath,
      institution: institution,
      universityLocation: universityLocation,
      program: program,
      programCode: programCode,
      year: year,
      semester: semester,
      phone: phone,
      email: email,
    );
    _saveProfile();
  }

  void setProfileImage(String path) {
    state = state.copyWith(profileImagePath: path);
    _saveProfile();
  }

  void clearProfileImage() {
    state = state.copyWith(clearImagePath: true);
    _saveProfile();
  }
}

final userProfileProvider = StateNotifierProvider<UserProfileNotifier, UserProfile>((ref) {
  return UserProfileNotifier();
});
