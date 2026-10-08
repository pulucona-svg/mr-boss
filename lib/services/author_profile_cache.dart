import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// In-memory cache and fetcher for commenter user profiles and authors.
///
/// Ensures commenter avatars and usernames are refreshed from authoritative
/// `users/{authorId}` documents without causing N+1 Firestore query storms
/// on every widget build, and reliably resolves anonymized/deleted users to
/// "Anonymous User".
class AuthorProfileCache extends ChangeNotifier {
  static AuthorProfileCache _instance = AuthorProfileCache._internal();
  factory AuthorProfileCache() => _instance;
  AuthorProfileCache._internal();

  static const String anonymousName = 'Anonymous User';
  static const String anonymousMaskAsset = 'assets/images/anonymous_mask.png';

  @visibleForTesting
  static void resetInstance() {
    _instance = AuthorProfileCache._internal();
  }

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  final Map<String, String?> _photoCache = {};
  final Map<String, String?> _nameCache = {};
  final Set<String> _pendingUids = {};
  final Set<String> _anonymizedUids = {};

  /// Checks if a UID is recognized as an anonymized or deleted user.
  bool isAnonymized(String uid) {
    if (uid.isEmpty || uid == 'anonymous' || uid == 'deleted') return true;
    return _anonymizedUids.contains(uid);
  }

  /// Retrieves the cached profile picture URL, or falls back to [fallback].
  String? getPhoto(String uid, {String? fallback}) {
    if (uid.isEmpty || uid == 'anonymous' || uid == 'deleted' || _anonymizedUids.contains(uid)) {
      return null;
    }
    if (_photoCache.containsKey(uid)) {
      return _photoCache[uid] ?? fallback;
    }
    return fallback;
  }

  /// Retrieves the cached display name, or falls back to [fallback].
  String? getName(String uid, {String? fallback}) {
    if (uid.isEmpty || uid == 'anonymous' || uid == 'deleted' || _anonymizedUids.contains(uid)) {
      return anonymousName;
    }
    if (_nameCache.containsKey(uid)) {
      return _nameCache[uid] ?? fallback ?? anonymousName;
    }
    return fallback ?? anonymousName;
  }

  /// Test helper to pre-populate cache.
  @visibleForTesting
  void setCachedProfileForTesting(String uid, {String? photoURL, String? username, bool isAnon = false}) {
    if (isAnon) {
      _anonymizedUids.add(uid);
      _photoCache[uid] = null;
      _nameCache[uid] = anonymousName;
    } else {
      _photoCache[uid] = photoURL;
      _nameCache[uid] = username;
    }
    notifyListeners();
  }

  /// Fetches authoritative profile information for [uid] if not already cached.
  Future<void> loadAuthor(String uid) async {
    if (uid.isEmpty || uid == 'anonymous' || uid == 'deleted') {
      _anonymizedUids.add(uid);
      _photoCache[uid] = null;
      _nameCache[uid] = anonymousName;
      return;
    }

    if (_photoCache.containsKey(uid) || _pendingUids.contains(uid)) {
      return;
    }

    _pendingUids.add(uid);
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data();
        final isAnon = data?['isAnonymized'] == true ||
            data?['deletionStatus'] == 'permanently_deleted';

        if (isAnon) {
          _anonymizedUids.add(uid);
          _photoCache[uid] = null;
          _nameCache[uid] = anonymousName;
        } else {
          _photoCache[uid] = data?['photoURL'] as String?;
          _nameCache[uid] = data?['username'] as String?;
        }
        notifyListeners();
      } else {
        // Document does not exist in Firestore (permanently scrubbed/deleted user)
        _anonymizedUids.add(uid);
        _photoCache[uid] = null;
        _nameCache[uid] = anonymousName;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('AuthorProfileCache: [WARN] Failed to fetch author $uid: $e');
    } finally {
      _pendingUids.remove(uid);
    }
  }

  /// Batch prefetches authors for a collection of UIDs.
  void prefetchAll(Iterable<String> uids) {
    for (final uid in uids) {
      if (uid.isNotEmpty && !_photoCache.containsKey(uid) && !_pendingUids.contains(uid)) {
        loadAuthor(uid);
      }
    }
  }
}
