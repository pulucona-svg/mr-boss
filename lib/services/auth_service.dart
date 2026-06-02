import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'user_service.dart';
import 'resource_service.dart';
import 'device_id_manager.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserService _userService = UserService();
  
  // Use the singleton instance for GoogleSignIn in version 7.2.0+
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _isInitialized = false;

  // The Web Client ID from Google Cloud Console / Firebase.
  // This MUST be the "client_type": 3 ID from your google-services.json.
  static const String _webClientId = '386198984140-4d8s7o98rdds643i18ico294tcco0paj.apps.googleusercontent.com';

  /// Ensures that GoogleSignIn is initialized before use.
  /// Version 7.2.0+ requires calling initialize() exactly once.
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      debugPrint('AuthService: Initializing GoogleSignIn...');
      try {
        await _googleSignIn.initialize(
          clientId: _webClientId,
        );
        _isInitialized = true;
        debugPrint('AuthService: GoogleSignIn initialized successfully.');
      } catch (e) {
        debugPrint('AuthService: [ERROR] Failed to initialize GoogleSignIn: $e');
        rethrow;
      }
    }
  }

  // Auth state changes stream
  Stream<User?> get user => _auth.authStateChanges();

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Sign in with email and password
  Future<UserCredential?> signInWithEmailAndPassword(String email, String password) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(email: email, password: password);
      if (userCredential.user != null) {
        await _handleLoginSuccess(userCredential.user!);
      }
      return userCredential;
    } on FirebaseAuthException catch (e) {
      debugPrint('AuthService: signInWithEmailAndPassword error: ${e.code}');
      rethrow;
    }
  }

  // Helper to handle session sync on successful login
  Future<void> _handleLoginSuccess(User user) async {
    try {
      final deviceId = await DeviceIdManager.getPersistentDeviceId();
      final platform = kIsWeb ? 'Web' : Platform.operatingSystem;
      
      debugPrint('AuthService: [SESSION] Handling login success for UID: ${user.uid}');
      debugPrint('AuthService: [SESSION] Device ID: $deviceId, Platform: $platform');
      
      await _userService.syncUser(user);
      await _userService.syncSession(user.uid, deviceId, platform);
      
      debugPrint('AuthService: [SESSION] Session sync complete.');
    } catch (e) {
      debugPrint('AuthService: [ERROR] _handleLoginSuccess failed: $e');
    }
  }

  // Resolve username to email
  Future<String?> resolveEmailFromUsername(String username) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        return query.docs.first.data()['email'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('AuthService: resolveEmailFromUsername error: $e');
      return null;
    }
  }

  // Register with email and password
  Future<UserCredential?> registerWithEmailAndPassword(String email, String password) async {
    debugPrint('AuthService: [DEBUG] createUserWithEmailAndPassword() starting for $email');
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      debugPrint('AuthService: [DEBUG] createUserWithEmailAndPassword() SUCCESS');
      
      if (userCredential.user != null) {
        await _handleLoginSuccess(userCredential.user!);
      }
      
      return userCredential;
    } on FirebaseAuthException catch (e) {
      debugPrint('AuthService: [DEBUG] createUserWithEmailAndPassword() FAILED: Code=${e.code}, Message=${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('AuthService: [DEBUG] createUserWithEmailAndPassword() UNKNOWN ERROR: $e');
      rethrow;
    }
  }

  // Send email verification
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    debugPrint('AuthService: [DEBUG] sendEmailVerification() starting for ${user?.email}');
    if (user == null) {
      debugPrint('AuthService: [DEBUG] sendEmailVerification() FAILED: Current user is NULL');
      throw Exception('User not logged in');
    }
    try {
      await user.sendEmailVerification();
      debugPrint('AuthService: [DEBUG] sendEmailVerification() SUCCESS');
    } on FirebaseAuthException catch (e) {
      debugPrint('AuthService: [DEBUG] sendEmailVerification() FAILED: Code=${e.code}, Message=${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('AuthService: [DEBUG] sendEmailVerification() UNKNOWN ERROR: $e');
      rethrow;
    }
  }

  // Reload current user to refresh emailVerified status
  Future<void> reloadUser() async {
    await _auth.currentUser?.reload();
  }

  // Update password
  Future<void> updatePassword(String newPassword) async {
    try {
      await _auth.currentUser?.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      debugPrint('AuthService: updatePassword error: ${e.message}');
      rethrow;
    }
  }

  // Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    debugPrint('AuthService: [DEBUG] Starting signInWithGoogle flow...');
    
    try {
      debugPrint('AuthService: [DEBUG] Step 1: Ensuring GoogleSignIn is initialized...');
      await _ensureInitialized();
      debugPrint('AuthService: [DEBUG] Step 1: Initialization complete.');

      // Force account picker by disconnecting and signing out first
      try {
        debugPrint('AuthService: [DEBUG] Step 2: Prep - Disconnecting existing Google account...');
        await _googleSignIn.disconnect().catchError((e) {
          debugPrint('AuthService: [DEBUG] Disconnect failed (normal if first time): $e');
          return null;
        });
        debugPrint('AuthService: [DEBUG] Step 2: Signing out from Google...');
        await _googleSignIn.signOut().catchError((e) {
          debugPrint('AuthService: [DEBUG] SignOut failed (normal): $e');
          return null;
        });
      } catch (e) {
        debugPrint('AuthService: [DEBUG] Prep error (safe to ignore): $e');
      }

      // Authenticate
      debugPrint('AuthService: [DEBUG] Step 3: Triggering account picker via authenticate()...');
      // In 7.2.0, authenticate() replaces signIn()
      final googleUser = await _googleSignIn.authenticate();
      debugPrint('AuthService: [DEBUG] Step 3: Google User authenticated: ${googleUser.email}');

      // Get tokens
      debugPrint('AuthService: [DEBUG] Step 4: Retrieving authentication details (idToken)...');
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      debugPrint('AuthService: [DEBUG] Step 4: idToken available: ${googleAuth.idToken != null}');
      
      // Optionally retrieve access token for scopes if needed (often required by Firebase)
      debugPrint('AuthService: [DEBUG] Step 5: Requesting authorization for scopes...');
      final authz = await googleUser.authorizationClient.authorizationForScopes(['openid', 'email', 'profile']);
      debugPrint('AuthService: [DEBUG] Step 5: Authorization for scopes retrieved: ${authz != null}');

      // Create Firebase Credential
      debugPrint('AuthService: [DEBUG] Step 6: Creating Firebase GoogleAuthProvider credential...');
      final credential = GoogleAuthProvider.credential(
        accessToken: authz?.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase
      debugPrint('AuthService: [DEBUG] Step 7: Calling signInWithCredential on FirebaseAuth...');
      final userCredential = await _auth.signInWithCredential(credential);
      debugPrint('AuthService: [DEBUG] Step 7: FirebaseAuth sign-in successful. UID: ${userCredential.user?.uid}');
      
      if (userCredential.user != null) {
        await _handleLoginSuccess(userCredential.user!);
      }

      return userCredential;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        debugPrint('AuthService: [DEBUG] User cancelled the Google Sign-In picker.');
        return null;
      }
      debugPrint('AuthService: [FATAL ERROR] Google Sign-In failed (GoogleSignInException): $e');
      debugPrint('AuthService: [DEBUG] Code: ${e.code}');
      throw Exception("Google Sign-In failed: $e");
    } on FirebaseAuthException catch (e) {
      debugPrint('AuthService: [FATAL ERROR] FirebaseAuthException: ${e.code} - ${e.message}');
      throw Exception("Firebase Auth Error: ${e.message}");
    } catch (e, stackTrace) {
      debugPrint('AuthService: [FATAL ERROR] Unexpected error during Google Sign-In: $e');
      debugPrint('AuthService: [STACK TRACE]: $stackTrace');
      throw Exception("Google Sign-In failed: $e");
    }
  }

  // Sign out
  Future<void> signOut() async {
    debugPrint('AuthService: [DEBUG] Starting signOut flow...');
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final deviceId = await DeviceIdManager.getPersistentDeviceId();
        await _userService.deactivateSession(user.uid, deviceId);
      }
      
      // Clear all resource state and listeners to prevent data leakage
      ResourceService().clear();
      
      await _ensureInitialized();
      await Future.wait<dynamic>([
        _auth.signOut(),
        _googleSignIn.signOut(),
      ]);
      debugPrint('AuthService: [DEBUG] Sign out successful.');
    } catch (e) {
      debugPrint('AuthService: [ERROR] Sign out error: $e');
    }
  }

  // Password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      debugPrint('AuthService: sendPasswordResetEmail error: ${e.message}');
      rethrow;
    }
  }
}
