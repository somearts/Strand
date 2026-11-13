import 'package:flutter/material.dart';

import '../../data/storage.dart';
import 'welcome_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  /// The mark's entrance fade, unchanged.
  late final AnimationController _enter;
  late final Animation<double> _enterOpacity;

  /// The splash → welcome cross-fade.
  ///
  /// It is driven in place rather than by a route transition: both screens are
  /// stacked on one white page, the mark fades to zero and the welcome rises
  /// from zero underneath it, and only once the cross-fade is complete does the
  /// navigator swap to the real welcome route. A route transition can be
  /// shortened or skipped by the platform's animation settings; this fade
  /// cannot, and there is never a frame where the page is not white.
  late final AnimationController _cross;
  late final Animation<double> _splashOpacity;
  late final Animation<double> _welcomeOpacity;

  bool _welcomeVisible = false;

  @override
  void initState() {
    super.initState();

    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
    _enterOpacity = CurvedAnimation(parent: _enter, curve: Curves.easeOut);

    _cross = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    );
    _splashOpacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _cross,
        curve: const Interval(0, 0.5, curve: Curves.easeInOutCubic),
      ),
    );
    _welcomeOpacity = CurvedAnimation(
      parent: _cross,
      curve: const Interval(0.12, 1, curve: Curves.easeInOutCubic),
    );

    _go();
  }

  Future<void> _go() async {
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;
    // Someone who has already been through setup goes straight to their
    // nights. Replaying the welcome every launch is not onboarding, it is a
    // door that re-locks behind you.
    //
    // The account step is newer than the original setup, so an install that is
    // already onboarded but has never seen it is shown the welcome once.
    final bool showAuthIntro =
        !Storage.onboarded ||
        (!Storage.authIntroSeen && Storage.account == null);
    if (showAuthIntro) await Storage.setAuthIntroSeen(true);
    if (!mounted) return;

    if (!showAuthIntro) {
      Navigator.of(context).pushReplacementNamed('/main');
      return;
    }

    // Build the welcome here, invisible, and cross-fade the two screens.
    setState(() => _welcomeVisible = true);
    await _cross.forward();
    if (!mounted) return;

    // The welcome is now fully opaque and identical to the route we hand over
    // to, so this swap is invisible: no flash, no second fade.
    Navigator.of(context).pushReplacement<void, void>(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
        ) => const WelcomeScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _enter.dispose();
    _cross.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Only the mark fades; the white page underneath never does, so
          // there is no dark frame between the two screens.
          FadeTransition(
            opacity: _splashOpacity,
            child: SafeArea(
              child: Center(
                child: FadeTransition(
                  opacity: _enterOpacity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'strand',
                        style: Theme.of(context).textTheme.displayLarge
                            ?.copyWith(
                              fontSize: 56,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -2,
                            ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'EVERY NIGHT LEAVES A STORY',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          letterSpacing: 3,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_welcomeVisible)
            IgnorePointer(
              child: FadeTransition(
                opacity: _welcomeOpacity,
                child: const WelcomeScreen(),
              ),
            ),
        ],
      ),
    );
  }
}
