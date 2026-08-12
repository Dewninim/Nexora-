import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color _accentBlue  = Color(0xFF1B63E8);
const Color _textPrimary = Color(0xFF0F172A);
const Color _textSub     = Color(0xFF64748B);
const Color _border      = Color(0xFFE2E8F0);

class UploadFeatureCards extends StatelessWidget {
  const UploadFeatureCards({super.key});

  static const _data = [
    _CardData(Icons.auto_awesome_rounded, Color(0xFF6366F1), Color(0xFFEEF2FF),
        'Smart Math Understanding',
        'Advanced AI that deciphers complex formulas, handwritten equations, and word problems across Grades 6–11 with high precision.'),
    _CardData(Icons.route_rounded, Color(0xFF0EA5E9), Color(0xFFE0F2FE),
        'Personalized Learning Path',
        'Every student learns differently. We break down content into custom steps tailored precisely to your unique grade level and speed.'),
    _CardData(Icons.emoji_events_rounded, Color(0xFFF59E0B), Color(0xFFFEF3C7),
        'Meaningful Practice',
        'Instead of simple repetition, we offer insightful feedback that builds deep conceptual clarity and lasting mathematical confidence.'),
  ];

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 760;
    if (narrow) {
      return Column(
          children: _data
              .map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _Card(d: d)))
              .toList());
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _data
          .map((d) => Expanded(
                child: Padding(
                  padding:
                      EdgeInsets.only(right: d == _data.last ? 0 : 14),
                  child: _Card(d: d),
                ),
              ))
          .toList(),
    );
  }
}

class _CardData {
  final IconData icon;
  final Color iconColor, iconBg;
  final String title, desc;
  const _CardData(
      this.icon, this.iconColor, this.iconBg, this.title, this.desc);
}

class _Card extends StatefulWidget {
  final _CardData d;
  const _Card({required this.d});
  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit:  (_) => setState(() => _hov = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: _hov
                  ? _accentBlue.withOpacity(0.3)
                  : _border),
          boxShadow: [
            BoxShadow(
              color: _hov
                  ? _accentBlue.withOpacity(0.1)
                  : Colors.black.withOpacity(0.05),
              blurRadius: _hov ? 20 : 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: widget.d.iconBg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(widget.d.icon,
                  size: 19, color: widget.d.iconColor),
            ),
            const SizedBox(height: 12),
            Text(widget.d.title,
                style: GoogleFonts.openSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                    height: 1.3)),
            const SizedBox(height: 6),
            Text(widget.d.desc,
                style: GoogleFonts.openSans(
                    fontSize: 12, color: _textSub, height: 1.55)),
          ],
        ),
      ),
    );
  }
}
