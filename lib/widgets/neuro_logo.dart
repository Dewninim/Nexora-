import 'package:flutter/material.dart';

class NeuroMathixLogo extends StatelessWidget {
  final bool white;
  final double iconSize;
  final double titleSize;
  final bool showSubtitle;

  const NeuroMathixLogo({
    super.key,
    this.white = false,
    this.iconSize = 28,
    this.titleSize = 22,
    this.showSubtitle = true,
  });

  @override
  Widget build(BuildContext context) {
    final fg = white ? Colors.white : const Color(0xFF111827);
    final sub = white ? Colors.white70 : const Color(0xFF6B7280);
    final bg = white
        ? Colors.white.withValues(alpha: 0.12)
        : const Color(0xFFE0E7FF);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: iconSize + 18,
          height: iconSize + 18,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.psychology_alt_rounded, size: iconSize, color: fg),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NeuroMathix',
              style: TextStyle(
                color: fg,
                fontSize: titleSize,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
            if (showSubtitle)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  'AI-Powered Learning',
                  style: TextStyle(
                    color: sub,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
