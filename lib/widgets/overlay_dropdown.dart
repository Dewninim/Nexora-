import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'teacher_app_shell.dart';

class OverlayDropdown<T> extends StatefulWidget {
  final Widget child;
  final List<T> items;
  final T selected;
  final String Function(T item) label;
  final ValueChanged<T> onChanged;

  const OverlayDropdown({
    super.key,
    required this.child,
    required this.items,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  @override
  State<OverlayDropdown<T>> createState() => _OverlayDropdownState<T>();
}

class _OverlayDropdownState<T> extends State<OverlayDropdown<T>> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _remove();
    super.dispose();
  }

  void _toggle() {
    if (_entry != null) {
      _remove();
    } else {
      _show();
    }
  }

  void _show() {
    final overlay = Overlay.of(context);
    if (overlay == null) return;

    _entry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            // tap outside
            Positioned.fill(
              child: GestureDetector(
                onTap: _remove,
                behavior: HitTestBehavior.translucent,
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              offset: const Offset(0, 56),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 260,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6E6E6).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final item in widget.items)
                        _OverlayDropdownItem(
                          label: widget.label(item),
                          selected: item == widget.selected,
                          onTap: () {
                            widget.onChanged(item);
                            _remove();
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_entry!);
  }

  void _remove() {
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(999),
        child: widget.child,
      ),
    );
  }
}

class _OverlayDropdownItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OverlayDropdownItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFCCCCCC) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Text(
          label,
          style: GoogleFonts.openSans(
            color: neuromathixText,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
