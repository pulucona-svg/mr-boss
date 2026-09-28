import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/material_model.dart';
import '../../providers/providers.dart';
import '../../services/resource_service.dart';
import '../../services/admin_service.dart';
import '../../widgets/notification_modal.dart';
import '../../widgets/resource_card.dart';
import '../../widgets/upload_bottom_sheet.dart';
import '../material_viewer_screen.dart';

class MaterialsApproveScreen extends ConsumerStatefulWidget {
  const MaterialsApproveScreen({super.key});

  @override
  ConsumerState<MaterialsApproveScreen> createState() => _MaterialsApproveScreenState();
}

class _MaterialsApproveScreenState extends ConsumerState<MaterialsApproveScreen> {
  final List<String> _categories = [
    'Pending Materials',
    'Approved',
    'Rejected',
    'Modified',
  ];

  late final PageController _pageController;
  int _selectedCategoryIndex = 0;

  // Single-selection mode for Pending Materials
  String? _selectedPendingMaterialId;
  bool get _isSelectionMode => _selectedPendingMaterialId != null;

  // 12 Standard Rejection Reasons
  static const List<String> _kRejectionReasons = [
    'Low image or scan quality',
    'Incomplete notes or missing pages',
    'Wrong unit code or course mismatch',
    'Incorrect academic year or semester',
    'Duplicate material already exists',
    'Inappropriate or irrelevant content',
    'Copyright or plagiarism issue',
    'Unreadable handwriting or illegible text',
    'Corrupted file or unable to open',
    'Past paper missing solutions or poorly formatted',
    'Incorrect material category or type',
    'Blurry or obscured pages',
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);

    // Verify admin privileges
    AdminService().isCurrentUserAdmin().then((isVerified) {
      if (!isVerified && mounted && FirebaseAuth.instance.currentUser != null) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onCategoryTap(int index) {
    if (_isSelectionMode) {
      _exitSelectionMode();
    }
    setState(() {
      _selectedCategoryIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    if (_isSelectionMode) {
      _exitSelectionMode();
    }
    setState(() {
      _selectedCategoryIndex = index;
    });
  }

  void _enterOrToggleSelection(String materialId) {
    setState(() {
      if (_selectedPendingMaterialId == materialId) {
        _selectedPendingMaterialId = null;
      } else {
        // Strictly only ONE selected at a time
        _selectedPendingMaterialId = materialId;
      }
    });
  }

  void _exitSelectionMode() {
    if (_selectedPendingMaterialId != null) {
      setState(() {
        _selectedPendingMaterialId = null;
      });
    }
  }

  void _showNotifications() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NotificationModal(),
    );
  }

  void _openViewer(Resource resource) {
    if (resource.fileUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Material file URL is not available.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MaterialViewerScreen(
          title: resource.title,
          fileUrl: resource.fileUrl,
          unitName: resource.unitName,
          unitCode: resource.unitCode,
          category: resource.type,
          publicationYear: resource.publicationYear,
        ),
      ),
    );
  }

  // --- APPROVAL FLOW ---
  void _openApproveDialog(Resource resource) {
    final remarkController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF141232),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF00E676), width: 1),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF00E676).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF00E676), size: 22),
            ),
            const SizedBox(width: 12),
            const Text(
              'Approve Material',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to approve "${resource.title}" (${resource.unitCode})?',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              const Text(
                'Admin Remark (Optional):',
                style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: remarkController,
                maxLines: 2,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Add an optional approval remark...',
                  hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF00E676)),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final remark = remarkController.text.trim();
              await ref.read(resourceServiceProvider).approveMaterial(
                resource.id,
                adminRemark: remark.isNotEmpty ? remark : null,
              );
              _exitSelectionMode();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Material "${resource.title}" approved successfully!'),
                    backgroundColor: const Color(0xFF00E676),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Approve', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // --- REJECTION FLOW ---
  void _openRejectDialog(Resource resource) {
    final selectedReasons = <String>{};
    final remarkController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final canConfirm = selectedReasons.isNotEmpty;

          return AlertDialog(
            backgroundColor: const Color(0xFF141232),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFFFF5252), width: 1),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5252).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.cancel_rounded, color: Color(0xFFFF5252), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Reject Material',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select at least one reason for denying "${resource.title}":',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    ..._kRejectionReasons.map((reason) {
                      final isChecked = selectedReasons.contains(reason);
                      return InkWell(
                        onTap: () {
                          setDialogState(() {
                            if (isChecked) {
                              selectedReasons.remove(reason);
                            } else {
                              selectedReasons.add(reason);
                            }
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: isChecked,
                                  activeColor: const Color(0xFFFF5252),
                                  checkColor: Colors.white,
                                  side: const BorderSide(color: Colors.white38),
                                  onChanged: (val) {
                                    setDialogState(() {
                                      if (val == true) {
                                        selectedReasons.add(reason);
                                      } else {
                                        selectedReasons.remove(reason);
                                      }
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  reason,
                                  style: TextStyle(
                                    color: isChecked ? Colors.white : Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    const Text(
                      'Admin Remark (Optional):',
                      style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: remarkController,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Add an optional note explaining the decision...',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFFF5252)),
                        ),
                      ),
                    ),
                  ],
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
                  backgroundColor: canConfirm ? const Color(0xFFFF5252) : Colors.white12,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: canConfirm
                    ? () async {
                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.pop(dialogCtx);
                        final remark = remarkController.text.trim();
                        await ref.read(resourceServiceProvider).rejectMaterial(
                          resource.id,
                          rejectionReasons: selectedReasons.toList(),
                          adminRemark: remark.isNotEmpty ? remark : null,
                        );
                        _exitSelectionMode();
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Material "${resource.title}" rejected.'),
                              backgroundColor: const Color(0xFFFF5252),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    : null,
                child: const Text('Confirm Denial', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- MODERATION MODIFY FLOW ---
  void _openModerationModify(Resource resource) {
    _exitSelectionMode();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => UploadBottomSheet(
        modifyingMaterial: resource,
        isModerationModify: true,
      ),
    );
  }

  // --- RECONSIDER FLOW ---
  void _reconsiderMaterial(Resource resource) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF141232),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF20C8FF), width: 1),
        ),
        title: const Text('Reconsider Material', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        content: Text(
          'Return "${resource.title}" to Pending Materials for fresh review?',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF20C8FF),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Reconsider', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(resourceServiceProvider).reconsiderMaterial(resource.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${resource.title}" returned to Pending Materials.'),
            backgroundColor: const Color(0xFF20C8FF),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final resourceService = ref.watch(resourceServiceProvider);

    final pendingList = resourceService.pendingResources;
    final approvedList = resourceService.approvedResources;
    final rejectedList = resourceService.rejectedResources;
    final modifiedList = resourceService.modifiedResources;

    final selectedResource = _selectedPendingMaterialId != null
        ? pendingList.where((r) => r.id == _selectedPendingMaterialId).firstOrNull
        : null;

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF070716),
        body: SafeArea(
          child: Column(
            children: [
              // Header Row: Back button, Title, Notification Bell
              _buildTopBar(),

              // Explore-style Category Navigation Tabs
              _buildCategoryTabBar(),

              // Pending Selection Action Bar (Strictly 1 item selected)
              if (_selectedCategoryIndex == 0 && _isSelectionMode && selectedResource != null)
                _buildPendingSelectionBar(selectedResource),

              // PageView Content
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  children: [
                    _buildPendingPage(pendingList),
                    _buildApprovedPage(approvedList),
                    _buildRejectedPage(rejectedList),
                    _buildModifiedPage(modifiedList),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- TOP BAR ---
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
            onPressed: () {
              if (_isSelectionMode) {
                _exitSelectionMode();
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          Text(
            _categories[_selectedCategoryIndex].toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 24),
            onPressed: _showNotifications,
          ),
        ],
      ),
    );
  }

  // --- CATEGORY TAB BAR (EXPLORE STYLE) ---
  Widget _buildCategoryTabBar() {
    const neonCyan = Color(0xFF20C8FF);

    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = index == _selectedCategoryIndex;

          return GestureDetector(
            onTap: () => _onCategoryTap(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? neonCyan.withValues(alpha: 0.9)
                    : const Color(0xFF181739).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? neonCyan : Colors.white10,
                  width: 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: neonCyan.withValues(alpha: 0.5),
                          blurRadius: 12,
                          spreadRadius: 1,
                        )
                      ]
                    : [],
              ),
              child: Center(
                child: Text(
                  category,
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // --- PENDING SELECTION ACTION BAR (ZERO OVERFLOW) ---
  Widget _buildPendingSelectionBar(Resource resource) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF181739),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF20C8FF).withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _exitSelectionMode,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '1 selected',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Action 1: Approve (Check)
          IconButton(
            icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF00E676), size: 22),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: 'Approve',
            onPressed: () => _openApproveDialog(resource),
          ),
          const SizedBox(width: 4),
          // Action 2: Modify
          IconButton(
            icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF20C8FF), size: 24),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: 'Modify',
            onPressed: () => _openModerationModify(resource),
          ),
          const SizedBox(width: 4),
          // Action 3: Reject / Deny
          IconButton(
            icon: const Icon(Icons.cancel_rounded, color: Color(0xFFFF5252), size: 22),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: 'Reject',
            onPressed: () => _openRejectDialog(resource),
          ),
        ],
      ),
    );
  }

  // --- PAGE 1: PENDING MATERIALS ---
  Widget _buildPendingPage(List<Resource> pendingList) {
    if (pendingList.isEmpty) {
      return _buildEmptyState(
        icon: Icons.hourglass_empty_rounded,
        title: 'No Pending Materials',
        subtitle: 'All user-uploaded materials have been reviewed.',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.65,
      ),
      itemCount: pendingList.length,
      itemBuilder: (context, index) {
        final res = pendingList[index];
        final isSelected = _selectedPendingMaterialId == res.id;

        return ResourceCard(
          key: ValueKey(res.id),
          resource: res,
          isSelectionMode: _isSelectionMode,
          isSelected: isSelected,
          forceShowStatusTag: true,
          onTap: () {
            if (_isSelectionMode) {
              _enterOrToggleSelection(res.id);
            } else {
              _openViewer(res);
            }
          },
          onLongPress: () {
            _enterOrToggleSelection(res.id);
          },
        );
      },
    );
  }

  // --- PAGE 2: APPROVED MATERIALS ---
  Widget _buildApprovedPage(List<Resource> approvedList) {
    if (approvedList.isEmpty) {
      return _buildEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'No Approved Materials',
        subtitle: 'Approved materials will appear here.',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.65,
      ),
      itemCount: approvedList.length,
      itemBuilder: (context, index) {
        final res = approvedList[index];
        return ResourceCard(
          key: ValueKey(res.id),
          resource: res,
          forceShowStatusTag: true,
          onTap: () => _openViewer(res),
        );
      },
    );
  }

  // --- PAGE 3: REJECTED MATERIALS ---
  Widget _buildRejectedPage(List<Resource> rejectedList) {
    if (rejectedList.isEmpty) {
      return _buildEmptyState(
        icon: Icons.cancel_outlined,
        title: 'No Rejected Materials',
        subtitle: 'Denied materials under 30-day retention will appear here.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: rejectedList.length,
      itemBuilder: (context, index) {
        final res = rejectedList[index];
        final reasons = res.rejectionReasons ?? [];

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF141232),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFF5252).withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 280,
                child: ResourceCard(
                  key: ValueKey(res.id),
                  resource: res,
                  forceShowStatusTag: true,
                  onTap: () => _openViewer(res),
                ),
              ),
              if (reasons.isNotEmpty || (res.adminRemark != null && res.adminRemark!.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5252).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFF5252).withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (reasons.isNotEmpty) ...[
                          const Text(
                            'Rejection Reasons:',
                            style: TextStyle(color: Color(0xFFFF8A80), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          ...reasons.map((r) => Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text('• $r', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              )),
                        ],
                        if (res.adminRemark != null && res.adminRemark!.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Remark: ${res.adminRemark!}',
                            style: const TextStyle(color: Colors.white60, fontSize: 11, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF20C8FF),
                        side: const BorderSide(color: Color(0xFF20C8FF), width: 1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Reconsider', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () => _reconsiderMaterial(res),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- PAGE 4: MODIFIED MATERIALS ---
  Widget _buildModifiedPage(List<Resource> modifiedList) {
    if (modifiedList.isEmpty) {
      return _buildEmptyState(
        icon: Icons.edit_note_rounded,
        title: 'No Modified Materials',
        subtitle: 'Materials modified by an admin will appear here.',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.65,
      ),
      itemCount: modifiedList.length,
      itemBuilder: (context, index) {
        final res = modifiedList[index];
        return ResourceCard(
          key: ValueKey(res.id),
          resource: res,
          forceShowStatusTag: true,
          onTap: () => _openViewer(res),
        );
      },
    );
  }

  // --- EMPTY STATE ---
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white30, size: 48),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white38, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
