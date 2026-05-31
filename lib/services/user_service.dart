import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Sync user with Firestore (Create if doesn't exist)
  Future<Map<String, dynamic>?> syncUser(User user) async {
    try {
      final docRef = _firestore.collection('users').doc(user.uid);
      final docSnap = await docRef.get();

      if (!docSnap.exists) {
        // Create new user document
        final userData = {
          'uid': user.uid,
          'email': user.email,
          'username': user.displayName ?? '',
          'photoURL': user.photoURL,
          'onboardingComplete': false,
          'joinDate': FieldValue.serverTimestamp(),
          'institution': '',
          'universityLocation': 'Main Campus',
          'program': '',
          'programCode': '',
          'year': 'Year 1',
          'semester': 'Sem 1',
          'phone': '',
        };
        await docRef.set(userData);
        debugPrint('UserService: Created new user document for ${user.uid}');
        return userData;
      } else {
        debugPrint('UserService: User document already exists for ${user.uid}');
        return docSnap.data();
      }
    } catch (e) {
      debugPrint('UserService: Error syncing user: $e');
      rethrow;
    }
  }

  // Update user profile and mark onboarding as complete
  Future<void> completeOnboarding(String uid, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        ...data,
        'onboardingComplete': true,
      });
      debugPrint('UserService: Onboarding complete for $uid');
    } catch (e) {
      debugPrint('UserService: Error completing onboarding: $e');
      rethrow;
    }
  }

  // Get user profile from Firestore
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    try {
      final docSnap = await _firestore.collection('users').doc(uid).get();
      return docSnap.data();
    } catch (e) {
      debugPrint('UserService: Error getting user profile: $e');
      return null;
    }
  }
}
