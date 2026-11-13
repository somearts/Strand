import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/cycle_record.dart';
import '../../data/storage.dart';
import '../widgets/page_header.dart';

const _symptoms = [
  'Headache',
  'Bloating',
  'Fatigue',
  'Back pain',
  'Nausea',
  'Breast tenderness',
  'Acne',
];

class ObservationsScreen extends StatefulWidget {
  const ObservationsScreen({super.key});

  @override
  State<ObservationsScreen> createState() => _ObservationsScreenState();
}

class _ObservationsScreenState extends State<ObservationsScreen> {
  DateTime date = DateTime.now();
  String flow = 'medium';
  String cramps = 'none';
  final Set<String> symptoms = {};
  List<Observation> recent = [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _loadExisting();
  }

  void _loadRecent() {
    recent = Storage.getObservations()..sort((a, b) => b.date.compareTo(a.date));
    if (recent.length > 20) recent = recent.sublist(0, 20);
  }

  void _loadExisting() {
    final o = Storage.getObservation(date);
    if (o != null) {
      setState(() {
        flow = o.flow;
        cramps = o.cramps;
        symptoms
          ..clear()
          ..addAll(o.symptoms);
      });
    }
  }

  Future<void> _save() async {
    await Storage.saveObservation(Observation(
      date: DateTime(date.year, date.month, date.day),
      flow: flow,
      cramps: cramps,
      symptoms: symptoms.toList(),
    ));
    setState(() {
      _loadRecent();
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved'), duration: Duration(seconds: 1)));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: Colors.black, onPrimary: Colors.white, surface: Colors.white, onSurface: Colors.black)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        date = picked;
        flow = 'medium';
        cramps = 'none';
        symptoms.clear();
      });
      _loadExisting();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final df = DateFormat('d MMMM yyyy');
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(showGreeting: false),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _pickDate,
                child: Text(df.format(date), style: t.titleLarge),
              ),
              const SizedBox(height: 20),
              Text('Flow', style: t.bodySmall),
              const SizedBox(height: 8),
              _segmented(['light', 'medium', 'heavy'], flow, (v) => setState(() => flow = v)),
              const SizedBox(height: 16),
              Text('Cramps', style: t.bodySmall),
              const SizedBox(height: 8),
              _segmented(['none', 'mild', 'moderate', 'severe'], cramps, (v) => setState(() => cramps = v)),
              const SizedBox(height: 16),
              Text('Symptoms', style: t.bodySmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _symptoms.map((s) {
                  final selected = symptoms.contains(s);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (selected) symptoms.remove(s); else symptoms.add(s);
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? Colors.black : Colors.white,
                        border: Border.all(color: const Color(0xFFE6E6E6)),
                      ),
                      child: Text(s, style: TextStyle(fontSize: 12, color: selected ? Colors.white : Colors.black)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
                  onPressed: _save,
                  child: const Text('SAVE', style: TextStyle(letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.w500)),
                ),
              ),
              const SizedBox(height: 16),
              Text('Recent', style: t.bodySmall),
              const SizedBox(height: 8),
              Expanded(
                child: recent.isEmpty
                    ? Center(child: Text('No observations yet.', style: t.bodySmall))
                    : ListView.builder(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.paddingOf(context).bottom + 96,
                        ),
                        itemCount: recent.length,
                        itemBuilder: (ctx, i) {
                          final o = recent[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(DateFormat('d MMM').format(o.date), style: t.bodyMedium),
                                Text('${o.flow} · ${o.cramps}', style: t.bodySmall),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segmented(List<String> options, String value, ValueChanged<String> onChanged) {
    return Row(
      children: options.map((o) {
        final selected = value == o;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(o),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? Colors.black : Colors.white,
                border: Border.all(color: const Color(0xFFE6E6E6)),
              ),
              child: Text(o, style: TextStyle(fontSize: 11, color: selected ? Colors.white : Colors.black, letterSpacing: 0.5)),
            ),
          ),
        );
      }).toList(),
    );
  }
}
