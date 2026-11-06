import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:mirror_laikipia/models/ai_provider.dart';
import 'package:mirror_laikipia/screens/ai_assistant_screen.dart';
import 'package:mirror_laikipia/screens/ai_chatgpt_screen.dart';

class MockPlatformWebViewController extends PlatformWebViewController {
  MockPlatformWebViewController(super.params) : super.implementation();

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setUserAgent(String? userAgent) async {}

  @override
  Future<void> setPlatformNavigationDelegate(PlatformNavigationDelegate handler) async {}

  @override
  Future<bool> canGoBack() async => false;

  @override
  Future<void> reload() async {}
}

class MockPlatformNavigationDelegate extends PlatformNavigationDelegate {
  MockPlatformNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback onNavigationRequest) async {}

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {}

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {}

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback onWebResourceError) async {}
}

class MockPlatformWebViewWidget extends PlatformWebViewWidget {
  MockPlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(key: Key('mock_platform_webview'));
  }
}

class MockWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return MockPlatformWebViewController(params);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return MockPlatformNavigationDelegate(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return MockPlatformWebViewWidget(params);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> securityChannelLog = <MethodCall>[];
  String? clipboardContent;

  setUp(() {
    securityChannelLog.clear();
    clipboardContent = null;
    WebViewPlatform.instance = MockWebViewPlatform();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.mirrordigital.app/security'),
      (MethodCall methodCall) async {
        securityChannelLog.add(methodCall);
        return true;
      },
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          clipboardContent = (methodCall.arguments as Map)['text'];
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.mirrordigital.app/security'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  testWidgets('AiChatGptScreen renders AppBar with official OpenAI logo, title, and actions', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: AiChatGptScreen(
          materialTitle: 'Advanced Data Structures',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('ChatGPT Assistant'), findsOneWidget);
    expect(find.text('Advanced Data Structures'), findsOneWidget);
    expect(find.byType(SvgPicture), findsWidgets);
    expect(find.byTooltip('Copy Study Prompt'), findsOneWidget);
    expect(find.byTooltip('Reload'), findsOneWidget);
    expect(find.byTooltip('Open in Official App / Browser'), findsOneWidget);

    // Verify secure screen was enabled on mount
    expect(securityChannelLog.any((c) => c.method == 'enableSecureScreen'), isTrue);
  });

  testWidgets('AiAssistantScreen supports all 5 AI providers with accurate brand titles', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final provider in AiProviderConfig.allProviders) {
      await tester.pumpWidget(
        MaterialApp(
          home: AiAssistantScreen(
            provider: provider,
            materialTitle: 'Organic Chemistry',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('${provider.displayName} Assistant'), findsOneWidget);
      expect(find.text('Organic Chemistry'), findsOneWidget);
      expect(find.byType(SvgPicture), findsWidgets);
    }
  });

  testWidgets('Copy prompt button copies relevant document prompt to clipboard', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: AiChatGptScreen(
          materialTitle: 'Organic Chemistry',
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Copy Study Prompt'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(clipboardContent, contains('Organic Chemistry'));
    expect(find.text('Prompt copied! Paste it into ChatGPT to start.'), findsOneWidget);
  });

  testWidgets('Privacy shield appears when app goes into background/inactive state', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: AiChatGptScreen(
          materialTitle: 'Physics I',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Privacy Shield Active'), findsNothing);

    // Simulate switching apps (inactive / paused)
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Privacy Shield Active'), findsOneWidget);

    // Simulate returning to the app (resumed)
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Privacy Shield Active'), findsNothing);
  });
}
