import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:page_flip/page_flip.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const LeafApp());

const _desk = Color(0xFF121C16);
const _paper = Color(0xFFF7F1E3);
const _accent = Color(0xFF8FD18A);

class LeafApp extends StatelessWidget {
  const LeafApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Leaf',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _desk,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomePage(),
    );
  }
}

// ---------------------------------------------------------------- model

class Note {
  Note({
    required this.id,
    required this.page,
    required this.x,
    required this.y,
    required this.color,
    this.text = '',
  });

  final String id;
  final int page; // index halaman (mulai 0)
  double x; // posisi relatif 0..1
  double y;
  int color;
  String text;

  Map<String, dynamic> toJson() =>
      {'id': id, 'page': page, 'x': x, 'y': y, 'color': color, 'text': text};

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: j['id'],
        page: j['page'],
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        color: j['color'],
        text: j['text'] ?? '',
      );
}

const noteColors = <int>[0xFFFFE066, 0xFFFF9EB5, 0xFF9EE6B8, 0xFF9ED0FF];

// ---------------------------------------------------------------- home

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<String> _books = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final list = (sp.getStringList('books') ?? [])
        .where((p) => File(p).existsSync())
        .toList();
    setState(() => _books = list);
  }

  Future<void> _addBook() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final src = res?.files.single.path;
    if (src == null) return;
    // salin ke penyimpanan app supaya nggak hilang
    final dir = await getApplicationDocumentsDirectory();
    final name = src.split(Platform.pathSeparator).last;
    final dest = '${dir.path}${Platform.pathSeparator}$name';
    await File(src).copy(dest);
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList('books') ?? [];
    if (!list.contains(dest)) list.add(dest);
    await sp.setStringList('books', list);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rak Leaf',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .5)),
        backgroundColor: Colors.transparent,
      ),
      body: _books.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Rak masih kosong.\nTambah buku PDF kamu di tombol bawah.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, height: 1.5),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _books.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final p = _books[i];
                final title = p
                    .split(Platform.pathSeparator)
                    .last
                    .replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
                return Material(
                  color: const Color(0xFF1F3027),
                  borderRadius: BorderRadius.circular(14),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    leading: const Icon(Icons.menu_book_rounded,
                        color: _accent, size: 32),
                    title: Text(title,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ReaderPage(path: p)),
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: _addBook,
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('Tambah buku PDF'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: _accent,
            foregroundColor: Colors.black,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- reader

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.path});
  final String path;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final _flipKey = GlobalKey<PageFlipWidgetState>();
  PdfDocument? _doc;
  int _pageCount = 0;
  int _current = 0;
  int _startIndex = 0;
  List<Widget> _pages = const [];
  final Map<int, Future<Uint8List>> _cache = {};
  Future<void> _renderLock = Future.value();

  List<Note> _notes = [];
  Set<int> _bookmarks = {};
  SharedPreferences? _sp;

  String get _kNotes => 'notes::${widget.path}';
  String get _kMarks => 'marks::${widget.path}';
  String get _kLast => 'last::${widget.path}';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _sp = await SharedPreferences.getInstance();
    final doc = await PdfDocument.openFile(widget.path);
    final notesRaw = _sp!.getString(_kNotes);
    setState(() {
      _doc = doc;
      _pageCount = doc.pagesCount;
      _current = (_sp!.getInt(_kLast) ?? 0).clamp(0, doc.pagesCount - 1);
      _startIndex = _current;
      // dibuat sekali supaya flip nggak ke-reset tiap setState
      _pages = List.generate(doc.pagesCount, _pageView);
      _bookmarks =
          (_sp!.getStringList(_kMarks) ?? []).map(int.parse).toSet();
      if (notesRaw != null) {
        _notes = (jsonDecode(notesRaw) as List)
            .map((e) => Note.fromJson(e))
            .toList();
      }
    });
  }

  @override
  void dispose() {
    _doc?.close();
    super.dispose();
  }

  Future<void> _saveNotes() => _sp!
      .setString(_kNotes, jsonEncode(_notes.map((n) => n.toJson()).toList()));

  Future<void> _saveMarks() => _sp!.setStringList(
      _kMarks, (_bookmarks.toList()..sort()).map((e) => '$e').toList());

  // render halaman satu per satu (antre) biar pdfx nggak rebutan
  Future<Uint8List> _render(int i) {
    return _cache.putIfAbsent(i, () {
      final c = Completer<Uint8List>();
      _renderLock = _renderLock.then((_) async {
        try {
          final page = await _doc!.getPage(i + 1);
          final img = await page.render(
            width: page.width * 2,
            height: page.height * 2,
            format: PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
          );
          await page.close();
          c.complete(img!.bytes);
        } catch (e) {
          c.completeError(e);
        }
      });
      return c.future;
    });
  }

  Widget _pageView(int i) {
    return Container(
      color: Colors.white,
      child: FutureBuilder<Uint8List>(
        future: _render(i),
        builder: (_, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Image.memory(snap.data!, fit: BoxFit.contain);
        },
      ),
    );
  }

  void _addNote() {
    final n = Note(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      page: _current,
      x: 0.35,
      y: 0.35,
      color: noteColors[_notes.length % noteColors.length],
    );
    setState(() => _notes.add(n));
    _editNote(n, isNew: true);
  }

  Future<void> _editNote(Note n, {bool isNew = false}) async {
    final ctrl = TextEditingController(text: n.text);
    int color = n.color;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF18261F),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sticky note · hal. ${n.page + 1}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Contoh: rumus ini sering keluar di ujian',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final c in noteColors)
                    GestureDetector(
                      onTap: () => setS(() => color = c),
                      child: Container(
                        width: 36,
                        height: 36,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: color == c
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 3),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(ctx, 'delete'),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Hapus'),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, 'save'),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Simpan'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: _accent,
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    setState(() {
      if (action == 'save') {
        n.text = ctrl.text.trim();
        n.color = color;
      } else if (action == 'delete' || (isNew && action == null)) {
        _notes.remove(n);
      }
    });
    await _saveNotes();
  }

  Widget _noteOverlay(double w, double h) {
    final here = _notes.where((n) => n.page == _current);
    return Stack(
      children: [
        for (final n in here)
          Positioned(
            left: n.x * w,
            top: n.y * h,
            child: GestureDetector(
              onTap: () => _editNote(n),
              onPanUpdate: (d) => setState(() {
                n.x = (n.x + d.delta.dx / w).clamp(0.0, 0.8);
                n.y = (n.y + d.delta.dy / h).clamp(0.0, 0.9);
              }),
              onPanEnd: (_) => _saveNotes(),
              child: Transform.rotate(
                angle: -0.03,
                child: Container(
                  width: 120,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Color(n.color),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black38,
                          blurRadius: 8,
                          offset: Offset(2, 4)),
                    ],
                  ),
                  child: Text(
                    n.text.isEmpty ? '(kosong)' : n.text,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.black87, fontSize: 13, height: 1.25),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _tabs() {
    final marks = _bookmarks.toList()..sort();
    if (marks.isEmpty) return const SizedBox(height: 8);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final p in marks)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonal(
                onPressed: () => _flipKey.currentState?.goToPage(p),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  backgroundColor: p == _current
                      ? _accent
                      : const Color(0xFF1F3027),
                  foregroundColor:
                      p == _current ? Colors.black : Colors.white,
                ),
                child: Text('Hal ${p + 1}'),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_doc == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final marked = _bookmarks.contains(_current);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('Hal ${_current + 1} / $_pageCount',
            style: const TextStyle(fontSize: 16)),
      ),
      body: Column(
        children: [
          _tabs(),
          Expanded(
            child: LayoutBuilder(
              builder: (_, box) => Stack(
                children: [
                  PageFlipWidget(
                    key: _flipKey,
                    backgroundColor: _desk,
                    showDragCutoff: false,
                    initialIndex: _startIndex,
                    lastPage: Container(
                      color: _paper,
                      child: const Center(child: Text('— Tamat —',
                          style: TextStyle(color: Colors.black54))),
                    ),
                    onPageFlipped: (i) {
                      setState(() => _current = i);
                      _sp?.setInt(_kLast, i);
                    },
                    children: _pages,
                  ),
                  _noteOverlay(box.maxWidth, box.maxHeight),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _addNote,
                icon: const Icon(Icons.sticky_note_2_rounded),
                label: const Text('Sticky note'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: _accent,
                  foregroundColor: Colors.black,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () async {
                  setState(() => marked
                      ? _bookmarks.remove(_current)
                      : _bookmarks.add(_current));
                  await _saveMarks();
                },
                icon: Icon(marked
                    ? Icons.bookmark_remove_rounded
                    : Icons.bookmark_add_rounded),
                label: Text(marked ? 'Lepas tab' : 'Pasang tab'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
