import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import 'store.dart';
import 'text_reader.dart';

// ------------------------------------------------------------------ cari di buku

class _Hit {
  _Hit(this.page, this.before, this.match, this.after);
  final int page;
  final String before, match, after;
}

class BookSearchPage extends StatefulWidget {
  const BookSearchPage({super.key, required this.path, required this.count});
  final String path;
  final int count;

  @override
  State<BookSearchPage> createState() => _BookSearchPageState();
}

class _BookSearchPageState extends State<BookSearchPage> {
  List<String?>? _texts; // null per halaman = belum terbaca (PDF gambar)
  PageOcr? _ocr;
  String _q = '';
  int _scanned = 0;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scanning = false;
    _ocr?.close();
    super.dispose();
  }

  static String _plain(List<String> paras) => paras
      .where((p) => !p.startsWith(figMark))
      .map((p) => p.startsWith(fnMark) ? p.split('|').skip(2).join('|') : p)
      .join(' ');

  Future<void> _load() async {
    List<String> pages;
    try {
      pages = await loadPageTexts(widget.path);
    } catch (_) {
      pages = const [];
    }
    final texts = <String?>[
      for (var i = 0; i < widget.count; i++)
        i < pages.length && pages[i].trim().length >= 150 ? pages[i] : null
    ];
    if (texts.contains(null)) {
      try {
        final ocr = PageOcr(widget.path);
        await ocr.init();
        _ocr = ocr;
        for (var i = 0; i < texts.length; i++) {
          if (texts[i] != null) continue;
          final c = ocr.cached(i);
          if (c != null) {
            texts[i] = _plain(c);
          } else if (i < pages.length && pages[i].trim().isNotEmpty) {
            texts[i] = pages[i];
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _texts = texts);
  }

  Future<void> _scanAll() async {
    final texts = _texts, ocr = _ocr;
    if (texts == null || ocr == null) return;
    setState(() {
      _scanning = true;
      _scanned = 0;
    });
    for (var i = 0; i < texts.length; i++) {
      if (!_scanning || !mounted) break;
      if (texts[i] != null) continue;
      try {
        texts[i] = _plain(await ocr.read(i));
      } catch (_) {
        texts[i] = '';
      }
      if (mounted) setState(() => _scanned++);
    }
    if (mounted) setState(() => _scanning = false);
  }

  List<_Hit> _search() {
    final q = _q.trim().toLowerCase();
    final texts = _texts;
    if (q.length < 2 || texts == null) return const [];
    final out = <_Hit>[];
    for (var i = 0; i < texts.length; i++) {
      final t = texts[i];
      if (t == null) continue;
      final flat = t.replaceAll(RegExp(r'\s+'), ' ');
      final low = flat.toLowerCase();
      var from = 0, perPage = 0;
      while (perPage < 3) {
        final at = low.indexOf(q, from);
        if (at < 0) break;
        final s = (at - 50).clamp(0, flat.length);
        final e = (at + q.length + 70).clamp(0, flat.length);
        out.add(_Hit(
          i,
          '${s > 0 ? '…' : ''}${flat.substring(s, at)}',
          flat.substring(at, at + q.length),
          '${flat.substring(at + q.length, e)}${e < flat.length ? '…' : ''}',
        ));
        from = at + q.length;
        perPage++;
      }
      if (out.length > 300) break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final texts = _texts;
    final unread = texts?.where((t) => t == null).length ?? 0;
    final hits = _search();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextField(
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(
              hintText: 'Contoh: ruangan misterius',
              prefixIcon: Icon(Icons.search_rounded),
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ),
      body: texts == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (unread > 0)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: p.accentSoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _scanning
                              ? 'Membaca halaman… $_scanned dari $unread'
                              : '$unread halaman berupa gambar dan belum terbaca, jadi belum ikut dicari.',
                          style: TextStyle(color: p.onAccentSoft, height: 1.4),
                        ),
                        const SizedBox(height: 10),
                        if (_scanning)
                          LinearProgressIndicator(
                            value: unread == 0 ? null : _scanned / (unread + _scanned),
                            color: p.accent,
                          )
                        else
                          FilledButton.icon(
                            onPressed: _scanAll,
                            icon: const Icon(Icons.document_scanner_outlined, size: 18),
                            label: const Text('Baca semua halaman'),
                          ),
                      ],
                    ),
                  ),
                if (_q.trim().length < 2)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Text('Ketik minimal 2 huruf buat mulai cari',
                        textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 4),
                    child: Text('${hits.length} hasil',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700, color: p.muted)),
                  ),
                  for (final h in hits)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(context, h.page),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                        decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: p.line))),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 54,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: p.surface,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text('hal ${h.page + 1}',
                                  style: TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w700, color: p.text)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text.rich(
                                TextSpan(children: [
                                  TextSpan(text: h.before),
                                  TextSpan(
                                    text: h.match,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: p.onAccentSoft,
                                      backgroundColor: p.accentSoft,
                                    ),
                                  ),
                                  TextSpan(text: h.after),
                                ]),
                                style: TextStyle(fontSize: 14, height: 1.45, color: p.text),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

// ------------------------------------------------------------------ daftar isi

class TocEntry {
  TocEntry(this.title, this.page, this.level);
  final String title;
  final int page;
  final int level;
}

List<Map<String, Object>> _outline(String path) {
  final doc = sf.PdfDocument(inputBytes: File(path).readAsBytesSync());
  final out = <Map<String, Object>>[];
  void walk(sf.PdfBookmarkBase base, int level) {
    for (var i = 0; i < base.count; i++) {
      final b = base[i];
      var page = -1;
      try {
        final d = b.destination ?? b.namedDestination?.destination;
        if (d != null) page = doc.pages.indexOf(d.page);
      } catch (_) {}
      out.add({'t': b.title, 'p': page, 'l': level});
      if (level < 3) walk(b, level + 1);
    }
  }

  walk(doc.bookmarks, 0);
  doc.dispose();
  return out;
}

Future<List<TocEntry>> loadToc(String path) async {
  try {
    final raw = await compute(_outline, path);
    return [
      for (final m in raw)
        TocEntry('${m['t']}'.trim(), m['p'] as int, m['l'] as int)
    ].where((e) => e.title.isNotEmpty).toList();
  } catch (_) {
    return const [];
  }
}

class TocPage extends StatelessWidget {
  const TocPage({super.key, required this.path, required this.current});
  final String path;
  final int current;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Daftar isi')),
      body: FutureBuilder<List<TocEntry>>(
        future: loadToc(path),
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.toc_rounded, size: 48, color: p.muted),
                    const SizedBox(height: 12),
                    Text(
                      'PDF ini nggak punya daftar isi bawaan.\nPakai "Cari di buku" buat loncat ke bab.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.muted, height: 1.5),
                    ),
                  ],
                ),
              ),
            );
          }
          // bab yang sedang dibaca = entri terakhir dengan halaman <= current
          var here = -1;
          for (var k = 0; k < items.length; k++) {
            if (items[k].page >= 0 && items[k].page <= current) here = k;
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            itemBuilder: (_, k) {
              final e = items[k];
              final on = k == here;
              return InkWell(
                onTap: e.page < 0 ? null : () => Navigator.pop(context, e.page),
                child: Container(
                  padding: EdgeInsets.fromLTRB(20.0 + e.level * 18, 14, 20, 14),
                  color: on ? p.accentSoft : null,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(e.title,
                            style: TextStyle(
                              fontSize: e.level == 0 ? 16 : 14.5,
                              fontWeight: e.level == 0 ? FontWeight.w700 : FontWeight.w500,
                              color: on ? p.onAccentSoft : p.text,
                            )),
                      ),
                      if (e.page >= 0)
                        Text('${e.page + 1}',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: on ? p.onAccentSoft : p.muted)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
