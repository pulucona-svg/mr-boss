import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_laikipia/models/dspace_job_model.dart';

void main() {
  group('DiscoveredDSpacePaper', () {
    test('serializes and deserializes correctly from map', () {
      final json = {
        'itemUuid': 'item-12345',
        'handle': '123456789/100',
        'title': 'COMP 311: Computer Networks Examination Paper',
        'unitCode': 'COMP 311',
        'unitName': 'Computer Networks',
        'publicationDate': '2023',
        'publicationYear': 2023,
        'collectionUuid': 'col-uuid-1',
        'collectionName': 'Department of Computer Science',
        'bitstreamUuid': 'bs-uuid-1',
        'downloadUrl': 'https://dspace.example.com/bitstream/12345/exam.pdf',
        'fileName': 'COMP311_Exam.pdf',
        'fileSizeBytes': 1048576,
        'md5': 'abcdef1234567890',
        'subjects': 'Computer Networks; Routing; TCP/IP',
        'authors': 'Laikipia University',
        'yearOfStudy': '3rd Year',
        'semester': 'Semester 1',
      };

      final paper = DiscoveredDSpacePaper.fromMap(json);

      expect(paper.itemUuid, 'item-12345');
      expect(paper.handle, '123456789/100');
      expect(paper.title, 'COMP 311: Computer Networks Examination Paper');
      expect(paper.unitCode, 'COMP 311');
      expect(paper.unitName, 'Computer Networks');
      expect(paper.publicationDate, '2023');
      expect(paper.publicationYear, 2023);
      expect(paper.collectionName, 'Department of Computer Science');
      expect(paper.downloadUrl, 'https://dspace.example.com/bitstream/12345/exam.pdf');
      expect(paper.fileSizeBytes, 1048576);
      expect(paper.subjects, 'Computer Networks; Routing; TCP/IP');

      final serialized = paper.toMap();
      expect(serialized['itemUuid'], 'item-12345');
      expect(serialized['title'], 'COMP 311: Computer Networks Examination Paper');
      expect(serialized['unitCode'], 'COMP 311');
      expect(serialized['fileSizeBytes'], 1048576);
    });

    test('handles null and missing fields gracefully with defaults', () {
      final json = <String, dynamic>{
        'itemUuid': 'empty-paper',
      };

      final paper = DiscoveredDSpacePaper.fromMap(json);

      expect(paper.itemUuid, 'empty-paper');
      expect(paper.title, 'Untitled Examination Paper');
      expect(paper.unitCode, '');
      expect(paper.unitName, '');
      expect(paper.publicationDate, '');
      expect(paper.publicationYear, isNull);
      expect(paper.fileSizeBytes, 0);
      expect(paper.subjects, '');
    });
  });

  group('DSpaceJobSummaryModel', () {
    test('serializes and deserializes accurately', () {
      final json = {
        'newDiscovered': 15,
        'successfullyImported': 12,
        'failedImports': 1,
        'skippedDuplicates': 2,
        'itemsPending': 0,
        'durationSeconds': 42,
      };

      final summary = DSpaceJobSummaryModel.fromMap(json);

      expect(summary.newDiscovered, 15);
      expect(summary.successfullyImported, 12);
      expect(summary.failedImports, 1);
      expect(summary.skippedDuplicates, 2);
      expect(summary.itemsPending, 0);
      expect(summary.durationSeconds, 42);

      final map = summary.toMap();
      expect(map['newDiscovered'], 15);
      expect(map['successfullyImported'], 12);
      expect(map['failedImports'], 1);
      expect(map['skippedDuplicates'], 2);
      expect(map['itemsPending'], 0);
      expect(map['durationSeconds'], 42);
    });
  });

  group('DSpaceJobModel', () {
    test('correctly parses full job model and computes helper getters', () {
      final json = {
        'action': 'check_and_download',
        'status': 'completed',
        'progress': 1.0,
        'totalItems': 10,
        'discoveredCount': 10,
        'importedCount': 8,
        'failedCount': 0,
        'skippedCount': 2,
        'pendingCount': 0,
        'message': 'Synchronization complete',
        'discoveredItems': [
          {
            'itemUuid': 'p-1',
            'title': 'BOTA 111: Plant Morphology',
            'unitCode': 'BOTA 111',
            'publicationYear': 2024,
          }
        ],
        'summary': {
          'newDiscovered': 10,
          'successfullyImported': 8,
          'failedImports': 0,
          'skippedDuplicates': 2,
          'itemsPending': 0,
          'durationSeconds': 35,
        },
      };

      final job = DSpaceJobModel.fromMap('dspace_job_abc123', json);

      expect(job.id, 'dspace_job_abc123');
      expect(job.action, 'check_and_download');
      expect(job.status, 'completed');
      expect(job.isCompleted, isTrue);
      expect(job.isBusy, isFalse);
      expect(job.isFailed, isFalse);
      expect(job.discoveredCount, 10);
      expect(job.discoveredItems.length, 1);
      expect(job.discoveredItems.first.title, 'BOTA 111: Plant Morphology');
      expect(job.summary?.successfullyImported, 8);
    });

    test('recognizes active/busy states', () {
      final runningJson = {
        'action': 'check',
        'status': 'running',
        'progress': 0.45,
      };

      final jobRunning = DSpaceJobModel.fromMap('job-1', runningJson);
      expect(jobRunning.isBusy, isTrue);
      expect(jobRunning.isRunning, isTrue);
      expect(jobRunning.isCompleted, isFalse);

      final queuedJson = {
        'action': 'check',
        'status': 'queued',
      };
      final jobQueued = DSpaceJobModel.fromMap('job-2', queuedJson);
      expect(jobQueued.isBusy, isTrue);
      expect(jobQueued.isQueued, isTrue);
    });

    test('recognizes failed, cancelled, and paused auto-resuming states', () {
      final failedJob = DSpaceJobModel.fromMap('job-failed', {
        'action': 'check',
        'status': 'failed',
        'error': 'DSpace connection timed out',
      });
      expect(failedJob.isFailed, isTrue);
      expect(failedJob.isBusy, isFalse);
      expect(failedJob.error, 'DSpace connection timed out');

      final cancelledJob = DSpaceJobModel.fromMap('job-cancelled', {
        'action': 'check',
        'status': 'cancelled',
      });
      expect(cancelledJob.isCancelled, isTrue);
      expect(cancelledJob.isBusy, isFalse);

      final pausedJob = DSpaceJobModel.fromMap('job-paused-1', {
        'action': 'check_and_download',
        'status': 'paused',
        'continuationJobId': 'job-continuation-2',
        'parentJobId': null,
        'sliceIndex': 1,
        'message': 'Batch execution limit reached (7.5m). Auto-resuming next slice...',
      });
      expect(pausedJob.isPaused, isTrue);
      expect(pausedJob.isBusy, isTrue);
      expect(pausedJob.continuationJobId, 'job-continuation-2');
      expect(pausedJob.sliceIndex, 1);
    });
  });
}
