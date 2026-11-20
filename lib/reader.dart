import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:page_flip/page_flip.dart';
import 'package:pdfx/pdfx.dart';

import 'sheets.dart';
import 'store.dart';

enum Mode { read, pen, highlight }

// halaman terang -> gelap hangat waktu mode gelap
const _darkPage = ColorFilter.matrix(<double>[
  -0.78, 0, 0, 0, 225, //
  0, -0.78, 0, 0, 228, //
  0, 0, -0.77, 0, 220, //
  0, 0, 0, 1, 0,
]);

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.path, this.openAt});
  final String path;
  final int? openAt;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  PdfDocument? _doc;
  String? _error;
  int _count = 0;
  int _current = 0;
  int _startIndex = 0;
  int _flipVersion = 0;
  double _ratio = 0.707; // lebar / tinggi halaman
  List<Widget> _pages = const [];
  final Map<int, Future<Uint8List>> _cache = {};
  Future<void> _lock = Future.value();

  List<Note> _notes = [];
  Set<int> _marks = {};
  List<InkStroke> _ink = [];

  Mode _mode = Mode.read;
  bool _stylusSeen = false;
  InkStroke? _live;
  int? _livePointer;
  double? _slide;
  Size _pageSize = Size.zero;

  String get _path => widget.path;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final doc = await PdfDocument.openFile(_path);
      final first = await doc.getPage(1);
      final ratio = first.width / first.height;
      await first.close();
      final count = doc.pagesCount;
      Store.setPageCount(_path, count);
      final start = (widget.openAt ?? Store.lastPage(_path)).clamp(0, count - 1);
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _count = count;
        _ratio = ratio.isFinite && ratio > 0 ? ratio : 0.707;
        _current = start;
        _startIndex = start;
        _pages = List.generate(count, _pageView);
        _notes = Store.notes(_path);
        _marks = Store.marks(_path);
        _ink = Store.ink(_path);
      });
      Store.setLastPage(_path, start);
    } catch (e) {
      if (mounted) setState(() => _error = 'PDF ini nggak bisa dibuka.');
    }
  }

  @override
  void dispose() {
    _doc?.close();
    super.dispose();
  }

  // ---------------------------------------------------------------- render

  Future<Uint8List> _render(int i) {
    return _cache.putIfAbsent(i, () {
      final c = Completer<Uint8List>();
      _lock = _lock.then((_) async {
        try {
          final page = await _doc!.getPage(i + 1);
          final scale = 1400 / page.width;
          final img = await page.render(
            width: page.width * scale,
            height: page.height * scale,
            format: PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
          );
          await page.close();
          if (img == null) throw Exception('render');
          c.complete(img.bytes);
        } catch (e) {
          _cache.remove(i);
          c.completeError(e);
        }
      });
      return c.future;
    });
  }

  Widget _pageView(int i) {
    return Builder(builder: (context) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      Widget img = FutureBuilder<Uint8List>(
        future: _render(i),
        builder: (_, snap) {
          if (snap.hasError) {
            return const Center(child: Icon(Icons.broken_image_outlined));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
          }
          return Image.memory(snap.data!, fit: BoxFit.fill, gaplessPlayback: true);
        },
      );
      if (dark) img = ColorFiltered(colorFilter: _darkPage, child: img);
      return Container(color: dark ? const Color(0xFF1A1C19) : Colors.white, child: img);
    });
  }

  void _jump(int i) {
    final t = i.clamp(0, _count - 1);
    setState(() {
      _current = t;
      _startIndex = t;
      _flipVersion++;
      _slide = null;
    });
    Store.setLastPage(_path, t);
  }

  // ---------------------------------------------------------------- note

  Future<void> _addNote() async {
    final n = Note(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      page: _current,
      x: 0.3,
      y: 0.3,
      color: noteColors[_notes.length % noteColors.length],
    );
    final r = await showNoteSheet(context, n, isNew: true);
    if (r == null || r.delete) return;
    n
      ..text = r.text
      ..font = r.font
      ..color = r.color;
    setState(() => _notes.add(n));
    await Store.saveNotes(_path, _notes);
  }

  Future<void> _editNote(Note n) async {
    final r = await showNoteSheet(context, n);
    if (r == null) return;
    setState(() {
      if (r.delete) {
        _notes.remove(n);
      } else {
        n
          ..text = r.text
          ..font = r.font
          ..color = r.color;
      }
    });
    await Store.saveNotes(_path, _notes);
  }

  Future<void> _toggleMark() async {
    setState(() {
      if (!_marks.remove(_current)) _marks.add(_current);
    });
    await Store.saveMarks(_path, _marks);
  }

  void _showMarks() {
    final marks = _marks.toList()..sort();
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final p = Pal.of(ctx);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tab penanda',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text)),
              const SizedBox(height: 14),
              if (marks.isEmpty)
                Text('Belum ada tab. Tap ikon penanda di atas buat nandain halaman.',
                    style: TextStyle(color: p.muted, height: 1.5))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in marks)
                      FilledButton.tonal(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _jump(m);
                        },
                        child: Text('Hal ${m + 1}'),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- coretan

  bool _isStylus(PointerEvent e) =>
      e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;

  Offset _norm(Offset o, Size s) =>
      Offset((o.dx / s.width).clamp(0.0, 1.0), (o.dy / s.height).clamp(0.0, 1.0));

  void _eraseAt(Offset n) {
    final before = _ink.length;
    _ink.removeWhere((k) =>
        k.page == _current && k.pts.any((p) => (p - n).distance < 0.025));
    if (_ink.length != before) {
      setState(() {});
      Store.saveInk(_path, _ink);
    }
  }

  void _down(PointerDownEvent e, Size s) {
    if (_isStylus(e)) _stylusSeen = true;
    // tolak telapak / jari kalau sudah pakai stylus
    if (_stylusSeen && !_isStylus(e)) return;
    if (_live != null) return;
    if (e.kind == PointerDeviceKind.invertedStylus) {
      _livePointer = e.pointer;
      _eraseAt(_norm(e.localPosition, s));
      return;
    }
    _livePointer = e.pointer;
    setState(() {
      _live = InkStroke(page: _current, tool: _mode == Mode.pen ? 'pen' : 'hl')
        ..add(_norm(e.localPosition, s), e.timeStamp.inMilliseconds);
    });
  }

  void _move(PointerMoveEvent e, Size s) {
    if (e.pointer != _livePointer) return;
    if (e.kind == PointerDeviceKind.invertedStylus) {
      _eraseAt(_norm(e.localPosition, s));
      return;
    }
    if (_live == null) return;
    setState(() => _live!.add(_norm(e.localPosition, s), e.timeStamp.inMilliseconds));
  }

  void _up(PointerEvent e) {
    if (e.pointer != _livePointer) return;
    _livePointer = null;
    final s = _live;
    if (s == null) return;
    setState(() {
      _live = null;
      if (s.pts.length > 1) _ink.add(s);
    });
    Store.saveInk(_path, _ink);
  }

  void _undo() {
    final i = _ink.lastIndexWhere((k) => k.page == _current);
    if (i < 0) return;
    setState(() => _ink.removeAt(i));
    Store.saveInk(_path, _ink);
  }

  Future<void> _convert() async {
    final strokes = _ink.where((k) => k.page == _current && k.tool == 'pen').toList();
    if (strokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tulis dulu pakai stylus atau jari, baru ubah ke teks')),
      );
      return;
    }
    final r = await showConvertSheet(context, strokes, _pageSize);
    if (r == null) return;
    var minX = 1.0, minY = 1.0;
    for (final s in strokes) {
      for (final o in s.pts) {
        minX = math.min(minX, o.dx);
        minY = math.min(minY, o.dy);
      }
    }
    setState(() {
      _ink.removeWhere(strokes.contains);
      _notes.add(Note(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        page: _current,
        x: minX.clamp(0.0, 0.62),
        y: minY.clamp(0.0, 0.86),
        color: r.color,
        text: r.text,
        font: r.font,
      ));
      _mode = Mode.read;
    });
    await Store.saveInk(_path, _ink);
    await Store.saveNotes(_path, _notes);
  }

  // ---------------------------------------------------------------- tampilan

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    if (_error != null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(_error!)));
    }
    if (_doc == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final marked = _marks.contains(_current);

    return Scaffold(
      backgroundColor: p.readerBg,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Store.title(_path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text('hal ${_current + 1} dari $_count',
                style: TextStyle(fontSize: 12, color: p.muted)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Daftar tab',
            onPressed: _showMarks,
            icon: const Icon(Icons.bookmarks_outlined),
          ),
          IconButton(
            tooltip: marked ? 'Lepas tab' : 'Pasang tab',
            onPressed: _toggleMark,
            icon: Icon(marked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                color: marked ? p.accent : null),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: p.line),
        ),
      ),
      body: LayoutBuilder(builder: (_, box) {
        const pad = 12.0;
        final maxW = box.maxWidth - pad * 2;
        final maxH = box.maxHeight - pad * 2;
        var w = maxW;
        var h = w / _ratio;
        if (h > maxH) {
          h = maxH;
          w = h * _ratio;
        }
        final size = Size(w, h);
        _pageSize = size;
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
              children: [
                PageFlipWidget(
                  key: ValueKey(_flipVersion),
                  backgroundColor: p.readerBg,
                  initialIndex: _startIndex,
                  lastPage: _endPage(p),
                  onPageFlipped: (i) {
                    if (i >= _count) return;
                    setState(() => _current = i);
                    Store.setLastPage(_path, i);
                  },
                  children: _pages,
                ),
                _inkLayer(size, p),
                ..._noteLayer(size),
              ],
            ),
          ),
        );
      }),
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: p.bg,
            border: Border(top: BorderSide(color: p.line)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: _mode == Mode.read ? _readBar(p) : _writeBar(p),
        ),
      ),
    );
  }

  Widget _endPage(Pal p) => Container(
        color: p.bg,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.eco_rounded, size: 40, color: p.accent),
            const SizedBox(height: 12),
            Text('Kamu sampai di akhir buku',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Kembali ke rak'),
            ),
          ],
        ),
      );

  Widget _inkLayer(Size s, Pal p) {
    final strokes = [
      ..._ink.where((k) => k.page == _current),
      if (_live != null) _live!,
    ];
    final paint = CustomPaint(size: s, painter: _InkPainter(strokes, p.pen));
    if (_mode == Mode.read) return IgnorePointer(child: paint);
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _down(e, s),
      onPointerMove: (e) => _move(e, s),
      onPointerUp: _up,
      onPointerCancel: _up,
      child: paint,
    );
  }

  List<Widget> _noteLayer(Size s) {
    final noteW = (s.width * 0.36).clamp(110.0, 180.0);
    return [
      for (final n in _notes.where((n) => n.page == _current))
        Positioned(
          left: n.x * s.width,
          top: n.y * s.height,
          child: IgnorePointer(
            ignoring: _mode != Mode.read,
            child: GestureDetector(
              onTap: () => _editNote(n),
              onPanUpdate: (d) => setState(() {
                n.x = (n.x + d.delta.dx / s.width).clamp(0.0, 1 - noteW / s.width);
                n.y = (n.y + d.delta.dy / s.height).clamp(0.0, 0.92);
              }),
              onPanEnd: (_) => Store.saveNotes(_path, _notes),
              child: Transform.rotate(
                angle: -0.03,
                child: Container(
                  width: noteW,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Color(n.color),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: const [
                      BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 6)),
                    ],
                  ),
                  child: Text(
                    n.text.isEmpty ? '(kosong)' : n.text,
                    maxLines: 7,
                    overflow: TextOverflow.ellipsis,
                    style: noteStyle(n.font, size: 12.5),
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _readBar(Pal p) {
    final shown = (_slide ?? _current.toDouble()).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_count > 1)
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: (_slide ?? _current.toDouble()).clamp(0.0, (_count - 1).toDouble()),
                  min: 0,
                  max: (_count - 1).toDouble(),
                  divisions: _count - 1,
                  label: 'Hal ${shown + 1}',
                  onChanged: (v) => setState(() => _slide = v),
                  onChangeEnd: (v) => _jump(v.round()),
                ),
              ),
              Text('${shown + 1} / $_count',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.muted)),
            ],
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _addNote,
                icon: const Icon(Icons.sticky_note_2_rounded, size: 18),
                label: const Text('Note'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _mode = Mode.pen),
                icon: const Icon(Icons.draw_rounded, size: 18),
                label: const Text('Tulis'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _mode = Mode.highlight),
                icon: const Icon(Icons.border_color_rounded, size: 18),
                label: const Text('Stabilo'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _writeBar(Pal p) {
    final pen = _mode == Mode.pen;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: SegmentedButton<Mode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: Mode.pen, icon: Icon(Icons.draw_rounded), label: Text('Pena')),
                  ButtonSegment(
                      value: Mode.highlight,
                      icon: Icon(Icons.border_color_rounded),
                      label: Text('Stabilo')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Urungkan',
              onPressed: _undo,
              icon: const Icon(Icons.undo_rounded),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _stylusSeen
              ? 'Stylus aktif, sentuhan jari diabaikan. Tombol hapus stylus = penghapus.'
              : 'Tulis pakai stylus atau jari. Balik halaman setelah tap Selesai.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: p.muted),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (pen) ...[
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _convert,
                  icon: const Icon(Icons.text_fields_rounded, size: 18),
                  label: const Text('Ubah ke teks'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: FilledButton.icon(
                onPressed: () => setState(() => _mode = Mode.read),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Selesai'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter(this.strokes, this.penColor);
  final List<InkStroke> strokes;
  final Color penColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      if (s.pts.isEmpty) continue;
      final hl = s.tool == 'hl';
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = hl ? StrokeCap.square : StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = hl ? size.width * 0.035 : math.max(2.2, size.width * 0.006)
        ..color = hl ? const Color(0x66FFD54F) : penColor;
      Offset at(int i) => Offset(s.pts[i].dx * size.width, s.pts[i].dy * size.height);
      final path = Path()..moveTo(at(0).dx, at(0).dy);
      if (s.pts.length == 1) {
        path.lineTo(at(0).dx + 0.1, at(0).dy);
      }
      for (var i = 1; i < s.pts.length - 1; i++) {
        final a = at(i);
        final b = at(i + 1);
        path.quadraticBezierTo(a.dx, a.dy, (a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      }
      if (s.pts.length > 1) {
        final last = at(s.pts.length - 1);
        path.lineTo(last.dx, last.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _InkPainter old) => true;
}
