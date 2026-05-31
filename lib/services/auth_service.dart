import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'user_service.dart';

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
        await _userService.syncUser(userCredential.user!);
      }
      return userCredential;
    } on FirebaseAuthException catch (e) {
      debugPrint('AuthService: signInWithEmailAndPassword error: ${e.message}');
      rethrow;
    }
  }

  // Register with email and password
  Future<UserCredential?> registerWithEmailAndPassword(String email, String password) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      if (userCredential.user != null) {
        await _userService.syncUser(userCredential.user!);
      }
      return userCredential;
    } on FirebaseAuthException catch (e) {
      debugPrint('AuthService: registerWithEmailAndPassword error: ${e.message}');
      rethrow;
    }
  }

  // Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    debugPrint('AuthService: [DEBUG] Starting signInWithGoogle flow...');
    
    try {
      await _ensureInitialized();

      // Force account picker by disconnecting and signing out first
      try {
        await _googleSignIn.disconnect().catchError((_) => null);
        await _googleSignIn.signOut().catchError((_) => null);
      } catch (e) {
        debugPrint('AuthService: [DEBUG] Prep error (safe to ignore): $e');
      }

      // Authenticate
      debugPrint('AuthService: [DEBUG] Calling authenticate()...');
      // In 7.2.0, authenticate() replaces signIn()
      final googleUser = await _googleSignIn.authenticate();
      debugPrint('AuthService: [DEBUG] Google User authenticated: ${googleUser.email}');

      // Get tokens
      debugPrint('AuthService: [DEBUG] Retrieving authentication details...');
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      
      // Optionally retrieve access token for scopes if needed (often required by Firebase)
      final authz = await googleUser.authorizationClient.authorizationForScopes(['openid', 'email', 'profile']);
      debugPrint('AuthService: [DEBUG] Tokens retrieved.');

      // Create Firebase Credential
      debugPrint('AuthService: [DEBUG] Creating Firebase GoogleAuthProvider credential...');
      final credential = GoogleAuthProvider.credential(
        accessToken: authz?.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase
      debugPrint('AuthService: [DEBUG] Calling signInWithCredential on FirebaseAuth...');
      final userCredential = await _auth.signInWithCredential(credential);
      debugPrint('AuthService: [DEBUG] FirebaseAuth sign-in successful. UID: ${userCredential.user?.uid}');
      
      if (userCredential.user != null) {
        await _userService.syncUser(userCredential.user!);
      }

      return userCredential;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        debugPrint('AuthService: [DEBUG] User cancelled the Google Sign-In picker.');
        return null;
      }
      debugPrint('AuthService: [FATAL ERROR] Google Sign-In failed: $e');
      throw Exception("Google Sign-In failed: $e");
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
