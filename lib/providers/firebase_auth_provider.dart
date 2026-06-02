import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'service_providers.dart';

final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).user;
});
