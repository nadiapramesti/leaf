import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart' as tr;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as px;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import 'lookup.dart';
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
    if (RegExp(r'^\*{1,3}\s*\S').hasMatch(l) && lines.indexOf(l) > lines.length * 0.6) {
      flush();
      final m = footRe.firstMatch(l);
      if (m != null) paras.add('$fnMark|${normMark(m.group(1)!)}|${m.group(2)!.trim()}');
      continue;
    }
    if (buf.isNotEmpty && _startsNew(l)) flush();
    buf = buf.isEmpty ? l : joinWrap(buf, l);
    final short = l.length < maxLen * 0.78;
    final heading = l.length < 60 && l == l.toUpperCase() && RegExp(r'[A-Z]').hasMatch(l);
    if (heading || (short && RegExp(r'[.!?:"”)]$').hasMatch(l))) flush();
  }
  flush();
  return paras;
}

/// Paragraf dari satu blok OCR (baris-baris dalam blok disambung).
/// "Aku: ...", "Kurihara-san : ..." -> nama pembicara + isi.
final speakerRe = RegExp(
    r"^([A-ZÀ-Ý][A-Za-zÀ-ÿ\-'.]*(?:[ \-][A-Za-zÀ-ÿ\-'.]+){0,2})\s*[:：]\s*(.+)$");

/// Baris yang harus jadi paragraf baru (dialog).
bool _startsNew(String l) =>
    speakerRe.hasMatch(l) || RegExp(r'^[“"‘«—–-]\s?\S').hasMatch(l);

/// Baca huruf dari gambar halaman (offline), dipakai kalau teks PDF nggak bisa diambil.
/// Sambung baris: kata yang dipenggal (di-↵lema) disatukan, tapi tanda hubung
/// asli dipertahankan (e-mail, Miyae-san, pelan-pelan).
const _keepAfterHyphen = {
  'san', 'kun', 'chan', 'sama', 'sensei', 'senpai', 'dono', 'shi', 'tan', 'nee', 'nii',
};

String joinWrap(String buf, String next) {
  if (!buf.endsWith('-') || !RegExp(r'^[a-zà-ÿ]').hasMatch(next)) return '$buf $next';
  final head = buf.substring(0, buf.length - 1);
  final prevWord = RegExp(r"([A-Za-zÀ-ÿ']+)$").firstMatch(head)?.group(1) ?? '';
  final nextWord = RegExp(r"^([A-Za-zÀ-ÿ']+)").firstMatch(next)?.group(1) ?? '';
  final keep = prevWord.length <= 1 ||
      _keepAfterHyphen.contains(nextWord.toLowerCase()) ||
      prevWord.toLowerCase() == nextWord.toLowerCase() ||
      RegExp(r'-[A-Za-zÀ-ÿ]+$').hasMatch(head); // sudah ada tanda hubung lain (Yanaoka-san-…)
  return keep ? '$buf$next' : '$head$next';
}

const figMark = '\u0001FIG';
const fnMark = '\u0002FN';

/// "1 Ryokan: penginapan…", "* Onsen: …", "¹ …"
final footRe = RegExp(r'^(\*{1,3}|\d{1,2}|[¹²³⁴⁵⁶⁷⁸⁹⁰]+)[\s.)]*(\S.*)$');

String normMark(String m) {
  const sup = {'¹': '1', '²': '2', '³': '3', '⁴': '4', '⁵': '5', '⁶': '6', '⁷': '7', '⁸': '8', '⁹': '9', '⁰': '0'};
  return m.split('').map((c) => sup[c] ?? c).join();
}

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
    if (_cache['v'] != 6) _cache = {'v': 6}; // versi lama: belum ada gambar / dialog
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

    // susun paragraf + gambar sesuai urutan dari atas.
    // Pakai baris OCR (bukan blok) lalu gabung yang sejajar kiri->kanan,
    // supaya "Aku" di kolom kiri ketemu ": isi dialog" di kolom kanan.
    final items = <({double top, String text})>[];
    final lines = <({Rect r, String t})>[];
    for (final b in blocks) {
      for (final l in b.lines) {
        final r = Rect.fromLTRB(l.boundingBox.left * k / sw, l.boundingBox.top * k / sh,
            l.boundingBox.right * k / sw, l.boundingBox.bottom * k / sh);
        if (figs.any((f) => f.contains(r.center))) continue; // label di dalam denah
        final t = l.text.trim();
        if (t.isEmpty || RegExp(r'^\d{1,4}$').hasMatch(t)) continue;
        lines.add((r: r, t: t));
      }
    }
    lines.sort((a, b) => a.r.center.dy.compareTo(b.r.center.dy));

    // kelompokkan jadi baris visual
    final rows = <({Rect r, String t})>[];
    var cur = <({Rect r, String t})>[];
    void closeRow() {
      if (cur.isEmpty) return;
      cur.sort((a, b) => a.r.left.compareTo(b.r.left));
      var box = cur.first.r;
      for (final c in cur.skip(1)) {
        box = box.expandToInclude(c.r);
      }
      rows.add((r: box, t: cur.map((c) => c.t).join(' ')));
      cur = [];
    }

    for (final l in lines) {
      if (cur.isNotEmpty) {
        final cy = cur.map((c) => c.r.center.dy).reduce((a, b) => a + b) / cur.length;
        final hgt = cur.map((c) => c.r.height).reduce((a, b) => a + b) / cur.length;
        if ((l.r.center.dy - cy).abs() > hgt * 0.6) closeRow();
      }
      cur.add(l);
    }
    closeRow();

    // catatan kaki: baris kecil di bawah halaman yang diawali angka / bintang
    final body = <({Rect r, String t})>[];
    final notes = <({String mark, String text})>[];
    if (rows.isNotEmpty) {
      final hs = rows.map((r) => r.r.height).toList()..sort();
      final med = hs[hs.length ~/ 2];
      var inFn = false;
      for (final row in rows) {
        final small = row.r.height < med * 0.88;
        final m = footRe.firstMatch(row.t);
        if (row.r.top > 0.66 && small && m != null) {
          inFn = true;
          notes.add((mark: normMark(m.group(1)!), text: m.group(2)!.trim()));
          continue;
        }
        if (inFn && small && notes.isNotEmpty) {
          final last = notes.removeLast();
          notes.add((mark: last.mark, text: '${last.text} ${row.t}'));
          continue;
        }
        body.add(row);
      }
    }

    // baris -> paragraf
    if (body.isNotEmpty) {
      final minLeft = body.map((r) => r.r.left).reduce((a, b) => a < b ? a : b);
      final maxRight = body.map((r) => r.r.right).reduce((a, b) => a > b ? a : b);
      final lineH = body.map((r) => r.r.height).reduce((a, b) => a + b) / body.length;
      var buf = '';
      var bufTop = 0.0;
      var speaker = false;
      ({Rect r, String t})? prev;
      void flush() {
        final t = buf.trim();
        if (t.isNotEmpty) items.add((top: bufTop, text: t));
        buf = '';
      }

      for (final row in body) {
        final t = row.t;
        var newPara = buf.isEmpty || _startsNew(t);
        if (!newPara && prev != null) {
          final gap = row.r.top - prev.r.bottom;
          final prevShort = prev.r.right < maxRight - 0.08 && RegExp(r'[.!?"”)…]$').hasMatch(prev.t);
          final indented = row.r.left > minLeft + 0.025;
          if (gap > lineH * 1.1) newPara = true;
          if (!speaker && (prevShort || indented)) newPara = true;
          if (speaker && prevShort && !indented) newPara = true;
        }
        if (newPara) {
          flush();
          bufTop = row.r.top;
          speaker = speakerRe.hasMatch(t);
          buf = t;
        } else {
          buf = joinWrap(buf, t);
        }
        prev = row;
      }
      flush();
    }
    for (var j = 0; j < notes.length; j++) {
      items.add((top: 5.0 + j, text: '$fnMark|${notes[j].mark}|${notes[j].text}'));
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

bool _isDialog(String p) => !p.startsWith(figMark) && !p.startsWith(fnMark) && _startsNew(p);

/// Nama pembicara tebal, isi menjorok rapi di bawahnya.
Widget _speaker(String p, TextStyle body, List<InlineSpan> Function(String) rich) {
  final m = speakerRe.firstMatch(p)!;
  return Text.rich(
    TextSpan(children: [
      TextSpan(text: '${m.group(1)}: ', style: body.copyWith(fontWeight: FontWeight.w700)),
      ...rich(m.group(2)!),
    ]),
    style: body,
  );
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

  // dengerin buku (text-to-speech)
  FlutterTts? _tts;
  bool _player = false;
  bool _speaking = false;
  int _ttsPage = 0;
  int _ttsPara = 0;
  final _ttsKey = GlobalKey();
  double _rate = Store.sp.getDouble('tts_rate') ?? 0.5;
  String _ttsLang = Store.sp.getString('tts_lang') ?? 'id-ID';

  // arti kata
  String _selection = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _tts?.stop();
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
                      IconButton(
                        tooltip: 'Dengerin buku',
                        onPressed: _openPlayer,
                        icon: Icon(_speaking ? Icons.graphic_eq_rounded : Icons.headphones_rounded),
                      ),
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
            bottomNavigationBar: _player ? _playerBar() : null,
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
                for (final (j, p) in paras[i]!.where((p) => !p.startsWith(fnMark)).indexed)
                  Container(
                    key: _speaking && i == _ttsPage && j == _ttsPara ? _ttsKey : null,
                    margin: EdgeInsets.only(
                        bottom: _isDialog(p) ? t.size * 0.45 : t.size * 0.8),
                    decoration: _speaking && i == _ttsPage && j == _ttsPara
                        ? BoxDecoration(
                            color: Pal.of(context).accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8),
                          )
                        : null,
                    child: p.startsWith(figMark)
                        ? _Figure(p)
                        : speakerRe.hasMatch(p)
                        ? _speaker(p, body, (x) => _rich(x, body, notesOf(i), c.muted))
                        : _isHeading(p)
                        ? Text(p, textAlign: TextAlign.center, style: head)
                        : Text.rich(
                            TextSpan(children: _rich(p, body, notesOf(i), c.muted)),
                            textAlign: t.justify ? TextAlign.justify : TextAlign.start,
                            style: body),
                  ),
                if (notesOf(i).isNotEmpty) _footBox(notesOf(i), body, c),
              ],
            ),
          );
        }

        return NotificationListener<ScrollEndNotification>(
          onNotification: (_) {
            _updateVisible();
            return false;
          },
          child: SelectionArea(
            onSelectionChanged: (c) => _selection = c?.plainText ?? '',
            contextMenuBuilder: (ctx, st) => AdaptiveTextSelectionToolbar.buttonItems(
              anchors: st.contextMenuAnchors,
              buttonItems: [
                ContextMenuButtonItem(
                  label: 'Arti kata',
                  onPressed: () {
                    final w = _selection;
                    st.hideToolbar();
                    if (w.trim().isNotEmpty) showWordSheet(context, w);
                  },
                ),
                ...st.contextMenuButtonItems,
              ],
            ),
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
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- dengerin buku

  static const _ttsLangs = {'id-ID': 'Indonesia', 'en-US': 'English', 'ja-JP': '日本語'};
  static final _rates = <double, String>{0.38: '0.75×', 0.5: '1×', 0.62: '1.25×', 0.75: '1.5×'};

  Future<FlutterTts> _engine() async {
    final t = _tts ?? FlutterTts();
    if (_tts == null) {
      _tts = t;
      await t.awaitSpeakCompletion(false);
      t.setCompletionHandler(() {
        if (!_speaking || !mounted) return;
        setState(() => _ttsPara++);
        _speakNext();
      });
      t.setErrorHandler((_) {
        if (mounted) setState(() => _speaking = false);
      });
    }
    await t.setLanguage(_ttsLang);
    await t.setSpeechRate(_rate);
    return t;
  }

  void _openPlayer() {
    setState(() {
      _player = true;
      if (!_speaking) {
        _ttsPage = _visible;
        _ttsPara = 0;
      }
    });
    if (!_speaking) _play();
  }

  Future<void> _play() async {
    setState(() => _speaking = true);
    await _engine();
    _speakNext();
  }

  Future<void> _pause() async {
    setState(() => _speaking = false);
    await _tts?.stop();
  }

  Future<void> _closePlayer() async {
    await _pause();
    setState(() => _player = false);
  }

  Future<void> _speakNext() async {
    final paras = _paras;
    if (!_speaking || paras == null) return;
    while (_ttsPage < paras.length) {
      var list = paras[_ttsPage];
      if (list == null && _ocr != null) {
        try {
          list = await _ocr!.read(_ttsPage);
          if (mounted) setState(() => paras[_ttsPage] = list);
        } catch (_) {
          list = const [];
        }
      }
      final body = (list ?? const <String>[]).where((p) => !p.startsWith(fnMark)).toList();
      while (_ttsPara < body.length && body[_ttsPara].startsWith(figMark)) {
        _ttsPara++;
      }
      if (_ttsPara < body.length) {
        if (mounted) setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _ttsKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(ctx,
                alignment: 0.3, duration: const Duration(milliseconds: 350));
          }
        });
        final text = body[_ttsPara].replaceAll(RegExp(r'\s+'), ' ');
        await _tts?.speak(text);
        return;
      }
      _ttsPage++;
      _ttsPara = 0;
    }
    if (mounted) setState(() => _speaking = false);
  }

  Widget _playerBar() {
    final p = Pal.of(context);
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: p.bg, border: Border(top: BorderSide(color: p.line))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton.filled(
                  tooltip: _speaking ? 'Jeda' : 'Putar',
                  iconSize: 28,
                  style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
                  onPressed: _speaking ? _pause : _play,
                  icon: Icon(_speaking ? Icons.pause_rounded : Icons.play_arrow_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_speaking ? 'Membacakan hal ${_ttsPage + 1}' : 'Dijeda di hal ${_ttsPage + 1}',
                          style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
                      Text(_ttsLangs[_ttsLang] ?? _ttsLang,
                          style: TextStyle(fontSize: 12, color: p.muted)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Bahasa suara',
                  icon: const Icon(Icons.record_voice_over_outlined),
                  onSelected: (v) async {
                    setState(() => _ttsLang = v);
                    Store.sp.setString('tts_lang', v);
                    final was = _speaking;
                    await _pause();
                    if (was) _play();
                  },
                  itemBuilder: (_) => [
                    for (final e in _ttsLangs.entries)
                      PopupMenuItem(value: e.key, child: Text(e.value)),
                  ],
                ),
                IconButton(
                  tooltip: 'Tutup pemutar',
                  onPressed: _closePlayer,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<double>(
                showSelectedIcon: false,
                segments: [
                  for (final e in _rates.entries)
                    ButtonSegment(value: e.key, label: Text(e.value)),
                ],
                selected: {_rates.containsKey(_rate) ? _rate : 0.5},
                onSelectionChanged: (s) async {
                  setState(() => _rate = s.first);
                  Store.sp.setDouble('tts_rate', s.first);
                  await _tts?.setSpeechRate(s.first);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- catatan kaki & link

  Map<String, String> notesOf(int i) {
    final out = <String, String>{};
    for (final p in _paras?[i] ?? const <String>[]) {
      if (!p.startsWith(fnMark)) continue;
      final parts = p.split('|');
      if (parts.length >= 3) out[parts[1]] = parts.sublist(2).join('|');
    }
    return out;
  }

  static final _tokRe = RegExp(
      r'([\w.+\-]+@[\w\-]+\.[\w.\-]*\w)'
      r'|((?:https?://|www\.)[^\s)”"]+)'
      r'|([¹²³⁴⁵⁶⁷⁸⁹⁰]+)'
      r'|(?<=[A-Za-zÀ-ÿ)\]”"’])(\d{1,2}|\*{1,3})(?=[\s.,;:!?”"’)]|$)');

  List<InlineSpan> _rich(String text, TextStyle base, Map<String, String> notes, Color muted) {
    final spans = <InlineSpan>[];
    var last = 0;
    final accent = Pal.of(context).accent;
    for (final m in _tokRe.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final link = m.group(1) ?? m.group(2);
      if (link != null) {
        spans.add(TextSpan(
          text: link,
          style: base.copyWith(
              color: accent, decoration: TextDecoration.underline, decorationColor: accent),
          recognizer: TapGestureRecognizer()..onTap = () => _copy(link),
        ));
      } else {
        final key = normMark((m.group(3) ?? m.group(4))!);
        final note = notes[key];
        if (note == null) {
          spans.add(TextSpan(text: m.group(0)));
        } else {
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.top,
            child: GestureDetector(
              onTap: () => _showNote(key, note, base),
              child: Container(
                margin: const EdgeInsets.only(left: 2),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(key,
                    style: TextStyle(
                        fontSize: (base.fontSize ?? 18) * 0.62,
                        fontWeight: FontWeight.w800,
                        color: accent,
                        height: 1.1)),
              ),
            ),
          ));
        }
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return spans;
  }

  void _copy(String s) {
    Clipboard.setData(ClipboardData(text: s));
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$s disalin'), behavior: SnackBarBehavior.floating));
  }

  void _showNote(String key, String note, TextStyle base) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) {
        final p = Pal.of(ctx);
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(ctx).viewPadding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: p.accentSoft, borderRadius: BorderRadius.circular(8)),
                    child: Text(key,
                        style: TextStyle(fontWeight: FontWeight.w800, color: p.onAccentSoft)),
                  ),
                  const SizedBox(width: 10),
                  Text('Catatan kaki',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
                ],
              ),
              const SizedBox(height: 14),
              Text(note, style: base.copyWith(color: p.text, fontSize: 17)),
            ],
          ),
        );
      },
    );
  }

  Widget _footBox(Map<String, String> notes, TextStyle body, ({Color bg, Color fg, Color muted}) c) {
    final small = body.copyWith(fontSize: (body.fontSize ?? 18) * 0.82, height: 1.45);
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: c.muted.withValues(alpha: 0.5), width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CATATAN KAKI',
              style: TextStyle(
                  fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: c.muted)),
          const SizedBox(height: 8),
          for (final e in notes.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${e.key}  ', style: small.copyWith(fontWeight: FontWeight.w800)),
                  ..._rich(e.value, small, const {}, c.muted),
                ]),
                style: small,
              ),
            ),
        ],
      ),
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
