import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/ai_provider.dart';
import '../services/persistence_service.dart';

/// Persistence key for AI launcher mode: 'large' vs 'compact'
const String kAiLauncherModeKey = 'ai_launcher_mode';

/// Multi-AI Floating Launcher with draggable positioning, typing-style
/// character bounce animation, push-transition label & logo cycling,
/// state-aware single X button, and a compact 8-provider scrollable menu.
class AiFloatingLauncher extends StatefulWidget {
  final ValueChanged<AiProviderConfig> onSelectProvider;
  final VoidCallback? onDismiss;
  final double bottomInset;
  final bool initialExpanded;

  const AiFloatingLauncher({
    super.key,
    required this.onSelectProvider,
    this.onDismiss,
    this.bottomInset = 16.0,
    this.initialExpanded = false,
  });

  @override
  State<AiFloatingLauncher> createState() => _AiFloatingLauncherState();
}

class _AiFloatingLauncherState extends State<AiFloatingLauncher>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const String _keyPosX = 'ai_launcher_pos_x';
  static const String _keyPosY = 'ai_launcher_pos_y';

  static const double _buttonWidth = 186.0;
  static const double _buttonHeight = 44.0;
  static const double _menuWidth = 186.0;
  static const double _menuItemHeight = 34.0;

  late final AnimationController _animController;
  int _currentProviderIndex = 0;
  bool _isExpanded = false;

  Offset? _currentPos;
  double _accumulatedDragDistance = 0.0;
  bool _isDragThresholdExceeded = false;
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initialExpanded;
    WidgetsBinding.instance.addObserver(this);

    // 5200ms cycle: 3.0s bounce, 1.0s steady, 1.2s push-out transition
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    );

    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) {
          setState(() {
            _currentProviderIndex =
                (_currentProviderIndex + 1) % AiProviderConfig.allProviders.length;
          });
          _animController.forward(from: 0.0);
        }
      }
    });

    _animController.forward();
    _loadSavedPosition();
  }

  void _loadSavedPosition() {
    try {
      final savedX = PersistenceService().getDouble(_keyPosX);
      final savedY = PersistenceService().getDouble(_keyPosY);
      if (savedX != null &&
          savedY != null &&
          savedX.isFinite &&
          savedY.isFinite &&
          !savedX.isNaN &&
          !savedY.isNaN &&
          savedX >= 0 &&
          savedY >= 0) {
        _currentPos = Offset(savedX, savedY);
      } else {
        _currentPos = null;
      }
    } catch (_) {
      _currentPos = null;
    }
  }

  Future<void> _savePosition(Offset pos) async {
    try {
      await PersistenceService().setDouble(_keyPosX, pos.dx);
      await PersistenceService().setDouble(_keyPosY, pos.dy);
    } catch (e) {
      debugPrint('AiFloatingLauncher: Error saving position: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      if (!_animController.isAnimating) {
        _animController.forward();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (_animController.isAnimating) {
        _animController.stop();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    final now = DateTime.now();
    if (now.difference(_lastTapTime).inMilliseconds < 250) {
      return;
    }
    _lastTapTime = now;
    if (mounted) {
      setState(() {
        _isExpanded = !_isExpanded;
      });
    }
  }

  void _collapse() {
    if (_isExpanded && mounted) {
      setState(() {
        _isExpanded = false;
      });
    }
  }

  /// State-aware single X button action:
  /// - If menu is open: closes the menu only (launcher remains visible)
  /// - If menu is closed: hides the launcher and switches to compact toolbar mode
  void _handleXButtonTap() {
    if (_isExpanded) {
      _collapse();
    } else {
      widget.onDismiss?.call();
    }
  }

  Future<void> _launchExternalProvider(AiProviderConfig provider) async {
    final uri = Uri.parse(provider.url);
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not launch ${provider.displayName}.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('AiFloatingLauncher: Error launching external provider: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;

        if (availableWidth <= 0 || availableHeight <= 0) {
          return const SizedBox.shrink();
        }

        const minX = 16.0;
        final maxX = math.max(minX, availableWidth - _buttonWidth - 16.0);
        const minY = 16.0;
        final maxY = math.max(
          minY,
          availableHeight - _buttonHeight - widget.bottomInset,
        );

        // Position validation and recovery:
        if (_currentPos == null ||
            !_currentPos!.dx.isFinite ||
            !_currentPos!.dy.isFinite ||
            _currentPos!.dx < 0 ||
            _currentPos!.dy < 0 ||
            _currentPos!.dx > availableWidth ||
            _currentPos!.dy > availableHeight) {
          _currentPos = Offset(maxX, maxY);
          _savePosition(_currentPos!);
        } else {
          final clampedX = _currentPos!.dx.clamp(minX, maxX).toDouble();
          final clampedY = _currentPos!.dy.clamp(minY, maxY).toDouble();
          if (clampedX != _currentPos!.dx || clampedY != _currentPos!.dy) {
            _currentPos = Offset(clampedX, clampedY);
            _savePosition(_currentPos!);
          }
        }

        final pos = _currentPos!;
        final expandsUpward = pos.dy > (availableHeight / 2);
        // Small, compact menu height (approx 195dp, never oversized)
        final maxMenuHeight = math.min(210.0, availableHeight - 64.0);

        final menuTop = expandsUpward
            ? math.max(minY, pos.dy - maxMenuHeight - 6.0)
            : math.min(
                availableHeight - maxMenuHeight - 16.0,
                pos.dy + _buttonHeight + 6.0,
              );

        final menuLeft = pos.dx.clamp(
          minX,
          math.max(minX, availableWidth - _menuWidth - 16.0),
        ).toDouble();

        return PopScope(
          canPop: !_isExpanded,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && _isExpanded) {
              _collapse();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              // Tap-outside dismiss backdrop when expanded
              if (_isExpanded)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _collapse,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.35),
                    ),
                  ),
                ),

              // Small Floating AI Selector Menu (Direct child for reliable hit testing)
              if (_isExpanded)
                Positioned(
                  left: menuLeft,
                  top: menuTop,
                  child: _buildSmallExpandedSelector(context, maxMenuHeight),
                ),

              // Collapsed Floating Button (Draggable & Clamped)
              Positioned(
                left: pos.dx,
                top: pos.dy,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanDown: (details) {
                    _accumulatedDragDistance = 0.0;
                    _isDragThresholdExceeded = false;
                  },
                  onPanStart: (details) {
                    _accumulatedDragDistance = 0.0;
                    _isDragThresholdExceeded = false;
                  },
                  onPanUpdate: (details) {
                    _accumulatedDragDistance += details.delta.distance;
                    if (!_isDragThresholdExceeded &&
                        _accumulatedDragDistance > kTouchSlop) {
                      _isDragThresholdExceeded = true;
                    }

                    if (_isDragThresholdExceeded) {
                      setState(() {
                        final newX = (_currentPos?.dx ?? maxX) + details.delta.dx;
                        final newY = (_currentPos?.dy ?? maxY) + details.delta.dy;
                        _currentPos = Offset(
                          newX.clamp(minX, maxX).toDouble(),
                          newY.clamp(minY, maxY).toDouble(),
                        );
                      });
                    }
                  },
                  onPanEnd: (details) {
                    if (_isDragThresholdExceeded) {
                      if (_currentPos != null) {
                        _savePosition(_currentPos!);
                      }
                      _isDragThresholdExceeded = false;
                      _accumulatedDragDistance = 0.0;
                    } else {
                      // Displaced distance below kTouchSlop -> Pure tap gesture
                      _toggleExpanded();
                    }
                  },
                  onPanCancel: () {
                    _isDragThresholdExceeded = false;
                    _accumulatedDragDistance = 0.0;
                  },
                  child: _buildCollapsedButton(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCollapsedButton(BuildContext context) {
    return Container(
      key: const ValueKey('ai_floating_button'),
      width: _buttonWidth,
      height: _buttonHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF141232),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF20C8FF), width: 1.5),
        boxShadow: [
          const BoxShadow(
            color: Colors.black54,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: const Color(0xFF20C8FF).withValues(alpha: 0.35),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Synchronized Provider Logo & Animated Name
          Expanded(
            child: _buildAnimatedContent(context),
          ),

          // Divider before the single X button
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 1,
            height: 16,
            color: Colors.white24,
          ),

          // Exactly ONE state-aware X button:
          // - When menu open: closes the menu only
          // - When menu closed: hides floating launcher & switches to compact toolbar mode
          GestureDetector(
            key: const ValueKey('ai_launcher_dismiss_button'),
            behavior: HitTestBehavior.opaque,
            onTap: _handleXButtonTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Icon(
                Icons.close_rounded,
                color: _isExpanded ? const Color(0xFF20C8FF) : Colors.white70,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedContent(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final allProviders = AiProviderConfig.allProviders;
    final currentConfig = allProviders[_currentProviderIndex];
    final nextConfig = allProviders[(_currentProviderIndex + 1) % allProviders.length];

    final currentLabel = 'Ask ${currentConfig.displayName}';
    final nextLabel = 'Ask ${nextConfig.displayName}';

    if (disableAnimations) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          currentConfig.buildIcon(size: 18, color: currentConfig.brandColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              currentLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      );
    }

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final totalMs = 5200.0;
        final elapsedMs = _animController.value * totalMs;

        // Phase 1: 0 - 3000ms -> Character Bounce (typing indicator) + Gentle Logo Bounce
        // Phase 2: 3000 - 4000ms -> Steady Hold
        // Phase 3: 4000 - 5200ms -> Push Transition (outgoing slides left, next enters from right)
        if (elapsedMs < 3000.0) {
          final bounceProgress = elapsedMs / 3000.0;
          final logoDy = math.sin(bounceProgress * math.pi * 6.0) * 1.5;

          return ClipRect(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.translate(
                  offset: Offset(0, logoDy),
                  child: currentConfig.buildIcon(
                    size: 18,
                    color: currentConfig.brandColor,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(currentLabel.length, (i) {
                        final char = currentLabel[i];
                        final charDy = math.sin(
                                (bounceProgress * math.pi * 6.0) - (i * 0.45)) *
                            2.5;
                        return Transform.translate(
                          offset: Offset(0, charDy),
                          child: Text(
                            char,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ),
          );
        } else if (elapsedMs < 4000.0) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              currentConfig.buildIcon(
                size: 18,
                color: currentConfig.brandColor,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  currentLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          );
        } else {
          final pushProgress =
              ((elapsedMs - 4000.0) / 1200.0).clamp(0.0, 1.0);
          const contentWidth = 110.0;

          final outgoingOffset = -pushProgress * (contentWidth + 24.0);
          final incomingOffset = (1.0 - pushProgress) * (contentWidth + 24.0);

          return ClipRect(
            child: SizedBox(
              height: 22,
              child: Stack(
                children: [
                  // Outgoing Provider
                  Transform.translate(
                    offset: Offset(outgoingOffset, 0),
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: 0,
                      maxWidth: double.infinity,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          currentConfig.buildIcon(
                            size: 18,
                            color: currentConfig.brandColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            currentLabel,
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Incoming Next Provider
                  Transform.translate(
                    offset: Offset(incomingOffset, 0),
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: 0,
                      maxWidth: double.infinity,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          nextConfig.buildIcon(
                            size: 18,
                            color: nextConfig.brandColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            nextLabel,
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  /// Original compact floating selection panel
  Widget _buildSmallExpandedSelector(BuildContext context, double maxMenuHeight) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: _menuWidth,
        decoration: BoxDecoration(
          color: const Color(0xFF141232),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF20C8FF), width: 1.5),
          boxShadow: [
            const BoxShadow(
              color: Colors.black87,
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
            BoxShadow(
              color: const Color(0xFF20C8FF).withValues(alpha: 0.25),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Compact Header (No duplicate X button)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.white12, width: 1),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.auto_awesome, color: Color(0xFF20C8FF), size: 12),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Choose AI',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFF20C8FF),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Compact Scrollable List (all 8 providers)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxMenuHeight - 34.0),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: AiProviderConfig.allProviders.map((provider) {
                    final hasStrikethrough = provider.showStrikethrough;
                    return InkWell(
                      key: ValueKey(
                        'ai_provider_${provider.displayName.toLowerCase().replaceAll(' ', '_')}',
                      ),
                      onTap: () {
                        _collapse();
                        if (!provider.showStrikethrough) {
                          widget.onSelectProvider(provider);
                        } else {
                          _launchExternalProvider(provider);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: _menuItemHeight,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: [
                            provider.buildIcon(
                              size: 16,
                              color: provider.brandColor,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                provider.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: hasStrikethrough
                                      ? Colors.white54
                                      : Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  decoration: hasStrikethrough
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor: const Color(0xFF20C8FF),
                                  decorationThickness: 2.0,
                                ),
                              ),
                            ),
                            if (hasStrikethrough) ...[
                              const Icon(
                                Icons.open_in_new_rounded,
                                color: Color(0xFF20C8FF),
                                size: 12,
                              ),
                            ] else ...[
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.white38,
                                size: 14,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Secondary Compact Circular Toolbar AI Launcher
/// Displays in the reader toolbar immediately to the right of the search icon.
/// Features a gradual, light-bulb-like fading animation:
/// 1. Holds fully illuminated (approx 1.0s)
/// 2. Gradually dims out until completely disappearing (approx 1.3s)
/// 3. Next provider logo gradually illuminates to full brightness (approx 1.3s)
/// Tapping this circle directly restores the large floating launcher without opening any menu.
class AiCompactToolbarLauncher extends StatefulWidget {
  final VoidCallback onRestoreLargeLauncher;
  final ValueChanged<AiProviderConfig>? onSelectProvider;

  const AiCompactToolbarLauncher({
    super.key,
    required this.onRestoreLargeLauncher,
    this.onSelectProvider,
  });

  @override
  State<AiCompactToolbarLauncher> createState() =>
      _AiCompactToolbarLauncherState();
}

class _AiCompactToolbarLauncherState extends State<AiCompactToolbarLauncher>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _bulbController;
  int _currentProviderIndex = 0;
  int _nextProviderIndex = 1;

  // Timings: 1000ms hold + 1300ms fade-out + 1300ms fade-in = 3600ms total
  static const int _holdMs = 1000;
  static const int _fadeMs = 1300;
  static const int _totalCycleMs = _holdMs + _fadeMs + _fadeMs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bulbController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _totalCycleMs),
    );

    _bulbController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) {
          setState(() {
            _currentProviderIndex = _nextProviderIndex;
            _nextProviderIndex =
                (_nextProviderIndex + 1) % AiProviderConfig.allProviders.length;
          });
          _bulbController.forward(from: 0.0);
        }
      }
    });

    _bulbController.forward();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      if (!_bulbController.isAnimating) {
        _bulbController.forward();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (_bulbController.isAnimating) {
        _bulbController.stop();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bulbController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final allProviders = AiProviderConfig.allProviders;
    final currentProvider = allProviders[_currentProviderIndex];

    return GestureDetector(
      key: const ValueKey('compact_ai_toolbar_launcher'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onRestoreLargeLauncher,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF141232),
          border: Border.all(color: const Color(0xFF20C8FF), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF20C8FF).withValues(alpha: 0.35),
              blurRadius: 6,
              spreadRadius: 0.5,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: disableAnimations
            ? currentProvider.buildIcon(
                key: ValueKey('compact_icon_${currentProvider.provider.name}'),
                size: 15,
                color: currentProvider.brandColor,
              )
            : AnimatedBuilder(
                animation: _bulbController,
                builder: (context, child) {
                  final elapsed = _bulbController.value * _totalCycleMs;
                  double opacity;
                  AiProviderConfig providerToDisplay;

                  if (elapsed < _holdMs) {
                    // Stage 1: Fully visible hold
                    opacity = 1.0;
                    providerToDisplay = currentProvider;
                  } else if (elapsed < _holdMs + _fadeMs) {
                    // Stage 2: Light bulb slowly losing brightness until gone
                    final t = (elapsed - _holdMs) / _fadeMs;
                    opacity = (1.0 - Curves.easeInOut.transform(t)).clamp(0.0, 1.0);
                    providerToDisplay = currentProvider;
                  } else {
                    // Stage 3: Next bulb gradually illuminating to full brightness
                    final t = (elapsed - _holdMs - _fadeMs) / _fadeMs;
                    opacity = Curves.easeInOut.transform(t).clamp(0.0, 1.0);
                    providerToDisplay = allProviders[_nextProviderIndex];
                  }

                  return Opacity(
                    opacity: opacity,
                    child: providerToDisplay.buildIcon(
                      key: ValueKey('compact_icon_${providerToDisplay.provider.name}'),
                      size: 15,
                      color: providerToDisplay.brandColor,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
