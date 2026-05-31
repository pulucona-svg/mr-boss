import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'user_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserService _userService = UserService();
  
  // Singleton instance for google_sign_in 7.2.0
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  // The Web Client ID from Google Cloud Console / Firebase.
  // This MUST be the "client_type": 3 ID from your google-services.json.
  static const String _webClientId = '386198984140-4d8s7o98rdds643i18ico294tcco0paj.apps.googleusercontent.com';

  bool _isInitialized = false;

  // Auth state changes stream
  Stream<User?> get user => _auth.authStateChanges();

  // Get current user
  User? get currentUser => _auth.currentUser;

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      debugPrint('AuthService: [DEBUG] Initializing GoogleSignIn with serverClientId: $_webClientId');
      try {
        await _googleSignIn.initialize(
          serverClientId: _webClientId,
        );
        _isInitialized = true;
        debugPrint('AuthService: [DEBUG] GoogleSignIn initialization successful.');
      } catch (e) {
        debugPrint('AuthService: [ERROR] GoogleSignIn initialization failed: $e');
        rethrow;
      }
    }
  }

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
      // 1. Mandatory initialization for 7.2.0
      await _ensureInitialized();

      // 2. Authenticate (Identity Flow)
      debugPrint('AuthService: [DEBUG] Calling authenticate(scopeHint: [email, profile])...');
      final GoogleSignInAccount? googleUser = await _googleSignIn.authenticate(
        scopeHint: ['email', 'profile'],
      );

      if (googleUser == null) {
        debugPrint('AuthService: [DEBUG] User cancelled the Google Sign-In picker.');
        return null;
      }
      debugPrint('AuthService: [DEBUG] Google User authenticated: ${googleUser.email}');

      // 3. Get Identity (idToken)
      debugPrint('AuthService: [DEBUG] Retrieving authentication details (idToken)...');
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      debugPrint('AuthService: [DEBUG] idToken retrieved (length: ${googleAuth.idToken?.length ?? 0})');

      // 4. Get Authorization (accessToken)
      // In 7.2.0, accessToken is retrieved explicitly via the authorizationClient.
      debugPrint('AuthService: [DEBUG] Requesting authorization for scopes [email, profile]...');
      final clientAuth = await googleUser.authorizationClient.authorizeScopes(['email', 'profile']);
      debugPrint('AuthService: [DEBUG] accessToken retrieved (length: ${clientAuth.accessToken.length})');

      // 5. Create Firebase Credential
      debugPrint('AuthService: [DEBUG] Creating Firebase GoogleAuthProvider credential...');
      final credential = GoogleAuthProvider.credential(
        accessToken: clientAuth.accessToken,
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
      await Future.wait([
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
