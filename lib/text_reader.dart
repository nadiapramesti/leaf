import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart' as tr;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as px;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import 'store.dart';

// ------------------------------------------------------------------ ambil teks

/// Jalan di isolate terpisah supaya layar nggak macet.
List<String> _extractAll(String path) {
  final doc = sf.PdfDocument(inputBytes: File(path).readAsBytesSync());
  final ex = sf.PdfTextExtractor(doc);
  final out = <String>[];
  for (var i = 0; i < doc.pages.count; i++) {
    try {
      out.add(ex.extractText(startPageIndex: i, endPageIndex: i));
    } catch (_) {
      out.add('');
    }
  }
  doc.dispose();
  return out;
}

Future<List<String>> loadPageTexts(String path) async {
  final dir = await getApplicationDocumentsDirectory();
  final f = File('${dir.path}${Platform.pathSeparator}text_${path.hashCode.abs()}.json');
  if (await f.exists()) {
    try {
      return (jsonDecode(await f.readAsString()) as List).map((e) => '$e').toList();
    } catch (_) {}
  }
  final pages = await compute(_extractAll, path);
  await f.writeAsString(jsonEncode(pages));
  return pages;
}

/// Gabungkan baris PDF jadi paragraf, sambung kata yang dipenggal (di-↵lema).
List<String> toParagraphs(String raw) {
  final lines = raw.replaceAll('\r', '').split('\n').map((l) => l.trim()).toList();
  var maxLen = 0;
  for (final l in lines) {
    if (l.length > maxLen) maxLen = l.length;
  }
  final paras = <String>[];
  var buf = '';
  void flush() {
    final t = buf.trim();
    if (t.isNotEmpty) paras.add(t);
    buf = '';
  }

  for (final l in lines) {
    if (l.isEmpty) {
      flush();
      continue;
    }
    if (RegExp(r'^\d{1,4}$').hasMatch(l)) continue; // nomor halaman
    if (buf.endsWith('-') && RegExp(r'^[a-z]').hasMatch(l)) {
      buf = buf.substring(0, buf.length - 1) + l;
    } else {
      buf = buf.isEmpty ? l : '$buf $l';
    }
    final short = l.length < maxLen * 0.78;
    final heading = l.length < 60 && l == l.toUpperCase() && RegExp(r'[A-Z]').hasMatch(l);
    if (heading || (short && RegExp(r'[.!?:"”)]$').hasMatch(l))) flush();
  }
  flush();
  return paras;
}

/// Paragraf dari satu blok OCR (baris-baris dalam blok disambung).
String _joinLines(List<String> lines) {
  var buf = '';
  for (final raw in lines) {
    final l = raw.trim();
    if (l.isEmpty) continue;
    if (buf.endsWith('-') && RegExp(r'^[a-z]').hasMatch(l)) {
      buf = buf.substring(0, buf.length - 1) + l;
    } else {
      buf = buf.isEmpty ? l : '$buf $l';
    }
  }
  return buf;
}

/// Baca huruf dari gambar halaman (offline), dipakai kalau teks PDF nggak bisa diambil.
const figMark = '\u0001FIG';

/// Baca huruf dari gambar halaman (offline), plus potong gambar/denah di halaman itu.
class PageOcr {
  PageOcr(this.path);
  final String path;
  px.PdfDocument? _doc;
  final _rec = tr.TextRecognizer(script: tr.TextRecognitionScript.latin);
  File? _cacheFile;
  String _dir = '';
  Map<String, dynamic> _cache = {};

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _dir = dir.path;
    _cacheFile = File('${dir.path}${Platform.pathSeparator}ocr_${path.hashCode.abs()}.json');
    if (await _cacheFile!.exists()) {
      try {
        _cache = jsonDecode(await _cacheFile!.readAsString()) as Map<String, dynamic>;
      } catch (_) {}
    }
    if (_cache['v'] != 2) _cache = {'v': 2}; // versi lama belum ada gambar
  }

  List<String>? cached(int i) {
    final v = _cache['$i'];
    return v == null ? null : (v as List).map((e) => '$e').toList();
  }

  Future<List<String>> read(int i) async {
    final hit = cached(i);
    if (hit != null) return hit;
    _doc ??= await px.PdfDocument.openFile(path);
    final page = await _doc!.getPage(i + 1);
    final scale = 1800 / page.width;
    final img = await page.render(
      width: page.width * scale,
      height: page.height * scale,
      format: px.PdfPageImageFormat.jpeg,
      backgroundColor: '#FFFFFF',
    );
    await page.close();
    if (img == null) return const [];
    final tmp = await getTemporaryDirectory();
    final f = File('${tmp.path}${Platform.pathSeparator}leaf_ocr.jpg');
    await f.writeAsBytes(img.bytes, flush: true);
    final res = await _rec.processImage(tr.InputImage.fromFilePath(f.path));

    // ukuran gambar asli (piksel) untuk skala kotak teks
    final codec = await ui.instantiateImageCodec(img.bytes, targetWidth: 300);
    final frame = await codec.getNextFrame();
    final small = frame.image;
    final sw = small.width, sh = small.height;
    final k = sw / (img.width ?? (page.width * scale)).toDouble();
    final raw = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
    small.dispose();

    // blok teks badan (bukan label kecil) menutup baris-barisnya
    final blocks = [
      for (final b in res.blocks)
        if (!RegExp(r'^\d{1,4}$').hasMatch(b.text.trim())) b
    ];
    bool isBody(tr.TextBlock b) =>
        b.text.trim().length >= 25 || b.boundingBox.width * k > sw * 0.45;
    final textRow = List<bool>.filled(sh, false);
    for (final b in blocks.where(isBody)) {
      final t = (b.boundingBox.top * k - 2).floor().clamp(0, sh - 1);
      final bt = (b.boundingBox.bottom * k + 2).ceil().clamp(0, sh - 1);
      for (var y = t; y <= bt; y++) {
        textRow[y] = true;
      }
    }

    // baris yang ada "tinta" tapi bukan teks badan = kandidat gambar
    final figs = <Rect>[];
    if (raw != null) {
      final px0 = (sw * 0.04).floor(), px1 = (sw * 0.96).ceil();
      bool dark(int x, int y) {
        final o = (y * sw + x) * 4;
        final l = raw.getUint8(o) * 0.3 + raw.getUint8(o + 1) * 0.59 + raw.getUint8(o + 2) * 0.11;
        return l < 170;
      }

      final ink = List<bool>.generate(sh, (y) {
        if (textRow[y]) return false;
        var n = 0;
        for (var x = px0; x < px1; x++) {
          if (dark(x, y)) n++;
        }
        return n > sw * 0.01;
      });
      final gap = (sh * 0.03).round();
      var y = (sh * 0.03).floor();
      while (y < sh * 0.97) {
        if (!ink[y]) {
          y++;
          continue;
        }
        var end = y, miss = 0, yy = y;
        while (yy < sh && miss <= gap && !textRow[yy]) {
          if (ink[yy]) {
            end = yy;
            miss = 0;
          } else {
            miss++;
          }
          yy++;
        }
        if (end - y >= sh * 0.08) {
          var l = sw, r = 0;
          for (var ry = y; ry <= end; ry++) {
            for (var x = px0; x < px1; x++) {
              if (dark(x, ry)) {
                if (x < l) l = x;
                if (x > r) r = x;
              }
            }
          }
          final pad = sw * 0.02;
          figs.add(Rect.fromLTRB(
            ((l - pad) / sw).clamp(0.0, 1.0),
            ((y - pad) / sh).clamp(0.0, 1.0),
            ((r + pad) / sw).clamp(0.0, 1.0),
            ((end + pad) / sh).clamp(0.0, 1.0),
          ));
        }
        y = end + 1;
      }
    }

    // susun paragraf + gambar sesuai urutan dari atas
    final items = <({double top, String text})>[];
    for (final b in blocks) {
      final cx = b.boundingBox.center.dx * k / sw, cy = b.boundingBox.center.dy * k / sh;
      if (figs.any((r) => r.contains(Offset(cx, cy)))) continue; // label di dalam denah
      final t = _joinLines([for (final l in b.lines) l.text]);
      if (t.isNotEmpty) items.add((top: b.boundingBox.top * k / sh, text: t));
    }
    if (figs.isNotEmpty) {
      final keep = File('$_dir${Platform.pathSeparator}ocrimg_${path.hashCode.abs()}_$i.jpg');
      await keep.writeAsBytes(img.bytes, flush: true);
      final ratio = sw / sh;
      for (final r in figs) {
        items.add((
          top: r.top,
          text: '$figMark|${keep.path}|${r.left}|${r.top}|${r.width}|${r.height}|$ratio',
        ));
      }
    }
    items.sort((a, b) => a.top.compareTo(b.top));
    final paras = [for (final it in items) it.text];
    _cache['$i'] = paras;
    await _cacheFile?.writeAsString(jsonEncode(_cache));
    return paras;
  }

  Future<void> close() async {
    await _rec.close();
    await _doc?.close();
  }
}

/// Potongan gambar dari halaman asli (denah, ilustrasi, tabel gambar).
class _Figure extends StatelessWidget {
  const _Figure(this.spec);
  final String spec;

  @override
  Widget build(BuildContext context) {
    final parts = spec.split('|');
    if (parts.length < 7) return const SizedBox();
    final file = File(parts[1]);
    final l = double.tryParse(parts[2]) ?? 0, t = double.tryParse(parts[3]) ?? 0;
    final w = (double.tryParse(parts[4]) ?? 1).clamp(0.05, 1.0);
    final h = (double.tryParse(parts[5]) ?? 1).clamp(0.05, 1.0);
    final ratio = double.tryParse(parts[6]) ?? 0.7;
    final ax = w >= 0.999 ? 0.0 : -1 + 2 * l / (1 - w);
    final ay = h >= 0.999 ? 0.0 : -1 + 2 * t / (1 - h);

    Widget crop(double width) => ClipRect(
          child: Align(
            alignment: Alignment(ax.clamp(-1.0, 1.0), ay.clamp(-1.0, 1.0)),
            widthFactor: w,
            heightFactor: h,
            child: Image.file(file,
                width: width / w, height: width / w / ratio, fit: BoxFit.fill),
          ),
        );

    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      return GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (ctx) => Dialog.fullscreen(
            backgroundColor: Colors.black,
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    maxScale: 6,
                    child: Center(child: crop(MediaQuery.of(ctx).size.width)),
                  ),
                ),
                Positioned(
                  top: 12 + MediaQuery.of(ctx).viewPadding.top,
                  right: 12,
                  child: IconButton.filledTonal(
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10)],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              crop(width),
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.zoom_in_rounded, size: 18, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

bool _isHeading(String p) =>
    p.length < 70 && p == p.toUpperCase() && RegExp(r'[A-Z]').hasMatch(p);

// ------------------------------------------------------------------ pengaturan

const textFonts = <String, String>{
  'Literata': 'Buku',
  'Merriweather': 'Klasik',
  'Plus Jakarta Sans': 'Modern',
  'Lexend': 'Mudah dibaca',
};

class TextPrefs {
  const TextPrefs({
    required this.font,
    required this.size,
    required this.line,
    required this.pad,
    required this.justify,
  });

  final String font;
  final double size;
  final double line;
  final double pad;
  final bool justify;

  static TextPrefs load() => TextPrefs(
        font: Store.sp.getString('tx_font') ?? 'Literata',
        size: Store.sp.getDouble('tx_size') ?? 18,
        line: Store.sp.getDouble('tx_line') ?? 1.6,
        pad: Store.sp.getDouble('tx_pad') ?? 24,
        justify: Store.sp.getBool('tx_justify') ?? true,
      );

  TextPrefs copyWith({String? font, double? size, double? line, double? pad, bool? justify}) {
    final t = TextPrefs(
      font: font ?? this.font,
      size: size ?? this.size,
      line: line ?? this.line,
      pad: pad ?? this.pad,
      justify: justify ?? this.justify,
    );
    Store.sp.setString('tx_font', t.font);
    Store.sp.setDouble('tx_size', t.size);
    Store.sp.setDouble('tx_line', t.line);
    Store.sp.setDouble('tx_pad', t.pad);
    Store.sp.setBool('tx_justify', t.justify);
    return t;
  }
}

({Color bg, Color fg, Color muted}) _colors(BuildContext c, int paper) {
  final dark = Theme.of(c).brightness == Brightness.dark;
  final m = paper <= 1 ? (dark ? 3 : 1) : paper;
  switch (m) {
    case 2:
      return (bg: const Color(0xFFF4ECD8), fg: const Color(0xFF3B2F20), muted: const Color(0xFF7A6A52));
    case 3:
      return (bg: const Color(0xFF151815), fg: const Color(0xFFD9DED8), muted: const Color(0xFF8C978F));
    default:
      return (bg: Colors.white, fg: const Color(0xFF1B1F1C), muted: const Color(0xFF6B756E));
  }
}

// ------------------------------------------------------------------ halaman

class TextReaderPage extends StatefulWidget {
  const TextReaderPage({super.key, required this.path, required this.count, required this.start});
  final String path;
  final int count;
  final int start;

  @override
  State<TextReaderPage> createState() => _TextReaderPageState();
}

class _TextReaderPageState extends State<TextReaderPage> {
  List<List<String>?>? _paras; // null per halaman = belum dibaca (OCR)
  PageOcr? _ocr;
  final List<int> _queue = [];
  bool _ocrBusy = false;
  bool _usingOcr = false;
  String? _error;
  bool _ui = true;
  late int _visible = widget.start;
  late int _start = widget.start;
  final _prefs = ValueNotifier<TextPrefs>(TextPrefs.load());
  final Map<int, GlobalKey> _keys = {};
  final _centerKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _ocr?.close();
    _prefs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    List<String> pages;
    try {
      pages = await loadPageTexts(widget.path);
    } catch (_) {
      pages = List.filled(widget.count, '');
    }
    final paras = <List<String>?>[for (final t in pages) toParagraphs(t)];
    while (paras.length < widget.count) {
      paras.add(const []);
    }
    // halaman tanpa teks / teksnya sedikit (biasanya ada gambar/denah) -> baca dari gambar
    final missing = [
      for (var i = 0; i < paras.length; i++)
        if (i >= pages.length || pages[i].trim().length < 150) i
    ];
    if (missing.isNotEmpty) {
      try {
        final ocr = PageOcr(widget.path);
        await ocr.init();
        _ocr = ocr;
        _usingOcr = missing.length > paras.length * 0.3;
        for (final i in missing) {
          paras[i] = ocr.cached(i);
        }
      } catch (_) {
        if (mounted) setState(() => _error = 'Teks PDF ini nggak bisa dibaca.');
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _paras = paras;
      _start = widget.start.clamp(0, paras.length - 1);
    });
  }

  void _want(int i) {
    final paras = _paras;
    if (_ocr == null || paras == null || paras[i] != null || _queue.contains(i)) return;
    _queue.add(i);
    _pump();
  }

  Future<void> _pump() async {
    if (_ocrBusy || _queue.isEmpty || _ocr == null) return;
    _ocrBusy = true;
    // dahulukan halaman paling dekat dengan yang sedang dibaca
    _queue.sort((a, b) => (a - _visible).abs().compareTo((b - _visible).abs()));
    final i = _queue.removeAt(0);
    try {
      final res = await _ocr!.read(i);
      if (mounted) setState(() => _paras![i] = res);
    } catch (_) {
      if (mounted) setState(() => _paras![i] = const []);
    }
    _ocrBusy = false;
    if (mounted) _pump();
  }

  void _toggleUi() {
    setState(() => _ui = !_ui);
    SystemChrome.setEnabledSystemUIMode(
        _ui ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
  }

  void _updateVisible() {
    var best = _visible;
    var bestY = double.negativeInfinity;
    _keys.forEach((page, key) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) return;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y <= 160 && y > bestY) {
        bestY = y;
        best = page;
      }
    });
    if (best != _visible) {
      setState(() => _visible = best);
      Store.setLastPage(widget.path, best);
    }
  }

  void _exit() => Navigator.pop(context, _visible);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Store.paper,
      builder: (context, paper, _) {
        final c = _colors(context, paper);
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _exit();
          },
          child: Scaffold(
            backgroundColor: c.bg,
            appBar: _ui
                ? AppBar(
                    backgroundColor: c.bg,
                    foregroundColor: c.fg,
                    leading: IconButton(
                      tooltip: 'Kembali ke PDF',
                      onPressed: _exit,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hal ${_visible + 1} dari ${widget.count}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        if (_usingOcr)
                          Text('Teks dibaca dari gambar, bisa ada salah huruf',
                              style: TextStyle(fontSize: 11, color: c.muted)),
                      ],
                    ),
                    actions: [
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: FilledButton.tonalIcon(
                          onPressed: _settings,
                          icon: const Icon(Icons.text_fields_rounded, size: 20),
                          label: const Text('Atur teks'),
                        ),
                      ),
                    ],
                  )
                : null,
            body: _body(c),
          ),
        );
      },
    );
  }

  Widget _body(({Color bg, Color fg, Color muted}) c) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_not_supported_outlined, size: 48, color: c.muted),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center, style: TextStyle(color: c.fg, height: 1.5)),
              const SizedBox(height: 20),
              FilledButton(onPressed: _exit, child: const Text('Balik ke tampilan PDF')),
            ],
          ),
        ),
      );
    }
    final paras = _paras;
    if (paras == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Menyiapkan mode teks…\n(sekali aja per buku)',
                textAlign: TextAlign.center, style: TextStyle(color: c.muted, height: 1.5)),
          ],
        ),
      );
    }

    return ValueListenableBuilder<TextPrefs>(
      valueListenable: _prefs,
      builder: (_, t, __) {
        final body = GoogleFonts.getFont(t.font,
            fontSize: t.size, height: t.line, color: c.fg);
        final head = GoogleFonts.getFont(t.font,
            fontSize: t.size * 1.15, height: 1.3, color: c.fg, fontWeight: FontWeight.w700);

        Widget page(int i) {
          final key = _keys.putIfAbsent(i, () => GlobalKey());
          return Padding(
            key: key,
            padding: EdgeInsets.symmetric(horizontal: t.pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: Divider(color: c.muted.withValues(alpha: 0.25))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text('${i + 1}',
                          style: TextStyle(fontSize: 12, color: c.muted, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(child: Divider(color: c.muted.withValues(alpha: 0.25))),
                  ],
                ),
                const SizedBox(height: 14),
                if (paras[i] == null)
                  Builder(builder: (_) {
                    WidgetsBinding.instance.addPostFrameCallback((_) => _want(i));
                    return SizedBox(
                      height: 320,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: c.muted),
                            ),
                            const SizedBox(height: 10),
                            Text('Membaca halaman ${i + 1}…',
                                style: TextStyle(color: c.muted, fontSize: 13)),
                          ],
                        ),
                      ),
                    );
                  })
                else if (paras[i]!.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text('(halaman ini nggak ada teksnya)',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.muted, fontStyle: FontStyle.italic)),
                  )
                else
                for (final p in paras[i]!)
                  Padding(
                    padding: EdgeInsets.only(bottom: t.size * 0.8),
                    child: p.startsWith(figMark)
                        ? _Figure(p)
                        : _isHeading(p)
                        ? Text(p, textAlign: TextAlign.center, style: head)
                        : Text(p,
                            textAlign: t.justify ? TextAlign.justify : TextAlign.start,
                            style: body),
                  ),
              ],
            ),
          );
        }

        return NotificationListener<ScrollEndNotification>(
          onNotification: (_) {
            _updateVisible();
            return false;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggleUi,
            child: CustomScrollView(
              center: _centerKey,
              slivers: [
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, k) => page(_start - 1 - k),
                    childCount: _start,
                  ),
                ),
                SliverList(
                  key: _centerKey,
                  delegate: SliverChildBuilderDelegate(
                    (_, k) => page(_start + k),
                    childCount: paras.length - _start,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- atur teks

  void _settings() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) {
        final p = Pal.of(ctx);
        Widget label(String s) => Padding(
              padding: const EdgeInsets.only(bottom: 6, top: 14),
              child: Text(s,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.muted)),
            );
        return ValueListenableBuilder<TextPrefs>(
          valueListenable: _prefs,
          builder: (_, t, __) => Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewPadding.bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Atur teks',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text)),
                  label('Gaya huruf'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in textFonts.entries)
                        ChoiceChip(
                          showCheckmark: false,
                          selected: t.font == e.key,
                          label: Text(e.value,
                              style: GoogleFonts.getFont(e.key, fontSize: 15, color: p.text)),
                          onSelected: (_) => _prefs.value = t.copyWith(font: e.key),
                        ),
                    ],
                  ),
                  label('Ukuran huruf · ${t.size.round()}'),
                  Row(
                    children: [
                      IconButton.outlined(
                        tooltip: 'Perkecil',
                        onPressed: t.size > 12
                            ? () => _prefs.value = t.copyWith(size: t.size - 1)
                            : null,
                        icon: const Icon(Icons.text_decrease_rounded),
                      ),
                      Expanded(
                        child: Slider(
                          value: t.size,
                          min: 12,
                          max: 32,
                          divisions: 20,
                          onChanged: (v) => _prefs.value = t.copyWith(size: v),
                        ),
                      ),
                      IconButton.outlined(
                        tooltip: 'Perbesar',
                        onPressed: t.size < 32
                            ? () => _prefs.value = t.copyWith(size: t.size + 1)
                            : null,
                        icon: const Icon(Icons.text_increase_rounded),
                      ),
                    ],
                  ),
                  label('Jarak baris · ${t.line.toStringAsFixed(1)}'),
                  Slider(
                    value: t.line,
                    min: 1.2,
                    max: 2.2,
                    divisions: 10,
                    onChanged: (v) => _prefs.value = t.copyWith(line: v),
                  ),
                  label('Margin samping · ${t.pad.round()}'),
                  Slider(
                    value: t.pad,
                    min: 8,
                    max: 72,
                    divisions: 16,
                    onChanged: (v) => _prefs.value = t.copyWith(pad: v),
                  ),
                  label('Rata teks'),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                            value: false,
                            icon: Icon(Icons.format_align_left_rounded),
                            label: Text('Kiri')),
                        ButtonSegment(
                            value: true,
                            icon: Icon(Icons.format_align_justify_rounded),
                            label: Text('Kanan-kiri')),
                      ],
                      selected: {t.justify},
                      onSelectionChanged: (s) => _prefs.value = t.copyWith(justify: s.first),
                    ),
                  ),
                  label('Warna kertas'),
                  ValueListenableBuilder<int>(
                    valueListenable: Store.paper,
                    builder: (_, mode, __) => SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 0, label: Text('Ikut tema')),
                          ButtonSegment(value: 2, label: Text('Sepia')),
                          ButtonSegment(value: 3, label: Text('Gelap')),
                        ],
                        selected: {mode <= 1 ? 0 : mode},
                        onSelectionChanged: (s) => Store.setPaper(s.first),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
