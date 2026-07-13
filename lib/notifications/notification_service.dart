// lib/notifications/notification_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // ─── INIT (call once in main.dart) ───────────────────────────────────────
  Future<void> init() async {
    tz.initializeTimeZones();

    // The `timezone` package defaults to UTC until told otherwise — it has
    // no way to know the device's real zone on its own. Without this,
    // every "8:00 AM" reminder was actually being scheduled for 8:00 AM
    // UTC, which is why reminders looked like they were "not working"
    // (they were firing hours off from the expected local time, or had
    // already passed for the day and silently rolled to tomorrow).
    try {
      final String deviceTimezone =
          (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(deviceTimezone));
    } catch (_) {
      // Fall back to UTC rather than crashing app startup — reminders
      // will just be off by the device's UTC offset until this resolves.
    }

    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings settings = InitializationSettings(
      android: android,
      iOS: ios,
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: _onNotificationTap,
    );

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidImpl?.requestNotificationsPermission();
  }

  static void _onNotificationTap(NotificationResponse response) {}

  // ─── OPT-IN: ASK FOR EXACT-ALARM PERMISSION ─────────────────────────────
  Future<void> requestExactAlarmPermission() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      await androidImpl?.requestExactAlarmsPermission();
    } catch (_) {}
  }

  // ─── CHECK IF EXACT ALARMS ARE ALLOWED ──────────────────────────────────
  Future<bool> canScheduleExactAlarms() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl == null) return true;
    return await androidImpl.canScheduleExactNotifications() ?? false;
  }

  // ─── NOTIFICATION DETAILS ────────────────────────────────────────────────
  NotificationDetails _details(String medName) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'med_reminder',
        'Medication Reminders',
        channelDescription: 'Reminds you to take your medications on time',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'Medication Reminder',
        styleInformation: BigTextStyleInformation(
          'Time to take $medName 💊\nStay consistent for best results.',
          contentTitle: '💊 Medication Reminder',
          summaryText: 'Curely',
        ),
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  // ─── SCHEDULE NOTIFICATIONS FOR A MEDICATION ────────────────────────────
  Future<void> scheduleMedReminders({
    required int notificationBaseId,
    required String medName,
    required List<TimeOfDay> times,
  }) async {
    await cancelMedReminders(notificationBaseId, times.length + 5);

    final exactAllowed = await canScheduleExactAlarms();
    final mode = exactAllowed
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    for (int i = 0; i < times.length; i++) {
      final tod = times[i];
      final scheduledDate = _nextInstanceOfTime(tod);

      await _plugin.zonedSchedule(
        id: notificationBaseId + i,
        title: '💊 Medication Reminder',
        body: 'Time to take $medName',
        scheduledDate: scheduledDate,
        notificationDetails: _details(medName),
        androidScheduleMode: mode,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  // ─── CANCEL ALL NOTIFICATIONS FOR A MED ─────────────────────────────────
  Future<void> cancelMedReminders(int baseId, int count) async {
    for (int i = 0; i < count; i++) {
      await _plugin.cancel(id: baseId + i);
    }
  }

  // ─── CANCEL EVERY SCHEDULED REMINDER FOR ONE REPORT ─────────────────────
  Future<void> cancelAllRemindersForReport(
    String reportId,
    Map<String, int> medTimesCounts,
  ) async {
    for (final entry in medTimesCounts.entries) {
      final baseId = makeBaseId(reportId, entry.key);
      await cancelMedReminders(baseId, entry.value + 5);
    }
  }

  // ─── NEXT OCCURRENCE OF A TIME TODAY OR TOMORROW ────────────────────────
  tz.TZDateTime _nextInstanceOfTime(TimeOfDay tod) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      tod.hour,
      tod.minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  // ─── PARSE FREQUENCY STRING → LIST OF TimeOfDay ─────────────────────────
  static List<TimeOfDay> parseFrequency(String freq) {
    final s = freq.trim().toLowerCase();

    if (s.contains('-')) {
      final parts = s.split('-');
      final slots = [
        const TimeOfDay(hour: 8, minute: 0),
        const TimeOfDay(hour: 14, minute: 0),
        const TimeOfDay(hour: 20, minute: 0),
        const TimeOfDay(hour: 22, minute: 0),
      ];
      final times = <TimeOfDay>[];
      for (int i = 0; i < parts.length && i < slots.length; i++) {
        if ((int.tryParse(parts[i].trim()) ?? 0) > 0) {
          times.add(slots[i]);
        }
      }
      return times.isEmpty ? [const TimeOfDay(hour: 8, minute: 0)] : times;
    }

    if (s == 'once' || s == '1') return [const TimeOfDay(hour: 8, minute: 0)];
    if (s == 'twice' || s == '2') {
      return [const TimeOfDay(hour: 8, minute: 0), const TimeOfDay(hour: 20, minute: 0)];
    }
    if (s == 'thrice' || s == '3') {
      return [
        const TimeOfDay(hour: 8, minute: 0),
        const TimeOfDay(hour: 14, minute: 0),
        const TimeOfDay(hour: 20, minute: 0),
      ];
    }

    final timesMatch = RegExp(r'(\d+)\s*time').firstMatch(s);
    if (timesMatch != null) {
      final n = int.tryParse(timesMatch.group(1)!);
      if (n != null && n > 0) {
        final gap = 16 ~/ n;
        return List.generate(n, (i) => TimeOfDay(hour: 8 + gap * i, minute: 0));
      }
    }

    final n = int.tryParse(s);
    if (n != null && n > 0) {
      final gap = 16 ~/ n;
      return List.generate(n, (i) => TimeOfDay(hour: 8 + gap * i, minute: 0));
    }

    return [const TimeOfDay(hour: 8, minute: 0)];
  }

  // ─── GENERATE A STABLE NOTIFICATION BASE ID ──────────────────────────────
  static int makeBaseId(String reportId, String medName) {
    return (reportId + medName).hashCode.abs() % 90000 + 1000;
  }

  // ─── DAILY HEALTH-ENTRY REMINDER ─────────────────────────────────────────
  static const int kDailyHealthReminderId = 999999;

  NotificationDetails _dailyHealthReminderDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_health_reminder',
        'Daily Health Reminder',
        channelDescription: "Reminds you to log today's health entry",
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        ticker: 'Daily Health Reminder',
        styleInformation: BigTextStyleInformation(
          "Don't forget to log today's health data in Curely.",
          contentTitle: '📋 Daily Health Check-In',
          summaryText: 'Curely',
        ),
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  Future<void> scheduleDailyHealthReminder(TimeOfDay time) async {
    final exactAllowed = await canScheduleExactAlarms();
    final mode = exactAllowed
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    await _plugin.zonedSchedule(
      id: kDailyHealthReminderId,
      title: '📋 Daily Health Check-In',
      body: "Don't forget to log today's health data in Curely.",
      scheduledDate: _nextInstanceOfTime(time),
      notificationDetails: _dailyHealthReminderDetails(),
      androidScheduleMode: mode,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelDailyHealthReminder() async {
    await _plugin.cancel(id: kDailyHealthReminderId);
  }

  // ─── RESTORE DAILY HEALTH REMINDER ON STARTUP / REBOOT ──────────────────
  // Call this from main.dart after a user is confirmed signed in.
  // Silently re-schedules the notification from the time saved in Firestore,
  // handling two cases:
  //   1. Device reboot — Android's AlarmManager is wiped on reboot, so
  //      every scheduled notification stops firing until re-registered.
  //   2. App reinstall — the OS clears all scheduled notifications, so
  //      the reminder would silently stop even for long-time users.
  // Using the Firestore-saved time means neither case requires the user
  // to set their reminder time again.
  static Future<void> restoreHealthReminderIfEnabled(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('patients')
          .doc(uid)
          .get();
      final data = doc.data();
      if (data == null) return;

      final enabled = data['reminderEnabled'] as bool? ?? false;
      if (!enabled) return;

      final timeMap = data['reminderTime'] as Map<String, dynamic>?;
      if (timeMap == null) return;

      final hour = timeMap['hour'] as int?;
      final minute = timeMap['minute'] as int?;
      if (hour == null || minute == null) return;

      await NotificationService()
          .scheduleDailyHealthReminder(TimeOfDay(hour: hour, minute: minute));
    } catch (_) {
      // Best-effort — a network hiccup on startup shouldn't crash the app.
    }
  }
}