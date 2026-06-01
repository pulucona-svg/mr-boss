import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // Upload profile picture to ImageKit via Cloud Functions
  Future<String?> uploadProfilePicture(String uid, String localPath) async {
    try {
      debugPrint('UserService: [DEBUG] Profile picture upload process started for UID: $uid');
      
      // 1. Read old photo data from Firestore
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final userData = userDoc.data();
      final oldPhotoUrl = userData?['photoURL'] as String?;
      final oldFileId = userData?['photoFileId'] as String?;
      debugPrint('UserService: [DEBUG] Old photo URL: ${oldPhotoUrl ?? "None"}');
      debugPrint('UserService: [DEBUG] Old file ID: ${oldFileId ?? "None"}');

      // 2. Delete old image from ImageKit if it exists
      if (oldFileId != null && oldFileId.isNotEmpty) {
        try {
          await _functions.httpsCallable('deleteFromImageKit').call({'fileId': oldFileId});
          debugPrint('UserService: [DEBUG] Old image deleted successfully from ImageKit.');
        } catch (e) {
          debugPrint('UserService: [WARNING] Failed to delete old image from ImageKit: $e');
        }
      }

      // 3. Upload new image to ImageKit via Cloud Function
      final fileBytes = await File(localPath).readAsBytes();
      final base64File = base64Encode(fileBytes);
      final fileName = 'profile_pic_${uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      debugPrint('UserService: [DEBUG] Uploading new image to ImageKit: $fileName');
      final result = await _functions.httpsCallable('uploadToImageKit').call({
        'file': base64File,
        'fileName': fileName,
        'folder': 'PROFILE PICTURES',
      });
      
      final downloadUrl = result.data['url'] as String;
      final fileId = result.data['fileId'] as String;
      debugPrint('UserService: [DEBUG] New upload URL: $downloadUrl');
      
      // 4. Save new download URL and fileId to Firestore
      await _firestore.collection('users').doc(uid).update({
        'photoURL': downloadUrl,
        'photoFileId': fileId,
      });
      debugPrint('UserService: [DEBUG] Firestore update result: SUCCESS');
      
      return downloadUrl;
    } catch (e) {
      debugPrint('UserService: [ERROR] uploadProfilePicture failed: $e');
      return null;
    }
  }

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
        
        String authProvider = 'email';
        if (user.providerData.any((p) => p.providerId == 'google.com')) {
          authProvider = 'google';
        }

        // Create new user document
        final userData = {
          'uid': user.uid,
          'email': user.email,
          'username': user.displayName ?? '',
          'photoURL': user.photoURL,
          'onboardingComplete': false,
          'joinDate': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'institution': '',
          'universityLocation': 'Main Campus',
          'program': '',
          'programCode': '',
          'year': 'Year 1',
          'semester': 'Sem 1',
          'phone': '',
          'authProvider': authProvider,
          'emailVerified': user.emailVerified,
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
      
      debugPrint('FIRESTORE DEBUG: attempting profile update (set with merge) for collection=users, docId=$uid');
      try {
        await docRef.set({
          ...data,
          'onboardingComplete': true,
        }, SetOptions(merge: true));
        debugPrint('FIRESTORE DEBUG: profile update/creation success for uid=$uid');
      } catch (e, st) {
        debugPrint('FIRESTORE ERROR [set/merge]: $e');
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

  // Check if username is unique
  Future<bool> isUsernameUnique(String username, {String? excludeUid}) async {
    try {
      Query query = _firestore
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1);
      
      final querySnapshot = await query.get();
      
      if (querySnapshot.docs.isEmpty) return true;
      
      if (excludeUid != null) {
        // If the only document found belongs to the current user, it's still "unique" for them
        return querySnapshot.docs.first.id == excludeUid;
      }
      
      return false;
    } catch (e) {
      debugPrint('UserService: isUsernameUnique error: $e');
      return true; // Default to true or handle error
    }
  }

  // Update session ID in Firestore
  Future<void> updateSessionId(String uid, String sessionId) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'sessionId': sessionId,
      });
      debugPrint('UserService: Updated sessionId to $sessionId for $uid');
    } catch (e) {
      debugPrint('UserService: updateSessionId error: $e');
    }
  }

  // Stream of session ID from Firestore
  Stream<String?> streamUserSessionId(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((snapshot) {
      if (snapshot.exists) {
        return snapshot.data()?['sessionId'] as String?;
      }
      return null;
    });
  }
}
