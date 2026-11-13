import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/cycle_record.dart';
import '../../data/models/cycle_record.dart';

class CycleDetailScreen extends StatelessWidget {
  final CycleRecord record;
  final DateTime? endDate;
  final int? cycleDuration;
  final List<Observation> observations;

  const CycleDetailScreen({
    super.key,
    required this.record,
    this.endDate,
    this.cycleDuration,
    this.observations = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final df = DateFormat('d MMMM yyyy');
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Cycle details', style: t.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
          children: [
            _row(t, 'Start date', df.format(record.startDate)),
            _row(t, 'End date', endDate == null ? 'Ongoing' : df.format(endDate!)),
            _row(t, 'Cycle duration', cycleDuration == null ? '—' : '$cycleDuration days'),
            _row(t, 'Period duration', '${record.periodDuration} days'),
            _row(t, 'Flow', _flowSummary()),
            const SizedBox(height: 16),
            Text('Observations', style: t.titleMedium),
            const SizedBox(height: 8),
            if (observations.isEmpty)
              Text('No observations recorded for this cycle.', style: t.bodySmall)
            else
              ...observations.map((o) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      '${DateFormat('d MMM').format(o.date)} · ${o.flow} flow · cramps ${o.cramps}${o.symptoms.isEmpty ? '' : ' · ${o.symptoms.join(', ')}'}',
                      style: t.bodySmall,
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  String _flowSummary() {
    if (observations.isEmpty) return 'No flow observations';
    final flows = observations.map((o) => o.flow).toSet();
    if (flows.length == 1) return flows.first;
    return flows.join(', ');
  }

  Widget _row(TextTheme t, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: t.bodyMedium),
          Flexible(child: Text(value, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w500), textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
