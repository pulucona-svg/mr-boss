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
  }) : createdAt = createdAt ?? DateTime.now();

  String get statusDisplay {
    switch (status) {
      case QueuedUploadStatus.queued:
        return 'Queued';
      case QueuedUploadStatus.waiting_internet:
        return 'Waiting for Internet';
      case QueuedUploadStatus.uploading:
        return 'Uploading';
      case QueuedUploadStatus.paused:
        return 'Paused';
      case QueuedUploadStatus.retrying:
        return 'Retrying';
      case QueuedUploadStatus.completed:
        return 'Completed';
      case QueuedUploadStatus.failed:
        return 'Failed';
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
  int get pendingCount => _queue.where((item) => item.status != QueuedUploadStatus.completed && item.status != QueuedUploadStatus.failed).length;

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
        thumbnailStatus: item.statusDisplay, // "Waiting for Internet", "Uploading", "Retrying", "Paused"
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
        status: 'approved',
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

    // Initial check on app startup
    if (!ConnectivityService().isOffline && pendingCount > 0) {
      _processQueue();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('OfflineUploadQueueService: App resumed to foreground. Checking connectivity and pending upload queue...');
      if (!ConnectivityService().isOffline && pendingCount > 0) {
        _processQueue();
      }
    }
  }

  void _onConnectivityChanged() {
    final isOffline = ConnectivityService().isOffline;
    if (isOffline) {
      _wasOffline = true;
      debugPrint('OfflineUploadQueueService: Internet disconnected. Pausing active queue...');
      for (var item in _queue) {
        if (item.status == QueuedUploadStatus.uploading || item.status == QueuedUploadStatus.queued) {
          item.status = QueuedUploadStatus.waiting_internet;
        }
      }
      _saveQueue();
      _notifyUI();
    } else {
      debugPrint('OfflineUploadQueueService: Internet connected. Processing FIFO queue (${_queue.length} items)...');
      
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

      if (pendingWork.isNotEmpty) {
        _processQueue();
      }
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
      // Process items in FIFO order
      while (_queue.isNotEmpty) {
        if (ConnectivityService().isOffline) {
          debugPrint('OfflineUploadQueueService: Network lost during queue processing.');
          break;
        }

        // Find first item ready to process
        final index = _queue.indexWhere((item) => item.status != QueuedUploadStatus.completed && item.status != QueuedUploadStatus.failed);
        if (index == -1) break;

        final item = _queue[index];

        // Check retry timer if scheduled
        if (item.nextRetryTime != null && item.nextRetryTime!.isAfter(DateTime.now())) {
          debugPrint('OfflineUploadQueueService: Item ${item.id} waiting for next retry at ${item.nextRetryTime}');
          break;
        }

        item.status = QueuedUploadStatus.uploading;
        item.progress = 0.1;
        _saveQueue();
        _notifyUI();

        final success = await _uploadSingleItem(item);
        if (success) {
          item.status = QueuedUploadStatus.completed;
          item.progress = 1.0;
          _queue.removeWhere((i) => i.id == item.id || i.status == QueuedUploadStatus.completed); // Purge completed from queue
          await _saveQueue();
          _notifyUI();
          debugPrint('OfflineUploadQueueService: Upload ${item.id} completed successfully and purged from queue.');
        } else {
          // Check if network error or unrecoverable error
          if (ConnectivityService().isOffline) {
            item.status = QueuedUploadStatus.waiting_internet;
            _saveQueue();
            _notifyUI();
            break;
          } else {
            // Schedule retry with exponential backoff
            item.retryCount += 1;
            final delaySec = _getRetryDelaySeconds(item.retryCount);
            item.nextRetryTime = DateTime.now().add(Duration(seconds: delaySec));
            item.status = QueuedUploadStatus.retrying;
            _saveQueue();
            _notifyUI();

            debugPrint('OfflineUploadQueueService: Upload ${item.id} failed. Retrying in ${delaySec}s (Attempt ${item.retryCount})');

            // Schedule timer for next attempt
            _scheduleRetryTimer(Duration(seconds: delaySec));
            break;
          }
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  int _getRetryDelaySeconds(int count) {
    if (count <= 1) return 30;
    if (count == 2) return 60;
    if (count == 3) return 120;
    if (count == 4) return 300;
    if (count == 5) return 600;
    if (count == 6) return 1800;
    return 3600; // Cap at 1 hour
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

      // Reconstruct file instances
      File? primaryFile;
      if (item.filePath != null && item.filePath!.isNotEmpty) {
        primaryFile = File(item.filePath!);
        if (!primaryFile.existsSync()) {
          item.lastError = 'Local file not found on device';
          item.status = QueuedUploadStatus.failed;
          return false;
        }
      }

      List<File> fileList = [];
      for (var path in item.filePaths) {
        final f = File(path);
        if (f.existsSync()) fileList.add(f);
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

      // Perform Upload via dedicated pipeline
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

      final String finalFileUrl = uploadResult['fileUrl'] ?? '';
      final String finalFileId = uploadResult['fileId'] ?? '';
      final String finalFileName = uploadResult['fileName'] ?? '';
      final String finalThumbUrl = uploadResult['thumbnailUrl'] ?? '';
      final String finalThumbId = uploadResult['thumbnailId'] ?? '';
      final String finalThumbStatus = uploadResult['thumbnailStatus'] ?? (item.uploadMode == 'timetable' ? 'completed' : 'pending');


      String resourceTitle;
      if (item.uploadMode == 'timetable') {
        resourceTitle = '${fullMaterial.programs.join(", ")} Timetable';
      } else if (fullMaterial.materialType == 'CATs' && fullMaterial.catType != null) {
        resourceTitle = '${fullMaterial.unitName} ${fullMaterial.catType}';
      } else {
        resourceTitle = fullMaterial.unitName;
      }

      final resource = Resource(
        title: resourceTitle,
        fileName: finalFileName,
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
        uploadDate: DateTime.now(),
        status: 'approved',
        visibility: 'public',
        targetPrograms: fullMaterial.programs,
        programCodes: fullMaterial.programCodes,
        materialFormat: item.uploadMode == 'timetable' ? 'Image' : (fullMaterial.fileFormat ?? 'PDF'),
        isAnonymous: item.uploadMode == 'timetable' ? false : fullMaterial.isAnonymous,
      );

      // Publish to Firestore
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

  void clearCompleted() {
    _queue.removeWhere((item) => item.status == QueuedUploadStatus.completed);
    _saveQueue();
    _notifyUI();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
