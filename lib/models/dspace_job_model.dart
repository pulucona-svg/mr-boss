import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single discovered DSpace examination paper.
class DiscoveredDSpacePaper {
  final String itemUuid;
  final String handle;
  final String title;
  final String publicationDate;
  final int? publicationYear;
  final String publicationDateSource;
  final String subjects;
  final String authors;
  final String collectionUuid;
  final String collectionName;
  final String unitCode;
  final String unitName;
  final List<String> targetPrograms;
  final List<String> programCodes;
  final List<String> lecturers;
  final String yearOfStudy;
  final String semester;
  final String? bitstreamUuid;
  final String fileName;
  final int fileSizeBytes;
  final String md5;
  final String downloadUrl;

  const DiscoveredDSpacePaper({
    required this.itemUuid,
    required this.handle,
    required this.title,
    required this.publicationDate,
    this.publicationYear,
    this.publicationDateSource = '',
    this.subjects = '',
    this.authors = '',
    this.collectionUuid = '',
    this.collectionName = '',
    this.unitCode = '',
    this.unitName = '',
    this.targetPrograms = const [],
    this.programCodes = const [],
    this.lecturers = const [],
    this.yearOfStudy = '1st Year',
    this.semester = 'Semester 1',
    this.bitstreamUuid,
    this.fileName = '',
    this.fileSizeBytes = 0,
    this.md5 = '',
    this.downloadUrl = '',
  });

  factory DiscoveredDSpacePaper.fromMap(Map<String, dynamic> map) {
    return DiscoveredDSpacePaper(
      itemUuid: map['itemUuid'] as String? ?? '',
      handle: map['handle'] as String? ?? '',
      title: map['title'] as String? ?? 'Untitled Examination Paper',
      publicationDate: map['publicationDate'] as String? ?? '',
      publicationYear: map['publicationYear'] is int
          ? map['publicationYear'] as int
          : (map['publicationYear'] != null ? int.tryParse(map['publicationYear'].toString()) : null),
      publicationDateSource: map['publicationDateSource'] as String? ?? '',
      subjects: map['subjects'] as String? ?? '',
      authors: map['authors'] as String? ?? '',
      collectionUuid: map['collectionUuid'] as String? ?? '',
      collectionName: map['collectionName'] as String? ?? '',
      unitCode: map['unitCode'] as String? ?? '',
      unitName: map['unitName'] as String? ?? '',
      targetPrograms: List<String>.from(map['targetPrograms'] ?? []),
      programCodes: List<String>.from(map['programCodes'] ?? []),
      lecturers: List<String>.from(map['lecturers'] ?? []),
      yearOfStudy: map['yearOfStudy'] as String? ?? '1st Year',
      semester: map['semester'] as String? ?? 'Semester 1',
      bitstreamUuid: map['bitstreamUuid'] as String?,
      fileName: map['fileName'] as String? ?? '',
      fileSizeBytes: (map['fileSizeBytes'] as num?)?.toInt() ?? 0,
      md5: map['md5'] as String? ?? '',
      downloadUrl: map['downloadUrl'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'itemUuid': itemUuid,
      'handle': handle,
      'title': title,
      'publicationDate': publicationDate,
      'publicationYear': publicationYear,
      'publicationDateSource': publicationDateSource,
      'subjects': subjects,
      'authors': authors,
      'collectionUuid': collectionUuid,
      'collectionName': collectionName,
      'unitCode': unitCode,
      'unitName': unitName,
      'targetPrograms': targetPrograms,
      'programCodes': programCodes,
      'lecturers': lecturers,
      'yearOfStudy': yearOfStudy,
      'semester': semester,
      'bitstreamUuid': bitstreamUuid,
      'fileName': fileName,
      'fileSizeBytes': fileSizeBytes,
      'md5': md5,
      'downloadUrl': downloadUrl,
    };
  }
}

/// Final summary reported upon job completion.
class DSpaceJobSummaryModel {
  final int newDiscovered;
  final int successfullyImported;
  final int failedImports;
  final int skippedDuplicates;
  final int itemsPending;
  final int durationSeconds;

  const DSpaceJobSummaryModel({
    required this.newDiscovered,
    required this.successfullyImported,
    required this.failedImports,
    required this.skippedDuplicates,
    required this.itemsPending,
    required this.durationSeconds,
  });

  factory DSpaceJobSummaryModel.fromMap(Map<String, dynamic> map) {
    return DSpaceJobSummaryModel(
      newDiscovered: (map['newDiscovered'] as num?)?.toInt() ?? 0,
      successfullyImported: (map['successfullyImported'] as num?)?.toInt() ?? 0,
      failedImports: (map['failedImports'] as num?)?.toInt() ?? 0,
      skippedDuplicates: (map['skippedDuplicates'] as num?)?.toInt() ?? 0,
      itemsPending: (map['itemsPending'] as num?)?.toInt() ?? 0,
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'newDiscovered': newDiscovered,
      'successfullyImported': successfullyImported,
      'failedImports': failedImports,
      'skippedDuplicates': skippedDuplicates,
      'itemsPending': itemsPending,
      'durationSeconds': durationSeconds,
    };
  }
}

/// Represents an asynchronous DSpace job state stored in Firestore.
class DSpaceJobModel {
  final String id;
  final String action; // 'check' | 'check_and_download'
  final String status; // 'queued' | 'running' | 'completed' | 'failed' | 'cancelled' | 'partial_failure'
  final double progress;
  final int totalItems;
  final int discoveredCount;
  final int importedCount;
  final int failedCount;
  final int skippedCount;
  final int pendingCount;
  final List<DiscoveredDSpacePaper> discoveredItems;
  final String message;
  final DSpaceJobSummaryModel? summary;
  final String? error;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;
  final String? createdBy;
  final String? createdByName;
  final String? continuationJobId;
  final String? parentJobId;
  final int? sliceIndex;

  const DSpaceJobModel({
    required this.id,
    required this.action,
    required this.status,
    required this.progress,
    required this.totalItems,
    required this.discoveredCount,
    required this.importedCount,
    required this.failedCount,
    required this.skippedCount,
    required this.pendingCount,
    required this.discoveredItems,
    required this.message,
    this.summary,
    this.error,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.createdBy,
    this.createdByName,
    this.continuationJobId,
    this.parentJobId,
    this.sliceIndex,
  });

  bool get isPaused => status == 'paused';
  bool get isRunning => status == 'running';
  bool get isQueued => status == 'queued';
  bool get isBusy => isRunning || isQueued || isPaused;
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isCancelled => status == 'cancelled';
  bool get isPartialFailure => status == 'partial_failure';
  bool get isFinished => isCompleted || isFailed || isCancelled || isPartialFailure;

  factory DSpaceJobModel.fromFirestore(DocumentSnapshot doc) {
    final map = doc.data() as Map<String, dynamic>? ?? {};
    return DSpaceJobModel.fromMap(doc.id, map);
  }

  factory DSpaceJobModel.fromMap(String id, Map<String, dynamic> map) {
    DateTime? parseTimestamp(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    final rawItems = map['discoveredItems'] as List<dynamic>? ?? [];
    final items = rawItems
        .whereType<Map>()
        .map((m) => DiscoveredDSpacePaper.fromMap(Map<String, dynamic>.from(m)))
        .toList();

    DSpaceJobSummaryModel? summary;
    if (map['summary'] is Map) {
      summary = DSpaceJobSummaryModel.fromMap(Map<String, dynamic>.from(map['summary'] as Map));
    }

    return DSpaceJobModel(
      id: id,
      action: map['action'] as String? ?? 'check',
      status: map['status'] as String? ?? 'queued',
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      totalItems: (map['totalItems'] as num?)?.toInt() ?? 0,
      discoveredCount: (map['discoveredCount'] as num?)?.toInt() ?? 0,
      importedCount: (map['importedCount'] as num?)?.toInt() ?? 0,
      failedCount: (map['failedCount'] as num?)?.toInt() ?? 0,
      skippedCount: (map['skippedCount'] as num?)?.toInt() ?? 0,
      pendingCount: (map['pendingCount'] as num?)?.toInt() ?? 0,
      discoveredItems: items,
      message: map['message'] as String? ?? '',
      summary: summary,
      error: map['error'] as String?,
      createdAt: parseTimestamp(map['createdAt']),
      updatedAt: parseTimestamp(map['updatedAt']),
      completedAt: parseTimestamp(map['completedAt']),
      createdBy: map['createdBy'] as String?,
      createdByName: map['createdByName'] as String?,
      continuationJobId: map['continuationJobId'] as String?,
      parentJobId: map['parentJobId'] as String?,
      sliceIndex: (map['sliceIndex'] as num?)?.toInt(),
    );
  }
}
