import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'user_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserService _userService = UserService();
  
  // Standard GoogleSignIn initialization
  // Using dynamic to bypass persistent analyzer issues with constructor recognition
  // We use .instance if it's a singleton, or GoogleSignIn() if standard.
  // Reverting to what was likely working: .instance
  final dynamic _googleSignIn = GoogleSignIn.instance;

  // Auth state changes stream
  Stream<User?> get user => _auth.authStateChanges();

  // Get current user
  User? get currentUser => _auth.currentUser;

  // The Web Client ID from Google Cloud Console / Firebase.
  // This MUST be the "client_type": 3 ID from your google-services.json.
  static const String _webClientId = '386198984140-4d8s7o98rdds643i18ico294tcco0paj.apps.googleusercontent.com';

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
      // 1. Force account picker
      await _googleSignIn.signOut().catchError((_) => null);

      // 2. Initialize (if this version requires it)
      try {
        await _googleSignIn.initialize(serverClientId: _webClientId);
      } catch (_) {}

      // 3. Authenticate
      debugPrint('AuthService: [DEBUG] Calling signIn()...');
      final dynamic googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        debugPrint('AuthService: [DEBUG] User cancelled the Google Sign-In picker.');
        return null;
      }
      debugPrint('AuthService: [DEBUG] Google User authenticated: ${googleUser.email}');

      // 4. Get tokens
      debugPrint('AuthService: [DEBUG] Retrieving authentication details...');
      final dynamic googleAuth = await googleUser.authentication;
      debugPrint('AuthService: [DEBUG] Tokens retrieved.');

      // 5. Create Firebase Credential
      debugPrint('AuthService: [DEBUG] Creating Firebase GoogleAuthProvider credential...');
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 6. Sign in to Firebase
      debugPrint('AuthService: [DEBUG] Calling signInWithCredential on FirebaseAuth...');
      final userCredential = await _auth.signInWithCredential(credential);
      debugPrint('AuthService: [DEBUG] FirebaseAuth sign-in successful. UID: ${userCredential.user?.uid}');
      
      if (userCredential.user != null) {
        await _userService.syncUser(userCredential.user!);
      }

      return userCredential;
    } catch (e, stackTrace) {
      debugPrint('AuthService: [FATAL ERROR] Google Sign-In failed: $e');
      debugPrint('AuthService: [STACK TRACE]: $stackTrace');
      throw Exception("Google Sign-In failed: $e");
    }
  }

  // Sign out
  Future<void> signOut() async {
    debugPrint('AuthService: [DEBUG] Starting signOut flow...');
    try {
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
