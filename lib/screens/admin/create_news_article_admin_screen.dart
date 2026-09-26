import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/admin_service.dart';
import '../../models/explore_models.dart';

class _SubtopicFormData {
  final TextEditingController titleController = TextEditingController();
  final TextEditingController bodyController = TextEditingController();
  final TextEditingController imageDescriptionController = TextEditingController();
  bool isExpanded = false;
  File? pickedImageFile;
  String? pickedImageFileName;

  bool get isComplete {
    return titleController.text.trim().length >= 3 &&
        bodyController.text.trim().length >= 10 &&
        pickedImageFile != null &&
        imageDescriptionController.text.trim().length >= 3;
  }

  void dispose() {
    titleController.dispose();
    bodyController.dispose();
    imageDescriptionController.dispose();
  }
}

class CreateNewsArticleAdminScreen extends StatefulWidget {
  const CreateNewsArticleAdminScreen({super.key});

  @override
  State<CreateNewsArticleAdminScreen> createState() => _CreateNewsArticleAdminScreenState();
}

class _CreateNewsArticleAdminScreenState extends State<CreateNewsArticleAdminScreen> {
  final _formKey = GlobalKey<FormState>();
  final AdminService _adminService = AdminService();

  ExploreCategory? _selectedCategory;
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _linksController = TextEditingController();

  final List<_SubtopicFormData> _subtopics = [];
  bool _isPublishing = false;
  String? _publishingStatus;

  List<ExploreCategory> _categories = [];
  bool _isLoadingCategories = true;

  @override
  void initState() {
    super.initState();
    // Initialize exactly 4 subtopics to start
    for (int i = 0; i < 4; i++) {
      final sub = _SubtopicFormData();
      // First subtopic starts expanded for convenience
      if (i == 0) sub.isExpanded = true;
      _subtopics.add(sub);
    }

    _loadCategories();
  }

  @override
  void dispose() {
    _sourceController.dispose();
    _titleController.dispose();
    _linksController.dispose();
    for (final sub in _subtopics) {
      sub.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('categoryNews')
          .where('enabled', isEqualTo: true)
          .get();

      final list = snap.docs.map((doc) => ExploreCategory.fromMap(doc.id, doc.data())).toList();
      list.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

      if (mounted) {
        setState(() {
          _categories = list;
          _isLoadingCategories = false;
          if (list.isNotEmpty) {
            _selectedCategory = list.first;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingCategories = false);
      }
    }
  }

  int get _completedSubtopicsCount => _subtopics.where((s) => s.isComplete).length;

  bool get _hasAtLeastFourCompletedSubtopics => _completedSubtopicsCount >= 4;

  bool get _isValidUrl {
    final text = _linksController.text.trim();
    if (text.isEmpty) return false;
    final uri = Uri.tryParse(text);
    return uri != null && (uri.isScheme('http') || uri.isScheme('https')) && uri.host.isNotEmpty;
  }

  bool get _isFormValid {
    return _selectedCategory != null &&
        _sourceController.text.trim().isNotEmpty &&
        _titleController.text.trim().length >= 5 &&
        _hasAtLeastFourCompletedSubtopics &&
        _isValidUrl;
  }

  void _addNewSubtopic() {
    setState(() {
      final newSub = _SubtopicFormData();
      newSub.isExpanded = true;
      _subtopics.add(newSub);
    });
  }

  Future<void> _pickImageForSubtopic(_SubtopicFormData subtopic) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141226),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              const Text('Select Subtopic Photo', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF20C8FF).withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.photo_library_outlined, color: Color(0xFF20C8FF), size: 22),
                ),
                title: const Text('Gallery Image', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('JPG, PNG, WebP photograph', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final picker = ImagePicker();
                  final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
                  if (xfile != null) {
                    setState(() {
                      subtopic.pickedImageFile = File(xfile.path);
                      subtopic.pickedImageFileName = xfile.name;
                    });
                  }
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.folder_open_rounded, color: Colors.amber, size: 22),
                ),
                title: const Text('Device Files', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Browse image file', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final res = await FilePicker.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
                  );
                  if (res != null && res.files.single.path != null) {
                    setState(() {
                      subtopic.pickedImageFile = File(res.files.single.path!);
                      subtopic.pickedImageFileName = res.files.single.name;
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitArticle() async {
    if (!_isFormValid || _isPublishing) return;

    setState(() {
      _isPublishing = true;
      _publishingStatus = 'Preparing media and stitching article...';
    });

    try {
      // 1. Prepare subtopics with base64 image data
      final List<Map<String, dynamic>> subtopicPayloads = [];

      for (int i = 0; i < _subtopics.length; i++) {
        final sub = _subtopics[i];
        if (!sub.isComplete) continue; // Only include valid subtopics

        setState(() {
          _publishingStatus = 'Encoding photo ${i + 1} of ${_subtopics.length}...';
        });

        final bytes = await sub.pickedImageFile!.readAsBytes();
        final base64String = base64Encode(bytes);

        subtopicPayloads.add({
          'title': sub.titleController.text.trim(),
          'body': sub.bodyController.text.trim(),
          'imageBase64': base64String,
          'imageFileName': sub.pickedImageFileName ?? 'image_${i + 1}.jpg',
          'imageDescription': sub.imageDescriptionController.text.trim(),
        });
      }

      setState(() {
        _publishingStatus = 'Uploading to ImageKit & publishing article...';
      });

      final result = await _adminService.createAdminArticle(
        categoryId: _selectedCategory!.id,
        categoryName: _selectedCategory!.name,
        source: _sourceController.text.trim(),
        title: _titleController.text.trim(),
        sourceUrl: _linksController.text.trim(),
        subtopics: subtopicPayloads,
      );

      if (mounted) {
        setState(() {
          _isPublishing = false;
          _publishingStatus = null;
        });

        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Color(0xFF00E676), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Article "${_titleController.text.trim()}" published successfully!'),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1E1B4B),
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.pop(context); // Return to Explore
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPublishing = false;
          _publishingStatus = null;
        });

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1830),
            title: const Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 22),
                SizedBox(width: 10),
                Text('Publication Failed', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              'Failed to create article:\n\n$e',
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: Color(0xFF20C8FF))),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090814),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0C1D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create News Article',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
            Text(
              'Professional Explore Journalism Pipeline',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            onChanged: () => setState(() {}),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // 1. CATEGORY DROPDOWN
                const Text('1. CATEGORY *', style: TextStyle(color: Color(0xFF20C8FF), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                const SizedBox(height: 6),
                _isLoadingCategories
                    ? const LinearProgressIndicator(color: Color(0xFF20C8FF), backgroundColor: Colors.white10)
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<ExploreCategory>(
                            value: _selectedCategory,
                            dropdownColor: const Color(0xFF141226),
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF20C8FF)),
                            items: _categories.map((cat) {
                              return DropdownMenuItem<ExploreCategory>(
                                value: cat,
                                child: Text(cat.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                              );
                            }).toList(),
                            onChanged: (cat) => setState(() => _selectedCategory = cat),
                          ),
                        ),
                      ),

                const SizedBox(height: 18),

                // 2. SOURCE FIELD
                const Text('2. SOURCE / PUBLISHER *', style: TextStyle(color: Color(0xFF20C8FF), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _sourceController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. Daily Nation, Reuters, Mirror Tech',
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.04),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF20C8FF))),
                  ),
                ),

                const SizedBox(height: 18),

                // 3. TITLE FIELD
                const Text('3. ARTICLE TITLE *', style: TextStyle(color: Color(0xFF20C8FF), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _titleController,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Enter engaging, factual headline...',
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.04),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF20C8FF))),
                  ),
                ),

                const SizedBox(height: 22),

                // 4. SUBTOPICS HEADER & COMPLETION COUNTER
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    const Text(
                      '4. SUBTOPICS (MINIMUM 4 REQUIRED) *',
                      style: TextStyle(
                        color: Color(0xFF20C8FF),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _hasAtLeastFourCompletedSubtopics
                            ? const Color(0xFF00E676).withValues(alpha: 0.2)
                            : Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_completedSubtopicsCount / 4 Completed',
                        style: TextStyle(
                          color: _hasAtLeastFourCompletedSubtopics
                              ? const Color(0xFF00E676)
                              : Colors.amber,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // SUBTOPICS LIST
                ...List.generate(_subtopics.length, (index) {
                  final sub = _subtopics[index];
                  final isComplete = sub.isComplete;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isComplete
                            ? const Color(0xFF00E676).withValues(alpha: 0.4)
                            : (sub.isExpanded ? const Color(0xFF20C8FF).withValues(alpha: 0.4) : Colors.white12),
                        width: 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Compact Header Row: Title & Checkbox
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: isComplete ? const Color(0xFF00E676).withValues(alpha: 0.2) : Colors.white10,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  String.fromCharCode(65 + index), // A, B, C, D...
                                  style: TextStyle(
                                    color: isComplete ? const Color(0xFF00E676) : Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: sub.titleController,
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                                  decoration: InputDecoration(
                                    hintText: 'Subtopic ${String.fromCharCode(65 + index)} Title...',
                                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                              // Checkbox to expand/collapse body & media
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    sub.isExpanded ? 'Editing' : 'Expand',
                                    style: TextStyle(
                                      color: sub.isExpanded ? const Color(0xFF20C8FF) : Colors.white38,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Checkbox(
                                    value: sub.isExpanded,
                                    activeColor: const Color(0xFF20C8FF),
                                    checkColor: Colors.black,
                                    onChanged: (val) {
                                      setState(() {
                                        sub.isExpanded = val ?? false;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Expanded Body & Media Section
                        if (sub.isExpanded) ...[
                          const Divider(color: Colors.white10, height: 1),
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // A. SUBTOPIC BODY
                                const Text('A. SUBTOPIC BODY *', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: sub.bodyController,
                                  maxLines: 5,
                                  style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                                  decoration: InputDecoration(
                                    hintText: 'Write or paste the journalistic content for this subtopic...',
                                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                                    filled: true,
                                    fillColor: Colors.white.withValues(alpha: 0.03),
                                    contentPadding: const EdgeInsets.all(12),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white12)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white12)),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF20C8FF))),
                                  ),
                                ),

                                const SizedBox(height: 14),

                                // B. SUBTOPIC IMAGE PICKER
                                const Text('B. SUBTOPIC PHOTO *', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                if (sub.pickedImageFile != null)
                                  Container(
                                    height: 120,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFF20C8FF).withValues(alpha: 0.3)),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.file(sub.pickedImageFile!, fit: BoxFit.cover),
                                        Positioned(
                                          top: 6,
                                          right: 6,
                                          child: GestureDetector(
                                            onTap: () => setState(() {
                                              sub.pickedImageFile = null;
                                              sub.pickedImageFileName = null;
                                            }),
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                              child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  OutlinedButton.icon(
                                    onPressed: () => _pickImageForSubtopic(sub),
                                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                                    label: const Text('Select Photo from Device', style: TextStyle(fontSize: 12)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF20C8FF),
                                      side: const BorderSide(color: Color(0xFF20C8FF)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    ),
                                  ),

                                const SizedBox(height: 14),

                                // C. IMAGE DESCRIPTION
                                const Text('C. IMAGE DESCRIPTION / CAPTION *', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: sub.imageDescriptionController,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: 'Enter caption / description for this photo...',
                                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                                    filled: true,
                                    fillColor: Colors.white.withValues(alpha: 0.03),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white12)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white12)),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF20C8FF))),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),

                // "+ Add another subtopic" button (shown when at least 4 completed subtopics exist)
                if (_hasAtLeastFourCompletedSubtopics) ...[
                  Center(
                    child: TextButton.icon(
                      onPressed: _addNewSubtopic,
                      icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF20C8FF), size: 18),
                      label: const Text('+ Add another subtopic', style: TextStyle(color: Color(0xFF20C8FF), fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // "PASTE LINKS THEN UPLOAD" (shown when at least 4 completed subtopics exist)
                if (_hasAtLeastFourCompletedSubtopics) ...[
                  const Divider(color: Colors.white12, height: 28),
                  const Text('PASTE LINKS THEN UPLOAD *', style: TextStyle(color: Color(0xFF20C8FF), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _linksController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      hintText: 'https://example.com/original-article-report',
                      hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.04),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF20C8FF))),
                      prefixIcon: const Icon(Icons.link_rounded, color: Color(0xFF20C8FF), size: 18),
                      suffixIcon: _isValidUrl
                          ? const Icon(Icons.check_circle_rounded, color: Color(0xFF00E676), size: 18)
                          : null,
                    ),
                  ),
                  if (_linksController.text.trim().isNotEmpty && !_isValidUrl) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Please provide a valid URL starting with http:// or https://',
                      style: TextStyle(color: Colors.redAccent, fontSize: 11),
                    ),
                  ],
                ],

                const SizedBox(height: 24),

                // Final Publish Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isFormValid && !_isPublishing ? _submitArticle : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF20C8FF),
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: Colors.white12,
                      disabledForegroundColor: Colors.white30,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Publish News Article', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),

          // Loading / Publishing Overlay
          if (_isPublishing)
            Container(
              color: Colors.black87,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141226),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF20C8FF).withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Color(0xFF20C8FF)),
                      const SizedBox(height: 18),
                      const Text(
                        'Publishing Article',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _publishingStatus ?? 'Processing...',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
