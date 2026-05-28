import 'package:flutter/material.dart';
import '../services/progress_service.dart';
import '../services/usage_service.dart';

class MaterialViewerScreen extends StatefulWidget {
  final String title;

  const MaterialViewerScreen({super.key, required this.title});

  @override
  State<MaterialViewerScreen> createState() => _MaterialViewerScreenState();
}

class _MaterialViewerScreenState extends State<MaterialViewerScreen> {
  final ScrollController _scrollController = ScrollController();
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _progress = ProgressService().getProgress(widget.title);
    _scrollController.addListener(_onScroll);
    
    // Start tracking reading time
    UsageService().startMaterialTracking(widget.title);

    // Set initial scroll position after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _progress > 0) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent * _progress);
      }
    });
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final double maxScroll = _scrollController.position.maxScrollExtent;
      final double currentScroll = _scrollController.position.pixels;
      
      if (maxScroll > 0) {
        final double newProgress = (currentScroll / maxScroll).clamp(0.0, 1.0);
        if ((newProgress - _progress).abs() > 0.01) {
          _progress = newProgress;
          ProgressService().updateProgress(widget.title, _progress);
        }
      }
    }
  }

  @override
  void dispose() {
    // Stop tracking reading time
    UsageService().stopMaterialTracking();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070716),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141232),
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          children: [
            Container(
              height: 2000, // Large height to simulate a long document
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.05),
                    Colors.white.withValues(alpha: 0.01),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reading Mode Active',
                    style: TextStyle(color: Color(0xFF20C8FF), fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Scrolling tracks your progress automatically. Your highest reached point is saved.\n\n' * 50,
                    style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.6),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
