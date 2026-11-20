import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:page_flip/page_flip.dart';
import 'package:pdfx/pdfx.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'extras.dart';
import 'sheets.dart';
import 'store.dart';

enum Mode { read, pen, highlight }


class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.path, this.openAt});
  final String path;
  final int? openAt;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> with WidgetsBindingObserver {
  PdfDocument? _doc;
  String? _error;
  int _count = 0;
  int _current = 0;
  int _startIndex = 0;
  int _flipVersion = 0;
  double _ratio = 0.707; // lebar / tinggi halaman
  List<Widget> _pages = const [];
  final Map<int, Future<Uint8List>> _cache = {};
  final Map<int, Future<Uint8List>> _thumbs = {};
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

  bool _full = false;
  Offset? _tapDown;
  DateTime? _tapAt;

  final Stopwatch _watch = Stopwatch();
  Timer? _tick;
  Timer? _focus;
  int _focusLeft = 0;
  int _focusMinutes = 0;

  String get _path => widget.path;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _awake(true);
    _watch.start();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _flush());
    _open();
  }

  void _awake(bool on) {
    try {
      on ? WakelockPlus.enable() : WakelockPlus.disable();
    } catch (_) {}
  }

  void _flush() {
    final s = _watch.elapsed.inSeconds;
    _watch.reset();
    Store.addReading(s);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _watch.start();
      _awake(true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _flush();
      _watch.stop();
      _awake(false);
    }
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
    WidgetsBinding.instance.removeObserver(this);
    if (_full) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _flush();
    _tick?.cancel();
    _focus?.cancel();
    _awake(false);
    _doc?.close();
    super.dispose();
  }

  // ---------------------------------------------------------------- render

  Future<Uint8List> _render(int i) => _renderAt(i, 1400, _cache);
  Future<Uint8List> _thumb(int i) => _renderAt(i, 260, _thumbs);

  Future<Uint8List> _renderAt(int i, double width, Map<int, Future<Uint8List>> cache) {
    return cache.putIfAbsent(i, () {
      final c = Completer<Uint8List>();
      _lock = _lock.then((_) async {
        try {
          final page = await _doc!.getPage(i + 1);
          final scale = width / page.width;
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
          cache.remove(i);
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
      final child = img;
      return ValueListenableBuilder<int>(
        valueListenable: Store.paper,
        builder: (_, mode, __) {
          final f = pageFilter(mode, dark);
          return Container(
            color: pageBg(mode, dark),
            child: f == null ? child : ColorFiltered(colorFilter: f, child: child),
          );
        },
      );
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

  Future<void> _openGrid() async {
    final noted = {for (final n in _notes) n.page};
    final i = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => PageGridPage(
          count: _count,
          current: _current,
          thumb: _thumb,
          marks: _marks,
          notedPages: noted,
        ),
      ),
    );
    if (i != null) _jump(i);
  }

  void _openZoom() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => ZoomPage(
          image: _render(_current),
          page: _current,
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- layar penuh

  void _setFull(bool on) {
    setState(() => _full = on);
    SystemChrome.setEnabledSystemUIMode(
        on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    if (on && !(Store.sp.getBool('full_hint') ?? false)) {
      Store.sp.setBool('full_hint', true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ketuk tengah halaman buat munculin tombol lagi'),
        duration: Duration(seconds: 2),
      ));
    }
  }

  /// tap singkat di tengah halaman (bukan di note) = buka/tutup layar penuh
  void _maybeToggle(PointerUpEvent e, Size s) {
    final d = _tapDown, t = _tapAt;
    _tapDown = null;
    if (d == null || t == null || _mode != Mode.read) return;
    if ((e.localPosition - d).distance > 12) return;
    if (DateTime.now().difference(t).inMilliseconds > 280) return;
    final x = d.dx / s.width;
    if (x < 0.25 || x > 0.75) return; // pinggir = area balik halaman
    final noteW = (s.width * 0.36).clamp(110.0, 180.0);
    for (final n in _notes.where((n) => n.page == _current)) {
      final r = Rect.fromLTWH(n.x * s.width, n.y * s.height, noteW, 160);
      if (r.contains(d)) return;
    }
    _setFull(!_full);
  }

  // ---------------------------------------------------------------- fokus & kertas

  Future<void> _pickFocus() async {
    final m = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) {
        final p = Pal.of(ctx);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Timer fokus',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text)),
              const SizedBox(height: 6),
              Text('Baca tanpa distraksi, nanti diingetin istirahat.',
                  style: TextStyle(color: p.muted)),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final v in [15, 25, 45]) ...[
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () => Navigator.pop(ctx, v),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                        child: Text('$v menit',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    if (v != 45) const SizedBox(width: 10),
                  ],
                ],
              ),
              if (_focus != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, 0),
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Hentikan timer'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ],
            ],
          ),
        );
      },
    );
    if (m == null) return;
    if (m == 0) {
      _stopFocus();
    } else {
      _startFocus(m);
    }
  }

  void _stopFocus() {
    _focus?.cancel();
    setState(() => _focus = null);
  }

  void _startFocus(int minutes) {
    _focus?.cancel();
    setState(() {
      _focusMinutes = minutes;
      _focusLeft = minutes * 60;
    });
    _focus = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _focusLeft--);
      if (_focusLeft <= 0) {
        t.cancel();
        setState(() => _focus = null);
        HapticFeedback.heavyImpact();
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.self_improvement_rounded, size: 36),
            title: const Text('Waktunya istirahat'),
            content: Text(
                'Kamu udah fokus $_focusMinutes menit. Istirahat 5 menit dulu biar materinya nempel.'),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Oke')),
            ],
          ),
        );
      }
    });
  }

  Future<void> _pickPaper() async {
    const values = [0, 2, 3];
    const labels = ['Asli', 'Sepia', 'Gelap'];
    const icons = [
      Icons.picture_as_pdf_rounded,
      Icons.coffee_rounded,
      Icons.dark_mode_rounded,
    ];
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final p = Pal.of(ctx);
        return ValueListenableBuilder<int>(
          valueListenable: Store.paper,
          builder: (_, mode, __) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Mode kertas',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text)),
                const SizedBox(height: 6),
                Text('Asli = warna PDF apa adanya. Sepia nyaman buat baca lama, Gelap buat malam.',
                    style: TextStyle(color: p.muted)),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.9,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (var i = 0; i < 3; i++)
                      _paperButton(
                        selected: effectivePaper(mode, false) == effectivePaper(values[i], false),
                        onPressed: () => Store.setPaper(values[i]),
                        icon: icons[i],
                        label: labels[i],
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _paperButton({
    required bool selected,
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
  }) {
    final style = FilledButton.styleFrom(
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
    return selected
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : FilledButton.tonal(onPressed: onPressed, style: style, child: child);
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

    return PopScope(
      canPop: !_full,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _full) _setFull(false);
      },
      child: Scaffold(
      backgroundColor: _full ? Colors.black : p.readerBg,
      appBar: _full ? null : AppBar(
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
            tooltip: 'Semua halaman',
            onPressed: _openGrid,
            icon: const Icon(Icons.grid_view_rounded),
          ),
          IconButton(
            tooltip: marked ? 'Lepas tab' : 'Pasang tab',
            onPressed: _toggleMark,
            icon: Icon(marked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                color: marked ? p.accent : null),
          ),
          PopupMenuButton<String>(
            tooltip: 'Lainnya',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              if (v == 'full') _setFull(true);
              if (v == 'zoom') _openZoom();
              if (v == 'paper') _pickPaper();
              if (v == 'focus') _pickFocus();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'full',
                  child: ListTile(
                      leading: Icon(Icons.fullscreen_rounded), title: Text('Layar penuh'))),
              PopupMenuItem(
                  value: 'zoom',
                  child: ListTile(
                      leading: Icon(Icons.zoom_in_rounded), title: Text('Perbesar halaman'))),
              PopupMenuItem(
                  value: 'paper',
                  child: ListTile(
                      leading: Icon(Icons.contrast_rounded), title: Text('Mode kertas'))),
              PopupMenuItem(
                  value: 'focus',
                  child: ListTile(
                      leading: Icon(Icons.timer_outlined), title: Text('Timer fokus'))),
            ],
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: p.line),
        ),
      ),
      body: LayoutBuilder(builder: (_, box) {
        final pad = _full ? 0.0 : 12.0;
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
        return Stack(
          children: [
            Center(
          child: SizedBox(
            width: w,
            height: h,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (e) {
                _tapDown = e.localPosition;
                _tapAt = DateTime.now();
              },
              onPointerUp: (e) => _maybeToggle(e, size),
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
          ),
        ),
            if (_full)
              Positioned(
                bottom: 14,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text('${_current + 1} / $_count',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
          ],
        );
      }),
      bottomNavigationBar: _full ? null : SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: p.bg,
            border: Border(top: BorderSide(color: p.line)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: _mode == Mode.read ? _readBar(p) : _writeBar(p),
        ),
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
    final mm = (_focusLeft ~/ 60).toString().padLeft(2, '0');
    final ss = (_focusLeft % 60).toString().padLeft(2, '0');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_focus != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(Icons.timer_outlined, size: 20, color: p.accent),
                const SizedBox(width: 8),
                Text('Fokus $mm:$ss',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: p.text)),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _stopFocus,
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: const Text('Stop'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
                ),
              ],
            ),
          ),
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
