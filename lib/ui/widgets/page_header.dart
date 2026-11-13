import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../auth/auth_scope.dart';
import '../display_name.dart';

/// The shared page header used by every tab.
///
/// Only the Rhythm homepage shows the greeting and the live date sentence.
/// Every other page keeps the same header area but leaves it empty.
class PageHeader extends StatefulWidget {
  const PageHeader({super.key, this.showGreeting = true, this.trailing});

  /// Whether to show the greeting and date sentence.
  final bool showGreeting;

  /// Optional trailing action, e.g. the settings gear on Rhythm.
  final Widget? trailing;

  @override
  State<PageHeader> createState() => _PageHeaderState();
}

class _PageHeaderState extends State<PageHeader> with WidgetsBindingObserver {
  late DateTime _today;
  Timer? _midnightTimer;

  @override
  void initState() {
    super.initState();
    _today = DateUtils.dateOnly(DateTime.now());
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnightRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshDate();
      _scheduleMidnightRefresh();
    }
  }

  void _refreshDate() {
    final now = DateUtils.dateOnly(DateTime.now());
    if (now != _today && mounted) {
      setState(() => _today = now);
    }
  }

  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(nextMidnight.difference(now), () {
      _refreshDate();
      _scheduleMidnightRefresh();
    });
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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

  /// Used when no account has given Strand a name. The greeting stays warm
  /// without inventing a person — it never says "User".
  String _timeGreeting() {
    final int hour = DateTime.now().hour;
    if (hour < 12) return 'GOOD MORNING';
    if (hour < 18) return 'GOOD AFTERNOON';
    return 'GOOD EVENING';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final month = DateFormat('MMMM').format(_today);
    final sentence =
        "It's the ${_today.day}${_ordinal(_today.day)} day of $month, "
        '${_today.year} — what a great day to be alive.';
    final show = widget.showGreeting;
    final String name = displayName(
      AuthScope.maybeOf(context)?.greetingName ?? '',
    );
    final String greeting = name.isEmpty
        ? _timeGreeting()
        : 'HELLO, ${name.toUpperCase()}';

    // The header area keeps its height on every page so the rest of the
    // layout never shifts; only Rhythm actually shows its contents.
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: ExcludeSemantics(
                  excluding: !show,
                  child: Opacity(
                    opacity: show ? 1 : 0,
                    child: Text(
                      greeting,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelSmall?.copyWith(letterSpacing: 3),
                    ),
                  ),
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 16),
                widget.trailing!,
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ExcludeSemantics(
              excluding: !show,
              child: Opacity(
                opacity: show ? 1 : 0,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    sentence,
                    maxLines: 1,
                    softWrap: false,
                    style: t.bodySmall?.copyWith(
                      color: Colors.black,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
