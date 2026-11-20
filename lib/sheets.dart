import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart'
    as mk;

import 'store.dart';

class NoteResult {
  NoteResult({required this.text, required this.font, required this.color, this.delete = false});
  final String text;
  final String font;
  final int color;
  final bool delete;
}

// ------------------------------------------------------------------ pilihan

class FontPicker extends StatelessWidget {
  const FontPicker({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final k in fontFamilies.keys)
          ChoiceChip(
            showCheckmark: false,
            selected: value == k,
            onSelected: (_) => onChanged(k),
            label: Text(fontLabels[k]!, style: noteStyle(k, size: 15, color: p.text)),
          ),
      ],
    );
  }
}

class ColorPicker extends StatelessWidget {
  const ColorPicker({super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    const names = ['Kuning', 'Pink', 'Hijau', 'Biru'];
    return Row(
      children: [
        for (var i = 0; i < noteColors.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Semantics(
              button: true,
              selected: value == noteColors[i],
              label: names[i],
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onChanged(noteColors[i]),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Color(noteColors[i]),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: value == noteColors[i] ? p.accent : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: value == noteColors[i]
                      ? const Icon(Icons.check_rounded, color: noteInk, size: 20)
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Widget _label(BuildContext c, String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: Pal.of(c).muted)),
    );

// ------------------------------------------------------------------ edit note

Future<NoteResult?> showNoteSheet(BuildContext context, Note n, {bool isNew = false}) {
  return showModalBottomSheet<NoteResult>(
    context: context,
    isScrollControlled: true,
    enableDrag: false,
    builder: (_) => _NoteSheet(note: n, isNew: isNew),
  );
}

class _NoteSheet extends StatefulWidget {
  const _NoteSheet({required this.note, required this.isNew});
  final Note note;
  final bool isNew;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  late final _ctrl = TextEditingController(text: widget.note.text);
  late String _font = widget.note.font;
  late int _color = widget.note.color;
  bool _pad = false;

  @override
  void initState() {
    super.initState();
    InkEngine.warmIfReady(Store.sp.getString('ink_lang') ?? 'id');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _openPad() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _pad = true);
  }

  void _append(String t) {
    final cur = _ctrl.text.trimRight();
    _ctrl.text = cur.isEmpty ? t : '$cur $t';
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        physics: _pad ? const NeverScrollableScrollPhysics() : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Sticky note',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700, color: p.text)),
                ),
                Text('Hal ${widget.note.page + 1}',
                    style: TextStyle(fontSize: 13, color: p.muted)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _label(context, 'Isi catatan')),
                if (!_pad)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: FilledButton.tonalIcon(
                      onPressed: _openPad,
                      icon: const Icon(Icons.draw_rounded, size: 18),
                      label: const Text('Tulis tangan'),
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
                    ),
                  ),
              ],
            ),
            if (_pad) ...[
              HandwritingPad(onText: _append, onClose: () => setState(() => _pad = false)),
              const SizedBox(height: 10),
            ],
            Listener(
              onPointerDown: (e) {
                if (e.kind == PointerDeviceKind.stylus ||
                    e.kind == PointerDeviceKind.invertedStylus) {
                  _openPad();
                }
              },
              child: TextField(
              controller: _ctrl,
              autofocus: widget.isNew && !_pad,
              readOnly: _pad,
              stylusHandwritingEnabled: false,
              maxLines: 4,
              minLines: 3,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: noteStyle(_font, size: 15, color: p.text),
              decoration: InputDecoration(
                  hintText: _pad
                      ? 'Hasil tulisan tangan muncul di sini'
                      : 'Contoh: rumus ini sering keluar di ujian'),
            ),
            ),
            const SizedBox(height: 16),
            _label(context, 'Gaya huruf'),
            FontPicker(value: _font, onChanged: (v) => setState(() => _font = v)),
            const SizedBox(height: 16),
            _label(context, 'Warna'),
            ColorPicker(value: _color, onChanged: (v) => setState(() => _color = v)),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(
                        context, NoteResult(text: '', font: _font, color: _color, delete: true)),
                    icon: Icon(widget.isNew ? Icons.close_rounded : Icons.delete_outline),
                    label: Text(widget.isNew ? 'Batal' : 'Hapus'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context,
                        NoteResult(text: _ctrl.text.trim(), font: _font, color: _color)),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Simpan'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
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

// ------------------------------------------------------------------ tulisan -> teks

const _langs = <String, String>{'id': 'Indonesia', 'en-US': 'English', 'ja': '日本語'};

Future<NoteResult?> showConvertSheet(
    BuildContext context, List<InkStroke> strokes, Size pageSize) {
  return showModalBottomSheet<NoteResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ConvertSheet(strokes: strokes, size: pageSize),
  );
}

class _ConvertSheet extends StatefulWidget {
  const _ConvertSheet({required this.strokes, required this.size});
  final List<InkStroke> strokes;
  final Size size;

  @override
  State<_ConvertSheet> createState() => _ConvertSheetState();
}

class _ConvertSheetState extends State<_ConvertSheet> {
  final _ctrl = TextEditingController();
  String _lang = Store.sp.getString('ink_lang') ?? 'id';
  String _font = 'rapi';
  int _color = noteColors.first;
  bool _loading = true;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _recognize();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _recognize() async {
    setState(() {
      _loading = true;
      _error = null;
      _status = 'Membaca tulisan…';
    });
    try {
      if (!await InkEngine.isDownloaded(_lang) && mounted) {
        setState(() => _status = 'Mengunduh model bahasa (sekali aja)…');
      }
      final text = await recognizeInk(widget.strokes, widget.size, _lang);
      if (!mounted) return;
      setState(() {
        _ctrl.text = text;
        _loading = false;
        if (text.isEmpty) _error = 'Tulisan belum kebaca. Ketik manual aja di bawah.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Gagal membaca tulisan. Pertama kali butuh internet buat unduh model.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ubah ke teks',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text)),
            const SizedBox(height: 14),
            _label(context, 'Bahasa tulisan'),
            Wrap(
              spacing: 8,
              children: [
                for (final e in _langs.entries)
                  ChoiceChip(
                    showCheckmark: false,
                    selected: _lang == e.key,
                    label: Text(e.value),
                    onSelected: _loading
                        ? null
                        : (_) {
                            setState(() => _lang = e.key);
                            Store.sp.setString('ink_lang', e.key);
                            _recognize();
                          },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _label(context, 'Hasil (bisa diedit)'),
            if (_loading)
              Container(
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: p.surface, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: p.accent)),
                    const SizedBox(width: 12),
                    Text(_status ?? '', style: TextStyle(color: p.muted)),
                  ],
                ),
              )
            else
              TextField(
                controller: _ctrl,
                maxLines: 4,
                minLines: 3,
                style: noteStyle(_font, size: 15, color: p.text),
                decoration: InputDecoration(
                  hintText: 'Contoh: rumus ini sering keluar di ujian',
                  helperText: _error,
                  helperMaxLines: 2,
                ),
              ),
            const SizedBox(height: 16),
            _label(context, 'Gaya huruf'),
            FontPicker(value: _font, onChanged: (v) => setState(() => _font = v)),
            const SizedBox(height: 16),
            _label(context, 'Warna note'),
            ColorPicker(value: _color, onChanged: (v) => setState(() => _color = v)),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    child: const Text('Batal'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loading
                        ? null
                        : () => Navigator.pop(context,
                            NoteResult(text: _ctrl.text.trim(), font: _font, color: _color)),
                    icon: const Icon(Icons.sticky_note_2_rounded),
                    label: const Text('Jadikan note'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
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


// ------------------------------------------------------------------ pengenal tulisan

/// Mesin pengenal tulisan disiapkan sekali per bahasa, lalu dipakai ulang (biar cepat).
class InkEngine {
  static final Map<String, mk.DigitalInkRecognizer> _rec = {};
  static final Map<String, Future<void>> _ready = {};

  static Future<bool> isDownloaded(String lang) =>
      mk.DigitalInkRecognizerModelManager().isModelDownloaded(lang);

  static Future<void> warm(String lang) {
    return _ready.putIfAbsent(lang, () async {
      try {
        final mm = mk.DigitalInkRecognizerModelManager();
        if (!await mm.isModelDownloaded(lang)) {
          await mm.downloadModel(lang, isWifiRequired: false);
        }
        final r = mk.DigitalInkRecognizer(languageCode: lang);
        // pancingan kecil supaya model langsung dimuat ke memori
        final ink = mk.Ink();
        final st = mk.Stroke();
        st.points.add(mk.StrokePoint(x: 0, y: 0, t: 0));
        st.points.add(mk.StrokePoint(x: 10, y: 10, t: 20));
        ink.strokes.add(st);
        try {
          await r.recognize(ink);
        } catch (_) {}
        _rec[lang] = r;
      } catch (e) {
        _ready.remove(lang);
        rethrow;
      }
    });
  }

  /// siapkan diam-diam kalau modelnya sudah ada di HP (tanpa unduh)
  static Future<void> warmIfReady(String lang) async {
    try {
      if (await isDownloaded(lang)) await warm(lang);
    } catch (_) {}
  }
}

Future<String> recognizeInk(List<InkStroke> strokes, Size size, String lang) async {
  await InkEngine.warm(lang);
  final ink = mk.Ink();
  for (final s in strokes) {
    final st = mk.Stroke();
    for (var i = 0; i < s.pts.length; i++) {
      st.points.add(mk.StrokePoint(
        x: s.pts[i].dx * size.width,
        y: s.pts[i].dy * size.height,
        t: s.ts[i],
      ));
    }
    ink.strokes.add(st);
  }
  final c = await InkEngine._rec[lang]!.recognize(ink);
  return c.isNotEmpty ? c.first.text : '';
}

/// Papan tulis tangan: tulis pakai stylus/jari, jeda sebentar, otomatis jadi teks.
class HandwritingPad extends StatefulWidget {
  const HandwritingPad({super.key, required this.onText, required this.onClose});
  final ValueChanged<String> onText;
  final VoidCallback onClose;

  @override
  State<HandwritingPad> createState() => _HandwritingPadState();
}

class _HandwritingPadState extends State<HandwritingPad> {
  final List<InkStroke> _strokes = [];
  InkStroke? _live;
  int? _pointer;
  Timer? _wait;
  bool _busy = false;
  String? _msg;
  Size _size = const Size(1, 1);
  String _lang = Store.sp.getString('ink_lang') ?? 'id';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    setState(() => _ready = false);
    final lang = _lang;
    try {
      final had = await InkEngine.isDownloaded(lang);
      if (!had && mounted) setState(() => _msg = 'Mengunduh model bahasa (sekali aja)…');
      await InkEngine.warm(lang);
      if (!mounted || lang != _lang) return;
      setState(() {
        _ready = true;
        if (!had) _msg = null;
      });
    } catch (_) {
      if (mounted) setState(() => _msg = 'Pertama kali butuh internet buat unduh model bahasa');
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  Offset _n(Offset o) => Offset(
      (o.dx / _size.width).clamp(0.0, 1.0), (o.dy / _size.height).clamp(0.0, 1.0));

  void _down(PointerDownEvent e) {
    if (_pointer != null || _busy) return;
    _wait?.cancel();
    _pointer = e.pointer;
    setState(() {
      _msg = null;
      _live = InkStroke(page: 0, tool: 'pen')..add(_n(e.localPosition), e.timeStamp.inMilliseconds);
    });
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer || _live == null) return;
    setState(() => _live!.add(_n(e.localPosition), e.timeStamp.inMilliseconds));
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    final s = _live;
    setState(() {
      _live = null;
      if (s != null && s.pts.length > 1) _strokes.add(s);
    });
    _wait?.cancel();
    _wait = Timer(const Duration(milliseconds: 650), _recognize);
  }

  Future<void> _recognize() async {
    if (_strokes.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final text = await recognizeInk(List.of(_strokes), _size, _lang);
      if (!mounted) return;
      setState(() {
        _strokes.clear();
        _busy = false;
        if (text.trim().isEmpty) _msg = 'Belum kebaca, coba tulis lebih besar';
      });
      if (text.trim().isNotEmpty) widget.onText(text.trim());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _msg = 'Pertama kali butuh internet buat unduh model bahasa';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final shown = [..._strokes, if (_live != null) _live!];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 170,
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.accent, width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(builder: (_, box) {
            _size = Size(box.maxWidth, box.maxHeight);
            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: _up,
              // klaim geser supaya sheet nggak ikut kegeser waktu nulis
              child: RawGestureDetector(
                gestures: {
                  _AlwaysWinPan: GestureRecognizerFactoryWithHandlers<_AlwaysWinPan>(
                    () => _AlwaysWinPan(),
                    (r) => r
                      ..onStart = (_) {}
                      ..onUpdate = (_) {},
                  ),
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(painter: _PadPainter(shown, p.pen)),
                    ),
                    if (shown.isEmpty)
                      Center(
                        child: Text(_msg ?? 'Tulis di sini pakai stylus',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: p.muted, fontSize: 15)),
                      ),
                    if (_busy || !_ready)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: p.accent),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final e in _langs.entries)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  selected: _lang == e.key,
                  label: Text(e.value),
                  onSelected: (_) {
                    setState(() => _lang = e.key);
                    Store.sp.setString('ink_lang', e.key);
                    _prepare();
                  },
                ),
              ),
            const Spacer(),
            IconButton.outlined(
              tooltip: 'Hapus coretan',
              onPressed: () => setState(() {
                _strokes.clear();
                _msg = null;
              }),
              icon: const Icon(Icons.backspace_outlined, size: 20),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: 'Pakai keyboard',
              onPressed: widget.onClose,
              icon: const Icon(Icons.keyboard_rounded, size: 20),
            ),
          ],
        ),
      ],
    );
  }
}

class _AlwaysWinPan extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.strokes, this.color);
  final List<InkStroke> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in strokes) {
      if (s.pts.isEmpty) continue;
      final path = Path()..moveTo(s.pts[0].dx * size.width, s.pts[0].dy * size.height);
      for (final o in s.pts.skip(1)) {
        path.lineTo(o.dx * size.width, o.dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PadPainter old) => true;
}
