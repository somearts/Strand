import 'package:flutter/material.dart';

import '../../health/sleep_controller.dart';

class HealthConnectScreen extends StatelessWidget {
  const HealthConnectScreen({super.key});

  Future<void> _connect(BuildContext context) async {
    final NavigatorState navigator = Navigator.of(context);
    final SleepController? sleep = SleepScope.maybeOf(context);
    if (sleep != null) {
      // The real Android Health Connect permission sheet. It is started here
      // because the person just asked for it, and never during app startup.
      await sleep.retry();
    }
    if (!context.mounted) return;
    navigator.pushReplacementNamed('/main');
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
              const Spacer(flex: 2),
              Text(
                'Your nights have a story. Let\'s read it.',
                style: t.headlineLarge,
              ),
              const SizedBox(height: 24),
              Text(
                'Strand uses your sleep and health records to help you understand '
                'your nights, recognise patterns and explore your sleep over time.',
                style: t.bodyLarge,
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  onPressed: () => _connect(context),
                  child: const Text(
                    'CONNECT HEALTH DATA',
                    style: TextStyle(
                      letterSpacing: 2,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () =>
                      Navigator.of(context).pushReplacementNamed('/main'),
                  child: const Text(
                    'Continue without connecting',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black,
                      fontWeight: FontWeight.w500,
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
