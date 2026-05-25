import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dotted_border/dotted_border.dart';
import '../providers/upload_provider.dart';
import '../providers/user_provider.dart';
import '../services/resource_service.dart';

class UploadBottomSheet extends ConsumerStatefulWidget {
  const UploadBottomSheet({super.key});

  @override
  ConsumerState<UploadBottomSheet> createState() => _UploadBottomSheetState();
}

class _UploadBottomSheetState extends ConsumerState<UploadBottomSheet> {
  final _unitNameController = TextEditingController();
  final _unitCodeController = TextEditingController();
  final _programController = TextEditingController();
  final _programCodeController = TextEditingController();
  final _lecturerController = TextEditingController();
  final _yearOfPubController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Ensure the provider is reset every time the bottom sheet is opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(uploadProvider);
    });
  }

  @override
  void dispose() {
    _unitNameController.dispose();
    _unitCodeController.dispose();
    _programController.dispose();
    _programCodeController.dispose();
    _lecturerController.dispose();
    _yearOfPubController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uploadState = ref.watch(uploadProvider);
    final notifier = ref.read(uploadProvider.notifier);

    // Synchronize controllers with state (for auto-fill and reset)
    if (_unitNameController.text != uploadState.material.unitName) {
      _unitNameController.text = uploadState.material.unitName;
    }
    if (_unitCodeController.text != uploadState.material.unitCode) {
      _unitCodeController.text = uploadState.material.unitCode;
    }
    
    // Synchronize programs and codes
    if (uploadState.material.programs.isNotEmpty && _programController.text != uploadState.material.programs.first) {
      _programController.text = uploadState.material.programs.first;
    } else if (uploadState.material.programs.isEmpty && _programController.text.isNotEmpty) {
      _programController.clear();
    }
    
    if (uploadState.material.programCodes.isNotEmpty && _programCodeController.text != uploadState.material.programCodes.first) {
      _programCodeController.text = uploadState.material.programCodes.first;
    } else if (uploadState.material.programCodes.isEmpty && _programCodeController.text.isNotEmpty) {
      _programCodeController.clear();
    }

    if (uploadState.material.lecturers.isEmpty && _lecturerController.text.isNotEmpty) {
      _lecturerController.clear();
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF070716),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              // Handle bar
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Upload Menu',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildModeToggle(uploadState, notifier),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (uploadState.uploadMode == 'material') ...[
                        _sectionTitle('Course Details'),
                        const SizedBox(height: 16),
                        
                        // Unit Name
                        _buildTextField(
                          label: 'Unit Name',
                          hint: 'e.g. Digital Electronics',
                          controller: _unitNameController,
                          textCapitalization: TextCapitalization.sentences,
                          icon: Icons.book_outlined,
                          onChanged: notifier.updateUnitName,
                          suggestions: ref.watch(unitNameSuggestionsProvider(_unitNameController.text)),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Unit Code
                        _buildTextField(
                          label: 'Unit Code',
                          hint: 'e.g. COMP 212',
                          controller: _unitCodeController,
                          textCapitalization: TextCapitalization.sentences,
                          icon: Icons.qr_code_outlined,
                          onChanged: notifier.updateUnitCode,
                          suggestions: ref.watch(unitCodeSuggestionsProvider(_unitCodeController.text)),
                        ),

                        const SizedBox(height: 24),
                        _sectionTitle('Target Audience'),
                        const SizedBox(height: 16),
                        
                        // Target Program Multi-select
                        _buildMultiSelectField(
                          label: 'Target Program(s)',
                          hint: 'Search or type program...',
                          controller: _programController,
                          icon: Icons.school_outlined,
                          suggestions: ref.watch(programSuggestionsProvider(_programController.text)),
                          selectedItems: uploadState.material.programs,
                          onToggle: notifier.toggleProgram,
                          chipColor: const Color(0xFF20C8FF),
                        ),

                        const SizedBox(height: 16),

                        // Lecturers Multi-select
                        _buildMultiSelectField(
                          label: 'Lecturer(s)',
                          hint: 'Search or type lecturer name...',
                          controller: _lecturerController,
                          icon: Icons.person_search_outlined,
                          suggestions: ref.watch(lecturerSuggestionsProvider(_lecturerController.text)),
                          selectedItems: uploadState.material.lecturers,
                          onToggle: notifier.toggleLecturer,
                          chipColor: const Color(0xFF00A85A),
                        ),

                        const SizedBox(height: 16),
                      ] else ...[
                        // Timetable Fields
                        _sectionTitle('Schedule Details'),
                        const SizedBox(height: 16),
                        
                        Row(
                          children: [
                            Expanded(
                              child: _buildDropdown(
                                label: 'Year of Study',
                                value: uploadState.material.yearOfStudy,
                                items: ['1st Year', '2nd Year', '3rd Year', '4th Year'],
                                onChanged: (val) => notifier.updateYearOfStudy(val!),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildDropdown(
                                label: 'Semester',
                                value: uploadState.material.semester,
                                items: ['Semester 1', 'Semester 2'],
                                onChanged: (val) => notifier.updateSemester(val!),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),
                        _sectionTitle('Target Audience'),
                        const SizedBox(height: 16),

                        // Program Single-select
                        _buildTextField(
                          label: 'Target Program',
                          hint: 'Search or type program...',
                          controller: _programController,
                          icon: Icons.school_outlined,
                          suggestions: ref.read(courseServiceProvider).programsList,
                          onChanged: notifier.updateProgram,
                        ),

                        const SizedBox(height: 16),

                        // Program Code Auto-filled
                        _buildTextField(
                          label: 'Program Code',
                          hint: 'e.g. COMP, ENSC, BIT...',
                          controller: _programCodeController,
                          icon: Icons.code_rounded,
                          suggestions: ref.read(courseServiceProvider).programCodes,
                          onChanged: notifier.updateProgramCode,
                        ),

                        const SizedBox(height: 16),
                      ],
                      
                      if (uploadState.uploadMode == 'material') ...[
                        Row(
                          children: [
                            Expanded(
                              child: _buildDropdown(
                                label: 'Year of Study',
                                value: uploadState.material.yearOfStudy,
                                items: ['1st Year', '2nd Year', '3rd Year', '4th Year'],
                                onChanged: (val) => notifier.updateYearOfStudy(val!),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildDropdown(
                                label: 'Semester',
                                value: uploadState.material.semester,
                                items: ['Semester 1', 'Semester 2'],
                                onChanged: (val) => notifier.updateSemester(val!),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),
                      ],

                      _sectionTitle('Material Info'),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: _buildDropdown(
                              label: 'Pub. Year',
                              value: uploadState.material.yearOfPublication.toString(),
                              items: () {
                                final currentYear = DateTime.now().year;
                                final List<String> years = [];
                                for (int year = currentYear; year >= 2020; year--) {
                                  years.add(year.toString());
                                }
                                return years;
                              }(),
                              onChanged: (val) => notifier.updateYearOfPublication(int.parse(val!)),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildDropdown(
                              label: 'Type',
                              value: uploadState.material.materialType,
                              items: uploadState.uploadMode == 'timetable'
                                  ? ['Class Timetable', 'EXAM Timetable']
                                  : ['Notes', 'CATs', 'Exams', 'Prac Manual', 'Supplementary Exams'],
                              onChanged: (val) => notifier.updateMaterialType(val!),
                            ),
                          ),
                        ],
                      ),

                      if (uploadState.material.materialType == 'CATs') ...[
                        const SizedBox(height: 16),
                        _buildDropdown(
                          label: 'CAT Selection',
                          value: uploadState.material.catType ?? 'CAT 1',
                          items: ['CAT 1', 'CAT 2'],
                          onChanged: (val) => notifier.updateCatType(val!),
                        ),
                      ],

                      const SizedBox(height: 24),
                      _sectionTitle('Files'),
                      const SizedBox(height: 16),
                      
                      if (uploadState.uploadMode == 'timetable')
                        _buildFilePicker(
                          label: 'Timetable Image',
                          file: uploadState.material.file,
                          isImage: true,
                          icon: Icons.calendar_month_outlined,
                          onTap: notifier.pickTimetableImage,
                        )
                      else
                        _buildFilePicker(
                          label: 'Material File',
                          file: uploadState.material.file,
                          icon: Icons.picture_as_pdf_outlined,
                          onTap: notifier.pickDocument,
                        ),

                      const SizedBox(height: 32),
                      
                      // Auto-filled info
                      _buildInfoRow('Uploaded By', ref.watch(userProfileProvider).username),
                      const SizedBox(height: 8),
                      _buildInfoRow('Upload Year', uploadState.material.yearOfUpload.toString()),
                      
                      const SizedBox(height: 40),
                      
                      // Upload Button
                      _buildUploadButton(uploadState, notifier),
                      
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
          
          // Progress Overlay
          if (uploadState.isUploading)
            _buildLoadingOverlay(uploadState.uploadProgress),
        ],
      ),
    );
  }

  Widget _buildModeToggle(UploadState state, UploadNotifier notifier) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => notifier.updateUploadMode('material'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: state.uploadMode == 'material' ? const Color(0xFF00A85A) : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Text(
                    'materials',
                    style: TextStyle(
                      color: state.uploadMode == 'material' ? Colors.white : Colors.white60,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => notifier.updateUploadMode('timetable'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: state.uploadMode == 'timetable' ? const Color(0xFF00A85A) : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Text(
                    'Time tables',
                    style: TextStyle(
                      color: state.uploadMode == 'timetable' ? Colors.white : Colors.white60,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogOverlay({
    required String title,
    required String message,
    required VoidCallback onConfirm,
    VoidCallback? onCancel,
    required String confirmLabel,
    String? cancelLabel,
  }) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (onCancel != null) ...[
                    TextButton(
                      onPressed: onCancel,
                      child: Text(cancelLabel ?? 'CANCEL', style: const TextStyle(color: Colors.white38)),
                    ),
                    const SizedBox(width: 16),
                  ],
                  ElevatedButton(
                    onPressed: onConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF20C8FF),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF20C8FF),
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    TextEditingController? controller,
    IconData? icon,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    required Function(String) onChanged,
    List<String>? suggestions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Autocomplete<String>(
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (suggestions == null || textEditingValue.text.isEmpty) {
              return const Iterable<String>.empty();
            }
            return suggestions;
          },
          onSelected: onChanged,
          fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
            // Link external controller if provided
            if (controller != null && textController.text != controller.text) {
              textController.text = controller.text;
            }
            return TextField(
              controller: textController,
              focusNode: focusNode,
              keyboardType: keyboardType,
              textCapitalization: textCapitalization,
              inputFormatters: inputFormatters,
              style: const TextStyle(color: Colors.white),
              onChanged: (val) {
                onChanged(val);
                if (controller != null) controller.text = val;
              },
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
                prefixIcon: icon != null ? Icon(icon, color: const Color(0xFF20C8FF), size: 20) : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: const Color(0xFF1A1A2E),
                elevation: 4,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: MediaQuery.of(context).size.width - 48,
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      return ListTile(
                        title: Text(option, style: const TextStyle(color: Colors.white)),
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF1A1A2E),
              style: const TextStyle(color: Colors.white),
              items: items.map((item) {
                return DropdownMenuItem(
                  value: item,
                  child: Text(item),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMultiSelectField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    required List<String> suggestions,
    required List<String> selectedItems,
    required Function(String) onToggle,
    required Color chipColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Autocomplete<String>(
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) {
              return suggestions;
            }
            return suggestions.where((option) {
              return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
            });
          },
          onSelected: (String selection) {
            onToggle(selection);
            // We don't clear or unfocus here to keep the menu potentially visible
          },
          fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
            return TextField(
              controller: textController,
              focusNode: focusNode,
              style: const TextStyle(color: Colors.white),
              onChanged: (val) => setState(() {}),
              onSubmitted: (val) {
                // Just clear and unfocus; don't add what's typed to the selection
                textController.clear();
                focusNode.unfocus(); 
              },
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
                prefixIcon: Icon(icon, color: const Color(0xFF20C8FF), size: 20),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: const Color(0xFF1A1A2E),
                elevation: 4,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: MediaQuery.of(context).size.width - 48,
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      final isSelected = selectedItems.contains(option);
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          isSelected ? Icons.check_circle : Icons.add_circle_outline,
                          color: isSelected ? const Color(0xFF20C8FF) : Colors.white24,
                          size: 18,
                        ),
                        title: Text(
                          option,
                          style: TextStyle(
                            color: isSelected ? const Color(0xFF20C8FF) : Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        onTap: () {
                          onToggle(option);
                          // Do NOT call onSelected(option) because it closes the menu
                          setState(() {}); 
                        },
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
        if (selectedItems.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: selectedItems.map((item) {
              return Chip(
                label: Text(item, style: const TextStyle(color: Colors.white, fontSize: 12)),
                backgroundColor: chipColor.withValues(alpha: 0.2),
                side: BorderSide(color: chipColor, width: 0.5),
                deleteIcon: const Icon(Icons.close, size: 14, color: Colors.white),
                onDeleted: () => onToggle(item),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildFilePicker({
    required String label,
    File? file,
    bool isImage = false,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: DottedBorder(
            options: RoundedRectDottedBorderOptions(
              color: const Color(0xFF20C8FF).withValues(alpha: 0.3),
              strokeWidth: 1,
              dashPattern: const [6, 3],
              radius: const Radius.circular(16),
            ),
            child: Container(
              height: 100,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(16),
              ),
              child: file != null
                  ? Stack(
                      children: [
                        if (isImage)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(file, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                          )
                        else
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.file_present_rounded, color: Color(0xFF00A85A), size: 32),
                                const SizedBox(height: 4),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Text(
                                    file.path.split(RegExp(r'[/\\]')).last,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.edit, color: Colors.white, size: 12),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: Colors.white24, size: 32),
                      const SizedBox(height: 8),
                      const Text('Tap to select', style: TextStyle(color: Colors.white38, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        isImage ? '(Images only)' : '(PDF, Image, HTML)',
                        style: const TextStyle(color: Colors.white10, fontSize: 10),
                      ),
                    ],
                  ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 13)),
        Text(value, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildUploadButton(UploadState state, UploadNotifier notifier) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: state.isValid ? () async {
          await notifier.upload();
          if (mounted && ref.read(uploadProvider).isSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Material uploaded successfully! 🎉')),
            );
            Navigator.pop(context);
          }
        } : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: state.isValid ? const Color(0xFF00A85A) : Colors.white10,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.05),
        ),
        child: const Text(
          'Upload Material',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay(double progress) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF00A85A)),
            const SizedBox(height: 24),
            Text(
              'Uploading... ${(progress * 100).toInt()}%',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              width: 200,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 200 * progress,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00A85A),
                    borderRadius: BorderRadius.circular(2),
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
