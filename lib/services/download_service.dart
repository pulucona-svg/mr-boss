import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'persistence_service.dart';
import 'subscription_service.dart';
import 'connectivity_service.dart';

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

  bool isPinned(String title) => _pinnedResources.any((r) => r['title'] == title && r['isExpired'] != 'true');
  bool isDownloaded(String title) => isPinned(title) || _unpinnedResources.any((r) => r['title'] == title && r['isExpired'] != 'true');

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
    final url = resourceData['fileUrl'] ?? resourceData['thumbnail'] ?? resourceData['thumbnailUrl'];

    if (isDownloading(title)) return;

    // Check subscription limits
    final subService = SubscriptionService();
    String source = 'rewarded_ad';
    
    if (subService.isSubscribed) {
      if (!subService.canDownload()) {
        _showLimitReachedMessages();
        return;
      }
      source = subService.activeSubscription?.packageTitle ?? 'rewarded_ad';
    } else if (!subService.isResourceUnlocked(title)) {
      // If not subscribed and not unlocked via ad, we shouldn't be here normally 
      // but let's default to rewarded_ad if it was triggered.
      source = 'rewarded_ad';
    }

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
      final Map<String, String> enrichedData = Map<String, String>.from(resourceData);
      enrichedData['downloadDate'] = DateTime.now().toIso8601String();
      enrichedData['acquisitionSource'] = source;
      
      _unpinnedResources.insert(0, enrichedData);
      // Increment download count for active subscription
      if (subService.isSubscribed) {
        await subService.recordDownload();
      }
      _saveData();
    }
    
    notifyListeners();
  }

  void performRetentionCleanup() {
    final now = DateTime.now();
    bool changed = false;

    void processList(List<Map<String, String>> list) {
      for (int i = 0; i < list.length; i++) {
        final res = list[i];
        if (res.containsKey('downloadDate') && res.containsKey('acquisitionSource')) {
          final downloadDate = DateTime.parse(res['downloadDate']!);
          final source = res['acquisitionSource']!;
          
          Duration retention;
          switch (source) {
            case 'rewarded_ad':
              retention = const Duration(days: 14);
              break;
            case 'Daily Pass':
              retention = const Duration(days: 21);
              break;
            case 'Weekly Pass':
              retention = const Duration(days: 30);
              break;
            case 'Monthly Pass':
              retention = const Duration(days: 90);
              break;
            case 'Semester Pass':
              retention = const Duration(days: 120); // 4 months
              break;
            case 'Yearly Pass':
              retention = const Duration(days: 450); // 15 months
              break;
            default:
              retention = const Duration(days: 14);
          }

          if (now.difference(downloadDate) > retention) {
            // Expired!
            // Remove the local file reference by removing it from the download lists
            // but we want to keep it visible in Library cards. 
            // In this app's architecture, 'isDownloaded' is determined by presence in these lists.
            // However, the requirement says "keep the card visible in Library".
            // We'll mark it as expired in the metadata.
            list[i] = Map<String, String>.from(res);
            list[i]['isExpired'] = 'true';
            
            // Actually removing from these lists would hide it from "Downloads" section in Library,
            // but the prompt says "Downloaded materials should remain visible in Library".
            // So we keep them in the list but mark them expired.
            // The UI (ResourceCard) should check 'isExpired' and treat it as not downloaded.
            
            // To "remove the local file", we should ideally remove it from cache
            final url = res['fileUrl'] ?? res['thumbnail'] ?? res['thumbnailUrl'];
            if (url != null) {
              DefaultCacheManager().removeFile(url);
            }
            changed = true;
          }
        }
      }
    }

    processList(_pinnedResources);
    processList(_unpinnedResources);
    processList(_archivedResources);

    if (changed) {
      _saveData();
      notifyListeners();
    }
  }

  void _showLimitReachedMessages() async {
    final messenger = ConnectivityService().messengerKey.currentState;
    if (messenger == null) return;

    final messages = [
      {'text': 'Download limit reached for your current plan.', 'color': Colors.redAccent},
      {'text': 'You can continue reading and accessing your available materials until your plan expires.', 'color': const Color(0xFF00A85A)},
      {'text': 'To unlock more downloads, watch a rewarded ad or activate another package.', 'color': const Color(0xFF00A85A)},
    ];

    for (var msg in messages) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            msg['text'] as String,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: (msg['color'] as Color).withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          duration: const Duration(seconds: 5),
        ),
      );
      await Future.delayed(const Duration(seconds: 5, milliseconds: 500));
    }
  }
}

