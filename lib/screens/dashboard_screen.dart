import 'package:flutter/material.dart';
import '../widgets/category_chip.dart';
import '../widgets/resource_card.dart';
import '../widgets/ad_carousel.dart';
import '../services/notification_service.dart';
import '../widgets/notification_modal.dart';
import '../services/resource_service.dart';
import '../widgets/filter_modal.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _selectedCategory = 'All';
  final TextEditingController _searchController = TextEditingController();
  Map<String, String> _activeFilters = {};

  void _showNotifications() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NotificationModal(),
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
      listenable: ResourceService(),
      builder: (context, child) {
        final allResources = ResourceService().allResources;
        final filteredResources = allResources.where((res) {
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
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF140C37), Color(0xFF070716)],
              ),
            ),
            child: SafeArea(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const SizedBox(),
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
                        const Text('Dashboard', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        const Text('Find your academic edge.', style: TextStyle(color: Color(0xFFC9CBF2))),
                        const SizedBox(height: 20),
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
                                    child: CategoryChip(label: label, icon: icon, color: color, isActive: isSelected),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onChanged: (value) => setState(() {}),
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Search unit code',
                                  hintStyle: const TextStyle(color: Colors.grey),
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
                        const AdCarousel(),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            const Expanded(child: Divider(color: Colors.white12, thickness: 1)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text('FOR YOU', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2)),
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
                  const SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded, color: Colors.white10, size: 64),
                          SizedBox(height: 16),
                          Text('No materials match your filters', style: TextStyle(color: Colors.white24, fontSize: 16)),
                          SizedBox(height: 8),
                          TextButton(onPressed: null, child: Text('Try resetting filters', style: TextStyle(color: Color(0xFF20C8FF)))),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.8),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final res = filteredResources[index];
                          return ResourceCard(
                            title: res.title,
                            type: res.type,
                            thumbnailUrl: res.thumbnailUrl,
                            unitName: res.unitName,
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
      );
    },
  );
}
}
