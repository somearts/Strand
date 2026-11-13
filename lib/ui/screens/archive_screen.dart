import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/cycle_record.dart';
import '../../data/models/cycle_record.dart';
import '../../data/storage.dart';
import '../../domain/cycle_engine.dart';
import '../widgets/page_header.dart';
import '../widgets/simple_line_chart.dart';
import 'cycle_detail_screen.dart';

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  List<CycleRecord> records = [];
  CycleStats? stats;
  List<Observation> observations = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = Storage.getCycles();
    final p = Storage.getProfile();
    final o = Storage.getObservations();
    final s = CycleEngine.compute(profile: p, records: r);
    setState(() {
      records = List<CycleRecord>.from(r)..sort((a, b) => b.startDate.compareTo(a.startDate));
      stats = s;
      observations = o;
      loading = false;
    });
  }

  DateTime? _nextStart(CycleRecord r) {
    final asc = List<CycleRecord>.from(records)..sort((a, b) => a.startDate.compareTo(b.startDate));
    final pos = asc.indexWhere((x) => x.startDate == r.startDate);
    if (pos >= 0 && pos + 1 < asc.length) return asc[pos + 1].startDate;
    return null;
  }

  int _cycleDuration(CycleRecord r, DateTime? next) {
    if (next != null) return next.difference(r.startDate).inDays;
    return DateTime.now().difference(r.startDate).inDays + 1;
  }

  List<Observation> _observationsFor(CycleRecord r, DateTime? next) {
    return observations.where((o) {
      if (o.date.isBefore(r.startDate)) return false;
      if (next != null && !o.date.isBefore(next)) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (loading) return const Scaffold(backgroundColor: Colors.white, body: SizedBox.shrink());
    final s = stats!;
    final df = DateFormat('d MMM yyyy');
    final asc = List<CycleRecord>.from(records)..sort((a, b) => a.startDate.compareTo(b.startDate));
    final cycleLengths = <double>[];
    for (int i = 1; i < asc.length; i++) {
      cycleLengths.add(asc[i].startDate.difference(asc[i - 1].startDate).inDays.toDouble());
    }
    final periodDurations = asc.map((r) => r.periodDuration.toDouble()).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
          child: ListView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 96,
            ),
            children: [
              PageHeader(showGreeting: false),
              const SizedBox(height: 16),
              _summary(t, 'Average rhythm', '${s.avgCycleLength.toStringAsFixed(1)} days'),
              _summary(t, 'Average flow', '${s.avgPeriodDuration.toStringAsFixed(1)} days'),
              _summary(t, 'Variability', '${s.variability.toStringAsFixed(1)} days'),
              _summary(t, 'Recorded rhythms', '${s.recordedCycles}'),
              const SizedBox(height: 16),
              Text('Cycle history', style: t.labelSmall?.copyWith(letterSpacing: 3)),
              const SizedBox(height: 8),
              if (records.isEmpty)
                Text('No previous tides yet.', style: t.bodySmall)
              else
                ...records.map((r) {
                  final next = _nextStart(r);
                  final duration = _cycleDuration(r, next);
                  return InkWell(
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => CycleDetailScreen(
                          record: r,
                          endDate: next == null ? null : next.subtract(const Duration(days: 1)),
                          cycleDuration: next == null ? null : duration,
                          observations: _observationsFor(r, next),
                        ),
                      ));
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(df.format(r.startDate), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                              const SizedBox(height: 2),
                              Text(
                                next == null
                                    ? 'Ongoing · Flow ${r.periodDuration} days'
                                    : '${df.format(next.subtract(const Duration(days: 1)))} · $duration days · Flow ${r.periodDuration} days',
                                style: t.bodySmall,
                              ),
                            ],
                          ),
                          const Icon(Icons.chevron_right, size: 16, color: Colors.black),
                        ],
                      ),
                    ),
                  );
                }),
              if (cycleLengths.length >= 3) ...[
                const SizedBox(height: 16),
                Text('Cycle length over time', style: t.labelSmall?.copyWith(letterSpacing: 3)),
                const SizedBox(height: 8),
                SimpleLineChart(values: cycleLengths),
              ],
              if (periodDurations.length >= 3) ...[
                const SizedBox(height: 16),
                Text('Period duration over time', style: t.labelSmall?.copyWith(letterSpacing: 3)),
                const SizedBox(height: 8),
                SimpleLineChart(values: periodDurations),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _summary(TextTheme t, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: t.bodySmall),
          Text(value, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
