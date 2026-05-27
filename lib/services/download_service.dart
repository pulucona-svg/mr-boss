import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class DownloadService extends ChangeNotifier {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  final List<Map<String, String>> _pinnedResources = [];
  final List<Map<String, String>> _unpinnedResources = [];
  final List<Map<String, String>> _archivedResources = [];
  final List<Map<String, dynamic>> _trashedResources = [];
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

  void _autoDeleteExpiredTrash() {
    final now = DateTime.now();
    _trashedResources.removeWhere((item) {
      final deletedAt = DateTime.parse(item['deletedAt'] as String);
      return now.difference(deletedAt).inDays >= 30;
    });
  }

  void _enforcePinLimit() {
    while (_pinnedResources.length > 4) {
      final evicted = _pinnedResources.removeLast();
      _unpinnedResources.insert(0, evicted);
    }
  }

  Map<String, String>? _findAndRemove(String title) {
    int idx = _pinnedResources.indexWhere((r) => r['title'] == title);
    if (idx != -1) return _pinnedResources.removeAt(idx);
    
    idx = _unpinnedResources.indexWhere((r) => r['title'] == title);
    if (idx != -1) return _unpinnedResources.removeAt(idx);
    
    idx = _archivedResources.indexWhere((r) => r['title'] == title);
    if (idx != -1) return _archivedResources.removeAt(idx);

    idx = _trashedResources.indexWhere((r) => (r['resource'] as Map<String, String>)['title'] == title);
    if (idx != -1) return _trashedResources.removeAt(idx)['resource'] as Map<String, String>;

    return null;
  }

  void pin(String title) {
    final data = _findAndRemove(title);
    if (data != null) {
      _pinnedResources.insert(0, data);
      _enforcePinLimit();
      notifyListeners();
    }
  }

  void unpin(String title) {
    final idx = _pinnedResources.indexWhere((r) => r['title'] == title);
    if (idx != -1) {
      final data = _pinnedResources.removeAt(idx);
      _unpinnedResources.insert(0, data);
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
    notifyListeners();
  }

  void archiveMultiple(List<String> titles) {
    for (var title in titles) {
      final res = _findAndRemove(title);
      if (res != null) {
        _archivedResources.insert(0, res);
      }
    }
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
    notifyListeners();
  }

  void restoreMultiple(List<String> titles) {
    for (var title in titles) {
      final res = _findAndRemove(title);
      if (res != null) {
        _unpinnedResources.insert(0, res);
      }
    }
    notifyListeners();
  }

  void permanentlyDeleteMultiple(List<String> titles) {
    _trashedResources.removeWhere((item) => titles.contains((item['resource'] as Map<String, String>)['title']));
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
    
    // Add to unpinned list if not already there, inserting at the beginning (index 0)
    if (!isDownloaded(title)) {
      _unpinnedResources.insert(0, resourceData);
    }
    
    notifyListeners();
  }
}
