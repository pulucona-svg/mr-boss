import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Sync user with Firestore (Create if doesn't exist)
  Future<Map<String, dynamic>?> syncUser(User user) async {
    debugPrint('FIRESTORE DEBUG: syncUser started for uid=${user.uid}');
    try {
      final docRef = _firestore.collection('users').doc(user.uid);
      
      debugPrint('FIRESTORE DEBUG: attempting profile fetch (get) for collection=users, docId=${user.uid}');
      DocumentSnapshot docSnap;
      try {
        docSnap = await docRef.get();
        debugPrint('FIRESTORE DEBUG: fetch success. Exists: ${docSnap.exists}');
      } catch (e, st) {
        debugPrint('FIRESTORE ERROR [get]: $e');
        debugPrint('STACK TRACE:\n$st');
        rethrow;
      }

      if (!docSnap.exists) {
        debugPrint('FIRESTORE DEBUG: profile not found. Attempting creation (set) for collection=users, docId=${user.uid}');
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
        
        try {
          await docRef.set(userData);
          debugPrint('FIRESTORE DEBUG: profile creation success for uid=${user.uid}');
        } catch (e, st) {
          debugPrint('FIRESTORE ERROR [set]: $e');
          debugPrint('STACK TRACE:\n$st');
          rethrow;
        }
        return userData;
      } else {
        debugPrint('FIRESTORE DEBUG: existing user document found for ${user.uid}');
        return docSnap.data() as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('UserService: [FATAL ERROR] syncUser failed: $e');
      rethrow;
    }
  }

  // Update user profile and mark onboarding as complete
  Future<void> completeOnboarding(String uid, Map<String, dynamic> data) async {
    debugPrint('FIRESTORE DEBUG: completeOnboarding started for uid=$uid');
    try {
      final docRef = _firestore.collection('users').doc(uid);
      
      debugPrint('FIRESTORE DEBUG: attempting profile update (update) for collection=users, docId=$uid');
      try {
        await docRef.update({
          ...data,
          'onboardingComplete': true,
        });
        debugPrint('FIRESTORE DEBUG: profile update success for uid=$uid');
      } catch (e, st) {
        debugPrint('FIRESTORE ERROR [update]: $e');
        debugPrint('STACK TRACE:\n$st');
        rethrow;
      }
    } catch (e) {
      debugPrint('UserService: [FATAL ERROR] completeOnboarding failed: $e');
      rethrow;
    }
  }

  // Get user profile from Firestore
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    debugPrint('FIRESTORE DEBUG: getUserProfile started for uid=$uid');
    try {
      final docRef = _firestore.collection('users').doc(uid);
      
      debugPrint('FIRESTORE DEBUG: attempting profile fetch (get) for collection=users, docId=$uid');
      DocumentSnapshot docSnap;
      try {
        docSnap = await docRef.get();
        debugPrint('FIRESTORE DEBUG: fetch success for uid=$uid. Exists: ${docSnap.exists}');
        return docSnap.data() as Map<String, dynamic>?;
      } catch (e, st) {
        debugPrint('FIRESTORE ERROR [getUserProfile/get]: $e');
        debugPrint('STACK TRACE:\n$st');
        return null;
      }
    } catch (e) {
      debugPrint('UserService: [FATAL ERROR] getUserProfile failed: $e');
      return null;
    }
  }
}
