import 'package:flutter/material.dart';
import '../widgets/category_chip.dart';
import '../widgets/resource_card.dart';
import '../services/download_service.dart';
import '../services/resource_service.dart';
import '../widgets/filter_modal.dart';
import '../services/notification_service.dart';
import '../widgets/notification_modal.dart';
import '../widgets/ad_carousel.dart';
import '../widgets/upload_bottom_sheet.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _selectedCategory = 'All';
  final TextEditingController _searchController = TextEditingController();
  Map<String, String> _activeFilters = {};
  bool _isDownloadsSelected = true;

  void _showNotifications() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NotificationModal(),
    );
  }

  void _showUploadDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const UploadBottomSheet(),
    );
  }

  void _showFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FilterModal(
        initialFilters: _activeFilters,
        onApply: (filters) {
          setState(() {
            _activeFilters = filters;
          });
        },
      ),
    );
  }

  void _resetAllFilters() {
    setState(() {
      _activeFilters = {};
      _selectedCategory = 'All';
      _searchController.clear();
    });
  }

  final List<Map<String, dynamic>> _categoryData = [
    {'label': 'All', 'color': Color(0xFF287BFF), 'icon': Icons.grid_view_rounded},
    {'label': 'Notes', 'color': Color(0xFF00A85A), 'icon': Icons.description_rounded},
    {'label': 'CATs', 'color': Color(0xFFFF8A00), 'icon': Icons.assignment_rounded},
    {'label': 'Exams', 'color': Color(0xFF7D46FF), 'icon': Icons.history_edu_rounded},
    {'label': 'Time tables', 'color': Color(0xFF00D1FF), 'icon': Icons.calendar_month_rounded},
    {'label': 'Prac Manual', 'color': Color(0xFFFF4667), 'icon': Icons.biotech_rounded},
    {'label': 'Supplementary Exams', 'color': Color(0xFF00B4D8), 'icon': Icons.auto_stories_rounded},
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([DownloadService(), ResourceService()]),
      builder: (context, child) {
        final downloadedTitles = DownloadService().downloadedResources.map((r) => r['title']).toSet();
        final allResources = ResourceService().allResources;
        final userUploads = ResourceService().userUploads;
        
        final baseResources = _isDownloadsSelected 
            ? allResources.where((res) => downloadedTitles.contains(res.title)).toList()
            : userUploads;
        
        final filteredResources = baseResources.where((res) {
          final matchesCategory = _selectedCategory == 'All' || res.type == _selectedCategory;
          final matchesSearch = res.title.toLowerCase().contains(_searchController.text.toLowerCase());
          
          bool matchesFilters = true;
          _activeFilters.forEach((key, value) {
            if (key == 'publicationYear' && res.publicationYear != value) matchesFilters = false;
            if (key == 'yearOfStudy' && res.yearOfStudy != value) matchesFilters = false;
            if (key == 'semester' && res.semester != value) matchesFilters = false;
            if (key == 'lecturer' && res.lecturer != value) matchesFilters = false;
            if (key == 'courseProgram' && res.courseProgram != value) matchesFilters = false;
          });

          return matchesCategory && matchesSearch && matchesFilters;
        }).toList();

        final hasActiveFilters = _activeFilters.isNotEmpty || _selectedCategory != 'All' || _searchController.text.isNotEmpty;

        return PopScope(
          canPop: !hasActiveFilters,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _resetAllFilters();
          },
          child: GestureDetector(
            onTap: () => ResourceService().setActiveResource(null),
            behavior: HitTestBehavior.opaque,
            child: Scaffold(
              backgroundColor: Colors.transparent,
            floatingActionButton: !_isDownloadsSelected ? FloatingActionButton(
              onPressed: _showUploadDialog,
              backgroundColor: const Color(0xFF00A85A),
              child: const Text('➕', style: TextStyle(fontSize: 24)),
            ) : null,
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF140C37), Color(0xFF070716)],
                ),
              ),
              child: SafeArea(
                child: CustomScrollView(
                  key: const PageStorageKey('library_scroll'),
                  slivers: [
                    SliverToBoxAdapter(                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Library', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700)),
                                ListenableBuilder(
                                  listenable: NotificationService(),
                                  builder: (context, child) {
                                    final unreadCount = NotificationService().unreadCount;
                                    return Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        IconButton(
                                          onPressed: _showNotifications,
                                          icon: const Text('🔔', style: TextStyle(fontSize: 24)),
                                        ),
                                        if (unreadCount > 0)
                                          Positioned(
                                            top: 8,
                                            right: 8,
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                              child: Text(
                                                unreadCount > 9 ? '9+' : unreadCount.toString(),
                                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          const SizedBox(height: 8),
                          AdCarousel(
                            interval: const Duration(seconds: 8),
                            ads: [
                              {
                                'type': 'image',
                                'isAsset': true,
                                'title': 'Davy Cybers 💻',
                                'subtitle': 'In need of professional cyber services? Worry no more, Davy Cybers we have got you.',
                                'url': 'assets/ad_cyber.jpeg',
                                'color': const Color(0xFF20C8FF),
                              },
                              {
                                'type': 'image',
                                'isAsset': true,
                                'title': 'Manu Data 🌐',
                                'subtitle': 'Tired of expensive data plans? Worry no more, Manu Data Solutions we have got you.',
                                'url': 'assets/ad_data.jpeg',
                                'color': const Color(0xFF00A85A),
                              },
                              {
                                'type': 'image',
                                'isAsset': true,
                                'title': 'Snake Light 💡',
                                'subtitle': 'In need of snake light? Say less, we got you with a discount.',
                                'url': 'assets/ad_snake.jpeg',
                                'color': const Color(0xFFFF8A00),
                              },
                              {
                                'type': 'video',
                                'title': 'Industrial Power 🏗️',
                                'subtitle': 'Smart factories and the future of automated manufacturing.',
                                'url': 'https://assets.mixkit.co/videos/preview/mixkit-industrial-robot-arms-moving-in-a-factory-42468-large.mp4',
                                'color': const Color(0xFF7D46FF),
                              },
                              {
                                'type': 'video',
                                'title': 'Electric Motion 🏎️',
                                'subtitle': 'The electric revolution in high-performance vehicles.',
                                'url': 'https://assets.mixkit.co/videos/preview/mixkit-blue-sports-car-racing-on-a-track-40243-large.mp4',
                                'color': const Color(0xFFFF4667),
                              },
                            ],
                          ),
                          const SizedBox(height: 18),
                          const Text('Your offline academic hub.', style: TextStyle(color: Color(0xFFC9CBF2), fontSize: 16)),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  textCapitalization: TextCapitalization.sentences,
                                  onChanged: (value) => setState(() {}),
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText: _isDownloadsSelected ? 'Search downloaded units' : 'Search your uploads',
                                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                                    prefixIcon: const Icon(Icons.search, color: Color(0xFF24C7FF)),
                                    filled: true,
                                    fillColor: const Color(0xFF181739).withValues(alpha: 0.72),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF302B65))),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF302B65))),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: () => setState(() {}),
                                child: Container(
                                  height: 56,
                                  width: 56,
                                  decoration: BoxDecoration(color: const Color(0xFF00A85A), borderRadius: BorderRadius.circular(16)),
                                  child: const Center(child: Text('🔍', style: TextStyle(fontSize: 20))),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            clipBehavior: Clip.none,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: _categoryData.map((data) {
                                  final String label = data['label'];
                                  final Color color = data['color'];
                                  final IconData icon = data['icon'];
                                  final isSelected = _selectedCategory == label;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 12.0),
                                    child: GestureDetector(
                                      onTap: () => setState(() => _selectedCategory = label),
                                      child: CategoryChip(label: label, color: color, icon: icon, isActive: isSelected),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _showFilters,
                              icon: Icon(Icons.tune, color: _activeFilters.isNotEmpty ? const Color(0xFF00A85A) : const Color(0xFF24C7FF)),
                              label: Text(
                                _activeFilters.isNotEmpty ? 'Filters Active (${_activeFilters.length})' : 'Filter',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16)),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Toggle Switch
                          Container(
                            height: 50,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A2E),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(() => _isDownloadsSelected = true),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: _isDownloadsSelected ? const Color(0xFF00A85A) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(21),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'Downloads',
                                          style: TextStyle(
                                            color: _isDownloadsSelected ? Colors.white : Colors.white60,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(() => _isDownloadsSelected = false),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: !_isDownloadsSelected ? const Color(0xFF00A85A) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(21),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'Uploads',
                                          style: TextStyle(
                                            color: !_isDownloadsSelected ? Colors.white : Colors.white60,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Section Header with lines
                          Row(
                            children: [
                              const Expanded(child: Divider(color: Colors.white12, thickness: 1)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  _isDownloadsSelected ? 'DOWNLOADS' : 'UPLOADS',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ),
                              const Expanded(child: Divider(color: Colors.white12, thickness: 1)),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                  if (filteredResources.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isDownloadsSelected ? Icons.download_for_offline_outlined : Icons.cloud_off_rounded,
                              color: Colors.white10,
                              size: 64,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _isDownloadsSelected 
                                  ? 'No materials match your filters'
                                  : 'You haven\'t uploaded any materials yet',
                              style: const TextStyle(color: Colors.white24, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.8,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final res = filteredResources[index];
                            return ResourceCard(
                              title: res.title,
                              type: res.type,
                              materialFormat: res.materialFormat,
                              thumbnailUrl: res.thumbnailUrl,                              unitName: res.unitName,
                              unitCode: res.unitCode,
                              year: res.year,
                              uploadYear: res.uploadYear,
                              publicationYear: res.publicationYear,
                              yearOfStudy: res.yearOfStudy,
                              semester: res.semester,
                              lecturer: res.lecturer,
                              uploadedBy: res.uploadedBy,
                              uploaderRole: res.uploaderRole,
                              views: res.views.toString(),
                              likes: res.likes.toString(),
                              comments: res.comments.toString(),
                              isLiked: res.isLiked,
                              showDownload: false,
                              status: !_isDownloadsSelected ? res.status : null,
                              declineReason: !_isDownloadsSelected ? res.declineReason : null,
                              onLikeToggle: () => ResourceService().toggleLike(res.title),
                              onViewIncrement: () => ResourceService().incrementViews(res.title),
                              onTap: () {},
                            );
                          },
                          childCount: filteredResources.length,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  },
);
}
}
