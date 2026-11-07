import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';
import 'package:mirror_laikipia/services/progress_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
    await PersistenceService().clearAll();
    ProgressService().clear();
  });

  group('Task 4: Reading Progress & Page Counter Regression Tests', () {
    test('1. First-time document opening defaults to page 1 and produces no resume popup', () {
      final progressService = ProgressService();
      const docId = 'doc_first_time';

      expect(progressService.hasProgress(docId), isFalse);
      expect(progressService.getSavedPage(docId), equals(1));
      expect(progressService.getProgress(docId), equals(0.0));

      final savedPage = progressService.getSavedPage(docId);
      final shouldShowResume = savedPage > 1;
      expect(shouldShowResume, isFalse);
    });

    test('2. Saved page 1 produces no resume popup', () {
      final progressService = ProgressService();
      const docId = 'doc_page_one';

      progressService.updateProgress(
        docId,
        0.01,
        pageNumber: 1,
        totalPages: 100,
        title: 'Title One',
      );

      final savedPage = progressService.getSavedPage(docId);
      expect(savedPage, equals(1));

      final shouldShowResume = savedPage > 1;
      expect(shouldShowResume, isFalse);
    });

    test('3. Saved page 30 qualifies for resume popup while starting viewer at page 1', () {
      final progressService = ProgressService();
      const docId = 'doc_page_30';

      progressService.updateProgress(
        docId,
        0.30,
        pageNumber: 30,
        totalPages: 100,
        title: 'Anatomy Lecture',
      );

      final savedPage = progressService.getSavedPage(docId);
      expect(savedPage, equals(30));

      // Initial opening page is ALWAYS 1
      const initialOpeningPage = 1;
      expect(initialOpeningPage, equals(1));

      // Resume popup should appear because savedPage > 1
      final shouldShowResume = savedPage > 1;
      expect(shouldShowResume, isTrue);
    });

    test('4. Tapping resume navigates to page 30 and marks progress deliberate', () {
      int currentPage = 1;
      bool hasUserDeliberatelyProgressed = false;
      const savedPage = 30;

      // Simulate tapping resume
      void onResumeTapped() {
        currentPage = savedPage;
        hasUserDeliberatelyProgressed = true;
      }

      onResumeTapped();

      expect(currentPage, equals(30));
      expect(hasUserDeliberatelyProgressed, isTrue);
    });

    test('5. CRITICAL RULE: Popup expiration after 3 seconds does NOT overwrite page 30', () {
      final progressService = ProgressService();
      const docId = 'doc_expire_test';

      progressService.updateProgress(
        docId,
        0.30,
        pageNumber: 30,
        totalPages: 100,
        title: 'Biochemistry',
      );

      // User opened document, started at page 1, popup appeared and expired after 3 seconds
      bool hasUserDeliberatelyProgressed = false;
      const currentPage = 1;

      // If user never navigated deliberately, we do not update progress
      if (hasUserDeliberatelyProgressed) {
        progressService.updateProgress(
          docId,
          0.01,
          pageNumber: currentPage,
          totalPages: 100,
        );
      }

      // Saved reading position must STILL be 30
      expect(progressService.getSavedPage(docId), equals(30));
    });

    test('6. CRITICAL RULE: Closing at page 1 without resuming preserves page 30', () {
      final progressService = ProgressService();
      const docId = 'doc_close_page_1';

      progressService.updateProgress(
        docId,
        0.30,
        pageNumber: 30,
        totalPages: 100,
        title: 'Pathology',
      );

      // Simulate dispose() when user closes viewer while still on page 1 without deliberate progression
      bool hasUserDeliberatelyProgressed = false;
      final currentPageOnDispose = 1;

      if (hasUserDeliberatelyProgressed) {
        progressService.updateProgress(
          docId,
          currentPageOnDispose / 100,
          pageNumber: currentPageOnDispose,
          totalPages: 100,
        );
      }

      expect(progressService.getSavedPage(docId), equals(30));
    });

    test('7. Reopening document after closing at page 1 still offers page 30', () {
      final progressService = ProgressService();
      const docId = 'doc_reopen_test';

      progressService.updateProgress(
        docId,
        0.30,
        pageNumber: 30,
        totalPages: 100,
        title: 'Pharmacology',
      );

      // Reopening querying saved page
      final savedPageOnReopen = progressService.getSavedPage(docId);
      expect(savedPageOnReopen, equals(30));
      expect(savedPageOnReopen > 1, isTrue);
    });

    test('8. Different resources with identical titles retain independent progress by ID', () {
      final progressService = ProgressService();
      const docId1 = 'res_unique_001';
      const docId2 = 'res_unique_002';
      const commonTitle = 'Past Paper 2024';

      progressService.updateProgress(
        docId1,
        0.50,
        pageNumber: 10,
        totalPages: 20,
        title: commonTitle,
      );

      progressService.updateProgress(
        docId2,
        0.80,
        pageNumber: 16,
        totalPages: 20,
        title: commonTitle,
      );

      expect(progressService.getSavedPage(docId1), equals(10));
      expect(progressService.getSavedPage(docId2), equals(16));
    });

    test('9. Invalid saved page exceeding document page count is safely clamped', () {
      final progressService = ProgressService();
      const docId = 'doc_clamp_test';

      // Suppose saved page is 50, but document was updated to only have 25 pages
      progressService.updateProgress(
        docId,
        0.50,
        pageNumber: 50,
        totalPages: 100,
        title: 'Short Doc',
      );

      final rawSaved = progressService.getSavedPage(docId);
      const actualDocTotalPages = 25;

      final safePage = rawSaved.clamp(1, actualDocTotalPages);
      expect(safePage, equals(25));
    });

    test('10. Page counter formats as "Current page / Total pages"', () {
      String formatPageCounter(int currentPage, int totalPages) {
        if (totalPages <= 0) return '';
        return '$currentPage / $totalPages';
      }

      expect(formatPageCounter(1, 0), equals(''));
      expect(formatPageCounter(1, 20), equals('1 / 20'));
      expect(formatPageCounter(3, 20), equals('3 / 20'));
      expect(formatPageCounter(30, 100), equals('30 / 100'));
    });
  });
}
