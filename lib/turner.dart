import 'package:flutter/material.dart';

/// Pindah halaman dengan geser simpel ke samping (ala Google Books).
/// Index `count` = halaman penutup ([endPage]).
class PageTurner extends StatefulWidget {
  const PageTurner({
    super.key,
    required this.count,
    required this.initial,
    required this.pageBuilder,
    required this.endPage,
    required this.paper,
    required this.onChanged,
    this.enabled = true,
  });

  final int count;
  final int initial;
  final Widget Function(int) pageBuilder;
  final Widget endPage;
  final Color paper;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  State<PageTurner> createState() => _PageTurnerState();
}

class _PageTurnerState extends State<PageTurner> {
  late final PageController _c =
      PageController(initialPage: widget.initial.clamp(0, widget.count));

  static const _dur = Duration(milliseconds: 280);
  static const _curve = Curves.easeOutCubic;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _tapUp(TapUpDetails d, double width) {
    if (!widget.enabled) return;
    final x = d.localPosition.dx / width;
    if (x > 0.78) {
      _c.nextPage(duration: _dur, curve: _curve);
    } else if (x < 0.22) {
      _c.previousPage(duration: _dur, curve: _curve);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, box) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (d) => _tapUp(d, box.maxWidth),
        child: PageView.builder(
          controller: _c,
          allowImplicitScrolling: true, // halaman sebelah sudah disiapkan, nggak kedip
          physics: widget.enabled
              ? const PageScrollPhysics(parent: ClampingScrollPhysics())
              : const NeverScrollableScrollPhysics(),
          itemCount: widget.count + 1,
          onPageChanged: widget.onChanged,
          itemBuilder: (_, i) => RepaintBoundary(
            child: i >= widget.count ? widget.endPage : widget.pageBuilder(i),
          ),
        ),
      ),
    );
  }
}
