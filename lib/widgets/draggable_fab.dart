import 'package:flutter/material.dart';

class DraggableFab extends StatefulWidget {
  final VoidCallback onTap;
  const DraggableFab({super.key, required this.onTap});

  @override
  State<DraggableFab> createState() => _DraggableFabState();
}

class _DraggableFabState extends State<DraggableFab> {
  Offset _offset = const Offset(20, 20); // Initial position lowered to be just above the nav bar
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return Positioned(
      right: _offset.dx,
      bottom: _offset.dy,
      child: GestureDetector(
        onPanStart: (_) => setState(() => _isDragging = true),
        onPanUpdate: (details) {
          setState(() {
            _offset = Offset(
              (_offset.dx - details.delta.dx).clamp(10, size.width - 70),
              (_offset.dy - details.delta.dy).clamp(10 + bottomPadding, size.height - 100),
            );
          });
        },
        onPanEnd: (_) => setState(() => _isDragging = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isDragging ? 1.1 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFF00A85A),
              shape: BoxShape.circle,
              boxShadow: [
                const BoxShadow(
                  color: Colors.black54,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
                BoxShadow(
                  color: const Color(0xFF00A85A).withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
