import 'package:flutter/material.dart';
import 'persistence_service.dart';

class ReadingProgressEntry {
  final int pageNumber;
  final int totalPages;
  final double progress;
  final DateTime updatedAt;

  ReadingProgressEntry({
    required this.pageNumber,
    required this.totalPages,
    required this.progress,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'pageNumber': pageNumber,
        'totalPages': totalPages,
        'progress': progress,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ReadingProgressEntry.fromJson(Map<String, dynamic> json) => ReadingProgressEntry(
        pageNumber: json['pageNumber'] as int? ?? 1,
        totalPages: json['totalPages'] as int? ?? 1,
        progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );
}

class ProgressService extends ChangeNotifier {
  static final ProgressService _instance = ProgressService._internal();
  factory ProgressService() => _instance;
  ProgressService._internal() {
    _restoreProgress();
  }

  Map<String, double> _readingProgress = {};
  Map<String, ReadingProgressEntry> _detailedProgress = {};

  double getProgress(String identifier, {String? fallbackTitle}) {
    if (_readingProgress.containsKey(identifier)) {
      return _readingProgress[identifier] ?? 0.0;
    }
    if (fallbackTitle != null && _readingProgress.containsKey(fallbackTitle)) {
      return _readingProgress[fallbackTitle] ?? 0.0;
    }
    return 0.0;
  }

  int getSavedPage(String identifier, {String? fallbackTitle}) {
    final entry = _detailedProgress[identifier] ??
        (fallbackTitle != null ? _detailedProgress[fallbackTitle] : null);
    if (entry != null) {
      return entry.pageNumber;
    }
    // Fallback: estimate from progress if total pages known
    final prog = getProgress(identifier, fallbackTitle: fallbackTitle);
    return prog > 0 ? (prog * 100).round().clamp(1, 100) : 1;
  }

  ReadingProgressEntry? getEntry(String identifier, {String? fallbackTitle}) {
    return _detailedProgress[identifier] ??
        (fallbackTitle != null ? _detailedProgress[fallbackTitle] : null);
  }

  Future<void> _restoreProgress() async {
    // 1. Restore legacy map first to guarantee backward compatibility
    final legacyJson = PersistenceService().getJson('reading_progress');
    if (legacyJson != null && legacyJson is Map) {
      _readingProgress = Map<String, double>.from(
        legacyJson.map((k, v) => MapEntry(k as String, (v as num).toDouble())),
      );
    }

    // 2. Restore detailed v2 model
    final v2Json = PersistenceService().getJson('reading_progress_v2');
    if (v2Json != null && v2Json is Map) {
      _detailedProgress = Map<String, ReadingProgressEntry>.from(
        v2Json.map((k, v) => MapEntry(
              k as String,
              ReadingProgressEntry.fromJson(Map<String, dynamic>.from(v as Map)),
            )),
      );
      // Synchronize reading progress map
      for (final entry in _detailedProgress.entries) {
        _readingProgress[entry.key] = entry.value.progress;
      }
    } else {
      // Migrate legacy progress to v2 without destroying data
      for (final entry in _readingProgress.entries) {
        _detailedProgress[entry.key] = ReadingProgressEntry(
          pageNumber: (entry.value * 100).round().clamp(1, 100),
          totalPages: 100,
          progress: entry.value,
          updatedAt: DateTime.now(),
        );
      }
    }
    notifyListeners();
  }

  Future<void> _saveProgress() async {
    await PersistenceService().setJson('reading_progress', _readingProgress);
    final v2Map = _detailedProgress.map((k, v) => MapEntry(k, v.toJson()));
    await PersistenceService().setJson('reading_progress_v2', v2Map);
  }

  void updateProgress(
    String identifier,
    double progress, {
    int? pageNumber,
    int? totalPages,
    String? title,
  }) {
    final cleanProgress = progress.clamp(0.0, 1.0);
    final safeTotal = (totalPages != null && totalPages > 0) ? totalPages : 1;
    final safePage = (pageNumber != null && pageNumber > 0)
        ? pageNumber.clamp(1, safeTotal)
        : (cleanProgress * safeTotal).round().clamp(1, safeTotal);

    final entry = ReadingProgressEntry(
      pageNumber: safePage,
      totalPages: safeTotal,
      progress: cleanProgress,
      updatedAt: DateTime.now(),
    );

    _detailedProgress[identifier] = entry;
    _readingProgress[identifier] = cleanProgress;

    // Also mirror to title if provided and different, preserving backward compatibility
    if (title != null && title.isNotEmpty && title != identifier) {
      _detailedProgress[title] = entry;
      _readingProgress[title] = cleanProgress;
    }

    _saveProgress();
    notifyListeners();
  }

  bool hasProgress(String identifier, {String? fallbackTitle}) {
    return _readingProgress.containsKey(identifier) ||
        (fallbackTitle != null && _readingProgress.containsKey(fallbackTitle));
  }

  void clear() {
    _readingProgress.clear();
    _detailedProgress.clear();
    _saveProgress();
    notifyListeners();
  }
}
