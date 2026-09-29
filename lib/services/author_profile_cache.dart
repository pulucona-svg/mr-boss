import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// In-memory cache and fetcher for commenter user profiles.
///
/// Ensures commenter avatars and usernames are refreshed from authoritative
/// `users/{authorId}` documents without causing N+1 Firestore query storms
/// on every widget build.
class AuthorProfileCache extends ChangeNotifier {
  static AuthorProfileCache _instance = AuthorProfileCache._internal();
  factory AuthorProfileCache() => _instance;
  AuthorProfileCache._internal();

  @visibleForTesting
  static void resetInstance() {
    _instance = AuthorProfileCache._internal();
  }

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  final Map<String, String?> _photoCache = {};
  final Map<String, String?> _nameCache = {};
  final Set<String> _pendingUids = {};

  /// Retrieves the cached profile picture URL, or falls back to [fallback].
  String? getPhoto(String uid, {String? fallback}) {
    if (uid.isEmpty) return fallback;
    if (_photoCache.containsKey(uid)) {
      return _photoCache[uid] ?? fallback;
    }
    return fallback;
  }

  /// Retrieves the cached display name, or falls back to [fallback].
  String? getName(String uid, {String? fallback}) {
    if (uid.isEmpty) return fallback;
    if (_nameCache.containsKey(uid)) {
      return _nameCache[uid] ?? fallback;
    }
    return fallback;
  }

  /// Test helper to pre-populate cache.
  @visibleForTesting
  void setCachedProfileForTesting(String uid, {String? photoURL, String? username}) {
    _photoCache[uid] = photoURL;
    _nameCache[uid] = username;
    notifyListeners();
  }

  /// Fetches authoritative profile information for [uid] if not already cached.
  Future<void> loadAuthor(String uid) async {
    if (uid.isEmpty || _photoCache.containsKey(uid) || _pendingUids.contains(uid)) {
      return;
    }

    _pendingUids.add(uid);
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data();
        _photoCache[uid] = data?['photoURL'] as String?;
        _nameCache[uid] = data?['username'] as String?;
        notifyListeners();
      } else {
        _photoCache[uid] = null;
        _nameCache[uid] = null;
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
