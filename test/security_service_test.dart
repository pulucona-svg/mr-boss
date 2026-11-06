import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_laikipia/services/security_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> log = <MethodCall>[];
  bool mockSecureState = true;
  bool shouldThrowError = false;

  setUp(() {
    log.clear();
    mockSecureState = true;
    shouldThrowError = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.mirrordigital.app/security'),
      (MethodCall methodCall) async {
        if (shouldThrowError) {
          throw PlatformException(code: 'ERROR', message: 'Platform failure');
        }
        log.add(methodCall);
        switch (methodCall.method) {
          case 'enableSecureScreen':
            mockSecureState = true;
            return true;
          case 'disableSecureScreen':
            // Platform keeps FLAG_SECURE active under global security policy
            return true;
          case 'isSecureScreenEnabled':
            return mockSecureState;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.mirrordigital.app/security'),
      null,
    );
  });

  test('SecurityService is a singleton', () {
    final s1 = SecurityService();
    final s2 = SecurityService();
    expect(identical(s1, s2), isTrue);
  });

  test('enableSecureScreen invokes platform channel and enforces global state', () async {
    final service = SecurityService();
    final result = await service.enableSecureScreen();

    expect(result, isTrue);
    expect(service.isSecureScreenEnabled, isTrue);
    expect(log.length, 1);
    expect(log.first.method, 'enableSecureScreen');
  });

  test('disableSecureScreen preserves global protection policy across all screens', () async {
    final service = SecurityService();
    await service.enableSecureScreen();
    expect(service.isSecureScreenEnabled, isTrue);

    // Calling disableSecureScreen must not clear global application protection
    final result = await service.disableSecureScreen();
    expect(result, isTrue);
    expect(service.isSecureScreenEnabled, isTrue);
    expect(log.length, 2);
    expect(log.last.method, 'disableSecureScreen');
  });

  test('checkPlatformSecureStatus queries platform state accurately', () async {
    final service = SecurityService();
    mockSecureState = true;
    final status = await service.checkPlatformSecureStatus();
    expect(status, isTrue);
    expect(service.isSecureScreenEnabled, isTrue);
    expect(log.last.method, 'isSecureScreenEnabled');
  });

  test('gracefully handles platform exceptions without dropping global protection', () async {
    shouldThrowError = true;
    final service = SecurityService();
    // Default safe fallback ensures protection remains enabled
    final enableResult = await service.enableSecureScreen();
    expect(enableResult, isTrue);
    expect(service.isSecureScreenEnabled, isTrue);

    final disableResult = await service.disableSecureScreen();
    expect(disableResult, isTrue);
    expect(service.isSecureScreenEnabled, isTrue);
  });
}
