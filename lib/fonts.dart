import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

import 'store.dart';

/// Daftar font mode teks, dikelompokkan, plus font buatan sendiri (.ttf/.otf).
const fontGroups = <String, List<String>>{
  'Buku (serif)': [
    'Literata', 'Merriweather', 'Lora', 'Crimson Pro', 'EB Garamond',
    'Source Serif 4', 'Libre Baskerville', 'Noto Serif', 'Fraunces',
  ],
  'Modern': [
    'Plus Jakarta Sans', 'Inter', 'Nunito', 'Poppins', 'Figtree', 'Work Sans', 'DM Sans',
  ],
  'Nyaman di mata': ['Lexend', 'Atkinson Hyperlegible', 'Quicksand', 'Comfortaa'],
  'Tulisan tangan': ['Patrick Hand', 'Kalam', 'Caveat', 'Gochi Hand', 'Indie Flower'],
  'Unik': ['Special Elite', 'Courier Prime', 'Playfair Display', 'Zen Maru Gothic'],
};

const sampleLine = 'Ruangan itu tidak punya pintu, tapi selalu ada yang tinggal di dalamnya.';

class Fonts {
  static List<String> _entries() => Store.sp.getStringList('custom_fonts') ?? [];

  /// nama-nama font milik sendiri
  static List<String> custom() => [for (final e in _entries()) e.split('|').first];

  static bool isCustom(String family) => custom().contains(family);

  static Future<void> _register(String family, String path) async {
    final f = File(path);
    if (!await f.exists()) return;
    final loader = FontLoader(family)
      ..addFont(f.readAsBytes().then((b) => ByteData.sublistView(b)));
    await loader.load();
  }

  /// dipanggil sekali waktu app mulai
  static Future<void> loadAll() async {
    for (final e in _entries()) {
      final parts = e.split('|');
      if (parts.length < 2) continue;
      try {
        await _register(parts[0], parts.sublist(1).join('|'));
      } catch (_) {}
    }
  }

  /// pilih file .ttf/.otf dari HP; hasil: nama font baru
  static Future<String?> add() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    final src = res?.files.single.path;
    if (src == null) return null;
    final name = src.split(Platform.pathSeparator).last;
    final lower = name.toLowerCase();
    if (!lower.endsWith('.ttf') && !lower.endsWith('.otf')) {
      throw const FormatException('Pilih file .ttf atau .otf');
    }
    final dir = await getApplicationDocumentsDirectory();
    final fdir = Directory('${dir.path}${Platform.pathSeparator}fonts');
    await fdir.create(recursive: true);
    final dest = '${fdir.path}${Platform.pathSeparator}$name';
    await File(src).copy(dest);
    final family = name
        .replaceAll(RegExp(r'\.(ttf|otf)$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .trim();
    await _register(family, dest);
    final list = _entries()..removeWhere((e) => e.startsWith('$family|'));
    list.add('$family|$dest');
    await Store.sp.setStringList('custom_fonts', list);
    return family;
  }

  static Future<void> remove(String family) async {
    final list = _entries();
    for (final e in list.where((e) => e.startsWith('$family|'))) {
      try {
        await File(e.split('|').sublist(1).join('|')).delete();
      } catch (_) {}
    }
    list.removeWhere((e) => e.startsWith('$family|'));
    await Store.sp.setStringList('custom_fonts', list);
  }

  static TextStyle style(
    String family, {
    double? size,
    double? height,
    Color? color,
    FontWeight? weight,
  }) {
    if (isCustom(family)) {
      return TextStyle(
          fontFamily: family, fontSize: size, height: height, color: color, fontWeight: weight);
    }
    try {
      return GoogleFonts.getFont(family,
          fontSize: size, height: height, color: color, fontWeight: weight);
    } catch (_) {
      return TextStyle(fontSize: size, height: height, color: color, fontWeight: weight);
    }
  }
}

/// Lembar pilih font dengan contoh kalimat di tiap font.
Future<String?> showFontPicker(BuildContext context, String current) {
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _FontPicker(current: current),
  );
}

class _FontPicker extends StatefulWidget {
  const _FontPicker({required this.current});
  final String current;

  @override
  State<_FontPicker> createState() => _FontPickerState();
}

class _FontPickerState extends State<_FontPicker> {
  Future<void> _add() async {
    try {
      final f = await Fonts.add();
      if (f != null && mounted) Navigator.pop(context, f);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pilih file font .ttf atau .otf')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final groups = <String, List<String>>{
      if (Fonts.custom().isNotEmpty) 'Font kamu': Fonts.custom(),
      ...fontGroups,
    };

    Widget tile(String family, bool mine) {
      final on = family == widget.current;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: on ? p.accentSoft : p.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.pop(context, family),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(family,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: on ? p.onAccentSoft : p.muted)),
                        const SizedBox(height: 4),
                        Text(sampleLine,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Fonts.style(family,
                                size: 18, height: 1.35, color: on ? p.onAccentSoft : p.text)),
                      ],
                    ),
                  ),
                  if (on) Icon(Icons.check_circle_rounded, color: p.accent),
                  if (mine)
                    IconButton(
                      tooltip: 'Hapus font',
                      onPressed: () async {
                        await Fonts.remove(family);
                        if (mounted) setState(() {});
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (_, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Pilih huruf',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                for (final g in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                    child: Text(g.key.toUpperCase(),
                        style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w800,
                            color: p.muted)),
                  ),
                  for (final f in g.value) tile(f, g.key == 'Font kamu'),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.font_download_outlined),
                label: const Text('Tambah font sendiri (.ttf / .otf)'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
