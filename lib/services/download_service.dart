import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class DownloadService extends ChangeNotifier {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  final Map<String, double> _downloadProgress = {};
  final Map<String, bool> _isDownloading = {};
  
  // Stores the full data of downloaded resources in chronological order
  final List<Map<String, String>> _downloadedResources = [];
  
  // Stores pinned titles in order of pinning (index 0 is newest)
  final List<String> _pinnedTitles = [];
  
  // Stores titles that were unpinned or evicted to keep them at the top of unpinned list
  final List<String> _recentlyUnpinned = [];

  double getProgress(String resourceTitle) => _downloadProgress[resourceTitle] ?? 0.0;
  bool isDownloading(String resourceTitle) => _isDownloading[resourceTitle] ?? false;
  
  List<Map<String, String>> get downloadedResources {
    final List<Map<String, String>> pinned = [];
    final List<Map<String, String>> recentlyUnpinned = [];
    final List<Map<String, String>> others = [];

    // 1. Add Pinned items
    for (var title in _pinnedTitles) {
      final res = _downloadedResources.firstWhere((r) => r['title'] == title, orElse: () => {});
      if (res.isNotEmpty) pinned.add(res);
    }

    // 2. Add Recently Unpinned items (in the order they were unpinned/evicted)
    for (var title in _recentlyUnpinned) {
      if (!_pinnedTitles.contains(title)) {
        final res = _downloadedResources.firstWhere((r) => r['title'] == title, orElse: () => {});
        if (res.isNotEmpty) recentlyUnpinned.add(res);
      }
    }

    // 3. Add the rest in their original LIFO download order
    for (var res in _downloadedResources) {
      final title = res['title'];
      if (!_pinnedTitles.contains(title) && !_recentlyUnpinned.contains(title)) {
        others.add(res);
      }
    }

    return [...pinned, ...recentlyUnpinned, ...others];
  }

  bool isPinned(String title) => _pinnedTitles.contains(title);

  void _enforcePinLimit() {
    while (_pinnedTitles.length > 4) {
      // Remove oldest (last in list)
      final evicted = _pinnedTitles.removeLast();
      // Move to recently unpinned so it stays at the top of unpinned list
      _recentlyUnpinned.remove(evicted);
      _recentlyUnpinned.insert(0, evicted);
    }
  }

  void togglePin(String title) {
    if (_pinnedTitles.contains(title)) {
      _pinnedTitles.remove(title);
      // When manually unpinned, move to top of unpinned section
      _recentlyUnpinned.remove(title);
      _recentlyUnpinned.insert(0, title);
    } else {
      _recentlyUnpinned.remove(title);
      _pinnedTitles.insert(0, title);
      _enforcePinLimit();
    }
    notifyListeners();
  }

  void pinMultiple(List<String> titles) {
    for (var title in titles) {
      _pinnedTitles.remove(title);
      _recentlyUnpinned.remove(title);
    }

    final reverseTitles = titles.reversed.toList();
    for (var title in reverseTitles) {
      _pinnedTitles.insert(0, title);
    }
    _enforcePinLimit();
    notifyListeners();
  }

  void unpinMultiple(List<String> titles) {
    for (var title in titles) {
      if (_pinnedTitles.contains(title)) {
        _pinnedTitles.remove(title);
        _recentlyUnpinned.remove(title);
        _recentlyUnpinned.insert(0, title);
      }
    }
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
    
    // Add to downloaded list if not already there, inserting at the beginning (index 0)
    // so that the most recently downloaded item appears first.
    if (!_downloadedResources.any((r) => r['title'] == title)) {
      _downloadedResources.insert(0, resourceData);
    }
    
    notifyListeners();
  }
}
