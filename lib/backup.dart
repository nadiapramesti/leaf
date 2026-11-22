import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'store.dart';

/// Cadangan semua catatan, coretan, tab, progres, dan pengaturan dalam satu file JSON.
/// File PDF-nya sendiri nggak ikut (biar kecil); dicocokkan lewat nama file.
class Backup {
  static const _settingKeys = [
    'goal', 'shelf_view', 'paper', 'theme', 'tx_font', 'tx_size', 'tx_line', 'tx_pad',
    'tx_justify', 'hl_color', 'pen_color', 'pen_w', 'turn_style', 'ink_lang', 'full_hint',
    'tts_rate', 'tts_lang',
  ];
  static const _bookKeys = ['notes', 'marks', 'last', 'count', 'ink', 'title'];

  static String _base(String p) => p.split(Platform.pathSeparator).last;
  static String _2(int n) => n.toString().padLeft(2, '0');

  static Map<String, dynamic> build() {
    final sp = Store.sp;
    return {
      'app': 'leaf',
      'version': 1,
      'created': DateTime.now().toIso8601String(),
      'settings': {
        for (final k in _settingKeys)
          if (sp.containsKey(k)) k: sp.get(k)
      },
      'days': {
        for (final k in sp.getKeys())
          if (k.startsWith('read::')) k: sp.get(k)
      },
      'books': [
        for (final b in Store.books())
          {
            'file': _base(b),
            for (final k in _bookKeys)
              if (sp.containsKey('$k::$b')) k: sp.get('$k::$b'),
          }
      ],
    };
  }

  /// Simpan file cadangan; bisa pilih lokasi termasuk Google Drive.
  static Future<String?> export() async {
    final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent(' ').convert(build())));
    final d = DateTime.now();
    return FilePicker.platform.saveFile(
      dialogTitle: 'Simpan cadangan Leaf',
      fileName: 'leaf-cadangan-${d.year}${_2(d.month)}${_2(d.day)}.json',
      bytes: bytes,
    );
  }

  static Future<void> _put(String k, dynamic v) async {
    final sp = Store.sp;
    if (v is bool) {
      await sp.setBool(k, v);
    } else if (v is int) {
      await sp.setInt(k, v);
    } else if (v is double) {
      await sp.setDouble(k, v);
    } else if (v is String) {
      await sp.setString(k, v);
    } else if (v is List) {
      await sp.setStringList(k, v.map((e) => '$e').toList());
    }
  }

  /// Hasil: jumlah buku yang dipulihkan + nama file yang PDF-nya belum ada di rak.
  static Future<({int books, List<String> missing})?> restore() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    final f = res?.files.single;
    if (f == null) return null;
    final raw = f.bytes ?? await File(f.path!).readAsBytes();
    final j = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    if (j['app'] != 'leaf') throw const FormatException('Bukan file cadangan Leaf');

    for (final e in ((j['settings'] as Map?) ?? {}).entries) {
      await _put('${e.key}', e.value);
    }
    for (final e in ((j['days'] as Map?) ?? {}).entries) {
      await _put('${e.key}', e.value);
    }
    final current = {for (final b in Store.books()) _base(b): b};
    var ok = 0;
    final missing = <String>[];
    for (final item in (j['books'] as List? ?? const [])) {
      final m = item as Map;
      final path = current[m['file']];
      if (path == null) {
        missing.add('${m['file']}');
        continue;
      }
      for (final k in _bookKeys) {
        if (m.containsKey(k)) await _put('$k::$path', m[k]);
      }
      ok++;
    }
    Store.themeMode.value = ThemeMode.values[(Store.sp.getInt('theme') ?? 0).clamp(0, 2)];
    Store.paper.value = Store.sp.getInt('paper') ?? 0;
    return (books: ok, missing: missing);
  }
}
