import 'package:flutter/material.dart';

class ResourceViewStats {
  DateTime? lastViewTime;
  int dailyCount;
  DateTime? lastViewDate;

  ResourceViewStats({
    this.lastViewTime,
    this.dailyCount = 0,
    this.lastViewDate,
  });
}

class ViewService extends ChangeNotifier {
  static final ViewService _instance = ViewService._internal();
  factory ViewService() => _instance;
  ViewService._internal();

  // Maps Resource Title (as ID for now) to its stats
  final Map<String, ResourceViewStats> _statsMap = {};

  bool canIncrementView(String resourceId) {
    final now = DateTime.now();
    final stats = _statsMap.putIfAbsent(resourceId, () => ResourceViewStats());

    // Check if it's a new day to reset daily count
    if (stats.lastViewDate == null || 
        stats.lastViewDate!.day != now.day || 
        stats.lastViewDate!.month != now.month || 
        stats.lastViewDate!.year != now.year) {
      stats.dailyCount = 0;
      stats.lastViewDate = now;
    }

    // Rule 1: Max 5 views per day
    if (stats.dailyCount >= 5) {
      return false;
    }

    // Rule 2: 60 minutes cooldown
    if (stats.lastViewTime != null) {
      final difference = now.difference(stats.lastViewTime!);
      if (difference.inMinutes < 60) {
        return false;
      }
    }

    return true;
  }

  void recordView(String resourceId) {
    final now = DateTime.now();
    final stats = _statsMap[resourceId]!;
    stats.lastViewTime = now;
    stats.dailyCount++;
    stats.lastViewDate = now;
    notifyListeners();
  }

  int getDailyViews(String resourceId) {
    return _statsMap[resourceId]?.dailyCount ?? 0;
  }

  bool hasViewed(String resourceId) {
    return _statsMap[resourceId]?.lastViewTime != null;
  }
}
