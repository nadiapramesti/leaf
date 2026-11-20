import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Pindah halaman. [style] 0 = buka lembaran (lipatan tegak), 1 = geser.
/// Index `count` = halaman penutup ([endPage]).
class PageTurner extends StatelessWidget {
  const PageTurner({
    super.key,
    required this.count,
    required this.initial,
    required this.pageBuilder,
    required this.endPage,
    required this.paper,
    required this.onChanged,
    this.enabled = true,
    this.style = 0,
  });

  final int count;
  final int initial;
  final Widget Function(int) pageBuilder;
  final Widget endPage;
  final Color paper;
  final ValueChanged<int> onChanged;
  final bool enabled;
  final int style;

  @override
  Widget build(BuildContext context) {
    if (style == 1) {
      return _SlideTurner(
        count: count,
        initial: initial,
        pageBuilder: pageBuilder,
        endPage: endPage,
        paper: paper,
        onChanged: onChanged,
        enabled: enabled,
      );
    }
    return _FoldTurner(
      count: count,
      initial: initial,
      pageBuilder: pageBuilder,
      endPage: endPage,
      paper: paper,
      onChanged: onChanged,
      enabled: enabled,
    );
  }
}

class _FoldTurner extends StatefulWidget {
  const _FoldTurner({
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
  State<_FoldTurner> createState() => _FoldTurnerState();
}

class _FoldTurnerState extends State<_FoldTurner> with SingleTickerProviderStateMixin {
  late int _cur = widget.initial.clamp(0, widget.count);
  int? _turn; // halaman yang sedang dilipat; di bawahnya _turn + 1
  bool _forward = true;
  Offset _corner = Offset.zero;
  Offset? _p; // titik sudut kertas yang ditarik
  Size _size = Size.zero;

  late final AnimationController _ac =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  Animation<Offset>? _anim;
  VoidCallback? _onDone;

  int get _last => widget.count; // halaman penutup

  @override
  void initState() {
    super.initState();
    _ac.addListener(() {
      final a = _anim;
      if (a != null) setState(() => _p = a.value);
    });
    _ac.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        final done = _onDone;
        _onDone = null;
        _anim = null;
        done?.call();
      }
    });
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  Widget _page(int i) => i >= widget.count ? widget.endPage : widget.pageBuilder(i);

  Offset _map(Offset local) {
    final w = _size.width, h = _size.height;
    final x = (local.dx * 2 - w).clamp(-w, w);
    // lipatan selalu tegak: tinggi titik tarik dikunci
    return Offset(x, h / 2);
  }

  Offset get _flat => _corner;
  Offset get _turned => Offset(-_size.width, _corner.dy);

  void _begin(bool forward, double y) {
    _forward = forward;
    _turn = forward ? _cur : _cur - 1;
    _corner = Offset(_size.width, _size.height / 2);
  }

  void _animate(Offset to, VoidCallback done) {
    final from = _p ?? to;
    final dist = (to - from).distance / (_size.width * 2);
    _ac.duration = Duration(milliseconds: (220 + 260 * dist).round());
    _anim = Tween(begin: from, end: to)
        .chain(CurveTween(curve: Curves.easeOutCubic))
        .animate(_ac);
    _onDone = done;
    _ac.forward(from: 0);
  }

  void _finish(int newCur) {
    setState(() {
      _cur = newCur;
      _turn = null;
      _p = null;
    });
    widget.onChanged(newCur);
  }

  // ------------------------------------------------------------ gestur

  bool get _busy => _ac.isAnimating;

  void _panStart(DragStartDetails d) {
    if (!widget.enabled || _busy) return;
    final x = d.localPosition.dx;
    if (x > _size.width * 0.5 && _cur < _last) {
      _begin(true, d.localPosition.dy);
    } else if (x <= _size.width * 0.5 && _cur > 0) {
      _begin(false, d.localPosition.dy);
    } else {
      return;
    }
    setState(() => _p = _map(d.localPosition));
  }

  void _panUpdate(DragUpdateDetails d) {
    if (_turn == null || _busy) return;
    setState(() => _p = _map(d.localPosition));
  }

  void _panEnd(DragEndDetails d) {
    if (_turn == null || _busy || _p == null) return;
    final v = d.velocity.pixelsPerSecond.dx;
    final t = _turn!;
    if (_forward) {
      final go = _p!.dx < 0 || v < -500;
      go ? _animate(_turned, () => _finish(t + 1)) : _animate(_flat, () => _finish(t + 1 - 1));
    } else {
      final go = _p!.dx > 0 || v > 500;
      go ? _animate(_flat, () => _finish(t)) : _animate(_turned, () => _finish(t + 1));
    }
  }

  void _tapUp(TapUpDetails d) {
    if (!widget.enabled || _busy || _turn != null) return;
    final x = d.localPosition.dx / _size.width;
    if (x > 0.78 && _cur < _last) {
      _begin(true, _size.height);
      _p = _flat;
      final t = _turn!;
      _animate(_turned, () => _finish(t + 1));
    } else if (x < 0.22 && _cur > 0) {
      _begin(false, _size.height);
      _p = _turned;
      final t = _turn!;
      _animate(_flat, () => _finish(t));
    }
  }

  // ------------------------------------------------------------ geometri

  /// potong poligon dengan setengah bidang f(x) >= 0
  static List<Offset> _clip(List<Offset> poly, double Function(Offset) f) {
    final out = <Offset>[];
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      final fa = f(a), fb = f(b);
      if (fa >= 0) out.add(a);
      if ((fa >= 0) != (fb >= 0)) out.add(Offset.lerp(a, b, fa / (fa - fb))!);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, box) {
      _size = Size(box.maxWidth, box.maxHeight);
      final w = _size.width, h = _size.height;

      List<Offset>? keep; // bagian halaman atas yang masih rata
      _Fold? fold;
      final turning = _turn != null && _p != null;
      if (turning) {
        final c = _corner, p = _p!;
        final d = p - c;
        if (d.distance < 0.5) {
          keep = null;
        } else {
          final m = (c + p) / 2;
          final n = d / d.distance;
          double f(Offset x) => (x - m).dx * n.dx + (x - m).dy * n.dy;
          final rect = [Offset.zero, Offset(w, 0), Offset(w, h), Offset(0, h)];
          keep = _clip(rect, f);
          final removed = _clip(rect, (x) => -f(x));
          final flap = [for (final x in removed) x - n * (2 * f(x))];
          fold = _Fold(m: m, n: n, depth: d.distance / 2, removed: removed, flap: flap, keep: keep);
        }
      }

      // urutan tetap & ber-key supaya halaman nggak dimuat ulang (nggak kedip)
      final topIdx = turning ? _turn! : _cur;
      final ids = <int>[
        if (topIdx + 1 <= _last) topIdx + 1,
        topIdx,
        if (!turning && _cur - 1 >= 0) _cur - 1,
      ];
      // halaman yang ikut dirender tapi belum kelihatan: sebelumnya (disembunyikan)
      final children = <Widget>[
        for (final i in ids)
          KeyedSubtree(
            key: ValueKey(i),
            child: ClipPath(
              clipper: _PolyClip(i == topIdx ? keep : (i < topIdx ? const [] : null)),
              child: RepaintBoundary(child: _page(i)),
            ),
          ),
      ];

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _panStart,
        onHorizontalDragUpdate: _panUpdate,
        onHorizontalDragEnd: _panEnd,
        onTapUp: _tapUp,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          fit: StackFit.expand,
          children: [
            ...children,
            if (fold != null)
              IgnorePointer(child: CustomPaint(painter: _FoldPainter(fold, widget.paper))),
          ],
        ),
      );
    });
  }
}

class _Fold {
  _Fold({
    required this.m,
    required this.n,
    required this.depth,
    required this.removed,
    required this.flap,
    required this.keep,
  });
  final Offset m, n;
  final double depth;
  final List<Offset> removed, flap;
  final List<Offset>? keep;
}

class _PolyClip extends CustomClipper<Path> {
  const _PolyClip(this.poly);
  final List<Offset>? poly; // null = penuh, [] = sembunyi

  @override
  Path getClip(Size size) {
    if (poly == null) return Path()..addRect(Offset.zero & size);
    if (poly!.length < 3) return Path();
    return Path()..addPolygon(poly!, true);
  }

  @override
  bool shouldReclip(covariant _PolyClip old) => true;
}

class _FoldPainter extends CustomPainter {
  _FoldPainter(this.f, this.paper);
  final _Fold f;
  final Color paper;

  @override
  void paint(Canvas canvas, Size size) {
    final spread = math.min(28.0, 8 + f.depth * 0.2);

    // bayangan di halaman bawah, dekat lipatan
    if (f.removed.length >= 3) {
      canvas.save();
      canvas.clipPath(Path()..addPolygon(f.removed, true));
      final g = ui.Gradient.linear(f.m, f.m - f.n * spread,
          [const Color(0x38000000), const Color(0x00000000)]);
      canvas.drawRect(Offset(-size.width, -size.height) & (size * 3), Paint()..shader = g);
      canvas.restore();
    }

    // bayangan tipis di halaman atas dekat lipatan
    final keep = f.keep;
    if (keep != null && keep.length >= 3) {
      canvas.save();
      canvas.clipPath(Path()..addPolygon(keep, true));
      final g = ui.Gradient.linear(f.m, f.m + f.n * spread * 0.7,
          [const Color(0x1A000000), const Color(0x00000000)]);
      canvas.drawRect(Offset(-size.width, -size.height) & (size * 3), Paint()..shader = g);
      canvas.restore();
    }

    // punggung kertas yang terlipat
    if (f.flap.length >= 3) {
      final path = Path()..addPolygon(f.flap, true);
      canvas.drawShadow(path, Colors.black, 3, false);
      final lum = paper.computeLuminance();
      final edge = lum > 0.5
          ? Color.lerp(paper, Colors.black, 0.10)!
          : Color.lerp(paper, Colors.white, 0.10)!;
      final mid = lum > 0.5 ? Colors.white : Color.lerp(paper, Colors.white, 0.04)!;
      final g = ui.Gradient.linear(
        f.m,
        f.m + f.n * math.max(1.0, f.depth),
        [edge, mid, Color.lerp(paper, Colors.black, lum > 0.5 ? 0.05 : 0.0)!],
        [0.0, 0.35, 1.0],
      );
      canvas.drawPath(path, Paint()..shader = g);
    }
  }

  @override
  bool shouldRepaint(covariant _FoldPainter old) => true;
}

class _SlideTurner extends StatefulWidget {
  const _SlideTurner({
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
  State<_SlideTurner> createState() => _SlideTurnerState();
}

class _SlideTurnerState extends State<_SlideTurner> {
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
