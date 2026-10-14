import 'package:flutter/material.dart';
import '../../models/dspace_job_model.dart';
import '../../services/dspace_admin_service.dart';

/// Dedicated DSpace Examination Papers Management Screen
///
/// Features:
/// - Clear title: DSpace Examination Papers
/// - Check button (read-only discovery)
/// - Check & Download button (discovery with confirmation & batch import)
/// - Realtime loading and progress indicator
/// - Scrollable list of newly discovered examination papers
/// - Total count of new materials found
/// - Clear success, failure, and partial-completion messages
/// - Strict concurrency protection against double-tapping or overlapping jobs
class DSpaceAdminScreen extends StatefulWidget {
  const DSpaceAdminScreen({super.key});

  @override
  State<DSpaceAdminScreen> createState() => _DSpaceAdminScreenState();
}

class _DSpaceAdminScreenState extends State<DSpaceAdminScreen> {
  final DSpaceAdminService _dspaceService = DSpaceAdminService();
  bool _isInitiating = false;
  String? _activeJobId;

  Future<void> _runJob(String action) async {
    if (_isInitiating) return;

    if (action == 'check_and_download') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1B1938),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.download_rounded, color: Color(0xFF20C8FF), size: 26),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Confirm Check & Download',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This operation will discover new examination papers from the DSpace archive and import them into Mirror Digital using the verified virtual uploader pipeline.',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
              SizedBox(height: 12),
              Text(
                '• Reuses the 20 virtual uploader accounts\n• Streams bitstreams to ImageKit\n• Creates Firestore resources with isImportedDSpace: true\n• Automatically schedules Flux thumbnail generation',
                style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.5),
              ),
              SizedBox(height: 12),
              Text(
                'Do you wish to start the import now?',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
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
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm & Start', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    setState(() => _isInitiating = true);

    try {
      final jobId = await _dspaceService.startDSpaceJob(action);
      if (mounted) {
        setState(() {
          _activeJobId = jobId;
          _isInitiating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Color(0xFF00E676), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    action == 'check' ? 'DSpace check job started.' : 'DSpace import job started.',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF141232),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isInitiating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Operation failed: $e', style: const TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF2A1015),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _cancelJob(String jobId) async {
    try {
      await _dspaceService.cancelDSpaceJob(jobId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cancellation requested.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel job: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0C1D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0C1D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'DSpace Examination Papers',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
        centerTitle: false,
      ),
      body: StreamBuilder<DSpaceJobModel?>(
        stream: _activeJobId != null
            ? _dspaceService.watchJob(_activeJobId!)
            : _dspaceService.watchLatestJob(),
        builder: (context, snapshot) {
          final job = snapshot.data;

          // Auto-follow continuation job if current slice paused and created a next slice
          if (job != null && job.isPaused && job.continuationJobId != null && _activeJobId != job.continuationJobId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _activeJobId = job.continuationJobId;
                });
              }
            });
          }

          final isBusy = _isInitiating || (job?.isBusy ?? false);

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // 1. Repository Info Banner
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: _buildRepositoryCard(),
                ),
              ),

              // 2. Action Buttons (Check & Check+Download)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildActionButtons(isBusy),
                ),
              ),

              // 3. Live Progress Indicator (if active)
              if (job != null && job.isBusy)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: _buildProgressCard(job),
                  ),
                ),

              // 4. Status / Result Message Banner
              if (job != null && !job.isBusy)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: _buildStatusBanner(job),
                  ),
                ),

              // 5. Total Count & Summary Metric Cards
              if (job != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: _buildMetricsGrid(job),
                  ),
                ),

              // 6. Section Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.menu_book_rounded, color: Color(0xFF20C8FF), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Newly Discovered Examination Papers (${job?.discoveredItems.length ?? 0})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 7. Scrollable Discovered Items List
              if (job == null || job.discoveredItems.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _buildEmptyState(job),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final paper = job.discoveredItems[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildPaperCard(index + 1, paper),
                        );
                      },
                      childCount: job.discoveredItems.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRepositoryCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141232),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF20C8FF).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.account_balance_rounded, color: Color(0xFF20C8FF), size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Laikipia University Repository',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 2),
                Text(
                  'Community: Examination Past Papers (DSpace 8 REST API)',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF00E676).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.4)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFF00E676), size: 12),
                SizedBox(width: 4),
                Text('Active', style: TextStyle(color: Color(0xFF00E676), fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isBusy) {
    return Row(
      children: [
        // 1. Check Button
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(
                color: isBusy ? Colors.white24 : const Color(0xFF20C8FF),
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              backgroundColor: isBusy
                  ? Colors.transparent
                  : const Color(0xFF20C8FF).withValues(alpha: 0.08),
            ),
            icon: const Icon(Icons.search_rounded, size: 20),
            label: const Text(
              'Check',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            onPressed: isBusy ? null : () => _runJob('check'),
          ),
        ),
        const SizedBox(width: 12),
        // 2. Check & Download Button
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: isBusy ? Colors.white24 : const Color(0xFF20C8FF),
              foregroundColor: Colors.black,
              elevation: isBusy ? 0 : 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.download_rounded, size: 20),
            label: const Text(
              'Check & Download',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            onPressed: isBusy ? null : () => _runJob('check_and_download'),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressCard(DSpaceJobModel job) {
    final percent = (job.progress * 100).clamp(0, 100).toInt();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1938),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF20C8FF).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF20C8FF)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  job.action == 'check'
                      ? 'Checking Repository Archive...'
                      : (job.isPaused ? 'Auto-Resuming Next Slice...' : 'Importing Examination Papers...'),
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '$percent%',
                style: const TextStyle(color: Color(0xFF20C8FF), fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: job.progress > 0 ? job.progress : null,
              minHeight: 6,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF20C8FF)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  job.message.isNotEmpty ? job.message : 'Processing...',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => _cancelJob(job.id),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Cancel', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(DSpaceJobModel job) {
    Color bannerBg;
    Color borderColor;
    Color iconColor;
    IconData iconData;
    String titleText;
    String detailText;

    if (job.isCompleted) {
      bannerBg = const Color(0xFF00E676).withValues(alpha: 0.1);
      borderColor = const Color(0xFF00E676).withValues(alpha: 0.3);
      iconColor = const Color(0xFF00E676);
      iconData = Icons.check_circle_rounded;
      titleText = job.action == 'check' ? 'Check Complete' : 'Import Complete';
      detailText = job.message.isNotEmpty
          ? job.message
          : (job.action == 'check'
              ? 'Discovery finished. Found ${job.discoveredCount} new papers.'
              : 'Successfully imported ${job.importedCount} papers into Mirror Digital.');
    } else if (job.isPartialFailure) {
      bannerBg = Colors.amber.withValues(alpha: 0.1);
      borderColor = Colors.amber.withValues(alpha: 0.4);
      iconColor = Colors.amber;
      iconData = Icons.warning_amber_rounded;
      titleText = 'Partial Completion';
      detailText = job.message.isNotEmpty
          ? job.message
          : 'Import finished with warnings: ${job.importedCount} imported, ${job.failedCount} failed, ${job.skippedCount} skipped.';
    } else if (job.isPaused) {
      bannerBg = const Color(0xFF20C8FF).withValues(alpha: 0.1);
      borderColor = const Color(0xFF20C8FF).withValues(alpha: 0.3);
      iconColor = const Color(0xFF20C8FF);
      iconData = Icons.autorenew_rounded;
      titleText = 'Batch Limit Reached (Auto-Resuming)';
      detailText = job.message.isNotEmpty
          ? job.message
          : '7.5m limit reached. Next batch slice is auto-resuming in background...';
    } else if (job.isFailed) {
      bannerBg = Colors.redAccent.withValues(alpha: 0.1);
      borderColor = Colors.redAccent.withValues(alpha: 0.3);
      iconColor = Colors.redAccent;
      iconData = Icons.error_outline_rounded;
      titleText = 'Operation Failed';
      detailText = job.error ?? job.message;
    } else {
      bannerBg = Colors.white.withValues(alpha: 0.05);
      borderColor = Colors.white12;
      iconColor = Colors.white60;
      iconData = Icons.info_outline_rounded;
      titleText = 'Status: ${job.status.toUpperCase()}';
      detailText = job.message;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bannerBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconData, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titleText,
                  style: TextStyle(color: iconColor, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  detailText,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(DSpaceJobModel job) {
    return Row(
      children: [
        // Total New Discovered
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF141232),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('New Found', style: TextStyle(color: Colors.white60, fontSize: 11)),
                const SizedBox(height: 4),
                Text(
                  '${job.discoveredCount}',
                  style: const TextStyle(
                    color: Color(0xFF20C8FF),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Imported
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF141232),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Imported', style: TextStyle(color: Colors.white60, fontSize: 11)),
                const SizedBox(height: 4),
                Text(
                  '${job.importedCount}',
                  style: const TextStyle(
                    color: Color(0xFF00E676),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Failed
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF141232),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Failed', style: TextStyle(color: Colors.white60, fontSize: 11)),
                const SizedBox(height: 4),
                Text(
                  '${job.failedCount}',
                  style: TextStyle(
                    color: job.failedCount > 0 ? Colors.redAccent : Colors.white38,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Skipped
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF141232),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Skipped', style: TextStyle(color: Colors.white60, fontSize: 11)),
                const SizedBox(height: 4),
                Text(
                  '${job.skippedCount}',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(DSpaceJobModel? job) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: const Color(0xFF141232),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF00E676).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_rounded, color: Color(0xFF00E676), size: 36),
          ),
          const SizedBox(height: 14),
          const Text(
            'Archive is Up to Date',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'All examination papers in the repository have already been synchronized with Mirror Digital. Tap "Check" at any time to query for new archive releases.',
            style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPaperCard(int index, DiscoveredDSpacePaper paper) {
    final year = paper.publicationYear?.toString() ?? 'N/A';
    final code = paper.unitCode.isNotEmpty ? paper.unitCode : 'EXAM';
    final title = paper.unitName.isNotEmpty ? paper.unitName : paper.title;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141232),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Index Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '#$index',
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              // Code Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF20C8FF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF20C8FF).withValues(alpha: 0.3)),
                ),
                child: Text(
                  code,
                  style: const TextStyle(color: Color(0xFF20C8FF), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              // Year Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 10, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(
                      year,
                      style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Program/Faculty Badge
              if (paper.yearOfStudy.isNotEmpty)
                Text(
                  paper.yearOfStudy,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Paper Title
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, height: 1.3),
          ),
          if (paper.subjects.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Subjects: ${paper.subjects}',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 8),
          // Metadata Footer (UUID, Collection, File size)
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'UUID: ${paper.itemUuid}',
                      style: const TextStyle(color: Colors.white30, fontSize: 10, fontFamily: 'monospace'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (paper.collectionName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Collection: ${paper.collectionName}',
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (paper.fileSizeBytes > 0)
                Text(
                  '${(paper.fileSizeBytes / 1024).toStringAsFixed(1)} KB',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
