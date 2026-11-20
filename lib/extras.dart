import 'dart:typed_data';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'store.dart';

// ------------------------------------------------------------------ zoom

class ZoomPage extends StatelessWidget {
  const ZoomPage({super.key, required this.image, required this.page, required this.dark});
  final Future<Uint8List> image;
  final int page;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Scaffold(
      backgroundColor: p.readerBg,
      appBar: AppBar(title: Text('Hal ${page + 1}')),
      body: FutureBuilder<Uint8List>(
        future: image,
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          Widget img = Image.memory(snap.data!, fit: BoxFit.contain);
          final f = pageFilter(Store.paper.value, dark);
          if (f != null) img = ColorFiltered(colorFilter: f, child: img);
          return InteractiveViewer(
            minScale: 1,
            maxScale: 6,
            child: Center(child: img),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text('Cubit dua jari buat perbesar atau perkecil',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.muted)),
        ),
      ),
    );
  }
}

const darkPageFilter = ColorFilter.matrix(<double>[
  -0.78, 0, 0, 0, 225, //
  0, -0.78, 0, 0, 228, //
  0, 0, -0.77, 0, 220, //
  0, 0, 0, 1, 0,
]);

const sepiaPageFilter = ColorFilter.matrix(<double>[
  0.153, 0.516, 0.052, 0, 60, //
  0.159, 0.537, 0.054, 0, 45, //
  0.155, 0.521, 0.053, 0, 30, //
  0, 0, 0, 1, 0,
]);

/// 0/1 = warna asli PDF (default, juga di mode gelap), 2 = sepia, 3 = gelap
int effectivePaper(int mode, bool dark) => mode <= 1 ? 1 : mode;

ColorFilter? pageFilter(int mode, bool dark) {
  switch (effectivePaper(mode, dark)) {
    case 2:
      return sepiaPageFilter;
    case 3:
      return darkPageFilter;
    default:
      return null;
  }
}

Color pageBg(int mode, bool dark) {
  switch (effectivePaper(mode, dark)) {
    case 2:
      return const Color(0xFFF4ECD8);
    case 3:
      return const Color(0xFF1A1C19);
    default:
      return Colors.white;
  }
}

// ------------------------------------------------------------------ grid halaman

enum PageFilter { all, marked, noted }

class PageGridPage extends StatefulWidget {
  const PageGridPage({
    super.key,
    required this.count,
    required this.current,
    required this.thumb,
    required this.marks,
    required this.notedPages,
  });

  final int count;
  final int current;
  final Future<Uint8List> Function(int) thumb;
  final Set<int> marks;
  final Set<int> notedPages;

  @override
  State<PageGridPage> createState() => _PageGridPageState();
}

class _PageGridPageState extends State<PageGridPage> {
  PageFilter _filter = PageFilter.all;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final row = widget.current ~/ 3;
      final w = MediaQuery.of(context).size.width;
      final rowH = (w - 32 - 20) / 3 / 0.7 + 40;
      _scroll.jumpTo((row * rowH).clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pages = [
      for (var i = 0; i < widget.count; i++)
        if (_filter == PageFilter.all ||
            (_filter == PageFilter.marked && widget.marks.contains(i)) ||
            (_filter == PageFilter.noted && widget.notedPages.contains(i)))
          i
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Semua halaman')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<PageFilter>(
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(value: PageFilter.all, label: Text('Semua')),
                  ButtonSegment(
                      value: PageFilter.marked, label: Text('Bertab (${widget.marks.length})')),
                  ButtonSegment(
                      value: PageFilter.noted,
                      label: Text('Ada note (${widget.notedPages.length})')),
                ],
                selected: {_filter},
                onSelectionChanged: (s) => setState(() => _filter = s.first),
              ),
            ),
          ),
          Expanded(
            child: pages.isEmpty
                ? Center(
                    child: Text('Belum ada halaman di sini',
                        style: TextStyle(color: p.muted)))
                : GridView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 14,
                      childAspectRatio: 0.58,
                    ),
                    itemCount: pages.length,
                    itemBuilder: (_, k) {
                      final i = pages[k];
                      final here = i == widget.current;
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => Navigator.pop(context, i),
                        child: Column(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: here ? p.accent : p.line, width: here ? 3 : 1),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    FutureBuilder<Uint8List>(
                                      future: widget.thumb(i),
                                      builder: (_, snap) {
                                        if (!snap.hasData) return const SizedBox();
                                        Widget img = Image.memory(snap.data!, fit: BoxFit.cover);
                                        final f = pageFilter(Store.paper.value, dark);
                                        if (f != null) {
                                          img = ColorFiltered(colorFilter: f, child: img);
                                        }
                                        return img;
                                      },
                                    ),
                                    if (widget.marks.contains(i))
                                      Positioned(
                                        top: 0,
                                        right: 8,
                                        child: Icon(Icons.bookmark_rounded, color: p.accent, size: 22),
                                      ),
                                    if (widget.notedPages.contains(i))
                                      Positioned(
                                        left: 6,
                                        bottom: 6,
                                        child: Container(
                                          width: 18,
                                          height: 18,
                                          decoration: BoxDecoration(
                                            color: Color(noteColors.first),
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('${i + 1}',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: here ? FontWeight.w800 : FontWeight.w600,
                                    color: here ? p.accent : p.text)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ review

class ReviewCard {
  ReviewCard(this.book, this.note);
  final String book;
  final Note note;
}

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.cards, required this.onOpen});
  final List<ReviewCard> cards;
  final void Function(String book, int page) onOpen;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> with SingleTickerProviderStateMixin {
  late final List<ReviewCard> _queue = [...widget.cards]..shuffle();
  late final int _total = _queue.length;
  int _known = 0;
  int _again = 0;
  bool _revealed = false;
  double _drag = 0;

  late final AnimationController _flip =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  void _reveal() {
    if (_revealed) {
      _flip.reverse();
    } else {
      _flip.forward();
    }
    setState(() => _revealed = !_revealed);
  }

  void _answer(bool knew) {
    HapticFeedback.selectionClick();
    setState(() {
      final c = _queue.removeAt(0);
      if (knew) {
        _known++;
      } else {
        _again++;
        _queue.add(c); // diulang di belakang sampai paham
      }
      _revealed = false;
      _drag = 0;
    });
    _flip.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final done = _queue.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review catatan'),
        actions: [
          if (!done)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text('${math.min(_known + 1, _total)} / $_total',
                    style: TextStyle(fontWeight: FontWeight.w700, color: p.muted)),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: _total == 0 ? 1 : _known / _total),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => LinearProgressIndicator(
                    value: v, minHeight: 6, color: p.accent, backgroundColor: p.line),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(child: done ? _summary(p) : _deck(p)),
    );
  }

  Widget _deck(Pal p) {
    final c = _queue.first;
    final next = _queue.length > 1 ? _queue[1] : null;
    return Column(
      children: [
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _pill(p, Icons.check_circle_rounded, '$_known paham', p.accent),
            const SizedBox(width: 8),
            _pill(p, Icons.replay_rounded, '$_again diulang', const Color(0xFFE8772E)),
          ],
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
                child: AspectRatio(
                  aspectRatio: 0.78,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (next != null)
                        Positioned.fill(
                          child: Transform.translate(
                            offset: const Offset(0, 14),
                            child: Transform.scale(
                              scale: 0.94,
                              child: _face(Color(next.note.color).withValues(alpha: 0.55),
                                  const SizedBox()),
                            ),
                          ),
                        ),
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: _reveal,
                          onHorizontalDragUpdate: (d) => setState(() => _drag += d.delta.dx),
                          onHorizontalDragEnd: (d) {
                            final v = d.primaryVelocity ?? 0;
                            if (_drag.abs() > 110 || v.abs() > 700) {
                              _answer((_drag + v / 10) > 0);
                            } else {
                              setState(() => _drag = 0);
                            }
                          },
                          child: AnimatedContainer(
                            duration: Duration(milliseconds: _drag == 0 ? 220 : 0),
                            transform: Matrix4.translationValues(_drag, 0, 0)
                              ..rotateZ(_drag / 1400),
                            transformAlignment: Alignment.bottomCenter,
                            child: AnimatedBuilder(
                              animation: _flip,
                              builder: (_, __) {
                                final t = Curves.easeInOut.transform(_flip.value);
                                final showBack = t > 0.5;
                                final angle = t * math.pi;
                                return Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()
                                    ..setEntry(3, 2, 0.0012)
                                    ..rotateY(angle),
                                  child: showBack
                                      ? Transform(
                                          alignment: Alignment.center,
                                          transform: Matrix4.identity()..rotateY(math.pi),
                                          child: _face(Color(c.note.color), _back(c)),
                                        )
                                      : _face(Color(c.note.color), _front(c)),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      if (_drag.abs() > 30)
                        Positioned(
                          top: 18,
                          left: _drag > 0 ? 18 : null,
                          right: _drag < 0 ? 18 : null,
                          child: _stamp(_drag > 0),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _answer(false),
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text('Masih lupa'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _answer(true),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Udah paham'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _pill(Pal p, IconData icon, String text, Color color) => Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
          ],
        ),
      );

  Widget _stamp(bool knew) => Transform.rotate(
        angle: knew ? -0.2 : 0.2,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: knew ? const Color(0xFF246B43) : const Color(0xFFC2541D),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(knew ? 'PAHAM' : 'ULANG',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        ),
      );

  Widget _face(Color color, Widget child) => Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(8),
            topRight: Radius.circular(8),
            bottomLeft: Radius.circular(8),
            bottomRight: Radius.circular(34),
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x2E000000), blurRadius: 28, offset: Offset(0, 14))
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: child,
      );

  Widget _front(ReviewCard c) => Column(
        children: [
          _bookChip(c),
          const Spacer(),
          const Icon(Icons.psychology_alt_rounded, size: 44, color: Color(0x992B2614)),
          const SizedBox(height: 14),
          const Text('Masih ingat isi catatan ini?',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 21, height: 1.3, fontWeight: FontWeight.w700, color: noteInk)),
          const SizedBox(height: 8),
          Text('Coba jawab dalam hati, lalu ketuk kartu',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: noteInk.withValues(alpha: 0.7))),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.touch_app_rounded, size: 18, color: noteInk.withValues(alpha: 0.6)),
              const SizedBox(width: 6),
              Text('Ketuk buat balik · geser buat jawab',
                  style: TextStyle(fontSize: 12, color: noteInk.withValues(alpha: 0.6))),
            ],
          ),
        ],
      );

  Widget _back(ReviewCard c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bookChip(c),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Text(c.note.text.isEmpty ? '(kosong)' : c.note.text,
                    textAlign: TextAlign.center, style: noteStyle(c.note.font, size: 22)),
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: () => widget.onOpen(c.book, c.note.page),
            style: FilledButton.styleFrom(
              backgroundColor: noteInk,
              foregroundColor: Color(c.note.color),
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.menu_book_rounded, size: 18),
            label: Text('Buka hal ${c.note.page + 1}'),
          ),
        ],
      );

  Widget _bookChip(ReviewCard c) => Align(
        alignment: Alignment.topLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0x1A000000),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text('${Store.title(c.book)} · hal ${c.note.page + 1}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: noteInk)),
        ),
      );

  Widget _summary(Pal p) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.4, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (_, v, child) => Transform.scale(scale: v, child: child),
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
                  child: Icon(Icons.eco_rounded, size: 52, color: p.accent),
                ),
              ),
              const SizedBox(height: 20),
              Text('Review selesai',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: p.text)),
              const SizedBox(height: 8),
              Text(
                _again == 0
                    ? 'Semua $_total catatan langsung paham.'
                    : '$_total catatan beres. $_again kali diulang sampai paham.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, height: 1.5),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                child: const Text('Selesai'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
