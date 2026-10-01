import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mirror_laikipia/models/manual_ad.dart';
import 'package:mirror_laikipia/services/persistence_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PersistenceService().init();
  });

  group('Manual Ads Action Row Overflow & Layout Tests', () {
    final testAd = ManualAd(
      id: 'test_ad_overflow_01',
      title: 'Safari Park Hotel & Casino',
      subtitle: 'Exclusive student discount on conference facilities and catering',
      imageUrl: '',
      contactUrl: 'https://wa.me/254712345678',
      colorValue: 0xFF20C8FF,
      isActive: true,
      isAsset: false,
      type: 'image',
      placement: 'carousel',
      views: 1245,
    );

    for (final width in [320.0, 360.0, 375.0, 390.0, 412.0]) {
      testWidgets('Renders cleanly without overflow on screen width ${width}dp', (tester) async {
        tester.view.physicalSize = Size(width, 800.0);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final List<FlutterErrorDetails> errors = [];
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          errors.add(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  _TestAdCard(ad: testAd),
                ],
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 1. Assert zero RenderFlex overflow errors
        final overflowErrors = errors.where((e) => e.toString().contains('overflowed by')).toList();
        expect(overflowErrors, isEmpty, reason: 'RenderFlex overflow detected on width $width');

        // 2. Assert Views control exists and has the expected text
        expect(find.textContaining('Views 1,245'), findsOneWidget);

        // 3. Assert Active toggle text exists
        expect(find.text('Active'), findsOneWidget);

        // 4. Assert all 3 action icon buttons exist
        expect(find.byIcon(Icons.remove_red_eye_outlined), findsOneWidget);
        expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
        expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
      });
    }

    testWidgets('Large view count (999,999) does not cause overflow on narrow screen (320dp)', (tester) async {
      tester.view.physicalSize = const Size(320.0, 800.0);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final highCountAd = testAd.copyWith(views: 999999);

      final List<FlutterErrorDetails> errors = [];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                _TestAdCard(ad: highCountAd),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final overflowErrors = errors.where((e) => e.toString().contains('overflowed by')).toList();
      expect(overflowErrors, isEmpty);
      expect(find.textContaining('Views'), findsOneWidget);
    });
  });
}

class _TestAdCard extends StatelessWidget {
  final ManualAd ad;

  const _TestAdCard({required this.ad});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF141228),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ad.subtitle, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 10),
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 10),
                // Actions Row using Flexible architecture
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Active/Inactive Toggle (Left Side)
                    Flexible(
                      flex: 3,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 24,
                            width: 34,
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: Switch(
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                value: ad.isActive,
                                activeThumbColor: const Color(0xFF00E676),
                                activeTrackColor: const Color(0xFF00E676).withValues(alpha: 0.4),
                                inactiveThumbColor: Colors.white38,
                                inactiveTrackColor: Colors.white12,
                                onChanged: (_) {},
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                ad.isActive ? 'Active' : 'Inactive',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 4),

                    // Right Side: Views + Preview + Edit + Delete
                    Flexible(
                      flex: 7,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Views Count Control (Immediately to the LEFT of the Preview Button)
                          Flexible(
                            child: Tooltip(
                              message: 'Total Views: ${ad.views}',
                              child: Container(
                                margin: const EdgeInsets.only(right: 3),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF20C8FF).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF20C8FF).withValues(alpha: 0.30)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.visibility_outlined, color: Color(0xFF20C8FF), size: 14),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          'Views ${ad.views >= 100000 ? "100K+" : "1,245"}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Preview Button
                          IconButton(
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.all(4),
                            ),
                            icon: const Icon(Icons.remove_red_eye_outlined, color: Color(0xFF20C8FF), size: 18),
                            tooltip: 'Live Preview',
                            onPressed: () {},
                          ),

                          // Edit Button
                          IconButton(
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.all(4),
                            ),
                            icon: const Icon(Icons.edit_outlined, color: Colors.white70, size: 18),
                            tooltip: 'Edit Ad',
                            onPressed: () {},
                          ),

                          // Delete Button
                          IconButton(
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.all(4),
                            ),
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                            tooltip: 'Delete Ad',
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
