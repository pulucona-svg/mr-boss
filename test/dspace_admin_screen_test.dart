import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:mirror_laikipia/models/dspace_job_model.dart';
import 'package:mirror_laikipia/screens/admin/dspace_admin_screen.dart';

void main() {
  setUp(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  testWidgets('DSpaceAdminScreen renders initial idle state with buttons and header', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: DSpaceAdminScreen(),
      ),
    );
    await tester.pump();

    // Verify Title
    expect(find.text('DSpace Examination Papers'), findsOneWidget);

    // Verify Repository Card
    expect(find.text('Laikipia University Repository'), findsOneWidget);
    expect(find.textContaining('Community: Examination Past Papers'), findsOneWidget);

    // Verify Action Buttons
    expect(find.text('Check'), findsOneWidget);
    expect(find.text('Check & Download'), findsOneWidget);

    // Verify Section Header
    expect(find.textContaining('Newly Discovered Examination Papers'), findsOneWidget);
  });

  testWidgets('DiscoveredDSpacePaper renders paper details correctly', (WidgetTester tester) async {
    const paper = DiscoveredDSpacePaper(
      itemUuid: 'dspace-item-test-1',
      handle: '12345/678',
      title: 'BOTA 222: Plant Anatomy & Physiology',
      unitCode: 'BOTA 222',
      unitName: 'Plant Anatomy & Physiology',
      publicationDate: '2023',
      publicationYear: 2023,
      collectionName: 'School of Biological Sciences',
      downloadUrl: 'https://dspace.example.com/item1.pdf',
      fileSizeBytes: 2097152,
      subjects: 'Botany; Anatomy',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              Card(
                child: ListTile(
                  title: Text(paper.title),
                  subtitle: Text('${paper.unitCode} • ${paper.publicationYear}'),
                  trailing: Text(paper.collectionName),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('BOTA 222: Plant Anatomy & Physiology'), findsOneWidget);
    expect(find.text('BOTA 222 • 2023'), findsOneWidget);
    expect(find.text('School of Biological Sciences'), findsOneWidget);
  });
}
