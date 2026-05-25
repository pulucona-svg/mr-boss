import 'package:flutter/material.dart';

class CustomSearchDropdown extends StatelessWidget {
  final List<String> suggestions;
  final String query;
  final Function(String) onSelected;
  final double width;

  const CustomSearchDropdown({
    super.key,
    required this.suggestions,
    required this.query,
    required this.onSelected,
    required this.width,
  });

  Widget _buildRichText(String text, String highlight, BuildContext context) {
    if (highlight.isEmpty) return Text(text, style: const TextStyle(color: Colors.white, fontSize: 14));
    
    final lowerText = text.toLowerCase();
    final lowerHighlight = highlight.toLowerCase();
    
    if (!lowerText.contains(lowerHighlight)) {
      return Text(text, style: const TextStyle(color: Colors.white, fontSize: 14));
    }
    
    final List<TextSpan> spans = [];
    int start = 0;
    int index = lowerText.indexOf(lowerHighlight);
    
    while (index != -1) {
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(TextSpan(
        text: text.substring(index, index + highlight.length),
        style: const TextStyle(color: Color(0xFF24C7FF), fontWeight: FontWeight.bold),
      ));
      start = index + highlight.length;
      index = lowerText.indexOf(lowerHighlight, start);
    }
    
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.white, fontSize: 14),
        children: spans,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        constraints: const BoxConstraints(maxHeight: 280),
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
                title: _buildRichText(suggestion, query, context),
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
