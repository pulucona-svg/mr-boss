import 'package:flutter/material.dart';

Widget glassCard({
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.all(14),
}) {
  return Container(
    padding: padding,
    decoration: BoxDecoration(
      color: const Color(0xFF181739).withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFF302B65)),
    ),
    child: child,
  );
}
