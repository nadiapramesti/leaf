import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
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
  List<List<String>>? _paras;
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
    _prefs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final pages = await loadPageTexts(widget.path);
      final paras = pages.map(toParagraphs).toList();
      if (!mounted) return;
      final total = paras.fold<int>(0, (a, p) => a + p.length);
      setState(() {
        if (total == 0) {
          _error = 'PDF ini isinya gambar hasil scan, jadi teksnya nggak bisa diambil.';
        } else {
          _paras = paras;
          _start = widget.start.clamp(0, paras.length - 1);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Teks PDF ini nggak bisa dibaca.');
    }
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
                    title: Text('Hal ${_visible + 1} dari ${widget.count}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
                for (final p in paras[i])
                  Padding(
                    padding: EdgeInsets.only(bottom: t.size * 0.8),
                    child: _isHeading(p)
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
