import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'store.dart';

// ------------------------------------------------------------------ zoom

class ZoomPage extends StatelessWidget {
  const ZoomPage({super.key, required this.image, required this.page, required this.dark});
  final Future<Uint8List> image;
  final int page;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Scaffold(
      backgroundColor: p.readerBg,
      appBar: AppBar(title: Text('Hal ${page + 1}')),
      body: FutureBuilder<Uint8List>(
        future: image,
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          Widget img = Image.memory(snap.data!, fit: BoxFit.contain);
          if (dark) img = ColorFiltered(colorFilter: darkPageFilter, child: img);
          return InteractiveViewer(
            minScale: 1,
            maxScale: 6,
            child: Center(child: img),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text('Cubit dua jari buat perbesar atau perkecil',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.muted)),
        ),
      ),
    );
  }
}

const darkPageFilter = ColorFilter.matrix(<double>[
  -0.78, 0, 0, 0, 225, //
  0, -0.78, 0, 0, 228, //
  0, 0, -0.77, 0, 220, //
  0, 0, 0, 1, 0,
]);

// ------------------------------------------------------------------ grid halaman

enum PageFilter { all, marked, noted }

class PageGridPage extends StatefulWidget {
  const PageGridPage({
    super.key,
    required this.count,
    required this.current,
    required this.thumb,
    required this.marks,
    required this.notedPages,
  });

  final int count;
  final int current;
  final Future<Uint8List> Function(int) thumb;
  final Set<int> marks;
  final Set<int> notedPages;

  @override
  State<PageGridPage> createState() => _PageGridPageState();
}

class _PageGridPageState extends State<PageGridPage> {
  PageFilter _filter = PageFilter.all;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final row = widget.current ~/ 3;
      final w = MediaQuery.of(context).size.width;
      final rowH = (w - 32 - 20) / 3 / 0.7 + 40;
      _scroll.jumpTo((row * rowH).clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pages = [
      for (var i = 0; i < widget.count; i++)
        if (_filter == PageFilter.all ||
            (_filter == PageFilter.marked && widget.marks.contains(i)) ||
            (_filter == PageFilter.noted && widget.notedPages.contains(i)))
          i
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Semua halaman')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<PageFilter>(
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(value: PageFilter.all, label: Text('Semua')),
                  ButtonSegment(
                      value: PageFilter.marked, label: Text('Bertab (${widget.marks.length})')),
                  ButtonSegment(
                      value: PageFilter.noted,
                      label: Text('Ada note (${widget.notedPages.length})')),
                ],
                selected: {_filter},
                onSelectionChanged: (s) => setState(() => _filter = s.first),
              ),
            ),
          ),
          Expanded(
            child: pages.isEmpty
                ? Center(
                    child: Text('Belum ada halaman di sini',
                        style: TextStyle(color: p.muted)))
                : GridView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 14,
                      childAspectRatio: 0.58,
                    ),
                    itemCount: pages.length,
                    itemBuilder: (_, k) {
                      final i = pages[k];
                      final here = i == widget.current;
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => Navigator.pop(context, i),
                        child: Column(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: here ? p.accent : p.line, width: here ? 3 : 1),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    FutureBuilder<Uint8List>(
                                      future: widget.thumb(i),
                                      builder: (_, snap) {
                                        if (!snap.hasData) return const SizedBox();
                                        Widget img = Image.memory(snap.data!, fit: BoxFit.cover);
                                        if (dark) {
                                          img = ColorFiltered(colorFilter: darkPageFilter, child: img);
                                        }
                                        return img;
                                      },
                                    ),
                                    if (widget.marks.contains(i))
                                      Positioned(
                                        top: 0,
                                        right: 8,
                                        child: Icon(Icons.bookmark_rounded, color: p.accent, size: 22),
                                      ),
                                    if (widget.notedPages.contains(i))
                                      Positioned(
                                        left: 6,
                                        bottom: 6,
                                        child: Container(
                                          width: 18,
                                          height: 18,
                                          decoration: BoxDecoration(
                                            color: Color(noteColors.first),
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('${i + 1}',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: here ? FontWeight.w800 : FontWeight.w600,
                                    color: here ? p.accent : p.text)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ review

class ReviewCard {
  ReviewCard(this.book, this.note);
  final String book;
  final Note note;
}

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.cards, required this.onOpen});
  final List<ReviewCard> cards;
  final void Function(String book, int page) onOpen;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late final List<ReviewCard> _queue = [...widget.cards]..shuffle();
  late final int _total = _queue.length;
  int _known = 0;
  int _again = 0;

  void _answer(bool knew) {
    setState(() {
      final c = _queue.removeAt(0);
      if (knew) {
        _known++;
      } else {
        _again++;
        _queue.add(c); // muncul lagi di belakang
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final done = _queue.isEmpty;
    final progress = _total == 0 ? 1.0 : _known / _total;

    return Scaffold(
      appBar: AppBar(
        title: Text(done ? 'Review selesai' : 'Review · ${_known + 1} dari $_total'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
              value: progress, minHeight: 4, color: p.accent, backgroundColor: p.line),
        ),
      ),
      body: done ? _summary(p) : _card(p, _queue.first),
      bottomNavigationBar: done
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _answer(false),
                        icon: const Icon(Icons.replay_rounded),
                        label: const Text('Masih lupa'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _answer(true),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Udah paham'),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _card(Pal p, ReviewCard c) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: (child, a) => SlideTransition(
          position: Tween(begin: const Offset(0.15, 0), end: Offset.zero).animate(a),
          child: FadeTransition(opacity: a, child: child),
        ),
        child: Container(
          key: ValueKey('${c.note.id}-$_known-$_again'),
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Color(c.note.color),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(6),
              bottomLeft: Radius.circular(6),
              bottomRight: Radius.circular(28),
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 30, offset: Offset(0, 14))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${Store.title(c.book)} · hal ${c.note.page + 1}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xAA2B2614))),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Text(c.note.text.isEmpty ? '(kosong)' : c.note.text,
                        textAlign: TextAlign.center, style: noteStyle(c.note.font, size: 24)),
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => widget.onOpen(c.book, c.note.page),
                style: FilledButton.styleFrom(
                  backgroundColor: noteInk,
                  foregroundColor: Color(c.note.color),
                  minimumSize: const Size(0, 46),
                ),
                icon: const Icon(Icons.menu_book_rounded, size: 18),
                label: const Text('Buka di halaman'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summary(Pal p) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.eco_rounded, size: 56, color: p.accent),
            const SizedBox(height: 16),
            Text('$_total catatan beres direview',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text)),
            const SizedBox(height: 8),
            Text(
              _again == 0
                  ? 'Semua langsung paham.'
                  : '$_again kali kamu tandai masih lupa, catatan itu diulang sampai paham.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(minimumSize: const Size(200, 52)),
              child: const Text('Selesai'),
            ),
          ],
        ),
      ),
    );
  }
}
