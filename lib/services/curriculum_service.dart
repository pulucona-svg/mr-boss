import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/curriculum_model.dart';
import 'course_service.dart';

class CurriculumService extends ChangeNotifier {
  static final CurriculumService _instance = CurriculumService._internal();
  factory CurriculumService() => _instance;
  CurriculumService._internal();

  @visibleForTesting
  static void resetInstance() {
    _instance.clear();
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  List<CurriculumRecord> _records = [];
  bool _isLoading = false;
  StreamSubscription? _curriculumSub;
  bool _isListening = false;

  List<CurriculumRecord> get allRecords => List.unmodifiable(_records);
  List<CurriculumRecord> get activeRecords => _records.where((r) => r.isActive).toList();
  bool get isLoading => _isLoading;

  void clear() {
    _curriculumSub?.cancel();
    _curriculumSub = null;
    _isListening = false;
    _records = [];
    _isLoading = false;
    notifyListeners();
  }

  @visibleForTesting
  void setRecords(List<CurriculumRecord> records) {
    _records = List.from(records);
    notifyListeners();
  }

  /// Listens to real-time updates from /curriculum.
  void startRealtimeSync() {
    if (_isListening) return;
    _isListening = true;

    _curriculumSub?.cancel();
    _curriculumSub = _firestore
        .collection('curriculum')
        .snapshots()
        .listen((snapshot) {
      _records = snapshot.docs.map((doc) => CurriculumRecord.fromMap(doc.data(), doc.id)).toList();
      _records.sort((a, b) {
        final cmp = a.programCode.compareTo(b.programCode);
        if (cmp != 0) return cmp;
        return a.unitCode.compareTo(b.unitCode);
      });
      notifyListeners();
      
      // Keep CourseService in sync with authoritative active units
      CourseService().syncFromCurriculumRecords(_records);
    }, onError: (e) {
      debugPrint('CurriculumService: [ERROR] Realtime sync error: $e');
    });
  }

  /// Fetches all records from backend (one-time).
  Future<void> fetchAll() async {
    _isLoading = true;
    notifyListeners();
    try {
      final snap = await _firestore.collection('curriculum').get();
      _records = snap.docs.map((d) => CurriculumRecord.fromMap(d.data(), d.id)).toList();
      _records.sort((a, b) {
        final cmp = a.programCode.compareTo(b.programCode);
        if (cmp != 0) return cmp;
        return a.unitCode.compareTo(b.unitCode);
      });
      CourseService().syncFromCurriculumRecords(_records);
    } catch (e) {
      debugPrint('CurriculumService: [ERROR] fetchAll failed: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Creates a new curriculum record with deterministic ID & validation.
  Future<String> addRecord(CurriculumRecord record) async {
    if (record.isActive && !record.isValidForActivation) {
      throw Exception('Cannot activate curriculum record: one or more required fields are incomplete.');
    }

    try {
      final callable = _functions.httpsCallable('createCurriculumRecord');
      final result = await callable.call({
        'programCode': record.programCode,
        'programName': record.programName,
        'unitCode': record.unitCode,
        'unitName': record.unitName,
        'yearOfStudy': record.yearOfStudy,
        'semester': record.semester,
        'lecturerName': record.lecturerName,
        'isActive': record.isActive,
      });

      final newId = result.data['id'] as String;
      // Optimistic update
      _records.removeWhere((r) => r.id == newId);
      _records.add(record.copyWith(id: newId));
      _records.sort((a, b) {
        final cmp = a.programCode.compareTo(b.programCode);
        if (cmp != 0) return cmp;
        return a.unitCode.compareTo(b.unitCode);
      });
      notifyListeners();
      CourseService().syncFromCurriculumRecords(_records);
      return newId;
    } catch (e) {
      debugPrint('CurriculumService: [ERROR] addRecord failed: $e');
      rethrow;
    }
  }

  /// Updates an existing record.
  Future<void> updateRecord(String id, Map<String, dynamic> updates) async {
    final cleanId = id.trim();
    final idx = _records.indexWhere((r) => r.id == cleanId);
    if (idx != -1) {
      final existing = _records[idx];
      final newIsActive = updates.containsKey('isActive') ? (updates['isActive'] == true) : existing.isActive;
      final newPCode = (updates['programCode'] ?? existing.programCode).toString();
      final newPName = (updates['programName'] ?? existing.programName).toString();
      final newUCode = (updates['unitCode'] ?? existing.unitCode).toString();
      final newUName = (updates['unitName'] ?? existing.unitName).toString();
      final newYear = (updates['yearOfStudy'] ?? existing.yearOfStudy).toString();
      final newSem = (updates['semester'] ?? existing.semester).toString();

      if (newIsActive && (newPCode.trim().isEmpty ||
          newPName.trim().isEmpty ||
          newUCode.trim().isEmpty ||
          newUName.trim().isEmpty ||
          newYear.trim().isEmpty ||
          newSem.trim().isEmpty)) {
        throw Exception('Cannot activate curriculum record: one or more required fields are incomplete.');
      }
    }

    try {
      final callable = _functions.httpsCallable('updateCurriculumRecord');
      await callable.call({
        'id': cleanId,
        'updates': updates,
      });

      if (idx != -1) {
        final current = _records[idx];
        _records[idx] = current.copyWith(
          programCode: updates['programCode'] as String?,
          programName: updates['programName'] as String?,
          unitCode: updates['unitCode'] as String?,
          unitName: updates['unitName'] as String?,
          yearOfStudy: updates['yearOfStudy'] as String?,
          semester: updates['semester'] as String?,
          lecturerName: updates['lecturerName'] as String?,
          isActive: updates['isActive'] as bool?,
          updatedAt: DateTime.now(),
        );
        notifyListeners();
        CourseService().syncFromCurriculumRecords(_records);
      }
    } catch (e) {
      debugPrint('CurriculumService: [ERROR] updateRecord failed: $e');
      rethrow;
    }
  }

  /// Toggles isActive with strict server-side validation.
  Future<void> toggleActive(String id, bool isActive) async {
    final cleanId = id.trim();
    final idx = _records.indexWhere((r) => r.id == cleanId);
    if (idx != -1) {
      final r = _records[idx];
      if (isActive && !r.isValidForActivation) {
        throw Exception('Cannot activate curriculum record: required fields are missing.');
      }
    }

    try {
      final callable = _functions.httpsCallable('toggleCurriculumActive');
      await callable.call({
        'id': cleanId,
        'isActive': isActive,
      });

      if (idx != -1) {
        _records[idx] = _records[idx].copyWith(
          isActive: isActive,
          updatedAt: DateTime.now(),
        );
        notifyListeners();
        CourseService().syncFromCurriculumRecords(_records);
      }
    } catch (e) {
      debugPrint('CurriculumService: [ERROR] toggleActive failed: $e');
      rethrow;
    }
  }

  /// Deletes a curriculum record.
  Future<void> deleteRecord(String id) async {
    final cleanId = id.trim();
    try {
      final callable = _functions.httpsCallable('deleteCurriculumRecord');
      await callable.call({'id': cleanId});

      _records.removeWhere((r) => r.id == cleanId);
      notifyListeners();
      CourseService().syncFromCurriculumRecords(_records);
    } catch (e) {
      debugPrint('CurriculumService: [ERROR] deleteRecord failed: $e');
      rethrow;
    }
  }

  /// Batch migrates initial curriculum records into Firestore.
  Future<int> migrateFromLessonsJson(List<dynamic> rawRecords) async {
    _isLoading = true;
    notifyListeners();
    try {
      final callable = _functions.httpsCallable('migrateCurriculumData');
      final result = await callable.call({'records': rawRecords});
      final count = (result.data['migratedCount'] as num?)?.toInt() ?? 0;
      await fetchAll();
      return count;
    } catch (e) {
      debugPrint('CurriculumService: [ERROR] migration failed: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
