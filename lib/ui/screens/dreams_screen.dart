import 'package:flutter/material.dart';

import '../../data/storage.dart';
import '../../health/presentation/sleep_format.dart';
import '../../social/dream.dart';

/// Dreams: the journal that used to live behind its own tab, with a reading
/// attached to every entry.
///
/// The dream is saved first and the interpretation second. Losing the worker,
/// the network, or the app mid-request must never cost someone the words they
/// just wrote, so the entry exists before the request leaves the phone and the
/// reading is dropped into the same record when it arrives.
class DreamsScreen extends StatefulWidget {
  const DreamsScreen({super.key});

  @override
  State<DreamsScreen> createState() => _DreamsScreenState();
}

class _DreamsScreenState extends State<DreamsScreen> {
  static const Color _readingTint = Color(0xFFF1EDF9);

  late List<Map<String, dynamic>> _entries;
  final Set<int> _pending = <int>{};
  final Map<int, String> _notes = <int, String>{};

  @override
  void initState() {
    super.initState();
    _entries = Storage.getJournalEntries();
  }

  Future<void> _write() async {
    final String? written = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const _DreamComposer()),
    );
    final String text = written?.trim() ?? '';
    if (text.isEmpty || !mounted) return;

    final int key = await Storage.saveDreamEntry(text: text);
    if (!mounted) return;
    setState(() {
      _entries = Storage.getJournalEntries();
      _pending.add(key);
      _notes.remove(key);
    });
    await _interpret(key, text);
  }

  Future<void> _interpret(int key, String text) async {
    setState(() {
      _pending.add(key);
      _notes.remove(key);
    });
    final DreamResult result = await requestDreamInterpretation(text);
    if (!mounted) return;
    if (result.ok) {
      await Storage.setDreamInterpretation(key, result.text);
      if (!mounted) return;
      setState(() {
        _entries = Storage.getJournalEntries();
        _pending.remove(key);
      });
      return;
    }
    setState(() {
      _pending.remove(key);
      _notes[key] = switch (result.status) {
        'unauthorized' => 'Sign in again to have this dream read.',
        'quota' => 'The dream reader has no quota left tonight.',
        'network' => 'No connection. Tap try again to have this dream read.',
        _ => 'The dream reader could not finish. Tap try again.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final double bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: true,
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(28, 20, 28, 120 + bottom),
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Dreams',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.9,
                      height: 1.1,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _WriteButton(onTap: _write),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _entries.isEmpty
                  ? 'Nothing written down yet.'
                  : _entries.length == 1
                  ? '1 dream saved'
                  : '${_entries.length} dreams saved',
              style: t.bodySmall?.copyWith(color: const Color(0xFF7A7A7A)),
            ),
            const SizedBox(height: 34),
            if (_entries.isEmpty)
              Text(
                'Write down what you remember when you wake up. '
                'A short reading is saved under each dream.',
                style: t.bodyMedium?.copyWith(height: 1.7),
              )
            else
              for (final Map<String, dynamic> entry in _entries)
                _DreamEntry(
                  key: ValueKey<dynamic>(entry['date']),
                  entry: entry,
                  readingTint: _readingTint,
                  pending: _pending.contains(_entryKey(entry)),
                  note: _notes[_entryKey(entry)],
                  onRetry: () => _interpret(
                    _entryKey(entry),
                    (entry['text'] as String?) ?? '',
                  ),
                ),
          ],
        ),
      ),
    );
  }

  static int _entryKey(Map<String, dynamic> entry) =>
      (entry['date'] as num?)?.toInt() ?? 0;
}

class _WriteButton extends StatelessWidget {
  const _WriteButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        onPressed: onTap,
        child: const Text(
          'WRITE',
          style: TextStyle(
            letterSpacing: 2,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DreamEntry extends StatelessWidget {
  const _DreamEntry({
    super.key,
    required this.entry,
    required this.readingTint,
    required this.pending,
    required this.note,
    required this.onRetry,
  });

  final Map<String, dynamic> entry;
  final Color readingTint;
  final bool pending;
  final String? note;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final int millis = (entry['date'] as num?)?.toInt() ?? 0;
    final DateTime written = DateTime.fromMillisecondsSinceEpoch(millis);
    final String dream = ((entry['text'] as String?) ?? '').trim();
    final String reading = ((entry['interpretation'] as String?) ?? '').trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            formatLongDate(written),
            style: t.labelSmall?.copyWith(
              fontSize: 9.5,
              letterSpacing: 1.8,
              color: const Color(0xFF7A7A7A),
            ),
          ),
          const SizedBox(height: 8),
          Text(dream, style: t.bodyLarge?.copyWith(height: 1.65)),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
            color: readingTint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'INTERPRETATION',
                  style: t.labelSmall?.copyWith(
                    fontSize: 8.5,
                    letterSpacing: 1.8,
                    color: const Color(0xFF4A4A4A),
                  ),
                ),
                const SizedBox(height: 8),
                if (pending)
                  Row(
                    children: <Widget>[
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Reading your dream...',
                          style: t.bodySmall?.copyWith(height: 1.5),
                        ),
                      ),
                    ],
                  )
                else if (reading.isNotEmpty)
                  Text(reading, style: t.bodyMedium?.copyWith(height: 1.65))
                else ...<Widget>[
                  Text(
                    note ?? 'This dream has not been read yet.',
                    style: t.bodySmall?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 2),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onRetry,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'TRY AGAIN',
                        style: t.labelSmall?.copyWith(
                          fontSize: 9,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A blank page for one dream, rather than a dialog. A dream is long enough
/// that a box with three lines and a keyboard over it is the wrong shape.
class _DreamComposer extends StatefulWidget {
  const _DreamComposer();

  @override
  State<_DreamComposer> createState() => _DreamComposerState();
}

class _DreamComposerState extends State<_DreamComposer> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final String text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final double bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(28, 20, 28, 20 + bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'New dream',
                      style: t.headlineLarge?.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'CANCEL',
                      style: t.labelSmall?.copyWith(fontSize: 9.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  textCapitalization: TextCapitalization.sentences,
                  style: t.bodyLarge?.copyWith(height: 1.7),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'What did you dream about?',
                    hintStyle: t.bodyLarge?.copyWith(
                      height: 1.7,
                      color: const Color(0xFF9A9A9A),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.black,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  onPressed: _save,
                  child: const Text(
                    'SAVE DREAM',
                    style: TextStyle(
                      letterSpacing: 2,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
