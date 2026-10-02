import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fourthapp/api.dart';
import 'package:fourthapp/habit_sharing_screen.dart';

void main() {
  testWidgets(
    'sharing switches save separately, failed saves keep prior state, and private clears every group',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var fail = false;
      var cleared = false;
      final writes = <Map<String, dynamic>>[];
      final api = HabitApi(
        client: MockClient((request) async {
          if (request.url.path == '/api/auth/login') {
            return http.Response('{"token":"token"}', 200);
          }
          expect(request.headers['authorization'], 'Bearer token');
          if (request.url.path == '/api/groups') {
            return http.Response(
              '{"groups":[{"id":"g1","name":"Study","memberCount":2,"isOwner":false},{"id":"g2","name":"Fitness","memberCount":2,"isOwner":false}]}',
              200,
            );
          }
          if (request.method == 'GET') {
            return http.Response('{"shares":[]}', 200);
          }
          if (fail) {
            return http.Response('{"error":"Save failed"}', 500);
          }
          if (request.method == 'DELETE') {
            expect(request.url.path, '/api/habits/h1/shares');
            cleared = true;
            return http.Response('', 204);
          }
          expect(request.method, 'PUT');
          writes.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{}', 200);
        }),
      );
      addTearDown(api.dispose);
      await api.authenticate('test@example.com', 'long-password');
      await tester.pumpWidget(
        MaterialApp(
          home: HabitSharingScreen(
            api: api,
            habit: Habit('Read', '', false, id: 'h1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private — not shared with any group'), findsOneWidget);
      await tester.tap(find.text('Study'));
      await tester.pumpAndSettle();
      expect(writes.last, {
        'shareDescription': false,
        'shareSchedule': false,
        'shareCheckIns': false,
      });
      await tester.tap(find.text('Description'));
      await tester.pumpAndSettle();
      expect(writes.last['shareDescription'], true);
      fail = true;
      await tester.tap(find.text('Schedule'));
      await tester.pumpAndSettle();
      expect(find.text('Save failed'), findsOneWidget);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Schedule'),
            )
            .value,
        false,
      );
      fail = false;
      await tester.tap(find.text('Schedule'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check-in history'));
      await tester.pumpAndSettle();
      expect(writes.last, {
        'shareDescription': true,
        'shareSchedule': true,
        'shareCheckIns': true,
      });
      await tester.tap(find.text('Fitness'));
      await tester.pumpAndSettle();
      expect(writes.last, {
        'shareDescription': false,
        'shareSchedule': false,
        'shareCheckIns': false,
      });
      expect(find.text('Shared with 2 groups'), findsOneWidget);
      fail = true;
      await tester.tap(find.text('Make private in all groups'));
      await tester.pumpAndSettle();
      expect(find.text('Shared with 2 groups'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Make private in all groups'));
      await tester.pumpAndSettle();
      expect(cleared, true);
      expect(find.text('Private — not shared with any group'), findsOneWidget);
      expect(find.text('Description'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
