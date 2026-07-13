// Unit tests for the pure health-metric logic in lib/dashboard/dashboard.dart.
//
// These functions used to be private instance methods on
// _DashboardScreenState, which made them impossible to test directly —
// you can't reference a class whose name starts with an underscore from
// outside its own file. They've been moved to top-level functions in
// dashboard.dart (no behavior change, just made reachable here) so they
// can be tested without spinning up Firebase or rendering any widgets.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_fyp_application/dashboard/dashboard.dart';

void main() {
  group('bpStatus', () {
    test('flags high blood pressure when systolic alone is high', () {
      expect(bpStatus(150, 70), 'High Blood Pressure ⚠️');
    });

    test('flags high blood pressure when diastolic alone is high', () {
      expect(bpStatus(110, 95), 'High Blood Pressure ⚠️');
    });

    test('flags low blood pressure', () {
      expect(bpStatus(85, 70), 'Low Blood Pressure ⚠️');
      expect(bpStatus(110, 55), 'Low Blood Pressure ⚠️');
    });

    test('reports normal within range', () {
      expect(bpStatus(120, 80), 'Blood Pressure Normal');
    });

    // This documents the bug we found earlier rather than a new one:
    // bpStatus(0, 0) correctly reports "Low" because a *real* reading of
    // 0/0 genuinely would be alarming. The actual fix belonged upstream,
    // in daily_health_entry_page.dart's input validation, which now
    // stops an empty form from ever being saved as a 0/0 reading in the
    // first place. This test exists so that if that validation is ever
    // accidentally removed, the false-alarm behavior is at least documented
    // and visible here rather than silently reappearing.
    test('treats 0/0 as Low — this is exactly why empty entries must be blocked before saving', () {
      expect(bpStatus(0, 0), 'Low Blood Pressure ⚠️');
    });
  });

  group('glucoseStatus', () {
    test('flags high glucose', () => expect(glucoseStatus(180), 'High Glucose ⚠️'));
    test('flags low glucose', () => expect(glucoseStatus(50), 'Low Glucose ⚠️'));
    test('reports normal within range', () => expect(glucoseStatus(95), 'Glucose Normal'));

    test('treats 0 as Low — same reasoning as the bpStatus case above', () {
      expect(glucoseStatus(0), 'Low Glucose ⚠️');
    });
  });

  group('tempStatus', () {
    test('flags fever at or above 38.0°C', () {
      expect(tempStatus(38.0), 'Fever Detected ⚠️');
      expect(tempStatus(39.2), 'Fever Detected ⚠️');
    });

    test('flags low temperature', () => expect(tempStatus(34.0), 'Low Temperature ⚠️'));
    test('reports normal within range', () => expect(tempStatus(36.8), 'Temperature Normal'));
  });

  group('parseValue', () {
    test('parses a numeric string field correctly', () {
      expect(parseValue({'glucose': '95'}, 'glucose'), 95.0);
    });

    test('defaults to 0 when the key is missing', () {
      expect(parseValue({}, 'glucose'), 0.0);
    });

    test('defaults to 0 for an empty string', () {
      expect(parseValue({'glucose': ''}, 'glucose'), 0.0);
    });

    test('defaults to 0 for non-numeric text', () {
      expect(parseValue({'glucose': 'abc'}, 'glucose'), 0.0);
    });
  });
}