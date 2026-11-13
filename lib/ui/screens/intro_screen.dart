import 'package:flutter/material.dart';

class IntroScreen extends StatelessWidget {
  const IntroScreen({super.key});

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
              Text('Everything flows', style: t.headlineLarge),
              const SizedBox(height: 24),
              Text(
                'There is a rhythm to everything that lives\n'
                'The changing seasons The rising tides The passing of time\n'
                'Your body follows a rhythm of its own\n'
                'Sometimes predictable Sometimes unexpected Always worth understanding',
                style: t.bodyLarge,
              ),
              const SizedBox(height: 24),
              Text(
                'WATER is a quiet space to observe that rhythm, recognise its patterns '
                'and know what lies ahead',
                style: t.bodyLarge,
              ),
              const SizedBox(height: 24),
              Text(
                'Because understanding your body begins with paying attention',
                style: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 32),
              Text('Life moves in cycles', style: t.titleLarge),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  ),
                  onPressed: () => Navigator.of(context).pushReplacementNamed('/onboarding'),
                  child: const Text('LET\'S BEGIN', style: TextStyle(letterSpacing: 2, fontSize: 12, fontWeight: FontWeight.w500)),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
