import 'dart:async';
import 'package:flutter/material.dart';

class TopNotificationService {
  static final TopNotificationService _instance = TopNotificationService._internal();
  factory TopNotificationService() => _instance;
  TopNotificationService._internal();

  static bool pendingWelcome = false;

  OverlayEntry? _overlayEntry;
  final List<String> _queue = [];
  bool _isShowing = false;
  BuildContext? _lastContext;

  void showNotification(BuildContext context, String message) {
    _lastContext = context;
    // Prevent exact duplicate consecutive messages in the queue
    if (_queue.isNotEmpty && _queue.last == message) return;
    
    _queue.add(message);
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
    final message = _queue.removeAt(0);

    try {
      // Find the overlay from the context provided
      final overlayState = Overlay.maybeOf(_lastContext!);
      if (overlayState == null) {
        _isShowing = false;
        return;
      }
      
      _overlayEntry = _createOverlayEntry(message);
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

  OverlayEntry _createOverlayEntry(String message) {
    return OverlayEntry(
      builder: (context) => _TopNotificationWidget(
        message: message,
      ),
    );
  }
}

class _TopNotificationWidget extends StatefulWidget {
  final String message;

  const _TopNotificationWidget({
    required this.message,
  });

  @override
  State<_TopNotificationWidget> createState() => _TopNotificationWidgetState();
}

class _TopNotificationWidgetState extends State<_TopNotificationWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;

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
    Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
                color: Colors.green.shade600,
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
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
