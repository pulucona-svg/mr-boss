import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../screens/material_viewer_screen.dart';
import 'interstitial_ad_service.dart';

class ExternalDocumentService {
  static final ExternalDocumentService _instance = ExternalDocumentService._internal();
  factory ExternalDocumentService() => _instance;
  ExternalDocumentService._internal();

  static const MethodChannel _channel = MethodChannel('com.mirrordigital.app/external_documents');
  bool _isInitialized = false;

  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    _channel.setMethodCallHandler(_handleMethodCall);

    // Check for cold-start incoming document
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkInitialDocument();
    });
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onDocumentReceived') {
      final data = call.arguments;
      if (data is Map) {
        _openDocument(Map<String, dynamic>.from(data));
      }
    }
  }

  Future<void> checkInitialDocument() async {
    try {
      final result = await _channel.invokeMethod<Map>('getInitialDocument');
      if (result != null) {
        _openDocument(Map<String, dynamic>.from(result));
      }
    } catch (e) {
      debugPrint('ExternalDocumentService: Error retrieving initial document: $e');
    }
  }

  void _openDocument(Map<String, dynamic> docData) {
    final String? filePath = docData['filePath'] as String?;
    final String title = (docData['title'] as String?)?.trim().isNotEmpty == true
        ? (docData['title'] as String).trim()
        : 'External Document';

    if (filePath == null || filePath.isEmpty) return;
    final file = File(filePath);
    if (!file.existsSync()) return;

    debugPrint('ExternalDocumentService: Opening external document directly in viewer: $title ($filePath)');

    // Open directly in MaterialViewerScreen without publishing or uploading to academic resources
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navState = InterstitialAdService.navigatorKey.currentState;
      if (navState != null) {
        navState.push(
          MaterialPageRoute(
            builder: (context) => MaterialViewerScreen(
              id: 'ext_${file.uri.pathSegments.last}',
              title: title,
              fileUrl: filePath,
              category: 'Document',
            ),
          ),
        );
      }
    });
  }

  Future<void> clearCache() async {
    try {
      await _channel.invokeMethod('clearExternalDocumentsCache');
    } catch (_) {}
  }
}
