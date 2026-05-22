import 'package:flutter/material.dart';

class CustomSearchDropdown extends StatelessWidget {
  final List<String> suggestions;
  final Function(String) onSelected;
  final double width;

  const CustomSearchDropdown({
    super.key,
    required this.suggestions,
    required this.onSelected,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        constraints: const BoxConstraints(maxHeight: 250),
        margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1A3F),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ListView.separated(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: suggestions.length,
            separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
            itemBuilder: (context, index) {
              final suggestion = suggestions[index];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.search, color: Colors.white24, size: 18),
                title: Text(
                  suggestion,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                onTap: () => onSelected(suggestion),
                hoverColor: Colors.white10,
              );
            },
          ),
        ),
      ),
    );
  }
}
