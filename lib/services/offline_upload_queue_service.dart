import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'connectivity_service.dart';
import 'persistence_service.dart';
import 'upload_service.dart';
import 'timetable_upload_service.dart';
import 'resource_service.dart';
import 'course_service.dart';
import '../models/material_model.dart';

enum QueuedUploadStatus {
  queued,
  // ignore: constant_identifier_names
  waiting_internet,
  uploading,
  paused,
  retrying,
  completed,
  failed,
}

class QueuedUploadItem {
  final String id;
  final String? filePath;
  final List<String> filePaths;
  final String? thumbnailPath;
  final Map<String, dynamic> materialData;
  final String uploadMode; // 'material' or 'timetable'
  QueuedUploadStatus status;
  double progress;
  int retryCount;
  DateTime? nextRetryTime;
  String? lastError;
  final DateTime createdAt;

  // Idempotency and duplicate prevention fields
  String? uploadedFileUrl;
  String? uploadedFileId;
  String? uploadedFileName;
  String? uploadedThumbnailUrl;
  String? uploadedThumbnailId;
  String? uploadedThumbnailStatus;
  String? firestoreDocId;

  QueuedUploadItem({
    required this.id,
    this.filePath,
    this.filePaths = const [],
    this.thumbnailPath,
    required this.materialData,
    this.uploadMode = 'material',
    this.status = QueuedUploadStatus.queued,
    this.progress = 0.0,
    this.retryCount = 0,
    this.nextRetryTime,
    this.lastError,
    DateTime? createdAt,
    this.uploadedFileUrl,
    this.uploadedFileId,
    this.uploadedFileName,
    this.uploadedThumbnailUrl,
    this.uploadedThumbnailId,
    this.uploadedThumbnailStatus,
    this.firestoreDocId,
  }) : createdAt = createdAt ?? DateTime.now();

  String get statusDisplay {
    switch (status) {
      case QueuedUploadStatus.queued:
        return 'Upload queued';
      case QueuedUploadStatus.waiting_internet:
        return 'Waiting for internet';
      case QueuedUploadStatus.uploading:
        final pct = (progress * 100).toInt();
        return pct > 0 ? 'Uploading ($pct%)' : 'Uploading';
      case QueuedUploadStatus.paused:
        return 'Upload paused due to connection loss';
      case QueuedUploadStatus.retrying:
        return 'Retrying';
      case QueuedUploadStatus.completed:
        return 'Upload completed';
      case QueuedUploadStatus.failed:
        return lastError != null && lastError!.isNotEmpty
            ? 'Failed: $lastError'
            : 'Permanent failure requiring user action';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'filePaths': filePaths,
        'thumbnailPath': thumbnailPath,
        'materialData': materialData,
        'uploadMode': uploadMode,
        'status': status.name,
        'progress': progress,
        'retryCount': retryCount,
        'nextRetryTime': nextRetryTime?.toIso8601String(),
        'lastError': lastError,
        'createdAt': createdAt.toIso8601String(),
        'uploadedFileUrl': uploadedFileUrl,
        'uploadedFileId': uploadedFileId,
        'uploadedFileName': uploadedFileName,
        'uploadedThumbnailUrl': uploadedThumbnailUrl,
        'uploadedThumbnailId': uploadedThumbnailId,
        'uploadedThumbnailStatus': uploadedThumbnailStatus,
        'firestoreDocId': firestoreDocId,
      };

  factory QueuedUploadItem.fromJson(Map<String, dynamic> json) => QueuedUploadItem(
        id: json['id'],
        filePath: json['filePath'],
        filePaths: List<String>.from(json['filePaths'] ?? []),
        thumbnailPath: json['thumbnailPath'],
        materialData: Map<String, dynamic>.from(json['materialData'] ?? {}),
        uploadMode: json['uploadMode'] ?? 'material',
        status: QueuedUploadStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => QueuedUploadStatus.waiting_internet,
        ),
        progress: (json['progress'] ?? 0.0).toDouble(),
        retryCount: json['retryCount'] ?? 0,
        nextRetryTime: json['nextRetryTime'] != null ? DateTime.tryParse(json['nextRetryTime']) : null,
        lastError: json['lastError'],
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt']) : DateTime.now(),
        uploadedFileUrl: json['uploadedFileUrl'],
        uploadedFileId: json['uploadedFileId'],
        uploadedFileName: json['uploadedFileName'],
        uploadedThumbnailUrl: json['uploadedThumbnailUrl'],
        uploadedThumbnailId: json['uploadedThumbnailId'],
        uploadedThumbnailStatus: json['uploadedThumbnailStatus'],
        firestoreDocId: json['firestoreDocId'],
      );
}

class OfflineUploadQueueService extends ChangeNotifier with WidgetsBindingObserver {
  static final OfflineUploadQueueService _instance = OfflineUploadQueueService._internal();
  factory OfflineUploadQueueService() => _instance;
  OfflineUploadQueueService._internal();

  static const String _queueStorageKey = 'offline_upload_queue_v1';
  final List<QueuedUploadItem> _queue = [];
  bool _isProcessing = false;
  bool _isInitialized = false;
  bool _wasOffline = false;
  Timer? _retryTimer;

  List<QueuedUploadItem> get queue => List.unmodifiable(_queue);
  int get pendingCount => _queue.where((item) =>
      item.status != QueuedUploadStatus.completed &&
      item.status != QueuedUploadStatus.failed).length;

  /// Returns queued offline items formatted as Resource cards for display on Uploads page
  List<Resource> get queuedResources {
    return _queue.map((item) {
      final mat = UploadMaterialModel.fromMap(item.materialData);
      String title;
      if (item.uploadMode == 'timetable') {
        title = '${mat.programs.join(", ")} Timetable';
      } else if (mat.materialType == 'CATs' && mat.catType != null) {
        title = '${mat.unitName} ${mat.catType}';
      } else {
        title = mat.unitName.isNotEmpty ? mat.unitName : 'Uploading Material';
      }

      return Resource(
        id: item.id,
        title: title,
        fileName: item.filePath?.split(RegExp(r'[/\\]')).last ?? 'material.pdf',
        type: mat.materialType,
        thumbnailUrl: item.thumbnailPath ?? '',
        thumbnailId: '',
        thumbnailStatus: item.statusDisplay,
        fileUrl: item.filePath ?? '',
        fileId: '',
        unitName: mat.unitName,
        unitCode: mat.unitCode,
        year: mat.yearOfUpload.toString(),
        uploadYear: mat.yearOfUpload.toString(),
        publicationYear: mat.yearOfPublication.toString(),
        yearOfStudy: mat.yearOfStudy,
        semester: mat.semester,
        lecturers: mat.lecturers.isNotEmpty ? mat.lecturers : ['TBD'],
        uploadedBy: mat.uploadedBy,
        uploaderRole: 'Student',
        uploaderId: mat.uploaderId,
        uploadDate: item.createdAt,
        status: item.status.name, // e.g. 'waiting_internet', 'queued', 'uploading', 'paused', 'retrying', 'failed'
        visibility: 'public',
        targetPrograms: mat.programs,
        programCodes: mat.programCodes,
        materialFormat: item.uploadMode == 'timetable' ? 'Image' : (mat.fileFormat ?? 'PDF'),
        isAnonymous: item.uploadMode == 'timetable' ? false : mat.isAnonymous,
      );
    }).toList();
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    WidgetsBinding.instance.addObserver(this);

    await _loadQueue();

    // Listen to network changes
    ConnectivityService().addListener(_onConnectivityChanged);

    // Initial check on app startup: verify reachability and process pending items
    _checkAndProcessStartup();
  }

  Future<void> _checkAndProcessStartup() async {
    if (pendingCount == 0) return;
    final reachable = await ConnectivityService().checkInternetReachability();
    if (reachable) {
      resetRetryDelays();
      _processQueue();
    } else {
      // Mark active items as waiting for internet
      for (var item in _queue) {
        if (item.status == QueuedUploadStatus.uploading || item.status == QueuedUploadStatus.queued) {
          item.status = QueuedUploadStatus.waiting_internet;
        }
      }
      await _saveQueue();
      _notifyUI();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('OfflineUploadQueueService: App resumed to foreground. Checking connectivity and pending upload queue...');
      reconcileAndRetry();
    }
  }

  /// Safe queue reconciliation and retry-eligibility check.
  /// Called upon app foregrounding, pull-to-refresh, or restored network.
  Future<void> reconcileAndRetry() async {
    final bool reachable = await ConnectivityService().checkReachabilityAndUpdate();
    if (reachable) {
      debugPrint('OfflineUploadQueueService: Network reachable. Resetting retry timers for pending items...');
      resetRetryDelays();
      _processQueue();
    } else {
      debugPrint('OfflineUploadQueueService: Reconcile check confirmed offline.');
      for (var item in _queue) {
        if (item.status == QueuedUploadStatus.uploading || item.status == QueuedUploadStatus.queued) {
          item.status = QueuedUploadStatus.waiting_internet;
        }
      }
      await _saveQueue();
      _notifyUI();
    }
  }

  /// Resets backoff retry timers to allow immediate processing upon restored connectivity.
  void resetRetryDelays() {
    for (var item in _queue) {
      if (item.status == QueuedUploadStatus.waiting_internet ||
          item.status == QueuedUploadStatus.paused ||
          item.status == QueuedUploadStatus.retrying ||
          item.status == QueuedUploadStatus.queued) {
        item.nextRetryTime = null;
        if (item.status == QueuedUploadStatus.paused || item.status == QueuedUploadStatus.waiting_internet || item.status == QueuedUploadStatus.retrying) {
          item.status = QueuedUploadStatus.queued;
        }
      }
    }
    _retryTimer?.cancel();
    _retryTimer = null;
    _saveQueue();
    _notifyUI();
  }

  void _onConnectivityChanged() {
    final isOffline = ConnectivityService().isOffline;
    if (isOffline) {
      _wasOffline = true;
      debugPrint('OfflineUploadQueueService: Internet disconnected. Pausing active queue...');
      for (var item in _queue) {
        if (item.status == QueuedUploadStatus.uploading) {
          item.status = QueuedUploadStatus.paused;
        } else if (item.status == QueuedUploadStatus.queued) {
          item.status = QueuedUploadStatus.waiting_internet;
        }
      }
      _saveQueue();
      _notifyUI();
    } else {
      debugPrint('OfflineUploadQueueService: Connectivity event online. Triggering reachability and queue check...');
      final pendingWork = _queue.where((item) =>
          item.status == QueuedUploadStatus.waiting_internet ||
          item.status == QueuedUploadStatus.paused ||
          item.status == QueuedUploadStatus.retrying ||
          item.status == QueuedUploadStatus.queued).toList();

      if (_wasOffline && pendingWork.isNotEmpty) {
        _wasOffline = false;
        final messenger = ConnectivityService().messengerKey.currentState;
        if (messenger != null) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.cloud_done_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      pendingWork.length > 1
                          ? 'Connection restored. Resuming your queued uploads...'
                          : 'Connection restored. Resuming your upload...',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF20C8FF),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        _wasOffline = false;
      }

      resetRetryDelays();
      _processQueue();
    }
  }

  void _notifyUI() {
    notifyListeners();
    try {
      ResourceService().notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadQueue() async {
    try {
      final jsonList = PersistenceService().getJson(_queueStorageKey);
      if (jsonList is List) {
        _queue.clear();
        for (var item in jsonList) {
          if (item is Map<String, dynamic>) {
            final queuedItem = QueuedUploadItem.fromJson(item);
            // Skip/purge completed items
            if (queuedItem.status == QueuedUploadStatus.completed) {
              continue;
            }
            // Reset active state to waiting_internet if app crashed during upload
            if (queuedItem.status == QueuedUploadStatus.uploading) {
              queuedItem.status = QueuedUploadStatus.waiting_internet;
            }
            _queue.add(queuedItem);
          }
        }
        await _saveQueue();
        debugPrint('OfflineUploadQueueService: Loaded ${_queue.length} items from persistent storage.');
        _notifyUI();
      }
    } catch (e) {
      debugPrint('OfflineUploadQueueService: Error loading persistent queue: $e');
    }
  }

  Future<void> _saveQueue() async {
    try {
      final jsonList = _queue.map((e) => e.toJson()).toList();
      await PersistenceService().setJson(_queueStorageKey, jsonList);
    } catch (e) {
      debugPrint('OfflineUploadQueueService: Error saving queue to persistent storage: $e');
    }
  }

  Future<QueuedUploadItem> enqueue({
    required UploadMaterialModel material,
    required String uploadMode,
    File? file,
    List<File> files = const [],
    File? thumbnail,
  }) async {
    final itemId = 'upload_${DateTime.now().millisecondsSinceEpoch}';

    final filePath = file?.path;
    final filePaths = files.map((f) => f.path).toList();
    final thumbnailPath = thumbnail?.path;

    final queuedItem = QueuedUploadItem(
      id: itemId,
      filePath: filePath,
      filePaths: filePaths,
      thumbnailPath: thumbnailPath,
      materialData: material.toMap(),
      uploadMode: uploadMode,
      status: ConnectivityService().isOffline
          ? QueuedUploadStatus.waiting_internet
          : QueuedUploadStatus.queued,
      createdAt: DateTime.now(),
      firestoreDocId: 'res_$itemId',
    );

    _queue.add(queuedItem); // Append in FIFO order
    await _saveQueue();
    _notifyUI();

    debugPrint('OfflineUploadQueueService: Enqueued upload ID "$itemId" (Mode: $uploadMode, Status: ${queuedItem.statusDisplay})');

    if (!ConnectivityService().isOffline) {
      _processQueue();
    }

    return queuedItem;
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    if (ConnectivityService().isOffline) return;

    _isProcessing = true;

    try {
      while (_queue.isNotEmpty) {
        if (ConnectivityService().isOffline) {
          debugPrint('OfflineUploadQueueService: Network lost during queue processing.');
          break;
        }

        // Find first item eligible for processing
        final index = _queue.indexWhere((item) =>
            item.status != QueuedUploadStatus.completed &&
            item.status != QueuedUploadStatus.failed);
        if (index == -1) break;

        final item = _queue[index];

        // Check retry timer if scheduled and still in the future
        if (item.nextRetryTime != null && item.nextRetryTime!.isAfter(DateTime.now())) {
          debugPrint('OfflineUploadQueueService: Item ${item.id} waiting for next retry at ${item.nextRetryTime}');
          final remainingSec = item.nextRetryTime!.difference(DateTime.now()).inSeconds;
          _scheduleRetryTimer(Duration(seconds: remainingSec.clamp(1, 600)));
          break;
        }

        item.status = QueuedUploadStatus.uploading;
        item.progress = item.progress > 0.1 ? item.progress : 0.1;
        await _saveQueue();
        _notifyUI();

        final success = await _uploadSingleItem(item);
        if (success) {
          item.status = QueuedUploadStatus.completed;
          item.progress = 1.0;
          _queue.removeWhere((i) => i.id == item.id || i.status == QueuedUploadStatus.completed);
          await _saveQueue();
          _notifyUI();
          debugPrint('OfflineUploadQueueService: Upload ${item.id} completed successfully and purged from queue.');
        } else {
          // If failure is permanent (e.g. file missing, marked failed already)
          if (item.status == QueuedUploadStatus.failed) {
            await _saveQueue();
            _notifyUI();
            debugPrint('OfflineUploadQueueService: Permanent failure for item ${item.id}: ${item.lastError}');
            // Move on to next item without retrying this permanent failure forever
            continue;
          }

          // Distinguish network failures from permanent failures
          final bool isNetErr = ConnectivityService.isNetworkError(item.lastError) ||
              ConnectivityService().isOffline;

          if (isNetErr) {
            if (ConnectivityService().isOffline) {
              item.status = QueuedUploadStatus.waiting_internet;
              await _saveQueue();
              _notifyUI();
              break;
            } else {
              item.retryCount += 1;
              final delaySec = _getRetryDelaySeconds(item.retryCount);
              item.nextRetryTime = DateTime.now().add(Duration(seconds: delaySec));
              item.status = QueuedUploadStatus.retrying;
              await _saveQueue();
              _notifyUI();

              debugPrint('OfflineUploadQueueService: Upload ${item.id} network failure. Retrying in ${delaySec}s (Attempt ${item.retryCount})');
              _scheduleRetryTimer(Duration(seconds: delaySec));
              break;
            }
          } else {
            // Non-network failure (e.g. format error, server reject, permission error)
            item.status = QueuedUploadStatus.failed;
            item.nextRetryTime = null;
            await _saveQueue();
            _notifyUI();
            debugPrint('OfflineUploadQueueService: Non-network failure for item ${item.id}. Will not retry automatically.');
            continue;
          }
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  int _getRetryDelaySeconds(int count) {
    if (count <= 1) return 15;
    if (count == 2) return 30;
    if (count == 3) return 60;
    if (count == 4) return 120;
    if (count == 5) return 300;
    return 600; // Cap at 10 minutes
  }

  void _scheduleRetryTimer(Duration duration) {
    _retryTimer?.cancel();
    _retryTimer = Timer(duration, () {
      if (!ConnectivityService().isOffline) {
        _processQueue();
      }
    });
  }

  Future<bool> _uploadSingleItem(QueuedUploadItem item) async {
    try {
      final materialModel = UploadMaterialModel.fromMap(item.materialData);

      // Reconstruct file instances and verify local file integrity
      File? primaryFile;
      if (item.filePath != null && item.filePath!.isNotEmpty) {
        primaryFile = File(item.filePath!);
        if (!primaryFile.existsSync()) {
          item.lastError = 'Original file no longer found on device';
          item.status = QueuedUploadStatus.failed;
          return false;
        }
      }

      List<File> fileList = [];
      for (var path in item.filePaths) {
        final f = File(path);
        if (f.existsSync()) {
          fileList.add(f);
        } else {
          item.lastError = 'One or more local images are missing from device';
          item.status = QueuedUploadStatus.failed;
          return false;
        }
      }

      File? thumbFile;
      if (item.thumbnailPath != null && item.thumbnailPath!.isNotEmpty) {
        thumbFile = File(item.thumbnailPath!);
      }

      final fullMaterial = materialModel.copyWith(
        file: primaryFile,
        files: fileList,
        thumbnail: thumbFile,
      );

      // DUPLICATE PREVENTION:
      // If the file was already uploaded to storage/ImageKit in a previous interrupted attempt,
      // reuse the existing storage identifiers and skip re-uploading!
      String finalFileUrl = item.uploadedFileUrl ?? '';
      String finalFileId = item.uploadedFileId ?? '';
      String finalFileName = item.uploadedFileName ?? '';
      String finalThumbUrl = item.uploadedThumbnailUrl ?? '';
      String finalThumbId = item.uploadedThumbnailId ?? '';
      String finalThumbStatus = item.uploadedThumbnailStatus ?? '';

      if (finalFileUrl.isEmpty) {
        Map<String, dynamic> uploadResult;
        if (item.uploadMode == 'timetable') {
          uploadResult = await TimetableUploadService().uploadTimetable(
            fullMaterial,
            (p) {
              item.progress = p;
              _notifyUI();
            },
          );
        } else {
          uploadResult = await UploadService().uploadMaterial(
            fullMaterial,
            (p) {
              item.progress = p;
              _notifyUI();
            },
          );
        }

        finalFileUrl = uploadResult['fileUrl'] ?? '';
        finalFileId = uploadResult['fileId'] ?? '';
        finalFileName = uploadResult['fileName'] ?? '';
        finalThumbUrl = uploadResult['thumbnailUrl'] ?? '';
        finalThumbId = uploadResult['thumbnailId'] ?? '';
        finalThumbStatus = uploadResult['thumbnailStatus'] ?? (item.uploadMode == 'timetable' ? 'completed' : 'pending');

        // Persist intermediate storage references immediately for idempotency
        item.uploadedFileUrl = finalFileUrl;
        item.uploadedFileId = finalFileId;
        item.uploadedFileName = finalFileName;
        item.uploadedThumbnailUrl = finalThumbUrl;
        item.uploadedThumbnailId = finalThumbId;
        item.uploadedThumbnailStatus = finalThumbStatus;
        await _saveQueue();
      }

      if (finalThumbStatus.isEmpty) {
        finalThumbStatus = item.uploadMode == 'timetable' ? 'completed' : 'pending';
      }

      String resourceTitle;
      if (item.uploadMode == 'timetable') {
        resourceTitle = '${fullMaterial.programs.join(", ")} Timetable';
      } else if (fullMaterial.materialType == 'CATs' && fullMaterial.catType != null) {
        resourceTitle = '${fullMaterial.unitName} ${fullMaterial.catType}';
      } else {
        resourceTitle = fullMaterial.unitName;
      }

      // DUPLICATE FIRESTORE PREVENTION:
      // Use deterministic doc ID so that retrying never creates duplicate Firestore documents
      final String docId = item.firestoreDocId ?? 'res_${item.id}';
      item.firestoreDocId = docId;

      final resource = Resource(
        id: docId,
        title: resourceTitle,
        fileName: finalFileName.isNotEmpty
            ? finalFileName
            : (item.filePath?.split(RegExp(r'[/\\]')).last ?? 'material.pdf'),
        type: fullMaterial.materialType,
        thumbnailUrl: finalThumbUrl,
        fileUrl: finalFileUrl,
        fileId: finalFileId,
        thumbnailId: finalThumbId,
        thumbnailStatus: finalThumbStatus,
        unitName: fullMaterial.unitName,
        unitCode: fullMaterial.unitCode,
        year: fullMaterial.yearOfUpload.toString(),
        uploadYear: fullMaterial.yearOfUpload.toString(),
        publicationYear: fullMaterial.yearOfPublication.toString(),
        yearOfStudy: fullMaterial.yearOfStudy,
        semester: fullMaterial.semester,
        lecturers: fullMaterial.lecturers.isNotEmpty ? fullMaterial.lecturers : ['TBD'],
        uploadedBy: fullMaterial.uploadedBy,
        uploaderRole: 'Student',
        uploaderId: fullMaterial.uploaderId,
        uploadDate: item.createdAt,
        status: 'approved',
        visibility: 'public',
        targetPrograms: fullMaterial.programs,
        programCodes: fullMaterial.programCodes,
        materialFormat: item.uploadMode == 'timetable' ? 'Image' : (fullMaterial.fileFormat ?? 'PDF'),
        isAnonymous: item.uploadMode == 'timetable' ? false : fullMaterial.isAnonymous,
      );

      // Publish to Firestore with idempotent set/merge
      await ResourceService().addUpload(resource, CourseService());
      await ResourceService().fetchUserUploadsOnce(fullMaterial.uploaderId);

      return true;
    } catch (e) {
      item.lastError = e.toString();
      debugPrint('OfflineUploadQueueService: Upload item ${item.id} error: $e');
      return false;
    }
  }

  void cancel(String id) {
    _queue.removeWhere((item) => item.id == id);
    _saveQueue();
    _notifyUI();
  }

  @visibleForTesting
  void resetForTesting() {
    _queue.clear();
    _isProcessing = false;
    _isInitialized = false;
    _wasOffline = false;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void clearCompleted() {
    _queue.removeWhere((item) => item.status == QueuedUploadStatus.completed);
    _saveQueue();
    _notifyUI();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    ConnectivityService().removeListener(_onConnectivityChanged);
    super.dispose();
  }
}
