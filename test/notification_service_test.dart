// Unit tests for the pure, static logic in
// lib/notifications/notification_service.dart. Both functions under test
// are already `static` and don't touch Firebase, the OS notification
// plugin, or any widget state — so they're testable as-is, with no mocking
// required.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fyp_application/notifications/notification_service.dart';

void main() {
  group('parseFrequency — dash-separated format (e.g. "1-0-1")', () {
    test('1-0-1 returns morning and night slots, skipping the 0', () {
      expect(NotificationService.parseFrequency('1-0-1'), [
        const TimeOfDay(hour: 8, minute: 0),
        const TimeOfDay(hour: 20, minute: 0),
      ]);
    });

    test('1-1-1 returns morning, afternoon, and night', () {
      expect(NotificationService.parseFrequency('1-1-1'), [
        const TimeOfDay(hour: 8, minute: 0),
        const TimeOfDay(hour: 14, minute: 0),
        const TimeOfDay(hour: 20, minute: 0),
      ]);
    });

    test('0-0-0 falls back to once a day instead of zero reminders', () {
      expect(NotificationService.parseFrequency('0-0-0'),
          [const TimeOfDay(hour: 8, minute: 0)]);
    });
  });

  group('parseFrequency — word formats', () {
    test("'once' returns a single morning slot", () {
      expect(NotificationService.parseFrequency('once'),
          [const TimeOfDay(hour: 8, minute: 0)]);
    });

    test("'twice' returns morning and night", () {
      expect(NotificationService.parseFrequency('twice'), [
        const TimeOfDay(hour: 8, minute: 0),
        const TimeOfDay(hour: 20, minute: 0),
      ]);
    });

    test("'thrice' returns morning, afternoon, and night", () {
      expect(NotificationService.parseFrequency('thrice'), [
        const TimeOfDay(hour: 8, minute: 0),
        const TimeOfDay(hour: 14, minute: 0),
        const TimeOfDay(hour: 20, minute: 0),
      ]);
    });

    test('is case-insensitive and trims surrounding whitespace', () {
      expect(NotificationService.parseFrequency('  TWICE  '), [
        const TimeOfDay(hour: 8, minute: 0),
        const TimeOfDay(hour: 20, minute: 0),
      ]);
    });
  });

  group('parseFrequency — free text like "3 times a day"', () {
    test('spreads doses evenly across 8am–midnight', () {
      final times = NotificationService.parseFrequency('3 times a day');
      expect(times.length, 3);
      expect(times.first, const TimeOfDay(hour: 8, minute: 0));
    });

    test('"4 times daily" returns 4 doses', () {
      expect(NotificationService.parseFrequency('4 times daily').length, 4);
    });
  });

  group('parseFrequency — fallback for unrecognized input', () {
    test('unrecognized text falls back to once a day', () {
      expect(NotificationService.parseFrequency('as needed'),
          [const TimeOfDay(hour: 8, minute: 0)]);
    });

    test('empty string falls back to once a day', () {
      expect(NotificationService.parseFrequency(''),
          [const TimeOfDay(hour: 8, minute: 0)]);
    });
  });

  group('makeBaseId', () {
    test('is deterministic for the same report + medication name', () {
      final id1 = NotificationService.makeBaseId('report123', 'Paracetamol');
      final id2 = NotificationService.makeBaseId('report123', 'Paracetamol');
      expect(id1, id2);
    });

    test('stays within the documented 1000–90999 range', () {
      final id = NotificationService.makeBaseId('report123', 'Paracetamol');
      expect(id, greaterThanOrEqualTo(1000));
      expect(id, lessThanOrEqualTo(90999));
    });

    test('different medication names produce different ids', () {
      final id1 = NotificationService.makeBaseId('report123', 'Paracetamol');
      final id2 = NotificationService.makeBaseId('report123', 'Ibuprofen');
      expect(id1, isNot(equals(id2)));
    });
  });
}