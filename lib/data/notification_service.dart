import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
    _initialized = true;
  }

  static Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? true;
  }

  static Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  static Future<void> scheduleAll({
    required bool enabled,
    required bool periodApproaching,
    required bool periodStart,
    required bool ovulation,
    required bool fertile,
    required int daysBefore,
    DateTime? nextPeriod,
    DateTime? ovulationDate,
    DateTime? fertileStart,
  }) async {
    await init();
    await _plugin.cancelAll();
    if (!enabled) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'water_cycle',
        'Cycle reminders',
        channelDescription: 'Cycle and period reminders',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );

    final now = DateTime.now().toUtc();

    Future<void> schedule(int id, String title, String body, DateTime when) async {
      if (!when.isAfter(now)) return;
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(when, tz.UTC),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }

    if (periodApproaching && nextPeriod != null && daysBefore > 0) {
      await schedule(
        1,
        'Period approaching',
        'Your estimated period may start soon.',
        DateTime(nextPeriod.year, nextPeriod.month, nextPeriod.day, 9, 0)
            .subtract(Duration(days: daysBefore)),
      );
    }
    if (periodStart && nextPeriod != null) {
      await schedule(
        2,
        'Estimated period start',
        'Your estimated period may begin today.',
        DateTime(nextPeriod.year, nextPeriod.month, nextPeriod.day, 9, 0),
      );
    }
    if (ovulation && ovulationDate != null) {
      await schedule(
        3,
        'Estimated ovulation',
        'You may be near your estimated peak today.',
        DateTime(ovulationDate.year, ovulationDate.month, ovulationDate.day, 9, 0),
      );
    }
    if (fertile && fertileStart != null) {
      await schedule(
        4,
        'Fertile phase',
        'You may be entering your estimated fertile phase.',
        DateTime(fertileStart.year, fertileStart.month, fertileStart.day, 9, 0),
      );
    }
  }
}
