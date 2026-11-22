import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'store.dart';

/// Lembar arti kata: definisi dari Wiktionary (butuh internet) + tombol KBBI / terjemahan.
Future<void> showWordSheet(BuildContext context, String raw) {
  final word = raw.trim().replaceAll(RegExp(r'^[^\wÀ-ÿ぀-鿿]+|[^\wÀ-ÿ぀-鿿]+$'), '');
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _WordSheet(word: word.isEmpty ? raw.trim() : word),
  );
}

class _Def {
  _Def(this.lang, this.pos, this.text);
  final String lang, pos, text;
}

class _WordSheet extends StatefulWidget {
  const _WordSheet({required this.word});
  final String word;

  @override
  State<_WordSheet> createState() => _WordSheetState();
}

class _WordSheetState extends State<_WordSheet> {
  List<_Def>? _defs;
  String? _err;

  bool get _single => !widget.word.contains(' ') && widget.word.length <= 40;

  @override
  void initState() {
    super.initState();
    if (_single) {
      _fetch();
    } else {
      _defs = const [];
    }
  }

  static String _strip(String html) => html
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .trim();

  Future<void> _fetch() async {
    try {
      final w = Uri.encodeComponent(widget.word.toLowerCase());
      final res = await http.get(
        Uri.parse('https://en.wiktionary.org/api/rest_v1/page/definition/$w'),
        headers: {'User-Agent': 'LeafReader/1.0 (aplikasi baca pribadi)'},
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        setState(() => _defs = const []);
        return;
      }
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      const order = ['id', 'ms', 'ja', 'en'];
      final langs = j.keys.toList()
        ..sort((a, b) {
          final ia = order.indexOf(a), ib = order.indexOf(b);
          return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
        });
      final out = <_Def>[];
      for (final lang in langs) {
        for (final entry in (j[lang] as List)) {
          final e = entry as Map<String, dynamic>;
          final langName = '${e['language'] ?? lang}';
          final pos = '${e['partOfSpeech'] ?? ''}';
          for (final d in (e['definitions'] as List? ?? const [])) {
            final t = _strip('${(d as Map)['definition'] ?? ''}');
            if (t.isNotEmpty) out.add(_Def(langName, pos, t));
            if (out.length >= 8) break;
          }
          if (out.length >= 8) break;
        }
        if (out.length >= 8) break;
      }
      if (mounted) setState(() => _defs = out);
    } catch (_) {
      if (mounted) setState(() => _err = 'Butuh internet buat cari arti kata.');
    }
  }

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final w = Uri.encodeComponent(widget.word);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.word,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.text)),
            const SizedBox(height: 12),
            Flexible(
              child: _err != null
                  ? Text(_err!, style: TextStyle(color: p.muted))
                  : _defs == null
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : _defs!.isEmpty
                          ? Text(
                              _single
                                  ? 'Arti kata ini belum ketemu. Coba lewat tombol di bawah.'
                                  : 'Buat kalimat, pakai terjemahan di bawah.',
                              style: TextStyle(color: p.muted, height: 1.5))
                          : ListView(
                              shrinkWrap: true,
                              children: [
                                for (final d in _defs!)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${d.lang}${d.pos.isEmpty ? '' : ' · ${d.pos}'}',
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: p.accent)),
                                        const SizedBox(height: 2),
                                        Text(d.text,
                                            style: TextStyle(
                                                fontSize: 15, height: 1.45, color: p.text)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (_single) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _open('https://kbbi.kemdikbud.go.id/entri/$w'),
                      icon: const Icon(Icons.menu_book_rounded, size: 18),
                      label: const Text('KBBI'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () =>
                        _open('https://translate.google.com/?sl=auto&tl=id&op=translate&text=$w'),
                    icon: const Icon(Icons.translate_rounded, size: 18),
                    label: const Text('Terjemahkan'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
