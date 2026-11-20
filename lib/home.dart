import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
        child: _tab == 0 ? _library(p) : _notesTab(p),
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
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 14,
            mainAxisSpacing: 18,
            childAspectRatio: 0.48,
            children: [
              for (final b in books)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _open(b),
                  onLongPress: () => _confirmDelete(b),
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
    final shown = _bookFilter == null || !withNotes.contains(_bookFilter)
        ? withNotes
        : [_bookFilter!];

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
          for (final b in shown) ...[
            const SizedBox(height: 22),
            Text(Store.title(b).toUpperCase(),
                style: TextStyle(
                    fontSize: 12,
                    letterSpacing: .6,
                    fontWeight: FontWeight.w700,
                    color: p.muted)),
            const SizedBox(height: 4),
            for (final n in (Store.notes(b)..sort((a, c) => a.page.compareTo(c.page))))
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
