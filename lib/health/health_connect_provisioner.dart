import '../settings/strand_store.dart';
import 'health_connect_sleep_source.dart';
import 'sleep_controller.dart';
import 'sleep_repository.dart';
import 'sleep_source_service.dart';
import 'sleep_store.dart';

/// Builds the real sleep stack.
///
/// One place that knows which integrations Strand ships and how they are wired
/// together, so the app can start up with a working repository without the
/// composition existing in two places. Adding a second integration is a line in
/// [_sources] and nothing else: the repository merges whatever it is given, and
/// no screen needs to learn the name of any of them.
abstract final class StrandHealth {
  /// The integrations Strand ships, sleep only.
  ///
  /// Health Connect is the first and, for this version, the only one. The list
  /// rather than a single service is the point — [SleepRepository] is written
  /// against a collection, so a wearable app or a Fitbit import arriving later
  /// is additive.
  static List<SleepSourceService> sources() => <SleepSourceService>[
    HealthConnectSleepSource(),
  ];

  /// The whole stack, over the real store.
  static SleepRepository open(StrandStore store) =>
      SleepRepository(sources: sources(), store: KeyValueSleepStore(store));

  /// A controller over [open], for the app shell.
  static SleepController controller(StrandStore store) =>
      SleepController(open(store));
}
