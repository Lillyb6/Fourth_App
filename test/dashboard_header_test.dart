import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourthapp/dashboard_header.dart';
import 'package:fourthapp/berry_theme.dart';

void main() {
  test('date heading uses weekday and correct ordinal suffix', () {
    expect(
      dashboardDate(DateTime(2026, 10, 2)),
      'Today is Friday, October 2nd',
    );
    for (final entry in {
      1: '1st',
      3: '3rd',
      11: '11th',
      12: '12th',
      13: '13th',
      21: '21st',
      22: '22nd',
      23: '23rd',
      31: '31st',
    }.entries) {
      expect(
        dashboardDate(DateTime(2026, 10, entry.key)),
        endsWith(entry.value),
      );
    }
  });
  testWidgets('dashboard header fits narrow and wide screens', (tester) async {
    for (final width in [320.0, 900.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: berryTheme(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: DashboardHeader(today: DateTime(2026, 10, 2)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Today is Friday, October 2nd'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
