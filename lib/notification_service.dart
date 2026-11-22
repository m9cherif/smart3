import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final List<_DesktopReminder> _desktopReminders = [];
  Timer? _desktopTimer;
  bool _isInitialized = false;
  Future<void>? _initFuture;

  /// Key handed to [MaterialApp.scaffoldMessengerKey] so reminders can be shown
  /// as an in-app banner even when the OS suppresses toast notifications.
  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static const String _prefsKey = 'scheduled_desktop_reminders_v1';

  /// How overdue a reminder may be at startup and still be delivered once.
  static const Duration _catchUpWindow = Duration(hours: 1);

  Future<void> initialize() async {
    if (_isInitialized) return;
    _initFuture ??= _doInitialize();
    return _initFuture!;
  }

  Future<void> _doInitialize() async {
    if (_isInitialized) return;

    try {
      tz.initializeTimeZones();

      String timeZoneName = 'UTC';
      try {
        final result = await FlutterTimezone.getLocalTimezone().timeout(
          const Duration(seconds: 2),
        );
        final raw = result.toString();
        debugPrint('NotificationService: raw timezone result = "$raw"');

        if (raw.contains('/') && !raw.contains('(')) {
          timeZoneName = raw.trim();
        } else {
          final match = RegExp(r'([A-Za-z]+/[A-Za-z_]+)').firstMatch(raw);
          if (match != null) {
            timeZoneName = match.group(1)!;
          }
        }
      } catch (e) {
        debugPrint('NotificationService: Failed to get timezone or timeout: $e');
      }

      try {
        tz.setLocalLocation(tz.getLocation(timeZoneName));
        debugPrint('NotificationService: Timezone set to $timeZoneName');
      } catch (e) {
        debugPrint('NotificationService: Could not set "$timeZoneName", falling back to UTC: $e');
        tz.setLocalLocation(tz.UTC);
      }

      if (_isDesktop) {
        try {
          await localNotifier.setup(appName: 'Smart Student AI');
        } catch (e) {
          debugPrint('NotificationService: localNotifier.setup failed: $e');
        }
      }

      const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
      const iosSettings = DarwinInitializationSettings();

      const initializationSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (details) {
          debugPrint('Notification tapped: ${details.payload}');
        },
      );

      if (Platform.isAndroid) {
        final androidPlugin =
            _notifications.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (androidPlugin != null) {
          debugPrint('NotificationService: Requesting Android permissions...');
          await androidPlugin.requestNotificationsPermission();
          try {
            await androidPlugin.requestExactAlarmsPermission();
          } catch (e) {
            debugPrint('NotificationService: Error requesting exact alarm permission: $e');
          }
        }
      }

      _isInitialized = true;

      // Restore any reminders scheduled before the app was restarted.
      if (_isDesktop) {
        await _restoreDesktopReminders();
      }
    } catch (e) {
      debugPrint('NotificationService: Initialization failed: $e');
    }
  }

  bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> _restoreDesktopReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      final now = DateTime.now();
      final restored = <_DesktopReminder>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final reminder = _DesktopReminder.fromMap(Map<String, dynamic>.from(item));
        if (reminder.time.isAfter(now)) {
          restored.add(reminder);
        } else if (now.difference(reminder.time) <= _catchUpWindow) {
          // Deliver reminders that were missed while the app was closed, once.
          restored.add(reminder.._deliverOnFirstCheck = true);
        }
      }

      if (restored.isEmpty) {
        await prefs.remove(_prefsKey);
        return;
      }

      _desktopReminders
        ..clear()
        ..addAll(restored);
      debugPrint('NotificationService: restored ${restored.length} reminder(s)');
      _startDesktopTimer();
    } catch (e) {
      debugPrint('NotificationService: failed to restore reminders: $e');
    }
  }

  Future<void> _persistDesktopReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_desktopReminders.isEmpty) {
        await prefs.remove(_prefsKey);
        return;
      }
      await prefs.setString(
        _prefsKey,
        jsonEncode(_desktopReminders.map((r) => r.toMap()).toList()),
      );
    } catch (e) {
      debugPrint('NotificationService: failed to persist reminders: $e');
    }
  }

  /// Schedules a reminder [reminderMinutes] before [dueDate].
  Future<bool> scheduleTaskReminder({
    required int id,
    required String title,
    required DateTime dueDate,
    required int reminderMinutes,
  }) async {
    final scheduledDate = dueDate.subtract(Duration(minutes: reminderMinutes));

    if (scheduledDate.isBefore(DateTime.now())) {
      debugPrint('NotificationService: reminder time $scheduledDate is in the past; skipping.');
      return false;
    }

    if (!_isInitialized) {
      await initialize();
    }

    if (_isDesktop) {
      _desktopReminders.removeWhere((r) => r.id == id);
      _desktopReminders.add(_DesktopReminder(
        id: id,
        title: title,
        description: 'Your task "$title" is due soon!',
        time: scheduledDate,
      ));
      await _persistDesktopReminders();
      debugPrint('NotificationService: scheduled desktop reminder at $scheduledDate (ID: $id)');
      _startDesktopTimer();
      return true;
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'task_reminders',
        'Task Reminders',
        channelDescription: 'Notifications for student tasks and reminders',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
      ),
      iOS: DarwinNotificationDetails(),
    );

    try {
      await _notifications.zonedSchedule(
        id,
        'Task Reminder',
        'Your task "$title" is due soon!',
        tz.TZDateTime.from(scheduledDate, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      debugPrint('NotificationService: scheduled exact reminder at $scheduledDate (ID: $id)');
    } catch (e) {
      debugPrint('NotificationService: exact scheduling failed, falling back: $e');
      await _notifications.zonedSchedule(
        id,
        'Task Reminder',
        'Your task "$title" is due soon!',
        tz.TZDateTime.from(scheduledDate, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
    return true;
  }

  void _startDesktopTimer() {
    _desktopTimer?.cancel();
    if (_desktopReminders.isEmpty) {
      _desktopTimer = null;
      return;
    }
    _desktopTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkDesktopReminders();
    });
    // Also run an immediate check so overdue items fire right away.
    _checkDesktopReminders();
  }

  void _checkDesktopReminders() {
    final now = DateTime.now();
    final toRemove = <int>[];

    for (final reminder in _desktopReminders) {
      final due = reminder._deliverOnFirstCheck || !reminder.time.isAfter(now);
      if (due) {
        debugPrint('NotificationService: triggering reminder "${reminder.title}"');
        _showImmediateNotification(
          id: reminder.id,
          title: 'Task Reminder',
          body: reminder.description,
        );
        toRemove.add(reminder.id);
      }
    }

    if (toRemove.isNotEmpty) {
      _desktopReminders.removeWhere((r) => toRemove.contains(r.id));
      _persistDesktopReminders();
    }

    if (_desktopReminders.isEmpty) {
      _desktopTimer?.cancel();
      _desktopTimer = null;
    }
  }

  Future<void> _showImmediateNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    if (_isDesktop) {
      // Windows/macOS toasts can be disabled system-wide (e.g. Windows
      // "Notifications" master switch, Focus Assist). Always surface the
      // reminder inside the app too, so it is never silently lost.
      _showInAppBanner(title: title, body: body);
      try {
        final notification = LocalNotification(
          identifier: id.toString(),
          title: title,
          body: body,
        );
        await notification.show();
      } catch (e) {
        debugPrint('NotificationService: failed to show desktop notification: $e');
      }
      return;
    }

    try {
      await _notifications.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails('task_reminders', 'Task Reminders'),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('NotificationService: failed to show notification: $e');
    }
  }

  /// Shows a notification immediately. Handy for testing / confirmations.
  Future<void> showNow({
    required String title,
    required String body,
    int id = 0,
  }) =>
      _showImmediateNotification(id: id, title: title, body: body);

  /// Presents a reminder as a floating in-app banner. This is the fallback that
  /// keeps reminders working when OS toasts are disabled or unavailable.
  void _showInAppBanner({required String title, required String body}) {
    final messenger = messengerKey.currentState;
    if (messenger == null) {
      debugPrint('NotificationService: no ScaffoldMessenger yet; banner skipped');
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 10),
          margin: const EdgeInsets.all(16),
          content: Row(
            children: <Widget>[
              const Icon(Icons.notifications_active_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(body, style: const TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'Dismiss',
            onPressed: messenger.hideCurrentSnackBar,
          ),
        ),
      );
  }

  Future<void> cancelReminder(int id) async {
    _desktopReminders.removeWhere((r) => r.id == id);
    await _persistDesktopReminders();
    if (_isInitialized) {
      try {
        await _notifications.cancel(id);
      } catch (e) {
        debugPrint('NotificationService: Failed to cancel reminder $id: $e');
      }
    }
  }
}

class _DesktopReminder {
  _DesktopReminder({
    required this.id,
    required this.title,
    required this.description,
    required this.time,
  });

  final int id;
  final String title;
  final String description;
  final DateTime time;

  /// Set for reminders that were missed while the app was closed.
  bool _deliverOnFirstCheck = false;

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'time': time.toIso8601String(),
      };

  factory _DesktopReminder.fromMap(Map<String, dynamic> map) => _DesktopReminder(
        id: (map['id'] as num?)?.toInt() ?? 0,
        title: (map['title'] ?? '').toString(),
        description: (map['description'] ?? '').toString(),
        time: DateTime.tryParse((map['time'] ?? '').toString()) ?? DateTime.now(),
      );
}
