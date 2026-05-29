import 'package:flutter/material.dart';
import 'persistence_service.dart';

class ProgressService extends ChangeNotifier {
  static final ProgressService _instance = ProgressService._internal();
  factory ProgressService() => _instance;
  ProgressService._internal() {
    _restoreProgress();
  }

  Map<String, double> _readingProgress = {};

  double getProgress(String title) => _readingProgress[title] ?? 0.0;

  Future<void> _restoreProgress() async {
    final json = PersistenceService().getJson('reading_progress');
    if (json != null) {
      _readingProgress = Map<String, double>.from((json as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())));
      notifyListeners();
    }
  }

  Future<void> _saveProgress() async {
    await PersistenceService().setJson('reading_progress', _readingProgress);
  }

  void updateProgress(String title, double progress) {
    // Only update if the new progress is higher than the stored one
    final current = _readingProgress[title] ?? 0.0;
    if (progress > current) {
      _readingProgress[title] = progress;
      _saveProgress();
      notifyListeners();
    }
  }

  bool hasProgress(String title) => _readingProgress.containsKey(title);
}

