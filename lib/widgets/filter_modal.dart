import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/resource_service.dart';
import '../providers/upload_provider.dart';

class FilterModal extends ConsumerStatefulWidget {
  final Map<String, String> initialFilters;
  final Function(Map<String, String>) onApply;

  const FilterModal({
    super.key,
    required this.initialFilters,
    required this.onApply,
  });

  @override
  ConsumerState<FilterModal> createState() => _FilterModalState();
}

class _FilterModalState extends ConsumerState<FilterModal> {
  late Map<String, String> _filters;
  final TextEditingController _lecturerController = TextEditingController();
  final TextEditingController _programController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filters = Map.from(widget.initialFilters);
    _lecturerController.text = _filters['lecturer'] ?? '';
    _programController.text = _filters['courseProgram'] ?? '';
  }

  @override
  void dispose() {
    _lecturerController.dispose();
    _programController.dispose();
    super.dispose();
  }

  List<String> _getYearOptions() {
    final currentYear = DateTime.now().year;
    return List.generate(
      currentYear - 2020 + 1,
      (index) => (currentYear - index).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final courseService = ref.watch(courseServiceProvider);
    
    // Combine lecturers from course data and current resources
    final allLecturers = {
      ...courseService.lecturersList,
      ...ResourceService().getUniqueLecturers(),
    }.where((l) => l.isNotEmpty).toList();
    allLecturers.sort();

    // Combine programs from course data and current resources
    final allPrograms = {
      ...courseService.programsList,
      ...ResourceService().getUniquePrograms(),
    }.where((p) => p.isNotEmpty).toList();
    allPrograms.sort();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF141232),
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: Column(
            children: [
              // Fixed Header with Handle
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Filter Materials',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close, color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),

              // Scrollable Filter Sections
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Select Criteria',
                          style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _filters = {};
                              _lecturerController.clear();
                              _programController.clear();
                            });
                          },
                          child: const Text('Reset All', style: TextStyle(color: Color(0xFF20C8FF), fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    _buildSlidingFilterSection('Year of Publication', _getYearOptions(), 'publicationYear'),
                    
                    _buildSearchFilterSection(
                      'Search Lecturer', 
                      'Type lecturer name...', 
                      _lecturerController, 
                      'lecturer',
                      allLecturers,
                    ),

                    _buildSearchFilterSection(
                      'Search Course Program', 
                      'Type program name...', 
                      _programController, 
                      'courseProgram',
                      allPrograms,
                    ),

                    _buildFilterSection('Year of Study', ['1st Year', '2nd Year', '3rd Year', '4th Year'], 'yearOfStudy'),
                    _buildFilterSection('Semester', ['Semester 1', 'Semester 2'], 'semester'),
                  ],
                ),
              ),

              // Floating Apply Button
              Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 20),
                child: GestureDetector(
                  onTap: () {
                    widget.onApply(_filters);
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF20C8FF),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF20C8FF).withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'Apply Filters',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSlidingFilterSection(String title, List<String> options, String key) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: options.map((option) {
              final isSelected = _filters[key] == option;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _filters.remove(key);
                      } else {
                        _filters[key] = option;
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF20C8FF).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF20C8FF) : Colors.white10,
                      ),
                    ),
                    child: Text(
                      option,
                      style: TextStyle(
                        color: isSelected ? const Color(0xFF20C8FF) : Colors.white54,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSearchFilterSection(String title, String hint, TextEditingController controller, String key, List<String> allOptions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        Autocomplete<String>(
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text == '') {
              return const Iterable<String>.empty();
            }
            return allOptions.where((String option) {
              return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
            });
          },
          onSelected: (String selection) {
            setState(() {
              _filters[key] = selection;
              controller.text = selection;
            });
          },
          fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
            return TextField(
              controller: textController,
              focusNode: focusNode,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: const Icon(Icons.search, color: Colors.white24, size: 18),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            //Suggestions pop up with their own scroll view to avoid keyboard issues
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(context).size.width - 40,
                  constraints: const BoxConstraints(maxHeight: 180),
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1A3F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10)
                    ],
                  ),
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final String option = options.elementAt(index);
                      return ListTile(
                        title: Text(option, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildFilterSection(String title, List<String> options, String key) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((option) {
            final isSelected = _filters[key] == option;
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _filters.remove(key);
                  } else {
                    _filters[key] = option;
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF20C8FF).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF20C8FF) : Colors.white10,
                  ),
                ),
                child: Text(
                  option,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFF20C8FF) : Colors.white54,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
