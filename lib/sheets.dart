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

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
            _label(context, 'Isi catatan'),
            TextField(
              controller: _ctrl,
              autofocus: widget.isNew,
              maxLines: 4,
              minLines: 3,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: noteStyle(_font, size: 15, color: p.text),
              decoration: const InputDecoration(
                  hintText: 'Contoh: rumus ini sering keluar di ujian'),
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
      final mm = mk.DigitalInkRecognizerModelManager();
      if (!await mm.isModelDownloaded(_lang)) {
        if (mounted) setState(() => _status = 'Mengunduh model bahasa (sekali aja)…');
        await mm.downloadModel(_lang, isWifiRequired: false);
      }
      final ink = mk.Ink();
      for (final s in widget.strokes) {
        final st = mk.Stroke();
        for (var i = 0; i < s.pts.length; i++) {
          st.points.add(mk.StrokePoint(
            x: s.pts[i].dx * widget.size.width,
            y: s.pts[i].dy * widget.size.height,
            t: s.ts[i],
          ));
        }
        ink.strokes.add(st);
      }
      final rec = mk.DigitalInkRecognizer(languageCode: _lang);
      final cands = await rec.recognize(ink);
      await rec.close();
      if (!mounted) return;
      setState(() {
        _ctrl.text = cands.isNotEmpty ? cands.first.text : '';
        _loading = false;
        if (cands.isEmpty) _error = 'Tulisan belum kebaca. Ketik manual aja di bawah.';
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
