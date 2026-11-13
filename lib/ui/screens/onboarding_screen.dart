import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/profile.dart';
import '../../data/models/cycle_record.dart';
import '../../data/storage.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int step = 0;
  final nameCtrl = TextEditingController();
  DateTime? dob;
  DateTime? lastPeriod;
  int cycleLen = 28;
  int periodDur = 5;

  final steps = const ['name', 'dob', 'period', 'cycle', 'duration'];

  Future<void> _pickDate({required bool isDob}) async {
    final now = DateTime.now();
    final initial = isDob ? DateTime(now.year - 25, now.month, now.day) : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1950),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: Colors.black, onPrimary: Colors.white, surface: Colors.white, onSurface: Colors.black)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isDob) dob = picked; else lastPeriod = picked;
      });
    }
  }

  void _next() {
    if (step == 0 && nameCtrl.text.trim().isEmpty) return;
    if (step == 1 && dob == null) return;
    if (step == 2 && lastPeriod == null) return;
    if (step < steps.length - 1) {
      setState(() => step++);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    final profile = Profile(
      name: nameCtrl.text.trim(),
      dateOfBirth: dob!,
      lastPeriodStart: lastPeriod!,
      avgCycleLength: cycleLen,
      avgPeriodDuration: periodDur,
    );
    await Storage.saveProfile(profile);
    // Seed a cycle record for the last period start
    await Storage.addCycle(CycleRecord.fromMap({
      'start': lastPeriod!.millisecondsSinceEpoch,
      'duration': periodDur,
    }));
    await Storage.setOnboarded(true);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/main');
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('WATER', style: t.labelSmall?.copyWith(letterSpacing: 4)),
              const SizedBox(height: 48),
              Expanded(child: _buildStep(t)),
              Row(
                children: [
                  if (step > 0)
                    TextButton(
                      onPressed: () => setState(() => step--),
                      child: const Text('BACK', style: TextStyle(letterSpacing: 2, fontSize: 11, color: Colors.black)),
                    ),
                  const Spacer(),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
                    onPressed: _next,
                    child: const Text('CONTINUE', style: TextStyle(letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(TextTheme t) {
    switch (step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What should we call you?', style: t.headlineMedium),
            const SizedBox(height: 24),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              style: t.bodyLarge,
              decoration: const InputDecoration(border: UnderlineInputBorder(), hintText: 'Your name'),
              onSubmitted: (_) => _next(),
            ),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('When were you born?', style: t.headlineMedium),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => _pickDate(isDob: true),
              child: Text(
                dob == null ? 'Select date' : DateFormat('d MMMM yyyy').format(dob!),
                style: t.bodyLarge?.copyWith(color: dob == null ? Colors.black : Colors.black),
              ),
            ),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('First day of your most recent flow?', style: t.headlineMedium),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => _pickDate(isDob: false),
              child: Text(
                lastPeriod == null ? 'Select date' : DateFormat('d MMMM yyyy').format(lastPeriod!),
                style: t.bodyLarge?.copyWith(color: lastPeriod == null ? Colors.black : Colors.black),
              ),
            ),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Average cycle length', style: t.headlineMedium),
            const SizedBox(height: 8),
            Text('Defaults to 28 days', style: t.bodySmall),
            const SizedBox(height: 24),
            Row(
              children: [
                IconButton(onPressed: () => setState(() => cycleLen = (cycleLen > 20 ? cycleLen - 1 : cycleLen)), icon: const Icon(Icons.remove)),
                Text('$cycleLen', style: t.displayMedium),
                IconButton(onPressed: () => setState(() => cycleLen = (cycleLen < 45 ? cycleLen + 1 : cycleLen)), icon: const Icon(Icons.add)),
              ],
            ),
          ],
        );
      case 4:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Average flow duration', style: t.headlineMedium),
            const SizedBox(height: 8),
            Text('Defaults to 5 days', style: t.bodySmall),
            const SizedBox(height: 24),
            Row(
              children: [
                IconButton(onPressed: () => setState(() => periodDur = (periodDur > 1 ? periodDur - 1 : periodDur)), icon: const Icon(Icons.remove)),
                Text('$periodDur', style: t.displayMedium),
                IconButton(onPressed: () => setState(() => periodDur = (periodDur < 12 ? periodDur + 1 : periodDur)), icon: const Icon(Icons.add)),
              ],
            ),
          ],
        );
    }
    return const SizedBox.shrink();
  }
}
