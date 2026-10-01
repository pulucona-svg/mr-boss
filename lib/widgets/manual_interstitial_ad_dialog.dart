import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';
import '../services/interstitial_ad_service.dart';
import '../services/manual_ad_view_tracker.dart';

/// Full-screen offline manual interstitial ad dialog.
/// Displays server-synchronized ads with full adaptive image fitting and video playback support.
class ManualInterstitialAdDialog extends StatefulWidget {
  final VoidCallback onDismissed;
  final Map<String, dynamic>? adData;
  final bool isAppLaunch;
  final bool isPreview;

  const ManualInterstitialAdDialog({
    super.key,
    required this.onDismissed,
    this.adData,
    this.isAppLaunch = false,
    this.isPreview = false,
  });

  @override
  State<ManualInterstitialAdDialog> createState() => _ManualInterstitialAdDialogState();
}

class _ManualInterstitialAdDialogState extends State<ManualInterstitialAdDialog> {
  late Map<String, dynamic> _ad;
  bool _isDismissed = false;
  VideoPlayerController? _videoController;
  bool _isVideo = false;
  bool _isVideoLoading = false;
  bool _isVideoError = false;
  bool _isMuted = false; // SOUND ON by default as required
  String? _videoErrorMessage;
  Timer? _creativeTimer;
  int _currentIdleStage = 0;

  bool get _isAppLaunch =>
      widget.isAppLaunch ||
      (_ad['isAppLaunch'] == true) ||
      (_ad['placement'] == 'app_launch') ||
      (_ad['placement'] == 'app_launch_interstitial');

  int _countdownSeconds = 5;
  bool _isXState = false;
  Timer? _countdownTimer;
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    InterstitialAdService().addListener(_onAdServiceUpdated);

    if (widget.adData != null && widget.adData!.isNotEmpty) {
      _ad = Map<String, dynamic>.from(widget.adData!);
    } else if (widget.isAppLaunch) {
      final launchAd = InterstitialAdService().getNextAppLaunchAd();
      _ad = (launchAd ?? InterstitialAdService().getNextManualAd()).toDialogData();
    } else {
      _ad = InterstitialAdService().getNextManualAd().toDialogData();
    }

    if (!widget.isPreview) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isDismissed) {
          final id = _ad['id'] as String?;
          if (id != null && id.isNotEmpty) {
            ManualAdViewTracker().recordDisplay(id);
          }
        }
      });
    }

    if (_isAppLaunch) {
      _countdownSeconds = 5;
      _isXState = false;
      if (kDebugMode) debugPrint('[AppLaunchOffline] counter=5');
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _isDismissed) {
          timer.cancel();
          return;
        }
        if (_countdownSeconds > 0) {
          setState(() {
            _countdownSeconds--;
          });
          if (kDebugMode) debugPrint('[AppLaunchOffline] counter=$_countdownSeconds');
        } else {
          timer.cancel();
          setState(() {
            _isXState = true;
          });
          if (kDebugMode) debugPrint('[AppLaunchOffline] state=X');
          _autoCloseTimer = Timer(const Duration(seconds: 2), () {
            if (!mounted || _isDismissed) return;
            if (kDebugMode) {
              debugPrint('[AppLaunchOffline] state=X');
              debugPrint('[AppLaunchOffline] xTimeout=true');
              debugPrint('[AppLaunchOffline] completed=true');
            }
            _dismiss();
          });
        }
      });
    }

    _setupCurrentMedia();
  }

  void _setupCurrentMedia() {
    final String url = (_ad['url'] as String?) ?? (_ad['imageUrl'] as String?) ?? '';
    final String type = (_ad['type'] as String?) ?? 'image';
    _isVideo = type == 'video' ||
        url.endsWith('.mp4') ||
        url.endsWith('.mov') ||
        url.endsWith('.webm') ||
        url.endsWith('.mkv');

    if (_isVideo && url.isNotEmpty) {
      _initVideo(url);
    } else {
      // Normal interstitial images rotate according to idle schedule.
      // App launch ads are governed strictly by the 5-second countdown timer.
      if (!_isAppLaunch) {
        _startCreativeTimer();
      }
    }
  }

  Duration _getCreativeDuration() {
    final override = InterstitialAdService().manualIdleDelayOverrideForTesting;
    if (override != null) {
      return override(_currentIdleStage);
    }
    if (_isVideo) {
      final dur = _videoController?.value.duration ?? Duration.zero;
      if (dur > Duration.zero && dur < const Duration(seconds: 30)) {
        return dur;
      }
      return const Duration(seconds: 30);
    }
    // Image creative: maximum display duration = 10s
    return const Duration(seconds: 10);
  }

  void _startCreativeTimer() {
    _creativeTimer?.cancel();
    _creativeTimer = null;

    final delay = _getCreativeDuration();
    debugPrint('ManualInterstitialAdDialog: [CREATIVE_TIMER_STARTED] ${_isVideo ? "Video" : "Image"} display timer set for ${delay.inSeconds}s (Stage $_currentIdleStage).');

    _creativeTimer = Timer(delay, () {
      if (mounted && !_isDismissed) {
        _advanceToNextAd();
      }
    });
  }

  void _advanceToNextAd() {
    if (!mounted || _isDismissed) return;

    _creativeTimer?.cancel();
    _creativeTimer = null;
    _disposeVideoController();

    final currentId = _ad['id'] as String?;
    final nextAd = InterstitialAdService().getNextManualAd(currentlyShowingId: currentId);
    _currentIdleStage++;

    setState(() {
      _ad = nextAd.toDialogData();
      _isVideoLoading = false;
      _isVideoError = false;
      _videoErrorMessage = null;
      _setupCurrentMedia();
    });

    if (!widget.isPreview) {
      final id = nextAd.id;
      if (id.isNotEmpty) {
        ManualAdViewTracker().recordDisplay(id);
      }
    }

    debugPrint('ManualInterstitialAdDialog: [IDLE_ADVANCE] Advanced in-place to next manual ad: "${_ad['title']}" (Stage $_currentIdleStage).');
  }

  void _onAdServiceUpdated() {
    if (!mounted || _isDismissed) return;
    final currentId = _ad['id'] as String?;
    final activePool = InterstitialAdService().runtimePool.where((a) => a.isActive).toList();
    if (currentId != null && !activePool.any((a) => a.id == currentId)) {
      debugPrint('ManualInterstitialAdDialog: [LIVE_SYNC_REMOVAL] Current ad "$currentId" was removed/deactivated by admin.');
      if (activePool.isEmpty) {
        _dismiss();
      } else {
        _advanceToNextAd();
      }
    }
  }

  void _onVideoProgress() {
    if (_isAppLaunch) return; // App launch ad duration is controlled by the 5-second countdown
    if (!mounted || _isDismissed || _videoController == null) return;
    final val = _videoController!.value;
    if (!val.isInitialized) return;

    final isAtMaxDuration = val.position >= const Duration(seconds: 30);
    final isNaturalEnd = val.duration > Duration.zero && val.position >= val.duration;

    if (isAtMaxDuration || isNaturalEnd) {
      _videoController?.removeListener(_onVideoProgress);
      _advanceToNextAd();
    }
  }

  Future<void> _initVideo(String url) async {
    setState(() {
      _isVideoLoading = true;
      _isVideoError = false;
      _videoErrorMessage = null;
    });

    try {
      final isNetwork = url.startsWith('http://') || url.startsWith('https://');
      VideoPlayerController controller;

      if (isNetwork) {
        // Try local cache first for zero-network playback
        File? cachedFile;
        try {
          final fileInfo = await DefaultCacheManager().getFileFromCache(url);
          if (fileInfo != null && await fileInfo.file.exists()) {
            cachedFile = fileInfo.file;
            debugPrint('ManualInterstitialAdDialog: [VIDEO_CACHE] Using cached video: ${cachedFile.path}');
          }
        } catch (_) {}

        if (cachedFile != null) {
          controller = VideoPlayerController.file(cachedFile);
        } else {
          final uri = Uri.tryParse(url.trim());
          if (uri == null || !uri.hasScheme) {
            throw Exception('Invalid video URL format: $url');
          }
          controller = VideoPlayerController.networkUrl(uri);

          // Trigger non-blocking background download to local cache
          unawaited(() async {
            try {
              await DefaultCacheManager().downloadFile(url, key: url);
            } catch (_) {}
          }());
        }
      } else {
        controller = VideoPlayerController.asset(url);
      }

      _videoController = controller;
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      // Offline video requirements:
      // 1. SOUND ON by default
      // 2. Loop DISABLED (ends naturally or terminates at 30s)
      await controller.setLooping(false);
      await controller.setVolume(_isMuted ? 0.0 : 1.0);
      controller.addListener(_onVideoProgress);
      await controller.play();

      if (mounted) {
        setState(() {
          _isVideoLoading = false;
        });
        if (!_isAppLaunch) {
          _startCreativeTimer();
        }
      }
    } catch (e) {
      debugPrint('ManualInterstitialAdDialog: [VIDEO_INIT_ERROR] Failed to initialize video: $e');
      if (mounted) {
        setState(() {
          _isVideoLoading = false;
          _isVideoError = true;
          _videoErrorMessage = 'Video playback unavailable.';
        });
        // Fallback 10s timer so error screen advances naturally
        if (!_isAppLaunch) {
          _startCreativeTimer();
        }
      }
    }
  }

  void _togglePlayPause() {
    if (_videoController == null || !_videoController!.value.isInitialized) return;
    setState(() {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
      } else {
        _videoController!.play();
      }
    });
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      if (_videoController != null && _videoController!.value.isInitialized) {
        _videoController!.setVolume(_isMuted ? 0.0 : 1.0);
      }
    });
  }

  void _disposeVideoController() {
    _videoController?.removeListener(_onVideoProgress);
    _videoController?.pause();
    _videoController?.dispose();
    _videoController = null;
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _autoCloseTimer?.cancel();
    _autoCloseTimer = null;
    _creativeTimer?.cancel();
    _creativeTimer = null;
    InterstitialAdService().removeListener(_onAdServiceUpdated);
    _disposeVideoController();
    super.dispose();
  }

  bool _completedLogged = false;

  void _onXTapped() {
    if (_isDismissed) return;
    _autoCloseTimer?.cancel();
    _autoCloseTimer = null;
    if (kDebugMode) {
      debugPrint('[AppLaunchOffline] xTapped=true');
      if (!_completedLogged) {
        _completedLogged = true;
        debugPrint('[AppLaunchOffline] completed=true');
      }
    }
    _dismiss();
  }

  void _dismiss() {
    if (_isDismissed) return;
    _isDismissed = true;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _autoCloseTimer?.cancel();
    _autoCloseTimer = null;
    _creativeTimer?.cancel();
    _creativeTimer = null;
    InterstitialAdService().removeListener(_onAdServiceUpdated);
    _disposeVideoController();

    if (_isAppLaunch && kDebugMode && !_completedLogged) {
      _completedLogged = true;
      debugPrint('[AppLaunchOffline] completed=true');
    }

    // 1. Pop dialog route first so that it is cleanly removed from the Navigator stack
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    // 2. Complete dismissal callback
    widget.onDismissed();
  }

  Future<void> _launchContact(String? urlStr) async {
    if (urlStr == null || urlStr.trim().isEmpty) return;
    final uri = Uri.tryParse(urlStr.trim());
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildCreativeLayer(Color themeColor, String imageUrl) {
    if (_isVideo) {
      if (_isVideoLoading) {
        return const ColoredBox(
          color: Colors.black,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF20C8FF)),
                SizedBox(height: 12),
                Text(
                  'Loading video advertisement...',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      }

      if (_isVideoError || _videoController == null || !_videoController!.value.isInitialized) {
        return Container(
          color: const Color(0xFF0F0E1E),
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.videocam_off_rounded, color: Colors.amber, size: 36),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Video Ad Preview Unavailable',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 6),
                Text(
                  _videoErrorMessage ?? 'Check internet connection or retry later.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () {
                    final String url = (_ad['url'] as String?) ?? (_ad['imageUrl'] as String?) ?? '';
                    if (url.isNotEmpty) _initVideo(url);
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF20C8FF)),
                  label: const Text('Retry Playback', style: TextStyle(color: Color(0xFF20C8FF), fontSize: 12, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF20C8FF), width: 1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return GestureDetector(
        onTap: _togglePlayPause,
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: VideoPlayer(_videoController!),
                ),
              ),
              // Play/Pause Overlay indicator when paused
              if (!_videoController!.value.isPlaying)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white30, width: 1.5),
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // IMAGE AD: occupies full screen, preserves aspect ratio, centered, zero distortion/cropping
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: imageUrl.startsWith('http')
            ? CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                alignment: Alignment.center,
                placeholder: (context, url) => Container(
                  color: Colors.black,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF20C8FF)),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.black,
                  child: const Center(
                    child: Icon(Icons.broken_image_rounded, color: Colors.white38, size: 48),
                  ),
                ),
              )
            : Image.asset(
                imageUrl,
                fit: BoxFit.contain,
                alignment: Alignment.center,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.black,
                  child: const Center(
                    child: Icon(Icons.broken_image_rounded, color: Colors.white38, size: 48),
                  ),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dynamic rawColor = _ad['color'] ?? _ad['colorValue'];
    final themeColor = rawColor is Color
        ? rawColor
        : (rawColor is int ? Color(rawColor) : const Color(0xFF20C8FF));
    final title = _ad['title'] as String? ?? 'Sponsored';
    final subtitle = _ad['subtitle'] as String? ?? '';
    final imageUrl = (_ad['url'] as String?) ?? (_ad['imageUrl'] as String?) ?? '';
    final contactUrl = _ad['contactUrl'] as String?;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && !_isDismissed) {
          _isDismissed = true;
          widget.onDismissed();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Full-screen creative presentation
            Positioned.fill(
              child: _buildCreativeLayer(themeColor, imageUrl),
            ),

            // 2. Subtle top gradient vignette for top bar contrast
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 120,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.75),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // 3. Strategic bottom metadata overlay with smooth gradient backing
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.90),
                      Colors.black.withValues(alpha: 0.70),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.7, 1.0],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Ad Title
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3,
                            shadows: [
                              Shadow(
                                color: Colors.black87,
                                offset: Offset(0, 1),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          // Ad Subtitle / Description
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 13,
                              height: 1.3,
                              shadows: const [
                                Shadow(
                                  color: Colors.black87,
                                  offset: Offset(0, 1),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        // Action buttons row
                        Row(
                          children: [
                            if (contactUrl != null)
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _launchContact(contactUrl),
                                  icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 16),
                                  label: const Text(
                                    'Contact via WhatsApp',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00A85A),
                                    foregroundColor: Colors.white,
                                    elevation: 3,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            if (contactUrl != null) const SizedBox(width: 10),
                            TextButton(
                              onPressed: _isAppLaunch ? (_isXState ? _onXTapped : null) : _dismiss,
                              style: TextButton.styleFrom(
                                foregroundColor: (_isAppLaunch && !_isXState) ? Colors.white30 : Colors.white70,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              child: const Text('Return to App', style: TextStyle(fontSize: 13)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 4. Fixed Top-Right Close Button and Top Controls inside SafeArea
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Header elements
                      if (_isAppLaunch) ...[
                        // Left: Sponsored badge
                        Container(
                          key: const ValueKey('launch_sponsored_badge'),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Text(
                            'Sponsored',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        // Right: [mute (if video)] + [countdown/X control]
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isVideo) ...[
                              IconButton(
                                key: const ValueKey('launch_mute_button'),
                                onPressed: _toggleMute,
                                tooltip: _isMuted ? 'Unmute' : 'Mute',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black.withValues(alpha: 0.5),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: Icon(
                                    _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            GestureDetector(
                              key: _isXState
                                  ? const ValueKey('launch_x_button')
                                  : const ValueKey('launch_countdown_badge'),
                              onTap: _isXState ? _onXTapped : null,
                              child: Container(
                                key: _isXState
                                    ? const ValueKey('launch_x_badge')
                                    : const ValueKey('launch_counter_control'),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: _isXState
                                        ? Colors.white70
                                        : const Color(0xFF20C8FF).withValues(alpha: 0.6),
                                  ),
                                ),
                                child: Text(
                                  _isXState ? 'X' : '$_countdownSeconds',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        // Normal Interstitial Header: Completely unchanged
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isVideo ? Icons.videocam_rounded : Icons.campaign_outlined,
                                    size: 14,
                                    color: const Color(0xFF20C8FF),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _isVideo ? 'VIDEO AD' : 'SPONSORED',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isVideo && _videoController != null && _videoController!.value.isInitialized)
                              IconButton(
                                onPressed: _toggleMute,
                                tooltip: _isMuted ? 'Unmute' : 'Mute',
                                icon: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black.withValues(alpha: 0.5),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: Icon(
                                    _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 4),
                            IconButton(
                              key: const ValueKey('normal_interstitial_close_button'),
                              tooltip: 'Close Ad',
                              onPressed: _dismiss,
                              icon: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.5),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: const Icon(Icons.close_rounded, size: 20, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
