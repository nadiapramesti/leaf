import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'extras.dart';
import 'reader.dart';
import 'store.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  String _query = '';
  String? _bookFilter;
  String _noteQuery = '';
  bool _busy = false;

  Future<void> _open(String path, {int? page}) async {
    Store.setOpened(path);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReaderPage(path: path, openAt: page)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _addPdf() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final src = res?.files.single.path;
    if (src == null) return;
    setState(() => _busy = true);
    try {
      final dest = await Store.importPdf(src);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${Store.title(dest)} masuk rak')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal menambah PDF, coba file lain')),
      );
    }
  }

  Future<void> _bookMenu(String path) async {
    final act = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(ctx).viewPadding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(Store.title(path),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.pop(ctx, 'rename'),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Ganti judul'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Hapus dari rak'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          ],
        ),
      ),
    );
    if (act == 'rename') await _rename(path);
    if (act == 'delete') await _confirmDelete(path);
  }

  Future<void> _pickGoal() async {
    final g = await showModalBottomSheet<int>(
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
              Text('Target baca harian',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text)),
              const SizedBox(height: 6),
              Text('Streak nambah tiap hari kamu baca minimal 1 menit.',
                  style: TextStyle(color: p.muted)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in [10, 15, 20, 30, 45, 60])
                    ChoiceChip(
                      showCheckmark: false,
                      selected: Store.dailyGoal == m,
                      label: Text('$m menit'),
                      onSelected: (_) => Navigator.pop(ctx, m),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (g == null) return;
    await Store.setGoal(g);
    if (mounted) setState(() {});
  }

  Future<void> _rename(String path) async {
    final ctrl = TextEditingController(text: Store.title(path));
    final t = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ganti judul'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: 'Contoh: ${Store.fileTitle(path)}'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Simpan')),
        ],
      ),
    );
    ctrl.dispose();
    if (t == null) return;
    await Store.setTitle(path, t);
    if (mounted) setState(() {});
  }

  void _startReview(List<String> books) {
    final cards = [
      for (final b in books)
        for (final n in Store.notes(b))
          if (n.text.trim().isNotEmpty) ReviewCard(b, n)
    ];
    if (cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Belum ada catatan berisi buat direview')));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => ReviewPage(
          cards: cards,
          onOpen: (book, page) {
            Navigator.pop(ctx);
            _open(book, page: page);
          },
        ),
      ),
    );
  }

  Future<void> _copyNotes(List<String> books) async {
    final buf = StringBuffer();
    for (final b in books) {
      final notes = Store.notes(b)..sort((a, c) => a.page.compareTo(c.page));
      if (notes.isEmpty) continue;
      buf.writeln('# ${Store.title(b)}');
      for (final n in notes) {
        if (n.text.trim().isEmpty) continue;
        buf.writeln('- (hal ${n.page + 1}) ${n.text.trim()}');
      }
      buf.writeln();
    }
    await Clipboard.setData(ClipboardData(text: buf.toString().trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catatan disalin, tinggal tempel di mana aja')));
  }

  Future<void> _confirmDelete(String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus dari rak?'),
        content: Text(
            '${Store.title(path)} beserta catatan dan coretannya akan dihapus.'),
        actions: [
          OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok == true) {
      await Store.removeBook(path);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: _tab == 0 ? _library(p) : _notesTab(p),
          ),
        ),
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _addPdf,
              icon: _busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: p.onAccent))
                  : const Icon(Icons.add_rounded),
              label: const Text('Tambah PDF',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              backgroundColor: p.accent,
              foregroundColor: p.onAccent,
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.auto_stories_outlined),
              selectedIcon: Icon(Icons.auto_stories),
              label: 'Rak'),
          NavigationDestination(
              icon: Icon(Icons.sticky_note_2_outlined),
              selectedIcon: Icon(Icons.sticky_note_2),
              label: 'Catatan'),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- rak

  Widget _library(Pal p) {
    final all = Store.books();
    final books = _query.isEmpty
        ? all
        : all
            .where((b) =>
                Store.title(b).toLowerCase().contains(_query.toLowerCase()))
            .toList();
    final last = Store.lastOpened();
    final dark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _query = v.trim()),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Contoh: basis data',
                  prefixIcon: const Icon(Icons.search_rounded),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide(color: p.accent, width: 2)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              tooltip: dark ? 'Mode terang' : 'Mode gelap',
              iconSize: 22,
              style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
              onPressed: () => Store.toggleTheme(Theme.of(context).brightness),
              icon: Icon(dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            ),
          ],
        ),
        if (all.isNotEmpty && _query.isEmpty) ...[
          const SizedBox(height: 14),
          _StatsCard(onTap: _pickGoal),
        ],
        if (last != null && _query.isEmpty) ...[
          const SizedBox(height: 22),
          Text('Lanjut baca',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
          const SizedBox(height: 12),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _open(last),
              child: Ink(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: p.line),
                ),
                child: Row(
                  children: [
                    SizedBox(width: 64, height: 92, child: _Cover(path: last)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(Store.title(last),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
                          const SizedBox(height: 4),
                          Text(
                            Store.pageCount(last) > 0
                                ? 'hal ${Store.lastPage(last) + 1} dari ${Store.pageCount(last)}'
                                : 'Belum dibuka',
                            style: TextStyle(fontSize: 13, color: p.muted),
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: Store.progress(last),
                              minHeight: 4,
                              color: p.accent,
                              backgroundColor: p.line,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(_query.isEmpty ? 'Rak kamu' : 'Hasil cari',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
            ),
            Text('${books.length} buku', style: TextStyle(fontSize: 13, color: p.muted)),
          ],
        ),
        const SizedBox(height: 14),
        if (books.isEmpty)
          _Empty(
            icon: Icons.auto_stories_outlined,
            text: all.isEmpty
                ? 'Rak masih kosong.\nTambah PDF pertamamu lewat tombol di bawah.'
                : 'Nggak ada buku dengan judul itu.',
          )
        else
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              crossAxisSpacing: 16,
              mainAxisSpacing: 20,
              childAspectRatio: 0.5,
            ),
            children: [
              for (final b in books)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _open(b),
                  onLongPress: () => _bookMenu(b),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(aspectRatio: 0.68, child: _Cover(path: b)),
                      const SizedBox(height: 8),
                      Text(Store.title(b),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              color: p.text)),
                      const SizedBox(height: 2),
                      Text(
                        Store.pageCount(b) == 0
                            ? 'Baru'
                            : '${(Store.progress(b) * 100).round()}%',
                        style: TextStyle(fontSize: 12, color: p.muted),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }

  // ---------------------------------------------------------------- catatan

  Widget _notesTab(Pal p) {
    final books = Store.books();
    final withNotes = [
      for (final b in books)
        if (Store.notes(b).isNotEmpty) b
    ];
    final q = _noteQuery.toLowerCase();
    List<Note> matched(String b) => (Store.notes(b)
          ..sort((a, c) => a.page.compareTo(c.page)))
        .where((n) => q.isEmpty || n.text.toLowerCase().contains(q))
        .toList();
    final shown = (_bookFilter == null || !withNotes.contains(_bookFilter)
            ? withNotes
            : [_bookFilter!])
        .where((b) => matched(b).isNotEmpty)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Text('Catatan',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: p.text)),
        const SizedBox(height: 14),
        if (withNotes.isEmpty)
          const _Empty(
            icon: Icons.sticky_note_2_outlined,
            text: 'Belum ada catatan.\nTempel sticky note waktu baca buku.',
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _startReview(shown),
                  icon: const Icon(Icons.style_rounded, size: 20),
                  label: const Text('Review'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copyNotes(shown),
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  label: const Text('Salin semua'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            onChanged: (v) => setState(() => _noteQuery = v.trim()),
            decoration: const InputDecoration(
              hintText: 'Contoh: normalisasi',
              prefixIcon: Icon(Icons.search_rounded),
              contentPadding: EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip('Semua', _bookFilter == null, () => setState(() => _bookFilter = null)),
                for (final b in withNotes)
                  _chip(Store.title(b), _bookFilter == b,
                      () => setState(() => _bookFilter = b)),
              ],
            ),
          ),
          if (shown.isEmpty)
            const _Empty(icon: Icons.search_off_rounded, text: 'Nggak ada catatan yang cocok.'),
          for (final b in shown) ...[
            const SizedBox(height: 22),
            Text(Store.title(b).toUpperCase(),
                style: TextStyle(
                    fontSize: 12,
                    letterSpacing: .6,
                    fontWeight: FontWeight.w700,
                    color: p.muted)),
            const SizedBox(height: 4),
            for (final n in matched(b))
              InkWell(
                onTap: () => _open(b, page: n.page),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                  decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: p.line))),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 40,
                        decoration: BoxDecoration(
                            color: Color(n.color), borderRadius: BorderRadius.circular(3)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          n.text.isEmpty ? '(kosong)' : n.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: noteStyle(n.font, size: 14, color: p.text),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.tonal(
                        onPressed: () => _open(b, page: n.page),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: Text('Hal ${n.page + 1}'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ],
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          selected: on,
          showCheckmark: false,
          onSelected: (_) => onTap(),
        ),
      );
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final today = Store.secondsOn(DateTime.now()) ~/ 60;
    final goal = Store.dailyGoal;
    final streak = Store.streak();
    final done = today >= goal;
    return Material(
      color: p.accentSoft,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: (today / goal).clamp(0.0, 1.0),
                        strokeWidth: 5,
                        color: p.accent,
                        backgroundColor: p.bg.withValues(alpha: 0.6),
                      ),
                    ),
                    Icon(done ? Icons.check_rounded : Icons.menu_book_rounded,
                        size: 20, color: p.onAccentSoft),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(done ? 'Target hari ini tercapai' : 'Hari ini $today / $goal menit',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, color: p.onAccentSoft)),
                    const SizedBox(height: 2),
                    Text('Ketuk buat ubah target',
                        style: TextStyle(fontSize: 12, color: p.onAccentSoft.withValues(alpha: 0.75))),
                  ],
                ),
              ),
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: p.bg,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_fire_department_rounded,
                        size: 18, color: streak > 0 ? const Color(0xFFE8772E) : p.muted),
                    const SizedBox(width: 4),
                    Text('$streak hari',
                        style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(3), right: Radius.circular(6)),
        boxShadow: const [
          BoxShadow(color: Color(0x26000000), blurRadius: 12, offset: Offset(0, 4))
        ],
        color: const Color(0xFF2F5D45),
      ),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<Uint8List?>(
        future: Thumbs.of(path),
        builder: (_, snap) {
          if (snap.data != null) {
            return Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true);
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(Store.title(path),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.fraunces(
                      fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 48, color: p.muted),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.5, color: p.muted)),
        ],
      ),
    );
  }
}
