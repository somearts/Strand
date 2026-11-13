import 'package:flutter/material.dart';

import '../widgets/strand_wordmark.dart';

/// The opening screen.
///
/// The wordmark and the LET'S BEGIN button are unchanged; everything between
/// them is the one place Strand introduces itself.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 22, 32, 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 54,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Spacer(flex: 2),
                      const StrandWordmark(),
                      const SizedBox(height: 26),
                      Text(
                        'Your nights have a story.\nSo do theirs.',
                        style: t.headlineLarge?.copyWith(height: 1.35),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Strand shows you your sleep and your friends’ — '
                        'duration, quality, consistency — so you can finally '
                        'compare the nights that matter.',
                        style: t.bodyLarge?.copyWith(height: 1.65),
                      ),
                      const SizedBox(height: 26),
                      const _PurposeLine(),
                      const Spacer(flex: 3),
                      // Unchanged.
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
                          onPressed: () =>
                              Navigator.of(context)
                                  .pushReplacementNamed('/account'),
                          child: const Text(
                            'LET\'S BEGIN',
                            style: TextStyle(
                              letterSpacing: 2,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          'You’ll choose exactly who sees your sleep data.',
                          textAlign: TextAlign.center,
                          style: t.bodySmall?.copyWith(
                            fontSize: 9.5,
                            height: 1.4,
                            color: Colors.black.withValues(alpha: 0.40),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// What Strand does, written as three quiet phrases rather than three icons.
///
/// Each phrase carries its own soft colour and its own coloured dot, so the row
/// reads as a small constellation rather than a feature list.
class _PurposeLine extends StatelessWidget {
  const _PurposeLine();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 9,
      runSpacing: 8,
      children: <Widget>[
        Text(
          'Health Sync',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
            color: Color(0xFFC96A6E),
          ),
        ),
        _Dot(color: Color(0xFFD9A05B)),
        Text(
          'Sleep Sharing',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
            color: Color(0xFF4FA37C),
          ),
        ),
        _Dot(color: Color(0xFF7FA9CC)),
        Text(
          'Dream Interpretation',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
            color: Color(0xFF8368C6),
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      '·',
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1,
        color: color,
      ),
    );
  }
}
