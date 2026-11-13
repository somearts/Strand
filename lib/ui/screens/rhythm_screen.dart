import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/cycle_education.dart';
import '../../data/models/profile.dart';
import '../../data/storage.dart';
import '../../domain/cycle_engine.dart';
import '../widgets/cycle_ring.dart';
import '../widgets/page_header.dart';
import 'settings_screen.dart';

class RhythmScreen extends StatefulWidget {
  const RhythmScreen({super.key});

  @override
  State<RhythmScreen> createState() => _RhythmScreenState();
}

class _RhythmScreenState extends State<RhythmScreen> {
  Profile? profile;
  CycleStats? stats;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = Storage.getProfile();
    final records = Storage.getCycles();
    final s = CycleEngine.compute(profile: p, records: records);
    setState(() {
      profile = p;
      stats = s;
      loading = false;
    });
  }

  String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return 'th';
    switch (n % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  String _phaseLabel(String phase) {
    switch (phase) {
      case CyclePhase.menstrual:
        return 'Menstrual phase';
      case CyclePhase.follicular:
        return 'Follicular phase';
      case CyclePhase.ovulatory:
        return 'Ovulatory phase';
      case CyclePhase.luteal:
        return 'Luteal phase';
    }
    return phase;
  }

  String _fertileRange(CycleStats s) {
    final start = s.fertileStart;
    final end = s.fertileEnd;
    if (start.month == end.month && start.year == end.year) {
      return '${start.day}–${end.day} ${DateFormat('MMMM').format(start)}';
    }
    return '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM').format(end)}';
  }

  Widget _infoBlock(TextTheme t, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE6E6E6), width: 0.8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: t.labelSmall?.copyWith(
              fontSize: 8.5,
              letterSpacing: 1.4,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: t.bodyMedium?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (loading) {
      return const Scaffold(backgroundColor: Colors.white, body: Center(child: SizedBox.shrink()));
    }
    final s = stats!;
    final day = s.currentCycleDay;
    final education = cycleEducationForDay(day);
    // The scroll viewport must reach the bottom of the screen so content can
    // pass *behind* the floating navigation. The only bottom padding is the
    // end-of-scroll clearance inside the list itself.
    final bottomClearance = MediaQuery.paddingOf(context).bottom + 96;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
          child: ListView(
            padding: EdgeInsets.only(bottom: bottomClearance),
            children: [
              PageHeader(
                trailing: IconButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                  icon: const Icon(Icons.settings_outlined, size: 20, color: Colors.black),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
              const SizedBox(height: 56),
              Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side = (constraints.maxWidth < constraints.maxHeight
                            ? constraints.maxWidth
                            : constraints.maxHeight) *
                        0.92;
                    final size = side.clamp(260.0, 400.0);
                    return CycleRing(
                      currentDay: day,
                      cycleLength: s.avgCycleLength.round().clamp(20, 45),
                      periodDuration: s.avgPeriodDuration.round().clamp(2, 10),
                      size: size,
                      phaseLabel: _phaseLabel(s.phase),
                    );
                  },
                ),
              ),
              const SizedBox(height: 48),
              Row(
                children: [
                  Expanded(
                    child: _infoBlock(
                      t,
                      'NEXT ARRIVAL',
                      DateFormat('d MMMM').format(s.nextPeriodDate),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _infoBlock(
                      t,
                      'DAYS UNTIL',
                      '${s.daysUntilNext} days',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _infoBlock(
                      t,
                      'FERTILE WINDOW',
                      _fertileRange(s),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 52),
              Text(
                'What happens on the $day${_ordinal(day)} day?',
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              ...education.map(
                (para) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(para, style: t.bodyMedium?.copyWith(height: 1.6)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
