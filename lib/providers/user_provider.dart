import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserProfile {
  final String uid;
  final String username;
  final String? profileImagePath;
  final String institution;
  final String program;
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
    required this.program,
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
    String? program,
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
      program: program ?? this.program,
      year: year ?? this.year,
      semester: semester ?? this.semester,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      joinDate: joinDate ?? this.joinDate,
    );
  }
}

class UserProfileNotifier extends StateNotifier<UserProfile> {
  UserProfileNotifier()
      : super(UserProfile(
          uid: 'user_12345',
          username: 'Cona Pulu',
          institution: 'University of Nairobi',
          program: 'Bachelor of Computer Science',
          year: 'Year 1',
          semester: 'Sem 1',
          phone: '0714072724',
          email: 'pulucona@gmail.com',
          joinDate: DateTime(2025, 1, 1),
        )) {
    _autoUpdateAcademicDetails();
  }

  void _autoUpdateAcademicDetails() {
    final now = DateTime.now();
    final month = now.month;
    
    // Logic: 
    // Semester 1: August (8) to December (12)
    // Semester 2: January (1) to July (7)
    String calculatedSemester = (month >= 8 && month <= 12) ? 'Sem 1' : 'Sem 2';
    
    // Progression Logic: 
    // When August arrives, Semester becomes Sem 1 and Year increases by 1.
    // We compare with joinDate or last updated year.
    // For now, let's base it on joinDate.
    if (state.joinDate != null) {
      int yearsPassed = now.year - state.joinDate!.year;
      // If we are in or past August of the current year, and the join month was before August
      if (month >= 8 && state.joinDate!.month < 8) {
        yearsPassed += 1;
      } else if (month < 8 && state.joinDate!.month >= 8) {
        yearsPassed -= 1;
      }
      
      int currentYearInt = int.tryParse(state.year.replaceAll('Year ', '')) ?? 1;
      int newYearInt = currentYearInt + (yearsPassed > 0 ? yearsPassed : 0);
      if (newYearInt > 4) newYearInt = 4; // Max Year 4 as per requirements

      state = state.copyWith(
        year: 'Year $newYearInt',
        semester: calculatedSemester,
      );
    }
  }

  void updateProfile({
    String? username,
    String? profileImagePath,
    String? institution,
    String? program,
    String? year,
    String? semester,
    String? phone,
    String? email,
  }) {
    state = state.copyWith(
      username: username,
      profileImagePath: profileImagePath,
      institution: institution,
      program: program,
      year: year,
      semester: semester,
      phone: phone,
      email: email,
    );
  }

  void setProfileImage(String path) {
    state = state.copyWith(profileImagePath: path);
  }

  void clearProfileImage() {
    state = state.copyWith(clearImagePath: true);
  }
}

final userProfileProvider = StateNotifierProvider<UserProfileNotifier, UserProfile>((ref) {
  return UserProfileNotifier();
});
