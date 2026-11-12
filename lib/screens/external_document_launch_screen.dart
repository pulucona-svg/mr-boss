import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import '../screens/material_viewer_screen.dart';

/// Intermediate launch screen for external documents.
/// Displays the branded Mirror Digital splash screen while Flutter prepares the document,
/// eliminating any white screen flash and transitioning smoothly into MaterialViewerScreen.
class ExternalDocumentLaunchScreen extends StatefulWidget {
  final Map<String, dynamic> docData;

  const ExternalDocumentLaunchScreen({super.key, required this.docData});

  @override
  State<ExternalDocumentLaunchScreen> createState() => _ExternalDocumentLaunchScreenState();
}

class _ExternalDocumentLaunchScreenState extends State<ExternalDocumentLaunchScreen> {
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareAndLaunchDocument();
    });
  }

  Future<void> _prepareAndLaunchDocument() async {
    try {
      final String? filePath = widget.docData['filePath'] as String?;
      final String title = (widget.docData['title'] as String?)?.trim().isNotEmpty == true
          ? (widget.docData['title'] as String).trim()
          : 'External Document';

      if (filePath == null || filePath.isEmpty) {
        _handleError('Document path is missing.');
        return;
      }

      final file = File(filePath);
      if (!file.existsSync() || file.lengthSync() == 0) {
        _handleError('Document file could not be found or is empty.');
        return;
      }

      if (!mounted) return;

      // Transition smoothly into MaterialViewerScreen (MaterialViewerScreen will remove FlutterNativeSplash once onViewerReady fires)
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => MaterialViewerScreen(
            id: 'ext_${file.uri.pathSegments.last}',
            title: title,
            fileUrl: filePath,
            category: 'Document',
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 250),
        ),
      );
    } catch (e) {
      _handleError('Unable to open document: $e');
    }
  }

  void _handleError(String message) {
    try {
      FlutterNativeSplash.remove();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _errorMessage = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF070716),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.amber, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Unable to Open Document',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF20C8FF),
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Exact branded Mirror Digital splash design matching launch_background.xml and flutter_native_splash
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/splash_logo.png',
                  width: 160,
                  height: 160,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const CircularProgressIndicator(color: Color(0xFF20C8FF)),
                ),
                const SizedBox(height: 24),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFF20C8FF),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Opening document...',
                  style: TextStyle(
                    color: Color(0xFF141232),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: Image.asset(
              'assets/splash_branding.png',
              height: 38,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}
