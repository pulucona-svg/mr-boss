import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/curriculum_model.dart';
import '../../providers/service_providers.dart';

class CurriculumAdminScreen extends ConsumerStatefulWidget {
  const CurriculumAdminScreen({super.key});

  @override
  ConsumerState<CurriculumAdminScreen> createState() => _CurriculumAdminScreenState();
}

class _CurriculumAdminScreenState extends ConsumerState<CurriculumAdminScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all', 'active', 'inactive'
  String _yearFilter = 'all'; // 'all', '1', '2', '3', '4'
  String _semesterFilter = 'all'; // 'all', '1', '2'
  bool _isTableView = false;
  final Set<String> _busyRecordIds = {};
  bool _isMigrating = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(curriculumServiceProvider).startRealtimeSync();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CurriculumRecord> _filterRecords(List<CurriculumRecord> records) {
    return records.where((r) {
      if (_statusFilter == 'active' && !r.isActive) return false;
      if (_statusFilter == 'inactive' && r.isActive) return false;

      if (_yearFilter != 'all' && r.yearOfStudy.trim() != _yearFilter) return false;
      if (_semesterFilter != 'all' && r.semester.trim() != _semesterFilter) return false;

      if (_searchQuery.isNotEmpty) {
        final matchesQuery = r.unitCode.toLowerCase().contains(_searchQuery) ||
            r.unitName.toLowerCase().contains(_searchQuery) ||
            r.programCode.toLowerCase().contains(_searchQuery) ||
            r.programName.toLowerCase().contains(_searchQuery) ||
            r.lecturerName.toLowerCase().contains(_searchQuery);
        if (!matchesQuery) return false;
      }

      return true;
    }).toList();
  }

  Future<void> _toggleActive(CurriculumRecord record, bool value) async {
    if (!record.isValidForActivation && value) {
      ScriculumSnackBar.show(
        context,
        'Cannot activate: one or more required fields (code, name, program, year, semester) are empty.',
        isError: true,
      );
      return;
    }

    setState(() => _busyRecordIds.add(record.id));
    try {
      await ref.read(curriculumServiceProvider).toggleActive(record.id, value);
      if (mounted) {
        ScriculumSnackBar.show(
          context,
          'Unit ${record.unitCode} is now ${value ? 'Active' : 'Inactive'}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScriculumSnackBar.show(context, 'Failed to update status: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _busyRecordIds.remove(record.id));
      }
    }
  }

  Future<void> _deleteRecord(CurriculumRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1938),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 10),
            Text('Delete Curriculum Unit', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete ${record.unitCode} - ${record.unitName}?',
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: const Text(
                'Note: Already-uploaded materials will retain their unit data and will NOT be deleted, but this unit will no longer appear in material upload selectors.',
                style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.3),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _busyRecordIds.add(record.id));
    try {
      await ref.read(curriculumServiceProvider).deleteRecord(record.id);
      if (mounted) {
        ScriculumSnackBar.show(context, 'Curriculum unit ${record.unitCode} deleted');
      }
    } catch (e) {
      if (mounted) {
        ScriculumSnackBar.show(context, 'Failed to delete record: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _busyRecordIds.remove(record.id));
      }
    }
  }

  Future<void> _openEditDialog({CurriculumRecord? existing}) async {
    final isEditing = existing != null;
    final programCodeCtrl = TextEditingController(text: existing?.programCode ?? '');
    final programNameCtrl = TextEditingController(text: existing?.programName ?? '');
    final unitCodeCtrl = TextEditingController(text: existing?.unitCode ?? '');
    final unitNameCtrl = TextEditingController(text: existing?.unitName ?? '');
    final yearCtrl = TextEditingController(text: existing?.yearOfStudy ?? '1');
    final semesterCtrl = TextEditingController(text: existing?.semester ?? '1');
    final lecturerCtrl = TextEditingController(text: existing?.lecturerName ?? '');
    bool isActive = existing?.isActive ?? true;

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final isValid = programCodeCtrl.text.trim().isNotEmpty &&
                programNameCtrl.text.trim().isNotEmpty &&
                unitCodeCtrl.text.trim().isNotEmpty &&
                unitNameCtrl.text.trim().isNotEmpty &&
                yearCtrl.text.trim().isNotEmpty &&
                semesterCtrl.text.trim().isNotEmpty;

            return AlertDialog(
              backgroundColor: const Color(0xFF1B1938),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(
                    isEditing ? Icons.edit_note_rounded : Icons.add_chart_rounded,
                    color: const Color(0xFF20C8FF),
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isEditing ? 'Edit Curriculum Unit' : 'Add Curriculum Unit',
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 1,
                              child: _buildFormField(
                                controller: programCodeCtrl,
                                label: 'Program Code *',
                                hint: 'e.g. COMS',
                                onChanged: (_) => setDialogState(() {}),
                                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: _buildFormField(
                                controller: programNameCtrl,
                                label: 'Program Name *',
                                hint: 'e.g. B.Sc. Computer Science',
                                onChanged: (_) => setDialogState(() {}),
                                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              flex: 1,
                              child: _buildFormField(
                                controller: unitCodeCtrl,
                                label: 'Unit Code *',
                                hint: 'e.g. COMP 111',
                                onChanged: (_) => setDialogState(() {}),
                                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: _buildFormField(
                                controller: unitNameCtrl,
                                label: 'Unit Name *',
                                hint: 'e.g. Intro to Programming',
                                onChanged: (_) => setDialogState(() {}),
                                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildFormField(
                                controller: yearCtrl,
                                label: 'Year of Study *',
                                hint: '1, 2, 3, or 4',
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setDialogState(() {}),
                                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildFormField(
                                controller: semesterCtrl,
                                label: 'Semester *',
                                hint: '1 or 2',
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setDialogState(() {}),
                                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildFormField(
                          controller: lecturerCtrl,
                          label: "Lecturer's Name (Optional)",
                          hint: 'e.g. Dr. Jane Doe',
                          onChanged: (_) => setDialogState(() {}),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Active Status',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                    Text(
                                      isValid
                                          ? 'Available in upload autocompletes'
                                          : 'All 6 required fields must be filled to activate',
                                      style: TextStyle(
                                        color: isValid ? Colors.white60 : Colors.amber,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: isActive,
                                activeThumbColor: const Color(0xFF00E676),
                                onChanged: isValid
                                    ? (val) => setDialogState(() => isActive = val)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF20C8FF),
                    foregroundColor: const Color(0xFF0D0C1D),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    if (isActive && !isValid) {
                      ScriculumSnackBar.show(
                        context,
                        'Please fill all required fields before activating.',
                        isError: true,
                      );
                      return;
                    }

                    Navigator.pop(dialogCtx);

                    final pCode = programCodeCtrl.text.trim();
                    final pName = programNameCtrl.text.trim();
                    final uCode = unitCodeCtrl.text.trim();
                    final uName = unitNameCtrl.text.trim();
                    final year = yearCtrl.text.trim();
                    final sem = semesterCtrl.text.trim();
                    final lecturer = lecturerCtrl.text.trim();

                    try {
                      if (isEditing) {
                        await ref.read(curriculumServiceProvider).updateRecord(
                          existing.id,
                          {
                            'programCode': pCode,
                            'programName': pName,
                            'unitCode': uCode,
                            'unitName': uName,
                            'yearOfStudy': year,
                            'semester': sem,
                            'lecturerName': lecturer,
                            'isActive': isActive,
                          },
                        );
                        if (mounted) {
                          ScriculumSnackBar.show(context, 'Curriculum unit $uCode updated');
                        }
                      } else {
                        final newRecord = CurriculumRecord(
                          id: CurriculumRecord.generateId(
                            programCode: pCode,
                            unitCode: uCode,
                            yearOfStudy: year,
                            semester: sem,
                          ),
                          programCode: pCode,
                          programName: pName,
                          unitCode: uCode,
                          unitName: uName,
                          yearOfStudy: year,
                          semester: sem,
                          lecturerName: lecturer,
                          isActive: isActive,
                          createdAt: DateTime.now(),
                          updatedAt: DateTime.now(),
                        );
                        await ref.read(curriculumServiceProvider).addRecord(newRecord);
                        if (mounted) {
                          ScriculumSnackBar.show(context, 'Curriculum unit $uCode added');
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        ScriculumSnackBar.show(context, 'Failed to save: $e', isError: true);
                      }
                    }
                  },
                  child: Text(
                    isEditing ? 'Save Changes' : 'Add Unit',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    ValueChanged<String>? onChanged,
    FormFieldValidator<String>? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      onChanged: onChanged,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
        isDense: true,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF20C8FF))),
      ),
    );
  }

  Future<void> _startMigration() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1938),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cloud_upload_outlined, color: Color(0xFF20C8FF), size: 24),
            SizedBox(width: 10),
            Text('Seed Curriculum Pool', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will seed 1,343 curriculum records from the bundled lessons.json into the authoritative Firestore /curriculum collection.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 12),
            Text(
              'The operation is deterministic and idempotent (uses programCode + unitCode + year + semester as key). Existing customizations will be merged safely.',
              style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.3),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF20C8FF),
              foregroundColor: const Color(0xFF0D0C1D),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Start Seeding', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isMigrating = true);
    try {
      final jsonString = await rootBundle.loadString('assets/lessons.json');
      final List<dynamic> rawRecords = json.decode(jsonString);

      final count = await ref.read(curriculumServiceProvider).migrateFromLessonsJson(rawRecords);
      if (mounted) {
        ScriculumSnackBar.show(context, 'Successfully seeded $count curriculum units to Firestore!');
      }
    } catch (e) {
      if (mounted) {
        ScriculumSnackBar.show(context, 'Migration failed: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isMigrating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final curriculumService = ref.watch(curriculumServiceProvider);
    final allRecords = curriculumService.allRecords;
    final filteredRecords = _filterRecords(allRecords);
    final activeCount = allRecords.where((r) => r.isActive).length;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0C1D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141232),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.table_chart_outlined, color: Color(0xFF20C8FF), size: 20),
                SizedBox(width: 8),
                Text(
                  'Curriculum',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Text(
              '${filteredRecords.length} of ${allRecords.length} units ($activeCount active)',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _isTableView ? 'Switch to Card View' : 'Switch to Spreadsheet View',
            icon: Icon(
              _isTableView ? Icons.view_agenda_outlined : Icons.table_rows_outlined,
              color: const Color(0xFF20C8FF),
              size: 20,
            ),
            onPressed: () => setState(() => _isTableView = !_isTableView),
          ),
          IconButton(
            tooltip: 'Seed 1,343 Units from lessons.json',
            icon: _isMigrating
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF20C8FF)))
                : const Icon(Icons.cloud_sync_outlined, color: Color(0xFF20C8FF), size: 22),
            onPressed: _isMigrating ? null : _startMigration,
          ),
          IconButton(
            tooltip: 'Add Unit',
            icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF20C8FF), size: 24),
            onPressed: () => _openEditDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Header
          _buildFilterHeader(allRecords.length),

          // Main Content
          Expanded(
            child: curriculumService.isLoading && allRecords.isEmpty
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF20C8FF)))
                : allRecords.isEmpty
                    ? _buildEmptyState()
                    : filteredRecords.isEmpty
                        ? _buildNoResultsState()
                        : _isTableView
                            ? _buildSpreadsheetTable(filteredRecords)
                            : _buildCardList(filteredRecords),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF20C8FF),
        foregroundColor: const Color(0xFF0D0C1D),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Unit', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => _openEditDialog(),
      ),
    );
  }

  Widget _buildFilterHeader(int totalCount) {
    return Container(
      color: const Color(0xFF141232),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          // Search Bar
          TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search by unit code, name, program, lecturer...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 18),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 16),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),

          // Filter Chips Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatusChip('All', 'all'),
                const SizedBox(width: 6),
                _buildStatusChip('Active Only', 'active'),
                const SizedBox(width: 6),
                _buildStatusChip('Inactive Only', 'inactive'),
                const SizedBox(width: 12),
                Container(width: 1, height: 16, color: Colors.white24),
                const SizedBox(width: 12),

                // Year selector
                _buildDropdownChip(
                  label: _yearFilter == 'all' ? 'Year: All' : 'Year $_yearFilter',
                  items: const ['all', '1', '2', '3', '4'],
                  current: _yearFilter,
                  onSelected: (val) => setState(() => _yearFilter = val),
                ),
                const SizedBox(width: 6),

                // Semester selector
                _buildDropdownChip(
                  label: _semesterFilter == 'all' ? 'Sem: All' : 'Sem $_semesterFilter',
                  items: const ['all', '1', '2'],
                  current: _semesterFilter,
                  onSelected: (val) => setState(() => _semesterFilter = val),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, String value) {
    final isSelected = _statusFilter == value;
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: isSelected ? const Color(0xFF0D0C1D) : Colors.white70, fontSize: 11)),
      selected: isSelected,
      selectedColor: const Color(0xFF20C8FF),
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide.none),
      onSelected: (sel) {
        if (sel) setState(() => _statusFilter = value);
      },
    );
  }

  Widget _buildDropdownChip({
    required String label,
    required List<String> items,
    required String current,
    required ValueChanged<String> onSelected,
  }) {
    return PopupMenuButton<String>(
      tooltip: label,
      initialValue: current,
      color: const Color(0xFF1B1938),
      onSelected: onSelected,
      itemBuilder: (ctx) => items.map((i) {
        final text = i == 'all' ? 'All' : i;
        return PopupMenuItem(
          value: i,
          child: Text(text, style: TextStyle(color: i == current ? const Color(0xFF20C8FF) : Colors.white, fontSize: 12)),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: current != 'all' ? const Color(0xFF20C8FF).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: current != 'all' ? const Color(0xFF20C8FF) : Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: current != 'all' ? const Color(0xFF20C8FF) : Colors.white70,
                fontSize: 11,
                fontWeight: current != 'all' ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, color: current != 'all' ? const Color(0xFF20C8FF) : Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF20C8FF).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.table_chart_outlined, color: Color(0xFF20C8FF), size: 48),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Curriculum Data Found',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'The backend Firestore curriculum collection is currently empty.\nYou can seed the pool directly with the 1,343 bundled units from lessons.json.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF20C8FF),
                foregroundColor: const Color(0xFF0D0C1D),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isMigrating ? null : _startMigration,
              icon: _isMigrating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0D0C1D)))
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(
                _isMigrating ? 'Seeding Database...' : 'Seed 1,343 Units Now',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded, color: Colors.white38, size: 48),
          const SizedBox(height: 12),
          const Text('No matching curriculum units', style: TextStyle(color: Colors.white70, fontSize: 15)),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _statusFilter = 'all';
                _yearFilter = 'all';
                _semesterFilter = 'all';
              });
            },
            child: const Text('Reset Filters', style: TextStyle(color: Color(0xFF20C8FF))),
          ),
        ],
      ),
    );
  }

  Widget _buildCardList(List<CurriculumRecord> records) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: records.length,
      itemBuilder: (context, index) {
        final record = records[index];
        final isBusy = _busyRecordIds.contains(record.id);
        final isValid = record.isValidForActivation;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF141232),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: record.isActive
                  ? const Color(0xFF20C8FF).withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.06),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left badge (Year & Sem)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Y${record.yearOfStudy.isEmpty ? '?' : record.yearOfStudy}',
                        style: const TextStyle(color: Color(0xFF20C8FF), fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      Text(
                        'S${record.semester.isEmpty ? '?' : record.semester}',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Middle: Unit info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF20C8FF).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              record.unitCode,
                              style: const TextStyle(
                                color: Color(0xFF20C8FF),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              record.unitName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${record.programCode} • ${record.programName}',
                        style: const TextStyle(color: Colors.white60, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (record.lecturerName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.person_outline_rounded, color: Colors.white38, size: 12),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                record.lecturerName,
                                style: const TextStyle(color: Colors.white54, fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Far-Right: Active Toggle + Action Buttons
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isValid)
                          const Tooltip(
                            message: 'Cannot activate: required fields incomplete',
                            child: Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 16),
                          ),
                        if (isBusy)
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: Padding(
                              padding: EdgeInsets.all(6),
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF20C8FF)),
                            ),
                          )
                        else
                          Switch(
                            value: record.isActive,
                            activeThumbColor: const Color(0xFF00E676),
                            onChanged: isValid
                                ? (val) => _toggleActive(record, val)
                                : null,
                          ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: Colors.white60, size: 18),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () => _openEditDialog(existing: record),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 18),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () => _deleteRecord(record),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSpreadsheetTable(List<CurriculumRecord> records) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 80),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFF1B1938)),
          dataRowColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
            return const Color(0xFF141232);
          }),
          columnSpacing: 16,
          horizontalMargin: 12,
          headingTextStyle: const TextStyle(color: Color(0xFF20C8FF), fontWeight: FontWeight.bold, fontSize: 12),
          dataTextStyle: const TextStyle(color: Colors.white, fontSize: 12),
          columns: const [
            DataColumn(label: Text('Year')),
            DataColumn(label: Text('Sem')),
            DataColumn(label: Text('Prog Code')),
            DataColumn(label: Text('Program Name')),
            DataColumn(label: Text('Unit Code')),
            DataColumn(label: Text('Unit Name')),
            DataColumn(label: Text('Lecturer')),
            DataColumn(label: Text('Active (Far-Right)')),
            DataColumn(label: Text('Actions')),
          ],
          rows: records.map((record) {
            final isBusy = _busyRecordIds.contains(record.id);
            final isValid = record.isValidForActivation;

            return DataRow(
              cells: [
                DataCell(Text(record.yearOfStudy)),
                DataCell(Text(record.semester)),
                DataCell(Text(record.programCode, style: const TextStyle(fontWeight: FontWeight.bold))),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(record.programName, overflow: TextOverflow.ellipsis),
                  ),
                ),
                DataCell(
                  Text(
                    record.unitCode,
                    style: const TextStyle(color: Color(0xFF20C8FF), fontWeight: FontWeight.bold),
                  ),
                ),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(record.unitName, overflow: TextOverflow.ellipsis),
                  ),
                ),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(record.lecturerName.isEmpty ? '—' : record.lecturerName, overflow: TextOverflow.ellipsis),
                  ),
                ),
                // Far-Right Active Switch
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isValid)
                        const Tooltip(
                          message: 'Cannot activate: required fields incomplete',
                          child: Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 16),
                        ),
                      if (isBusy)
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF20C8FF)),
                        )
                      else
                        Switch(
                          value: record.isActive,
                          activeThumbColor: const Color(0xFF00E676),
                          onChanged: isValid
                              ? (val) => _toggleActive(record, val)
                              : null,
                        ),
                    ],
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: Colors.white60, size: 18),
                        onPressed: () => _openEditDialog(existing: record),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 18),
                        onPressed: () => _deleteRecord(record),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class ScriculumSnackBar {
  static void show(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: isError ? Colors.redAccent : const Color(0xFF00E676),
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1B1938),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
