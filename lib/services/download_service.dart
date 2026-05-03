import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class DownloadService extends ChangeNotifier {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  final Map<String, double> _downloadProgress = {};
  final Map<String, bool> _isDownloading = {};
  
  // Stores the full data of downloaded resources
  final List<Map<String, String>> _downloadedResources = [];

  double getProgress(String resourceTitle) => _downloadProgress[resourceTitle] ?? 0.0;
  bool isDownloading(String resourceTitle) => _isDownloading[resourceTitle] ?? false;
  List<Map<String, String>> get downloadedResources => List.unmodifiable(_downloadedResources);

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
    
    // Add to downloaded list if not already there
    if (!_downloadedResources.any((r) => r['title'] == title)) {
      _downloadedResources.add(resourceData);
    }
    
    notifyListeners();
  }
}
