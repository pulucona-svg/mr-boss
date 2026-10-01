import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import 'connectivity_service.dart';
import 'persistence_service.dart';

/// Centralized service managing offline-first view counting and idempotent
/// online synchronization for manual / sponsored advertisements.
class ManualAdViewTracker extends ChangeNotifier {
  static final ManualAdViewTracker _instance = ManualAdViewTracker._internal();
  factory ManualAdViewTracker() => _instance;
  ManualAdViewTracker._internal();

  /// Key used in [PersistenceService] (SharedPreferences) to persist pending views
  static const String _kPendingViewsKey = 'manual_ad_pending_views_v1';

  FirebaseFunctions? _functionsInstance;
  FirebaseFunctions get _functions => _functionsInstance ??= FirebaseFunctions.instance;

  @visibleForTesting
  set functionsForTesting(FirebaseFunctions functions) => _functionsInstance = functions;

  final Map<String, int> _pendingViews = {};
  bool _isInitialized = false;
  bool _isSyncing = false;
  Timer? _debounceTimer;

  bool get isInitialized => _isInitialized;
  bool get isSyncing => _isSyncing;

  /// Unmodifiable view of currently pending view counts per ad ID
  Map<String, int> get pendingViews => Map.unmodifiable(_pendingViews);

  /// Returns total pending views across all manual ads on this device
  int get totalPendingViews => _pendingViews.values.fold(0, (sum, count) => sum + count);

  /// Returns the pending view count for a specific ad ID
  int getPendingViews(String adId) => _pendingViews[adId] ?? 0;

  // ==========================================
  // TESTING HOOKS
  // ==========================================
  @visibleForTesting
  Future<bool> Function({required String batchId, required Map<String, int> deltas})?
      syncCallOverrideForTesting;

  @visibleForTesting
  bool Function()? isOfflineOverrideForTesting;

  /// Initializes the service from local disk and registers connectivity observation.
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    _loadFromDisk();

    ConnectivityService().addListener(_onConnectivityChanged);

    // If online at launch and pending views exist, attempt background sync
    final bool isOffline = isOfflineOverrideForTesting != null
        ? isOfflineOverrideForTesting!()
        : ConnectivityService().isOffline;

    if (!isOffline && _pendingViews.isNotEmpty) {
      unawaited(syncPendingViews());
    }
  }

  void _onConnectivityChanged() {
    final bool isOffline = isOfflineOverrideForTesting != null
        ? isOfflineOverrideForTesting!()
        : ConnectivityService().isOffline;

    if (!isOffline && _pendingViews.isNotEmpty) {
      if (kDebugMode) {
        debugPrint(
          'ManualAdViewTracker: [CONNECTIVITY] Device returned online. '
          'Attempting synchronization of ${_pendingViews.length} pending ad view counts...',
        );
      }
      unawaited(syncPendingViews());
    }
  }

  /// Records an actual user-facing display for the specified advertisement ID.
  /// 
  /// Increments the local pending count immediately and persists it to disk.
  /// This operation succeeds completely offline without requiring Firestore.
  void recordDisplay(String adId) {
    final cleanId = adId.trim();
    if (cleanId.isEmpty || cleanId == 'emergency_bootstrap_cyber') {
      // Emergency bootstrap is an offline fallback asset and not a tracked server ad
      return;
    }

    final current = _pendingViews[cleanId] ?? 0;
    _pendingViews[cleanId] = current + 1;
    _saveToDisk();
    notifyListeners();

    if (kDebugMode) {
      debugPrint(
        'ManualAdViewTracker: [DISPLAY_RECORDED] Ad "$cleanId" view recorded. '
        'Pending local count: ${_pendingViews[cleanId]}. Total pending: $totalPendingViews',
      );
    }

    // Trigger debounced synchronization if online
    final bool isOffline = isOfflineOverrideForTesting != null
        ? isOfflineOverrideForTesting!()
        : ConnectivityService().isOffline;

    if (!isOffline) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(seconds: 2), () {
        if (!_isSyncing) {
          syncPendingViews();
        }
      });
    }
  }

  /// Synchronizes all accumulated pending views to the server.
  /// 
  /// Uses a snapshot isolation model: only the exact quantities present in the
  /// in-flight snapshot are deducted upon success. Any new views accumulated
  /// while the upload is in progress remain safely pending for the next cycle.
  Future<bool> syncPendingViews() async {
    if (_isSyncing) {
      if (kDebugMode) {
        debugPrint('ManualAdViewTracker: [SYNC_SKIP] Synchronization is already in progress.');
      }
      return false;
    }

    final bool isOffline = isOfflineOverrideForTesting != null
        ? isOfflineOverrideForTesting!()
        : ConnectivityService().isOffline;

    if (isOffline) {
      if (kDebugMode) {
        debugPrint('ManualAdViewTracker: [SYNC_SKIP] Device is offline. Retaining pending views on disk.');
      }
      return false;
    }

    // Filter positive view deltas
    final Map<String, int> snapshot = {};
    _pendingViews.forEach((key, value) {
      if (value > 0) {
        snapshot[key] = value;
      }
    });

    if (snapshot.isEmpty) {
      return true;
    }

    _isSyncing = true;
    final String batchId = const Uuid().v4();

    if (kDebugMode) {
      debugPrint(
        'ManualAdViewTracker: [SYNC_START] Initiating sync for batch "$batchId" with ${snapshot.length} ads...',
      );
    }

    try {
      bool success = false;

      if (syncCallOverrideForTesting != null) {
        success = await syncCallOverrideForTesting!(batchId: batchId, deltas: snapshot);
      } else {
        final callable = _functions.httpsCallable('syncManualAdViews');
        final response = await callable.call({
          'batchId': batchId,
          'deltas': snapshot,
        });

        if (response.data is Map) {
          final resMap = Map<String, dynamic>.from(response.data as Map);
          success = resMap['success'] == true;
        }
      }

      if (success) {
        // Snapshot deduction: safely subtract ONLY the quantities accepted in this batch
        for (final entry in snapshot.entries) {
          final current = _pendingViews[entry.key] ?? 0;
          final remaining = current - entry.value;
          if (remaining <= 0) {
            _pendingViews.remove(entry.key);
          } else {
            _pendingViews[entry.key] = remaining;
          }
        }

        _saveToDisk();

        if (kDebugMode) {
          debugPrint(
            'ManualAdViewTracker: [SYNC_SUCCESS] Batch "$batchId" successfully uploaded. '
            'Remaining pending views: $totalPendingViews',
          );
        }

        notifyListeners();
        _isSyncing = false;
        return true;
      } else {
        if (kDebugMode) {
          debugPrint('ManualAdViewTracker: [SYNC_REJECTED] Server rejected batch "$batchId". Retaining pending views.');
        }
        _isSyncing = false;
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ManualAdViewTracker: [SYNC_ERROR] Error uploading view batch "$batchId": $e. Will retry.');
      }
      _isSyncing = false;
      return false;
    }
  }

  void _loadFromDisk() {
    try {
      final jsonStr = PersistenceService().getString(_kPendingViewsKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final Map<String, dynamic> rawMap = jsonDecode(jsonStr);
        _pendingViews.clear();
        rawMap.forEach((key, value) {
          if (value is int && value > 0) {
            _pendingViews[key] = value;
          }
        });
        if (kDebugMode) {
          debugPrint(
            'ManualAdViewTracker: [DISK_LOAD] Restored ${_pendingViews.length} pending ad view entries '
            'from local persistent storage (Total: $totalPendingViews views).',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ManualAdViewTracker: [DISK_LOAD_ERROR] Failed to load pending views: $e');
      }
    }
  }

  void _saveToDisk() {
    try {
      if (_pendingViews.isEmpty) {
        PersistenceService().remove(_kPendingViewsKey);
      } else {
        PersistenceService().setString(_kPendingViewsKey, jsonEncode(_pendingViews));
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ManualAdViewTracker: [DISK_SAVE_ERROR] Failed to save pending views: $e');
      }
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingViews.clear();
    _saveToDisk();
    _isSyncing = false;
    _isInitialized = false;
    syncCallOverrideForTesting = null;
    isOfflineOverrideForTesting = null;
  }
}
