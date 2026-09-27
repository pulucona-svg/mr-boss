import 'dart:async';
import 'package:flutter/material.dart';

enum TopNotificationType {
  success,
  error,
  warning,
  info,
}

class _NotificationItem {
  final String message;
  final TopNotificationType type;
  final Color? backgroundColor;
  final IconData? icon;

  const _NotificationItem({
    required this.message,
    required this.type,
    this.backgroundColor,
    this.icon,
  });
}

class TopNotificationService {
  static final TopNotificationService _instance = TopNotificationService._internal();
  factory TopNotificationService() => _instance;
  TopNotificationService._internal();

  static bool pendingWelcome = false;

  OverlayEntry? _overlayEntry;
  final List<_NotificationItem> _queue = [];
  bool _isShowing = false;
  BuildContext? _lastContext;

  static TopNotificationType inferType(String message) {
    final lower = message.toLowerCase();

    // 1. Error / Failure detection
    if (lower.contains('fail') ||
        lower.contains('error') ||
        lower.contains('invalid') ||
        lower.contains('cancel') ||
        lower.contains('decline') ||
        lower.contains('reject') ||
        lower.contains('denied') ||
        lower.contains('reversed') ||
        lower.contains('expired') ||
        lower.contains('offline') ||
        lower.contains('not completed') ||
        lower.contains('not support') ||
        lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('cannot') ||
        lower.contains('unable') ||
        lower.contains('please enter')) {
      return TopNotificationType.error;
    }

    // 2. Warning detection
    if (lower.contains('warning') ||
        lower.contains('caution') ||
        lower.contains('attention') ||
        lower.contains('restricted') ||
        lower.contains('alert')) {
      return TopNotificationType.warning;
    }

    // 3. Info detection
    if (lower.contains('coming soon') ||
        lower.contains('where should we start')) {
      return TopNotificationType.info;
    }

    // 4. Default to success
    return TopNotificationType.success;
  }

  void showNotification(
    BuildContext context,
    String message, {
    TopNotificationType? type,
    Color? backgroundColor,
    IconData? icon,
  }) {
    _lastContext = context;
    // Prevent exact duplicate consecutive messages in the queue
    if (_queue.isNotEmpty && _queue.last.message == message) return;

    final resolvedType = type ?? inferType(message);

    _queue.add(_NotificationItem(
      message: message,
      type: resolvedType,
      backgroundColor: backgroundColor,
      icon: icon,
    ));

    if (!_isShowing) {
      _processQueue();
    }
  }

  void _processQueue() async {
    if (_queue.isEmpty || _lastContext == null) {
      _isShowing = false;
      return;
    }

    _isShowing = true;
    final item = _queue.removeAt(0);

    try {
      // Find the overlay from the context provided
      final overlayState = Overlay.maybeOf(_lastContext!);
      if (overlayState == null) {
        _isShowing = false;
        return;
      }

      _overlayEntry = _createOverlayEntry(item);
      overlayState.insert(_overlayEntry!);

      // Wait for the notification duration (matches animation timing)
      await Future.delayed(const Duration(seconds: 3));

      if (_overlayEntry != null) {
        _overlayEntry!.remove();
        _overlayEntry = null;
      }
    } catch (e) {
      debugPrint('TopNotificationService error: $e');
      _isShowing = false;
    }

    // Small gap before the next message
    await Future.delayed(const Duration(milliseconds: 500));
    _processQueue();
  }

  OverlayEntry _createOverlayEntry(_NotificationItem item) {
    return OverlayEntry(
      builder: (context) => _TopNotificationWidget(
        message: item.message,
        type: item.type,
        backgroundColor: item.backgroundColor,
        icon: item.icon,
      ),
    );
  }
}

class _TopNotificationWidget extends StatefulWidget {
  final String message;
  final TopNotificationType type;
  final Color? backgroundColor;
  final IconData? icon;

  const _TopNotificationWidget({
    required this.message,
    this.type = TopNotificationType.success,
    this.backgroundColor,
    this.icon,
  });

  @override
  State<_TopNotificationWidget> createState() => _TopNotificationWidgetState();
}

class _TopNotificationWidgetState extends State<_TopNotificationWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  Timer? _exitTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _controller.forward();

    // Start exit animation after 2.5 seconds (leaving 0.5s for the animation itself)
    _exitTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _exitTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Color get _resolvedBackgroundColor {
    if (widget.backgroundColor != null) return widget.backgroundColor!;
    switch (widget.type) {
      case TopNotificationType.success:
        return Colors.green.shade600;
      case TopNotificationType.error:
        return Colors.red.shade600;
      case TopNotificationType.warning:
        return Colors.orange.shade800;
      case TopNotificationType.info:
        return const Color(0xFF7B5CFF);
    }
  }

  IconData get _resolvedIcon {
    if (widget.icon != null) return widget.icon!;
    switch (widget.type) {
      case TopNotificationType.success:
        return Icons.check_circle_outline;
      case TopNotificationType.error:
        return Icons.error_outline_rounded;
      case TopNotificationType.warning:
        return Icons.warning_amber_rounded;
      case TopNotificationType.info:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 10,
      left: 20,
      right: 20,
      child: Material(
        color: Colors.transparent,
        child: SlideTransition(
          position: _offsetAnimation,
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _controller, curve: Curves.easeIn),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _resolvedBackgroundColor,
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(_resolvedIcon, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
