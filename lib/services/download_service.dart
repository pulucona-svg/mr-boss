import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'persistence_service.dart';

class DownloadService extends ChangeNotifier {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal() {
    _restoreData();
  }

  List<Map<String, String>> _pinnedResources = [];
  List<Map<String, String>> _unpinnedResources = [];
  List<Map<String, String>> _archivedResources = [];
  List<Map<String, dynamic>> _trashedResources = [];
  final Map<String, double> _downloadProgress = {};
  final Map<String, bool> _isDownloading = {};

  double getProgress(String resourceTitle) => _downloadProgress[resourceTitle] ?? 0.0;
  bool isDownloading(String resourceTitle) => _isDownloading[resourceTitle] ?? false;
  
  List<Map<String, String>> get downloadedResources => [..._pinnedResources, ..._unpinnedResources];
  List<Map<String, String>> get archivedResources => _archivedResources;
  List<Map<String, dynamic>> get trashedResources {
    _autoDeleteExpiredTrash();
    return _trashedResources;
  }

  bool isPinned(String title) => _pinnedResources.any((r) => r['title'] == title);
  bool isDownloaded(String title) => isPinned(title) || _unpinnedResources.any((r) => r['title'] == title);

  Future<void> _restoreData() async {
    final pinned = PersistenceService().getJson('download_pinned');
    final unpinned = PersistenceService().getJson('download_unpinned');
    final archived = PersistenceService().getJson('download_archived');
    final trashed = PersistenceService().getJson('download_trashed');

    if (pinned != null) _pinnedResources = List<Map<String, String>>.from((pinned as List).map((item) => Map<String, String>.from(item)));
    if (unpinned != null) _unpinnedResources = List<Map<String, String>>.from((unpinned as List).map((item) => Map<String, String>.from(item)));
    if (archived != null) _archivedResources = List<Map<String, String>>.from((archived as List).map((item) => Map<String, String>.from(item)));
    if (trashed != null) _trashedResources = List<Map<String, dynamic>>.from(trashed as List);
    
    notifyListeners();
  }

  Future<void> _saveData() async {
    await PersistenceService().setJson('download_pinned', _pinnedResources);
    await PersistenceService().setJson('download_unpinned', _unpinnedResources);
    await PersistenceService().setJson('download_archived', _archivedResources);
    await PersistenceService().setJson('download_trashed', _trashedResources);
  }

  void _autoDeleteExpiredTrash() {
    final now = DateTime.now();
    bool changed = false;
    _trashedResources.removeWhere((item) {
      final deletedAt = DateTime.parse(item['deletedAt'] as String);
      if (now.difference(deletedAt).inDays >= 30) {
        changed = true;
        return true;
      }
      return false;
    });
    if (changed) _saveData();
  }

  void _enforcePinLimit() {
    while (_pinnedResources.length > 4) {
      final evicted = _pinnedResources.removeLast();
      _unpinnedResources.insert(0, evicted);
    }
  }

  Map<String, String>? _findAndRemove(String title) {
    int idx = _pinnedResources.indexWhere((r) => r['title'] == title);
    if (idx != -1) {
      final res = _pinnedResources.removeAt(idx);
      _saveData();
      return res;
    }
    
    idx = _unpinnedResources.indexWhere((r) => r['title'] == title);
    if (idx != -1) {
      final res = _unpinnedResources.removeAt(idx);
      _saveData();
      return res;
    }
    
    idx = _archivedResources.indexWhere((r) => r['title'] == title);
    if (idx != -1) {
      final res = _archivedResources.removeAt(idx);
      _saveData();
      return res;
    }

    idx = _trashedResources.indexWhere((r) => (r['resource'] as Map<String, dynamic>)['title'] == title);
    if (idx != -1) {
      final res = Map<String, String>.from(_trashedResources.removeAt(idx)['resource'] as Map);
      _saveData();
      return res;
    }

    return null;
  }

  void pin(String title) {
    final data = _findAndRemove(title);
    if (data != null) {
      _pinnedResources.insert(0, data);
      _enforcePinLimit();
      _saveData();
      notifyListeners();
    }
  }

  void unpin(String title) {
    final idx = _pinnedResources.indexWhere((r) => r['title'] == title);
    if (idx != -1) {
      final data = _pinnedResources.removeAt(idx);
      _unpinnedResources.insert(0, data);
      _saveData();
      notifyListeners();
    }
  }

  void togglePin(String title) {
    if (isPinned(title)) unpin(title);
    else pin(title);
  }

  void pinMultiple(List<String> titles) {
    final List<Map<String, String>> toPin = [];
    for (var title in titles) {
      final res = _findAndRemove(title);
      if (res != null) toPin.add(res);
    }
    for (var res in toPin.reversed) {
      _pinnedResources.insert(0, res);
    }
    _enforcePinLimit();
    _saveData();
    notifyListeners();
  }

  void unpinMultiple(List<String> titles) {
    for (var title in titles) {
      final idx = _pinnedResources.indexWhere((r) => r['title'] == title);
      if (idx != -1) {
        final res = _pinnedResources.removeAt(idx);
        _unpinnedResources.insert(0, res);
      }
    }
    _saveData();
    notifyListeners();
  }

  void archiveMultiple(List<String> titles) {
    for (var title in titles) {
      final res = _findAndRemove(title);
      if (res != null) {
        _archivedResources.insert(0, res);
      }
    }
    _saveData();
    notifyListeners();
  }

  void deleteMultiple(List<String> titles) {
    for (var title in titles) {
      final res = _findAndRemove(title);
      if (res != null) {
        final Map<String, dynamic> trashedItem = {
          'resource': res,
          'deletedAt': DateTime.now().toIso8601String(),
        };
        _trashedResources.insert(0, trashedItem);
      }
    }
    _saveData();
    notifyListeners();
  }

  void restoreMultiple(List<String> titles) {
    for (var title in titles) {
      final res = _findAndRemove(title);
      if (res != null) {
        _unpinnedResources.insert(0, res);
      }
    }
    _saveData();
    notifyListeners();
  }

  void permanentlyDeleteMultiple(List<String> titles) {
    _trashedResources.removeWhere((item) => titles.contains((item['resource'] as Map<String, dynamic>)['title']));
    _saveData();
    notifyListeners();
  }

  void startDownload(Map<String, String> resourceData) async {
    final title = resourceData['title']!;
    final url = resourceData['thumbnail'] ?? resourceData['thumbnailUrl'];

    if (isDownloading(title)) return;

    _isDownloading[title] = true;
    _downloadProgress[title] = 0.0;
    notifyListeners();

    if (url != null) {
      try {
        await DefaultCacheManager().downloadFile(url, key: url);
      } catch (e) {
        debugPrint('Error caching file: $e');
      }
    }

    for (int i = 0; i <= 100; i += 5) {
      await Future.delayed(const Duration(milliseconds: 100));
      _downloadProgress[title] = i / 100.0;
      notifyListeners();
    }

    _isDownloading[title] = false;
    
    if (!isDownloaded(title)) {
      _unpinnedResources.insert(0, resourceData);
      _saveData();
    }
    
    notifyListeners();
  }
}

