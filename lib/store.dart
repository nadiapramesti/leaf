import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ------------------------------------------------------------------ warna

class Pal {
  const Pal({
    required this.bg,
    required this.surface,
    required this.nav,
    required this.text,
    required this.muted,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.onAccentSoft,
    required this.readerBg,
    required this.pen,
  });

  final Color bg, surface, nav, text, muted, line, accent, onAccent;
  final Color accentSoft, onAccentSoft, readerBg, pen;

  static const light = Pal(
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFF1F4F1),
    nav: Color(0xFFF6F8F6),
    text: Color(0xFF1B1F1C),
    muted: Color(0xFF5F6B63),
    line: Color(0xFFE3E8E4),
    accent: Color(0xFF246B43),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFD6ECDD),
    onAccentSoft: Color(0xFF1A5232),
    readerBg: Color(0xFFF1F4F1),
    pen: Color(0xFF1E2B3A),
  );

  static const dark = Pal(
    bg: Color(0xFF121613),
    surface: Color(0xFF1F2520),
    nav: Color(0xFF181D19),
    text: Color(0xFFE8ECE8),
    muted: Color(0xFF9BA79F),
    line: Color(0xFF2A312C),
    accent: Color(0xFF8FD6A6),
    onAccent: Color(0xFF121613),
    accentSoft: Color(0xFF24402E),
    onAccentSoft: Color(0xFFB9EBC8),
    readerBg: Color(0xFF0D100E),
    pen: Color(0xFFE6EDF5),
  );

  static Pal of(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? dark : light;
}

ThemeData leafTheme(Brightness b) {
  final p = b == Brightness.dark ? Pal.dark : Pal.light;
  final base = ThemeData(useMaterial3: true, brightness: b);
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF246B43),
    brightness: b,
  ).copyWith(
    primary: p.accent,
    onPrimary: p.onAccent,
    secondaryContainer: p.accentSoft,
    onSecondaryContainer: p.onAccentSoft,
    surface: p.bg,
    onSurface: p.text,
    outline: p.line,
    outlineVariant: p.line,
  );
  final radius = BorderRadius.circular(14);
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .apply(bodyColor: p.text, displayColor: p.text),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.nav,
      indicatorColor: p.accentSoft,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dividerColor: p.line,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      hintStyle: TextStyle(color: p.muted),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder:
          OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: radius, borderSide: BorderSide(color: p.accent, width: 2)),
    ),
  );
}

// ------------------------------------------------------------------ model

const noteColors = <int>[0xFFFFE27A, 0xFFFFA8BE, 0xFFA9EBC2, 0xFF9FD4FF];
const noteInk = Color(0xFF2B2614);

const fontFamilies = <String, String>{
  'rapi': 'Plus Jakarta Sans',
  'buku': 'Fraunces',
  'tangan': 'Caveat',
  'tebal': 'Archivo Black',
};
const fontLabels = <String, String>{
  'rapi': 'Rapi',
  'buku': 'Buku',
  'tangan': 'Tulisan',
  'tebal': 'Tebal',
};

TextStyle noteStyle(String font, {double size = 13, Color color = noteInk}) {
  final fam = fontFamilies[font] ?? 'Plus Jakarta Sans';
  final s = font == 'tangan' ? size * 1.3 : size;
  return GoogleFonts.getFont(fam,
      fontSize: s, color: color, height: 1.3, fontWeight: FontWeight.w600);
}

class Note {
  Note({
    required this.id,
    required this.page,
    required this.x,
    required this.y,
    required this.color,
    this.text = '',
    this.font = 'rapi',
  });

  final String id;
  final int page;
  double x;
  double y;
  int color;
  String text;
  String font;

  Map<String, dynamic> toJson() => {
        'id': id,
        'page': page,
        'x': x,
        'y': y,
        'color': color,
        'text': text,
        'font': font,
      };

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: '${j['id']}',
        page: (j['page'] as num).toInt(),
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        color: (j['color'] as num).toInt(),
        text: '${j['text'] ?? ''}',
        font: '${j['font'] ?? 'rapi'}',
      );
}

/// Coretan stylus/jari. Titik disimpan relatif (0..1) terhadap halaman.
class InkStroke {
  InkStroke({required this.page, required this.tool, List<Offset>? pts, List<int>? ts})
      : pts = pts ?? [],
        ts = ts ?? [];

  final int page;
  final String tool; // 'pen' | 'hl'
  final List<Offset> pts;
  final List<int> ts;

  void add(Offset p, int t) {
    pts.add(p);
    ts.add(t);
  }

  Map<String, dynamic> toJson() => {
        'page': page,
        'tool': tool,
        'p': [for (final o in pts) ...[o.dx, o.dy]],
        't': ts,
      };

  factory InkStroke.fromJson(Map<String, dynamic> j) {
    final raw = (j['p'] as List).map((e) => (e as num).toDouble()).toList();
    final pts = <Offset>[
      for (var i = 0; i + 1 < raw.length; i += 2) Offset(raw[i], raw[i + 1])
    ];
    final ts = (j['t'] as List).map((e) => (e as num).toInt()).toList();
    return InkStroke(
      page: (j['page'] as num).toInt(),
      tool: '${j['tool']}',
      pts: pts,
      ts: ts,
    );
  }
}

// ------------------------------------------------------------------ simpan

class Store {
  static late SharedPreferences sp;
  static final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

  static Future<void> init() async {
    sp = await SharedPreferences.getInstance();
    final i = sp.getInt('theme') ?? 0;
    themeMode.value = ThemeMode.values[i.clamp(0, 2)];
  }

  static void toggleTheme(Brightness now) {
    final next = now == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
    themeMode.value = next;
    sp.setInt('theme', next.index);
  }

  static List<String> books() => (sp.getStringList('books') ?? [])
      .where((p) => File(p).existsSync())
      .toList();

  static Future<String> importPdf(String src) async {
    final dir = await getApplicationDocumentsDirectory();
    var name = src.split(Platform.pathSeparator).last;
    if (!name.toLowerCase().endsWith('.pdf')) name = '$name.pdf';
    var dest = '${dir.path}${Platform.pathSeparator}$name';
    var n = 2;
    while (File(dest).existsSync() && !books().contains(dest)) {
      dest = '${dir.path}${Platform.pathSeparator}${n++}_$name';
    }
    if (!File(dest).existsSync()) await File(src).copy(dest);
    final list = sp.getStringList('books') ?? [];
    if (!list.contains(dest)) list.insert(0, dest);
    await sp.setStringList('books', list);
    return dest;
  }

  static Future<void> removeBook(String p) async {
    final list = sp.getStringList('books') ?? [];
    list.remove(p);
    await sp.setStringList('books', list);
    for (final k in ['notes', 'marks', 'last', 'count', 'ink', 'title']) {
      await sp.remove('$k::$p');
    }
    if (sp.getString('opened') == p) await sp.remove('opened');
    try {
      await File(p).delete();
    } catch (_) {}
  }

  static String title(String p) {
    final custom = sp.getString('title::$p');
    if (custom != null && custom.trim().isNotEmpty) return custom;
    return fileTitle(p);
  }

  static Future<void> setTitle(String p, String t) => sp.setString('title::$p', t.trim());

  static String fileTitle(String p) => p
      .split(Platform.pathSeparator)
      .last
      .replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '')
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .trim();

  static String? lastOpened() {
    final p = sp.getString('opened');
    return (p != null && File(p).existsSync()) ? p : null;
  }

  static void setOpened(String p) => sp.setString('opened', p);

  static int lastPage(String p) => sp.getInt('last::$p') ?? 0;
  static void setLastPage(String p, int i) => sp.setInt('last::$p', i);
  static int pageCount(String p) => sp.getInt('count::$p') ?? 0;
  static void setPageCount(String p, int n) => sp.setInt('count::$p', n);

  static double progress(String p) {
    final n = pageCount(p);
    if (n <= 1) return 0;
    return (lastPage(p) / (n - 1)).clamp(0.0, 1.0);
  }

  static List<Note> notes(String p) {
    final raw = sp.getString('notes::$p');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Note.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveNotes(String p, List<Note> n) => sp.setString(
      'notes::$p', jsonEncode(n.map((e) => e.toJson()).toList()));

  static Set<int> marks(String p) =>
      (sp.getStringList('marks::$p') ?? []).map(int.parse).toSet();

  static Future<void> saveMarks(String p, Set<int> m) => sp.setStringList(
      'marks::$p', (m.toList()..sort()).map((e) => '$e').toList());

  static List<InkStroke> ink(String p) {
    final raw = sp.getString('ink::$p');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => InkStroke.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveInk(String p, List<InkStroke> s) => sp.setString(
      'ink::$p', jsonEncode(s.map((e) => e.toJson()).toList()));
}

// ------------------------------------------------------------------ sampul

/// Sampul buku = halaman pertama PDF, dirender sekali lalu disimpan.
class Thumbs {
  static final Map<String, Future<Uint8List?>> _cache = {};
  static Future<void> _lock = Future.value();

  static Future<Uint8List?> of(String path) =>
      _cache.putIfAbsent(path, () {
        final c = Completer<Uint8List?>();
        _lock = _lock.then((_) async => c.complete(await _make(path)));
        return c.future;
      });

  static Future<Uint8List?> _make(String path) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}${Platform.pathSeparator}thumb_${path.hashCode.abs()}.jpg');
      if (await f.exists()) return await f.readAsBytes();
      final doc = await PdfDocument.openFile(path);
      final page = await doc.getPage(1);
      final img = await page.render(
        width: 360,
        height: 360 * page.height / page.width,
        format: PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
      );
      final count = doc.pagesCount;
      await page.close();
      await doc.close();
      if (Store.pageCount(path) == 0) Store.setPageCount(path, count);
      if (img == null) return null;
      await f.writeAsBytes(img.bytes);
      return img.bytes;
    } catch (_) {
      return null;
    }
  }
}
