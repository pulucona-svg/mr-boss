import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import '../models/ai_provider.dart';
import '../services/security_service.dart';

class AiAssistantScreen extends StatefulWidget {
  final AiProviderConfig provider;
  final String materialTitle;
  final String? initialPrompt;

  const AiAssistantScreen({
    super.key,
    required this.provider,
    required this.materialTitle,
    this.initialPrompt,
  });

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _isLoading = true;
  double _loadingProgress = 0.0;
  String? _errorMessage;
  bool _isBackgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SecurityService().enableSecureScreen();
    _initWebView();
  }

  void _initWebView() {
    // Standard clean mobile User-Agent to ensure Cloudflare Turnstile & WebKit compatibility
    final userAgent = Platform.isIOS
        ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1'
        : 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(userAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) {
              setState(() {
                _loadingProgress = progress / 100.0;
                if (progress >= 100) {
                  _isLoading = false;
                }
              });
            }
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('AiAssistantScreen (${widget.provider.displayName}): Resource error: ${error.description} (${error.errorCode})');
            if (error.isForMainFrame == true && mounted) {
              setState(() {
                _isLoading = false;
                _errorMessage = error.description;
              });
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;

            final host = uri.host.toLowerCase();
            final isAllowed = widget.provider.allowedDomains.any(
              (domain) => host == domain || host.endsWith('.$domain'),
            );

            if (isAllowed) {
              return NavigationDecision.navigate;
            }

            // Launch non-provider external URLs in system browser
            _launchExternal(request.url);
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.provider.url));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        setState(() => _isBackgrounded = false);
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (mounted) {
        setState(() => _isBackgrounded = true);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _handleBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _launchExternal([String? targetUrl]) async {
    final url = targetUrl ?? widget.provider.url;
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch external browser.')),
        );
      }
    } catch (e) {
      debugPrint('AiAssistantScreen: Error launching external URL: $e');
    }
  }

  void _copyPrompt() {
    final prompt = widget.initialPrompt ??
        'I am studying "${widget.materialTitle}". Can you explain the core concepts and summarize the key points for me?';
    Clipboard.setData(ClipboardData(text: prompt));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Color(0xFF20C8FF), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Prompt copied! Paste it into ${widget.provider.displayName} to start.',
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1F1B46),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF070716),
        appBar: AppBar(
          backgroundColor: const Color(0xFF141232),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
            onPressed: _handleBack,
            tooltip: 'Back to document',
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  widget.provider.buildIcon(size: 18, color: widget.provider.brandColor),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${widget.provider.displayName} Assistant',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF20C8FF),
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.materialTitle.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(
                  widget.materialTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white60,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 18),
              tooltip: 'Copy Study Prompt',
              onPressed: _copyPrompt,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
              tooltip: 'Reload',
              onPressed: () => _controller.reload(),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFF20C8FF), size: 18),
              tooltip: 'Open in Official App / Browser',
              onPressed: () => _launchExternal(),
            ),
            const SizedBox(width: 4),
          ],
          bottom: _isLoading
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2.5),
                  child: LinearProgressIndicator(
                    value: _loadingProgress > 0 ? _loadingProgress : null,
                    backgroundColor: Colors.transparent,
                    color: const Color(0xFF20C8FF),
                    minHeight: 2.5,
                  ),
                )
              : null,
        ),
        body: Stack(
          children: [
            if (_errorMessage != null)
              _buildErrorView()
            else
              WebViewWidget(controller: _controller),
            if (_isBackgrounded)
              _buildPrivacyShield(),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Container(
      color: const Color(0xFF070716),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.provider.buildIcon(size: 48, color: widget.provider.brandColor),
            const SizedBox(height: 16),
            Text(
              'Could not load ${widget.provider.displayName} in-app',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Network or security verification blocked the connection.',
              style: const TextStyle(color: Colors.white60, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _launchExternal(),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open in Official App / Browser'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF20C8FF),
                foregroundColor: const Color(0xFF070716),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                setState(() => _errorMessage = null);
                _controller.reload();
              },
              icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 18),
              label: const Text('Retry Connection', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyShield() {
    return Container(
      color: const Color(0xFF070716),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFF20C8FF), size: 48),
            SizedBox(height: 12),
            Text(
              'Privacy Shield Active',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
