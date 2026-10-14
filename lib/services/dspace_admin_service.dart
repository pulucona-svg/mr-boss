import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/dspace_job_model.dart';

/// Client service managing administrative DSpace synchronization operations.
///
/// Communicates authoritatively with Cloud Functions and listens to real-time
/// job progress in Firestore.
class DSpaceAdminService extends ChangeNotifier {
  static final DSpaceAdminService _instance = DSpaceAdminService._internal();
  factory DSpaceAdminService() => _instance;
  DSpaceAdminService._internal();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isActionInProgress = false;
  bool get isActionInProgress => _isActionInProgress;

  String? _activeJobId;
  String? get activeJobId => _activeJobId;

  String? _lastError;
  String? get lastError => _lastError;

  /// Starts a new DSpace job ('check' or 'check_and_download')
  Future<String> startDSpaceJob(String action) async {
    _isActionInProgress = true;
    _lastError = null;
    notifyListeners();

    try {
      final callable = _functions.httpsCallable(
        'startDSpaceJob',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );

      final result = await callable.call({'action': action});
      final data = result.data as Map<dynamic, dynamic>? ?? {};

      if (data['success'] != true || data['jobId'] == null) {
        throw Exception(data['message'] ?? 'Failed to start DSpace job.');
      }

      final jobId = data['jobId'] as String;
      _activeJobId = jobId;
      _isActionInProgress = false;
      notifyListeners();
      return jobId;
    } on FirebaseFunctionsException catch (e) {
      _lastError = e.message ?? e.code;
      _isActionInProgress = false;
      notifyListeners();
      rethrow;
    } catch (e) {
      _lastError = e.toString();
      _isActionInProgress = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Cancels an in-progress DSpace job
  Future<void> cancelDSpaceJob(String jobId) async {
    try {
      final callable = _functions.httpsCallable('cancelDSpaceJob');
      await callable.call({'jobId': jobId});
    } catch (e) {
      debugPrint('[DSPACE_SERVICE] Failed to cancel job $jobId: $e');
      rethrow;
    }
  }

  /// Real-time stream of a specific DSpace job
  Stream<DSpaceJobModel?> watchJob(String jobId) {
    return _firestore
        .collection('dspace_jobs')
        .doc(jobId)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      return DSpaceJobModel.fromFirestore(snap);
    });
  }

  /// Real-time stream of the latest DSpace job
  Stream<DSpaceJobModel?> watchLatestJob() {
    return _firestore
        .collection('dspace_jobs')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      return DSpaceJobModel.fromFirestore(snap.docs.first);
    });
  }
}
