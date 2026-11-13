import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/storage.dart';
import '../../ui/friend_selection.dart';
import '../widgets/liquid_glass_nav.dart';
import 'dreams_screen.dart';
import 'home_screen.dart';
import 'insights_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const double _navBottomGap = 28;

  int index = 0;
  final screens = const [HomeScreen(), DreamsScreen(), InsightsScreen()];

  @override
  void initState() {
    super.initState();
    // Reaching the shell is what finishes setup. Written once, cheaply, and
    // only after the person has actually got here — marking it any earlier
    // would skip a screen they had not seen.
    Storage.setOnboarded(true);
  }

  static const labels = ['Home', 'Dreams', 'Insights'];

  static const _pastels = [
    Color(0xFFDCE6F1),
    Color(0xFFF1ECD9),
    Color(0xFFDCEADF),
  ];

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (selectedFriendInsights.value != null) {
          selectedFriendInsights.value = null;
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            Positioned.fill(
              child: IndexedStack(index: index, children: screens),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: safeBottom + _navBottomGap,
              child: Center(
                child: LiquidGlassNav(
                  index: index,
                  labels: labels,
                  pastels: _pastels,
                  onSelected: (i) => setState(() => index = i),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
