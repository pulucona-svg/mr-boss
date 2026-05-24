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
        ));

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
