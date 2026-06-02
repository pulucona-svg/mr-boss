import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import '../services/progress_service.dart';
import '../services/usage_service.dart';
import '../services/file_service.dart';

class MaterialViewerScreen extends StatefulWidget {
  final String title;
  final String fileUrl;

  const MaterialViewerScreen({super.key, required this.title, required this.fileUrl});

  @override
  State<MaterialViewerScreen> createState() => _MaterialViewerScreenState();
}

class _MaterialViewerScreenState extends State<MaterialViewerScreen> {
  final FileService _fileService = FileService();
  bool _isLoading = true;
  String? _localPath;
  bool _isPdf = false;
  bool _isImage = false;
  double _progress = 0.0;
  final PdfViewerController _pdfController = PdfViewerController();

  @override
  void initState() {
    super.initState();
    _progress = ProgressService().getProgress(widget.title);
    _isPdf = _fileService.isPdf(widget.fileUrl);
    _isImage = _fileService.isImage(widget.fileUrl);
    
    // Start tracking reading time
    UsageService().startMaterialTracking(widget.title);

    _prepareFile();
  }

  Future<void> _prepareFile() async {
    debugPrint('MaterialViewerScreen: [DEBUG] Opening resource: ${widget.title}');
    debugPrint('MaterialViewerScreen: [DEBUG] fileUrl: ${widget.fileUrl}');

    if (widget.fileUrl.isEmpty) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Resource URL is empty.')),
        );
      }
      return;
    }

    // If it's not a PDF or Image, try to download and open with system app
    if (!_isPdf && !_isImage) {
      final fileName = '${widget.title.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}';
      final path = await _fileService.downloadFile(widget.fileUrl, fileName);
      if (path != null) {
        await _fileService.openFile(path);
        if (mounted) Navigator.pop(context);
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: Could not download file.')),
          );
        }
      }
      return;
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _onPdfChanged(PdfPageChangedDetails details) {
    final totalPages = _pdfController.pageCount;
    if (totalPages > 0) {
      final newProgress = (details.newPageNumber / totalPages).clamp(0.0, 1.0);
      if ((newProgress - _progress).abs() > 0.05) {
        _progress = newProgress;
        ProgressService().updateProgress(widget.title, _progress);
      }
    }
  }

  @override
  void dispose() {
    UsageService().stopMaterialTracking();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070716),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141232),
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        actions: [
          if (_isPdf)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(
                  '${(_progress * 100).toInt()}%',
                  style: const TextStyle(color: Color(0xFF20C8FF), fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF20C8FF)))
        : _buildViewer(),
    );
  }

  Widget _buildViewer() {
    if (_isPdf) {
      return SfPdfViewer.network(
        widget.fileUrl,
        controller: _pdfController,
        onPageChanged: _onPdfChanged,
        onDocumentLoaded: (details) {
          if (_progress > 0) {
            final targetPage = (_progress * _pdfController.pageCount).round().clamp(1, _pdfController.pageCount);
            _pdfController.jumpToPage(targetPage);
          }
        },
      );
    } else if (_isImage) {
      return Center(
        child: InteractiveViewer(
          child: CachedNetworkImage(
            imageUrl: widget.fileUrl,
            placeholder: (context, url) => const CircularProgressIndicator(),
            errorWidget: (context, url, error) => const Icon(Icons.broken_image, size: 100, color: Colors.white24),
          ),
        ),
      );
    } else {
      return const Center(
        child: Text(
          'File format not supported for in-app viewing.\nOpening in system app...',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
  }
}
