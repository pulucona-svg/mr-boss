import 'package:flutter/material.dart';

class ProgressService extends ChangeNotifier {
  static final ProgressService _instance = ProgressService._internal();
  factory ProgressService() => _instance;
  ProgressService._internal();

  final Map<String, double> _readingProgress = {};

  double getProgress(String title) => _readingProgress[title] ?? 0.0;

  void updateProgress(String title, double progress) {
    // Only update if the new progress is higher than the stored one
    final current = _readingProgress[title] ?? 0.0;
    if (progress > current) {
      _readingProgress[title] = progress;
      notifyListeners();
    }
  }

  bool hasProgress(String title) => _readingProgress.containsKey(title);
}
