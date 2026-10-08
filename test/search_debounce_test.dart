import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Search Debounce Behavior Unit Tests', () {
    test('Dashboard 200ms debounce: rapid keystrokes cancel previous timers and only execute once after pause', () async {
      int searchExecutedCount = 0;
      String lastExecutedQuery = '';
      Timer? debounceTimer;

      void onSearchChangedSimulated(String value) {
        if (value.isEmpty) {
          debounceTimer?.cancel();
          searchExecutedCount++;
          lastExecutedQuery = '';
          return;
        }

        debounceTimer?.cancel();
        debounceTimer = Timer(const Duration(milliseconds: 200), () {
          searchExecutedCount++;
          lastExecutedQuery = value;
        });
      }

      // Simulate rapid typing: 'c', 'ca', 'cal', 'calc' within 50ms intervals
      onSearchChangedSimulated('c');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(searchExecutedCount, 0, reason: 'Must not execute while typing');

      onSearchChangedSimulated('ca');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(searchExecutedCount, 0, reason: 'Must not execute while typing');

      onSearchChangedSimulated('cal');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(searchExecutedCount, 0, reason: 'Must not execute while typing');

      onSearchChangedSimulated('calc');
      // Wait less than 200ms
      await Future.delayed(const Duration(milliseconds: 100));
      expect(searchExecutedCount, 0, reason: 'Must not execute before 200ms expires');

      // Now pause for more than 200ms
      await Future.delayed(const Duration(milliseconds: 150)); // Total 250ms since last key
      expect(searchExecutedCount, 1, reason: 'Must execute exactly once after pause');
      expect(lastExecutedQuery, 'calc');

      // Immediate clear action
      onSearchChangedSimulated('');
      expect(searchExecutedCount, 2, reason: 'Clear action must execute immediately');
      expect(lastExecutedQuery, '', reason: 'Query must be cleared immediately');

      debounceTimer?.cancel();
    });

    test('PDF Search 300ms debounce: rapid keystrokes cancel previous timers and execute after 300ms pause', () async {
      int pdfSearchExecutedCount = 0;
      String lastPdfQuery = '';
      Timer? pdfDebounceTimer;

      void onPdfSearchChangedSimulated(String value) {
        pdfDebounceTimer?.cancel();
        if (value.isEmpty) {
          pdfSearchExecutedCount++;
          lastPdfQuery = '';
          return;
        }

        pdfDebounceTimer = Timer(const Duration(milliseconds: 300), () {
          pdfSearchExecutedCount++;
          lastPdfQuery = value;
        });
      }

      // Rapid keystrokes: 't', 'te', 'tes', 'test'
      onPdfSearchChangedSimulated('t');
      await Future.delayed(const Duration(milliseconds: 80));
      onPdfSearchChangedSimulated('te');
      await Future.delayed(const Duration(milliseconds: 80));
      onPdfSearchChangedSimulated('tes');
      await Future.delayed(const Duration(milliseconds: 80));
      onPdfSearchChangedSimulated('test');

      // 150ms after last keystroke (< 300ms)
      await Future.delayed(const Duration(milliseconds: 150));
      expect(pdfSearchExecutedCount, 0, reason: 'Must not trigger search before 300ms expires');

      // Another 200ms (total 350ms after 'test')
      await Future.delayed(const Duration(milliseconds: 200));
      expect(pdfSearchExecutedCount, 1, reason: 'Must trigger search exactly once after 300ms pause');
      expect(lastPdfQuery, 'test');

      // Clear immediately
      onPdfSearchChangedSimulated('');
      expect(pdfSearchExecutedCount, 2);
      expect(lastPdfQuery, '');

      pdfDebounceTimer?.cancel();
    });
  });
}
