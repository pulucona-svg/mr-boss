import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:video_player/video_player.dart';
import '../../models/manual_ad.dart';
import '../../services/admin_service.dart';
import '../../widgets/manual_interstitial_ad_dialog.dart';
import '../../services/interstitial_ad_service.dart';

/// Screen allowing administrators to view, create, edit, toggle, preview, and delete manual advertisements.
class ManualAdsAdminScreen extends StatefulWidget {
  const ManualAdsAdminScreen({super.key});

  @override
  State<ManualAdsAdminScreen> createState() => _ManualAdsAdminScreenState();
}

class _ManualAdsAdminScreenState extends State<ManualAdsAdminScreen> {
  final AdminService _adminService = AdminService();

  List<ManualAd> _ads = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAds();
  }

  Future<void> _loadAds({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final ads = await _adminService.getManualAds(forceRefresh: forceRefresh);
      if (mounted) {
        setState(() {
          _ads = ads;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleStatus(ManualAd ad, bool newStatus) async {
    final originalStatus = ad.isActive;
    setState(() {
      final idx = _ads.indexWhere((item) => item.id == ad.id);
      if (idx != -1) {
        _ads[idx] = ad.copyWith(isActive: newStatus);
      }
    });

    try {
      await _adminService.toggleManualAdStatus(ad.id, newStatus);
      // Immediately refresh normal user runtime pool on this device
      InterstitialAdService().syncManualAds();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${ad.title} is now ${newStatus ? "active" : "inactive"}.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF141228),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // Rollback state
        setState(() {
          final idx = _ads.indexWhere((item) => item.id == ad.id);
          if (idx != -1) {
            _ads[idx] = ad.copyWith(isActive: originalStatus);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade900,
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(ManualAd ad) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141228),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Colors.redAccent, width: 1),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Delete Advertisement',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to permanently delete "${ad.title}"?',
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This destructive operation cannot be undone.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Delete Permanently', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await _adminService.deleteManualAd(ad.id);
        // Refresh normal user runtime pool on this device
        InterstitialAdService().syncManualAds();
        if (mounted) {
          setState(() {
            _ads.removeWhere((item) => item.id == ad.id);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"${ad.title}" deleted.'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF141228),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete ad: $e'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red.shade900,
            ),
          );
        }
      }
    }
  }

  void _previewAd(ManualAd ad) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.90),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogContext, anim1, anim2) {
        return ManualInterstitialAdDialog(
          adData: ad.toDialogData(),
          onDismissed: () {},
        );
      },
    );
  }

  Future<void> _openAdEditor([ManualAd? existingAd]) async {
    final result = await showModalBottomSheet<ManualAd>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AdEditorModal(existingAd: existingAd),
    );

    if (result != null) {
      // Synchronize normal user runtime pool on this device
      InterstitialAdService().syncManualAds();
      setState(() {
        final index = _ads.indexWhere((item) => item.id == result.id);
        if (index != -1) {
          _ads[index] = result;
        } else {
          _ads.insert(0, result);
        }
      });
    }
  }

  Future<void> _seedDefaultAds() async {
    setState(() => _isLoading = true);
    try {
      await _adminService.seedDefaultAds(force: true);
      // Synchronize normal user runtime pool on this device
      InterstitialAdService().syncManualAds();
      await _loadAds();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Default ads initialized successfully.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF141228),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to seed default ads: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade900,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: const Color(0xFF070716),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D0C1D),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Manual Advertisements',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF20C8FF),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    'Admin Management Module',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF20C8FF)),
              tooltip: 'Refresh Ads',
              onPressed: () => _loadAds(forceRefresh: true),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF20C8FF)),
              tooltip: 'Create New Ad',
              onPressed: () => _openAdEditor(),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(color: Colors.white12, height: 1),
          ),
        ),
        body: _buildBody(),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openAdEditor(),
          backgroundColor: const Color(0xFF20C8FF),
          foregroundColor: const Color(0xFF070716),
          icon: const Icon(Icons.add_rounded, size: 22),
          label: const Text('NEW AD', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF20C8FF), strokeWidth: 2.5),
            SizedBox(height: 16),
            Text(
              'Loading advertisements...',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 40),
              ),
              const SizedBox(height: 16),
              const Text(
                'Unable to load ads',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => _loadAds(forceRefresh: true),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF20C8FF),
                  foregroundColor: const Color(0xFF070716),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_ads.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.campaign_outlined, color: Colors.white38, size: 48),
              ),
              const SizedBox(height: 16),
              const Text(
                'No Advertisements Configured',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'There are currently no manual ads in the system. You can create a new custom ad or seed the default offline ads.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _seedDefaultAds,
                    icon: const Icon(Icons.download_rounded, size: 18, color: Color(0xFF20C8FF)),
                    label: const Text('Seed Defaults', style: TextStyle(color: Color(0xFF20C8FF))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF20C8FF)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _openAdEditor(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Create Ad'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF20C8FF),
                      foregroundColor: const Color(0xFF070716),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _ads.length,
      itemBuilder: (context, index) {
        final ad = _ads[index];
        return _buildAdCard(ad);
      },
    );
  }

  Widget _buildAdCard(ManualAd ad) {
    final bool isActive = ad.isActive;
    final Color adAccent = ad.color;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF141228),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive ? adAccent.withValues(alpha: 0.35) : Colors.white10,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isActive ? adAccent.withValues(alpha: 0.10) : Colors.black26,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Top Preview Banner
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
                child: SizedBox(
                  height: 140,
                  width: double.infinity,
                  child: ad.isAsset
                      ? Image.asset(
                          ad.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: Colors.white10,
                            child: const Center(
                              child: Icon(Icons.broken_image_rounded, color: Colors.white24, size: 36),
                            ),
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: ad.imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.white10,
                            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.white10,
                            child: const Center(
                              child: Icon(Icons.broken_image_rounded, color: Colors.white24, size: 36),
                            ),
                          ),
                        ),
                ),
              ),

              // Gradient Overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.8),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),

              // Status & Placement Badges
              Positioned(
                top: 12,
                left: 12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xFF00E676) : Colors.white24,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isActive ? Colors.black : Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isActive ? 'ACTIVE' : 'INACTIVE',
                            style: TextStyle(
                              color: isActive ? Colors.black : Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (ad.placement == 'carousel')
                            ? const Color(0xFFFF8A00).withValues(alpha: 0.90)
                            : const Color(0xFF20C8FF).withValues(alpha: 0.90),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            ad.placement == 'carousel' ? Icons.view_carousel_rounded : Icons.fullscreen_rounded,
                            color: Colors.black,
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            ad.placement.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Color Chip Pill
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: adAccent.withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: adAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        ad.isAsset ? 'Local Asset' : 'Online URL',
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),

              // Ad Title on Banner
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Text(
                  ad.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1)),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Details Body
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ad.subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),

                // Contact Link Row
                if (ad.contactUrl.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A85A).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF00A85A).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const FaIcon(FontAwesomeIcons.whatsapp, size: 14, color: Color(0xFF00E676)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ad.contactUrl,
                            style: const TextStyle(
                              color: Color(0xFF00E676),
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 10),

                // Actions Row
                Row(
                  children: [
                    // Active/Inactive Toggle
                    Row(
                      children: [
                        Transform.scale(
                          scale: 0.8,
                          child: Switch(
                            value: isActive,
                            activeThumbColor: const Color(0xFF00E676),
                            activeTrackColor: const Color(0xFF00E676).withValues(alpha: 0.4),
                            inactiveThumbColor: Colors.white38,
                            inactiveTrackColor: Colors.white12,
                            onChanged: (val) => _toggleStatus(ad, val),
                          ),
                        ),
                        Text(
                          isActive ? 'Active' : 'Inactive',
                          style: TextStyle(
                            color: isActive ? Colors.white : Colors.white38,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),

                    // Preview Button
                    IconButton(
                      icon: const Icon(Icons.remove_red_eye_outlined, color: Color(0xFF20C8FF), size: 20),
                      tooltip: 'Live Preview',
                      onPressed: () => _previewAd(ad),
                    ),

                    // Edit Button
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Colors.white70, size: 20),
                      tooltip: 'Edit Ad',
                      onPressed: () => _openAdEditor(ad),
                    ),

                    // Delete Button
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                      tooltip: 'Delete Ad',
                      onPressed: () => _confirmDelete(ad),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Modal editor sheet for creating or modifying a manual ad with device media picking and ImageKit upload.
class _AdEditorModal extends StatefulWidget {
  final ManualAd? existingAd;

  const _AdEditorModal({this.existingAd});

  @override
  State<_AdEditorModal> createState() => _AdEditorModalState();
}

class _AdEditorModalState extends State<_AdEditorModal> {
  final _formKey = GlobalKey<FormState>();
  final AdminService _adminService = AdminService();

  late TextEditingController _titleController;
  late TextEditingController _subtitleController;
  late TextEditingController _contactUrlController;
  late TextEditingController _manualUrlController;

  File? _pickedMediaFile;
  String? _pickedFileName;
  int? _pickedFileSize;
  String _mediaType = 'image';
  String? _existingMediaUrl;
  String? _mediaFileId;

  String? _selectedPlacement; // 'interstitial' | 'carousel' | null
  Duration? _videoDuration;
  bool _isVideoDurationChecking = false;

  late int _selectedColorValue;
  late bool _isActive;
  late bool _isAsset;
  bool _isSaving = false;
  String? _uploadStatusText;
  bool _showManualUrlField = false;

  static const List<int> _presetColors = [
    0xFF20C8FF, // Cyan
    0xFF00A85A, // Emerald Green
    0xFFFF8A00, // Amber / Orange
    0xFF9C27B0, // Purple
    0xFFE91E63, // Pink / Magenta
    0xFF3F51B5, // Indigo
  ];

  @override
  void initState() {
    super.initState();
    final ad = widget.existingAd;
    _titleController = TextEditingController(text: ad?.title ?? '');
    _subtitleController = TextEditingController(text: ad?.subtitle ?? '');
    _contactUrlController = TextEditingController(text: ad?.contactUrl ?? 'https://wa.me/254108462492');
    _manualUrlController = TextEditingController(text: ad?.imageUrl ?? '');

    _existingMediaUrl = ad?.imageUrl;
    _mediaFileId = ad?.mediaFileId;
    _mediaType = ad?.type ?? 'image';
    _selectedPlacement = ad?.placement;
    _selectedColorValue = ad?.colorValue ?? 0xFF20C8FF;
    _isActive = ad?.isActive ?? true;
    _isAsset = ad?.isAsset ?? false;

    if (ad != null && ad.imageUrl.isNotEmpty) {
      _showManualUrlField = false;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    _contactUrlController.dispose();
    _manualUrlController.dispose();
    super.dispose();
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }


  Future<void> _processPickedFile(File file, String mediaType) async {
    final fileName = file.path.split(RegExp(r'[/\\]')).last;
    final fileSize = file.lengthSync();

    if (mediaType != 'video') {
      setState(() {
        _pickedMediaFile = file;
        _pickedFileName = fileName;
        _pickedFileSize = fileSize;
        _mediaType = mediaType;
        _videoDuration = null;
        _isAsset = false;
        _manualUrlController.text = fileName;
      });
      return;
    }

    setState(() {
      _pickedMediaFile = file;
      _pickedFileName = fileName;
      _pickedFileSize = fileSize;
      _mediaType = 'video';
      _isAsset = false;
      _manualUrlController.text = fileName;
      _isVideoDurationChecking = true;
    });

    try {
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      final duration = controller.value.duration;
      await controller.dispose();

      if (mounted) {
        setState(() {
          _videoDuration = duration;
          _isVideoDurationChecking = false;
        });
      }
      debugPrint('ManualAds: [VIDEO_PROBE_SUCCESS] Duration: ${duration.inSeconds}s (${duration.inMilliseconds}ms)');
    } catch (e) {
      debugPrint('ManualAds: [VIDEO_PROBE_ERROR] Failed to probe video duration: $e');
      if (mounted) {
        setState(() {
          _videoDuration = null;
          _isVideoDurationChecking = false;
        });
      }
    }
  }

  void _removeMedia() {
    setState(() {
      _pickedMediaFile = null;
      _pickedFileName = null;
      _pickedFileSize = null;
      _existingMediaUrl = null;
      _mediaFileId = null;
      _videoDuration = null;
      _manualUrlController.clear();
    });
  }

  Future<void> _pickMedia() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141228),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.perm_media_outlined, color: Color(0xFF20C8FF), size: 20),
                    const SizedBox(width: 10),
                    const Text(
                      'Select Advertisement Media',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
                const Divider(color: Colors.white10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF20C8FF).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.photo_library_outlined, color: Color(0xFF20C8FF), size: 22),
                  ),
                  title: const Text('Image from Gallery', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text('JPEG, PNG, WebP image banner', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final picker = ImagePicker();
                    final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
                    if (xfile != null) {
                      _processPickedFile(File(xfile.path), 'image');
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.videocam_outlined, color: Color(0xFF00E676), size: 22),
                  ),
                  title: const Text('Video from Gallery', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text('MP4, MOV video ad (<= 30s)', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final picker = ImagePicker();
                    final xfile = await picker.pickVideo(source: ImageSource.gallery);
                    if (xfile != null) {
                      _processPickedFile(File(xfile.path), 'video');
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.folder_open_rounded, color: Colors.amber, size: 22),
                  ),
                  title: const Text('Browse Device Files', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Select any image or video file', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final res = await FilePicker.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'mp4', 'mov', 'webm', 'mkv'],
                    );
                    if (res != null && res.files.single.path != null) {
                      final path = res.files.single.path!;
                      final ext = path.split('.').last.toLowerCase();
                      final isVideo = ['mp4', 'mov', 'webm', 'mkv'].contains(ext);
                      _processPickedFile(File(path), isVideo ? 'video' : 'image');
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final hasPickedFile = _pickedMediaFile != null;
    final hasManualUrl = _manualUrlController.text.trim().isNotEmpty;
    final hasExistingUrl = _existingMediaUrl != null && _existingMediaUrl!.trim().isNotEmpty;

    if (_selectedPlacement == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an ad placement (Interstitial or Carousel).'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!hasPickedFile && !hasManualUrl && !hasExistingUrl) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an advertisement media file.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _uploadStatusText = 'Preparing media...';
    });

    String? uploadedUrl;
    String? uploadedFileId;

    try {
      // 1. Transaction Step: Upload to ImageKit if local device file selected
      if (_pickedMediaFile != null) {
        final isVid = _mediaType == 'video';
        if (isVid && _videoDuration != null && _videoDuration!.inSeconds > 30) {
          setState(() => _uploadStatusText = 'Trimming video to 30s & preserving audio...');
        } else {
          setState(() => _uploadStatusText = 'Uploading ${_mediaType.toUpperCase()} to ImageKit...');
        }

        final bytes = await _pickedMediaFile!.readAsBytes();
        final base64File = base64Encode(bytes);
        final fileName = _pickedFileName ?? 'ad_media_${DateTime.now().millisecondsSinceEpoch}';

        debugPrint('ManualAds: [UPLOAD] Sending ${bytes.length} bytes to ImageKit callable (isVid: $isVid)...');
        final ikRes = await FirebaseFunctions.instance.httpsCallable('uploadToImageKit').call({
          'file': base64File,
          'fileName': fileName,
          'folder': 'MANUAL_ADS',
          'isVideo': isVid,
          'mediaType': _mediaType,
        });

        uploadedUrl = ikRes.data['url']?.toString();
        uploadedFileId = ikRes.data['fileId']?.toString();

        if (uploadedUrl == null || uploadedUrl.isEmpty) {
          throw Exception('ImageKit upload completed but returned no valid URL.');
        }
        debugPrint('ManualAds: [UPLOAD_SUCCESS] URL: $uploadedUrl, FileID: $uploadedFileId');
      }

      // 2. Transaction Step: Save metadata to Firebase via authoritative backend callable
      setState(() => _uploadStatusText = 'Saving advertisement metadata...');
      final String finalMediaUrl = uploadedUrl ??
          (hasManualUrl ? _manualUrlController.text.trim() : (_existingMediaUrl ?? ''));

      final newAd = ManualAd(
        id: widget.existingAd?.id ?? '',
        title: _titleController.text.trim(),
        subtitle: _subtitleController.text.trim(),
        imageUrl: finalMediaUrl,
        contactUrl: _contactUrlController.text.trim(),
        colorValue: _selectedColorValue,
        isActive: _isActive,
        isAsset: uploadedUrl != null ? false : (_manualUrlController.text.startsWith('assets/')),
        type: _mediaType,
        placement: _selectedPlacement!,
        mediaFileId: uploadedFileId ?? _mediaFileId,
      );

      final saved = await _adminService.saveManualAd(newAd);
      // Synchronize normal user runtime ad pool immediately
      InterstitialAdService().syncManualAds();
      if (mounted) {
        Navigator.pop(context, saved);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Advertisement "${saved.title}" saved successfully.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF141228),
          ),
        );
      }
    } catch (e) {
      debugPrint('ManualAds: [SAVE_ERROR] Error saving ad: $e');

      // Safe cleanup of orphaned ImageKit upload if metadata write failed
      if (uploadedFileId != null) {
        debugPrint('ManualAds: [CLEANUP] Cleaning up orphaned ImageKit file "$uploadedFileId"...');
        try {
          await FirebaseFunctions.instance.httpsCallable('deleteFromImageKit').call({
            'fileId': uploadedFileId,
          });
          debugPrint('ManualAds: [CLEANUP_SUCCESS] Orphaned file removed successfully.');
        } catch (ikErr) {
          debugPrint('ManualAds: [CLEANUP_WARN] Failed to delete orphaned file: $ikErr');
        }
      }

      if (mounted) {
        setState(() {
          _isSaving = false;
          _uploadStatusText = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save advertisement: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade900,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Widget _buildMediaSection() {
    if (_pickedMediaFile != null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF20C8FF).withValues(alpha: 0.4)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_mediaType == 'image')
              SizedBox(
                height: 160,
                width: double.infinity,
                child: Image.file(_pickedMediaFile!, fit: BoxFit.cover),
              )
            else
              Container(
                height: 140,
                color: const Color(0xFF0F0E20),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.videocam_rounded, color: Color(0xFF00E676), size: 36),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Video Ready for Upload',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (_mediaType == 'video' ? const Color(0xFF00E676) : const Color(0xFF20C8FF))
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _mediaType.toUpperCase(),
                          style: TextStyle(
                            color: _mediaType == 'video' ? const Color(0xFF00E676) : const Color(0xFF20C8FF),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _pickedFileName ?? 'Selected File',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_pickedFileSize != null)
                        Text(
                          _formatFileSize(_pickedFileSize!),
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                    ],
                  ),
                  if (_mediaType == 'video') ...[
                    const SizedBox(height: 8),
                    if (_isVideoDurationChecking)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E676))),
                            SizedBox(width: 8),
                            Text('Checking video duration...', style: TextStyle(color: Colors.white70, fontSize: 11)),
                          ],
                        ),
                      )
                    else if (_videoDuration != null)
                      Builder(builder: (context) {
                        final bool isWithinLimit = _videoDuration!.inMilliseconds <= 30000;
                        final String durationSecStr = (_videoDuration!.inMilliseconds / 1000.0).toStringAsFixed(1);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isWithinLimit
                                ? const Color(0xFF00E676).withValues(alpha: 0.15)
                                : Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isWithinLimit
                                  ? const Color(0xFF00E676).withValues(alpha: 0.4)
                                  : Colors.amber.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isWithinLimit ? Icons.check_circle_outline_rounded : Icons.content_cut_rounded,
                                size: 15,
                                color: isWithinLimit ? const Color(0xFF00E676) : Colors.amber,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  isWithinLimit
                                      ? 'Duration: ${durationSecStr}s (Within 30s limit)'
                                      : 'Duration: ${durationSecStr}s (Exceeds 30s: will be auto-trimmed to 30s upon upload with audio preserved)',
                                  style: TextStyle(
                                    color: isWithinLimit ? const Color(0xFF00E676) : Colors.amber,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: _isSaving ? null : _pickMedia,
                        icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                        label: const Text('Change Media', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFF20C8FF)),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _isSaving ? null : _removeMedia,
                        icon: const Icon(Icons.delete_outline_rounded, size: 16),
                        label: const Text('Remove', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_existingMediaUrl != null && _existingMediaUrl!.isNotEmpty) {
      final isExistingAsset = _isAsset || _existingMediaUrl!.startsWith('assets/');
      return Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_mediaType == 'video')
              Container(
                height: 120,
                color: const Color(0xFF0F0E20),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_circle_outline_rounded, color: Color(0xFF00E676), size: 32),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Existing Video Media',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                height: 140,
                width: double.infinity,
                child: isExistingAsset
                    ? Image.asset(_existingMediaUrl!, fit: BoxFit.cover)
                    : CachedNetworkImage(imageUrl: _existingMediaUrl!, fit: BoxFit.cover),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _existingMediaUrl!,
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _isSaving ? null : _pickMedia,
                    icon: const Icon(Icons.file_upload_outlined, size: 16),
                    label: const Text('Replace', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFF20C8FF)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: _isSaving ? null : _pickMedia,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF20C8FF).withValues(alpha: 0.3), width: 1.5),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF20C8FF).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_photo_alternate_outlined, color: Color(0xFF20C8FF), size: 32),
            ),
            const SizedBox(height: 12),
            const Text(
              'Select Advertisement Media *',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap to choose image (JPG, PNG) or video (MP4) from device',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingAd != null;
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF0D0C1D),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              // Grab Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF20C8FF).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.campaign_outlined, color: Color(0xFF20C8FF), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      isEditing ? 'Edit Advertisement' : 'Create Advertisement',
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white60),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const Divider(color: Colors.white12, height: 1),

              // Form Fields
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      // Media Section (Picker & Preview)
                      const Text(
                        'Advertisement Media *',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      _buildMediaSection(),

                      const SizedBox(height: 12),

                      // Optional URL toggle (for manual / existing bundled paths)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Manual URL / Asset Mode',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _showManualUrlField = !_showManualUrlField),
                            child: Text(
                              _showManualUrlField ? 'Hide' : 'Show',
                              style: const TextStyle(color: Color(0xFF20C8FF), fontSize: 12),
                            ),
                          ),
                        ],
                      ),

                      if (_showManualUrlField) ...[
                        const SizedBox(height: 6),
                        _buildTextField(
                          controller: _manualUrlController,
                          label: 'Direct URL or Asset Path',
                          hint: 'assets/ad_cyber.jpeg or https://ik.imagekit.io/...',
                          onChanged: (val) {
                            setState(() {
                              _existingMediaUrl = val.trim();
                              _isAsset = val.trim().startsWith('assets/');
                            });
                          },
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Title Field
                      _buildTextField(
                        controller: _titleController,
                        label: 'Ad Title *',
                        hint: 'e.g. Davy Cybers 💻',
                        validator: (val) => (val == null || val.trim().isEmpty) ? 'Title is required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Subtitle Field
                      _buildTextField(
                        controller: _subtitleController,
                        label: 'Subtitle / Description *',
                        hint: 'e.g. Need professional cyber services? We have got you covered.',
                        maxLines: 2,
                        validator: (val) => (val == null || val.trim().isEmpty) ? 'Subtitle is required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Contact WhatsApp URL Field
                      _buildTextField(
                        controller: _contactUrlController,
                        label: 'Contact WhatsApp URL *',
                        hint: 'https://wa.me/254108462492',
                        validator: (val) => (val == null || val.trim().isEmpty) ? 'Contact URL is required' : null,
                      ),
                      const SizedBox(height: 20),

                      // Color Accent Picker
                      const Text(
                        'Brand Accent Color',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: _presetColors.map((colorVal) {
                          final isSelected = _selectedColorValue == colorVal;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedColorValue = colorVal),
                            child: Container(
                              margin: const EdgeInsets.only(right: 12),
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Color(colorVal),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? Colors.white : Colors.transparent,
                                  width: 2.5,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: Color(colorVal).withValues(alpha: 0.6),
                                          blurRadius: 10,
                                          spreadRadius: 1,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),

                      // Active Switch
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.power_settings_new_rounded, color: Color(0xFF20C8FF), size: 20),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Active Status', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                                  Text('Display to users in rotation', style: TextStyle(color: Colors.white54, fontSize: 11)),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isActive,
                              activeThumbColor: const Color(0xFF00E676),
                              onChanged: (val) => setState(() => _isActive = val),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Mutually Exclusive Ad Placement Selector
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _selectedPlacement == null
                                ? Colors.amber.withValues(alpha: 0.5)
                                : const Color(0xFF20C8FF).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.aspect_ratio_rounded, color: Color(0xFF20C8FF), size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Display Destination (Required) *',
                                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Each ad belongs to exactly one destination. Choices are strictly mutually exclusive.',
                              style: TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                            const SizedBox(height: 12),

                            // Option 1: Interstitial
                            InkWell(
                              onTap: _isSaving
                                  ? null
                                  : () {
                                      setState(() {
                                        _selectedPlacement =
                                            (_selectedPlacement == 'interstitial') ? null : 'interstitial';
                                      });
                                    },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: _selectedPlacement == 'interstitial'
                                      ? const Color(0xFF20C8FF).withValues(alpha: 0.15)
                                      : Colors.white.withValues(alpha: 0.02),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _selectedPlacement == 'interstitial'
                                        ? const Color(0xFF20C8FF)
                                        : Colors.white12,
                                    width: _selectedPlacement == 'interstitial' ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _selectedPlacement == 'interstitial'
                                          ? Icons.check_box_rounded
                                          : Icons.check_box_outline_blank_rounded,
                                      color: _selectedPlacement == 'interstitial'
                                          ? const Color(0xFF20C8FF)
                                          : Colors.white38,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Interstitial',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            'Full-screen vertical presentation shown during navigation and idle breaks',
                                            style: TextStyle(color: Colors.white54, fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Option 2: Carousel
                            InkWell(
                              onTap: _isSaving
                                  ? null
                                  : () {
                                      setState(() {
                                        _selectedPlacement =
                                            (_selectedPlacement == 'carousel') ? null : 'carousel';
                                      });
                                    },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: _selectedPlacement == 'carousel'
                                      ? const Color(0xFFFF8A00).withValues(alpha: 0.15)
                                      : Colors.white.withValues(alpha: 0.02),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _selectedPlacement == 'carousel'
                                        ? const Color(0xFFFF8A00)
                                        : Colors.white12,
                                    width: _selectedPlacement == 'carousel' ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _selectedPlacement == 'carousel'
                                          ? Icons.check_box_rounded
                                          : Icons.check_box_outline_blank_rounded,
                                      color: _selectedPlacement == 'carousel'
                                          ? const Color(0xFFFF8A00)
                                          : Colors.white38,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Carousel',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            'Horizontal banner carousel displayed on Dashboard and Library',
                                            style: TextStyle(color: Colors.white54, fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            if (_selectedPlacement == null) ...[
                              const SizedBox(height: 10),
                              const Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 14),
                                  SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Please select Interstitial or Carousel to enable saving.',
                                      style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom Action Button with upload status
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_isSaving || _selectedPlacement == null) ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF20C8FF),
                      foregroundColor: const Color(0xFF070716),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      disabledBackgroundColor: Colors.white12,
                      disabledForegroundColor: Colors.white38,
                    ),
                    child: _isSaving
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF070716)),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _uploadStatusText ?? 'Processing...',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF070716)),
                              ),
                            ],
                          )
                        : Text(
                            isEditing ? 'UPDATE ADVERTISEMENT' : 'SAVE ADVERTISEMENT',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF20C8FF)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          validator: validator,
        ),
      ],
    );
  }
}
