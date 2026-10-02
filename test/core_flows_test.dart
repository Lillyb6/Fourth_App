import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fourthapp/api.dart';
import 'package:fourthapp/habit_sharing_screen.dart';
import 'package:fourthapp/journal_screen.dart';
import 'package:fourthapp/main.dart';

Future<HabitApi> openScreen(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handler, {
  Widget Function(HabitApi)? screen,
}) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = HabitApi(
    client: MockClient((request) async {
      if (request.url.path == '/api/auth/login') {
        return http.Response('{"token":"test-token"}', 200);
      }
      expect(request.headers['authorization'], 'Bearer test-token');
      return handler(request);
    }),
  );
  addTearDown(api.dispose);
  await api.authenticate('me@example.com', 'a-long-password');
  await tester.pumpWidget(
    screen == null
        ? MyApp(api: api)
        : MaterialApp(home: Scaffold(body: screen(api))),
  );
  await tester.pumpAndSettle();
  return api;
}

http.Response habitsResponse({bool completed = false}) => http.Response(
  jsonEncode({
    'habits': [
      {
        'id': 'read',
        'name': 'Read a chapter',
        'description': '',
        'schedule': 'daily',
        'checkIns': completed ? [apiDate(DateTime.now())] : <String>[],
      },
    ],
  }),
  200,
);

void main() {
  testWidgets(
    'Failed check-in keeps progress unchanged and retry completes it',
    (tester) async {
      var attempts = 0;
      await openScreen(tester, (request) async {
        if (request.url.path == '/api/habits') return habitsResponse();
        expect(request.method, 'PUT');
        expect(
          request.url.path,
          '/api/habits/read/check-ins/${apiDate(DateTime.now())}',
        );
        attempts++;
        return attempts == 1
            ? http.Response('{"error":"Check-in could not be saved"}', 500)
            : http.Response('{}', 200);
      });
      await tester.tap(find.byTooltip('Check in'));
      await tester.pumpAndSettle();
      expect(find.text('Check-in could not be saved'), findsOneWidget);
      expect(find.text('0 of 1 scheduled habits complete'), findsOneWidget);
      expect(find.byTooltip('Check in'), findsOneWidget);
      await tester.tap(find.byTooltip('Check in'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text('1 of 1 scheduled habits complete'), findsOneWidget);
      expect(find.byTooltip('Undo check-in'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Failed undo preserves completion and retry removes it', (
    tester,
  ) async {
    var attempts = 0;
    await openScreen(tester, (request) async {
      if (request.url.path == '/api/habits') {
        return habitsResponse(completed: true);
      }
      expect(request.method, 'DELETE');
      expect(
        request.url.path,
        '/api/habits/read/check-ins/${apiDate(DateTime.now())}',
      );
      attempts++;
      return attempts == 1
          ? http.Response('{"error":"Undo failed"}', 500)
          : http.Response('', 204);
    });
    await tester.tap(find.byTooltip('Undo check-in'));
    await tester.pumpAndSettle();
    expect(find.text('Undo failed'), findsOneWidget);
    expect(find.text('1 of 1 scheduled habits complete'), findsOneWidget);
    expect(find.byTooltip('Undo check-in'), findsOneWidget);
    await tester.tap(find.byTooltip('Undo check-in'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('0 of 1 scheduled habits complete'), findsOneWidget);
    expect(find.byTooltip('Check in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Failed logout retains session and retry removes account data', (
    tester,
  ) async {
    var attempts = 0;
    final api = await openScreen(tester, (request) async {
      if (request.url.path == '/api/habits') return habitsResponse();
      expect(request.method, 'POST');
      expect(request.url.path, '/api/auth/logout');
      attempts++;
      return attempts == 1
          ? http.Response('{"error":"Sign out failed"}', 503)
          : http.Response('', 204);
    });
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out failed'), findsOneWidget);
    expect(api.authenticated, isTrue);
    expect(find.text('Read a chapter'), findsOneWidget);
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(api.authenticated, isFalse);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Read a chapter'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Late journal error cannot hide the newly selected day', (
    tester,
  ) async {
    final oldResponse = Completer<http.Response>();
    final newResponse = Completer<http.Response>();
    final dates = <String>[];
    await openScreen(tester, (request) async {
      expect(request.url.path, '/api/journal');
      dates.add(request.url.queryParameters['date']!);
      if (dates.length == 1) return http.Response('{"entries":[]}', 200);
      return dates.length == 2 ? oldResponse.future : newResponse.future;
    }, screen: (api) => JournalScreen(api: api));
    await tester.tap(find.byTooltip('Next day'));
    await tester.pump();
    await tester.tap(find.byTooltip('Next day'));
    await tester.pump();
    expect(dates, hasLength(3));
    expect(dates[1], apiDate(day(DateTime.now()).add(const Duration(days: 1))));
    expect(dates[2], apiDate(day(DateTime.now()).add(const Duration(days: 2))));
    http.Response entry(String body, String date) => http.Response(
      jsonEncode({
        'entries': [
          {'id': body, 'date': date, 'kind': 'Note', 'body': body},
        ],
      }),
      200,
    );
    newResponse.complete(entry('Latest day note', dates[2]));
    await tester.pumpAndSettle();
    expect(find.text('Latest day note'), findsOneWidget);
    oldResponse.complete(
      http.Response('{"error":"Earlier day failed to load"}', 503),
    );
    await tester.pumpAndSettle();
    expect(find.text('Latest day note'), findsOneWidget);
    expect(find.text('Earlier day failed to load'), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Sharing options save independently without revealing other details',
    (tester) async {
      final writes = <Map<String, dynamic>>[];
      await openScreen(tester, (request) async {
        if (request.url.path == '/api/groups') return groupsResponse();
        if (request.method == 'GET') return sharesResponse();
        expect(request.method, 'PUT');
        expect(request.url.path, '/api/habits/read/shares/readers');
        writes.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{}', 200);
      }, screen: sharingScreen);
      for (final label in [
        'Description',
        'Schedule',
        'Check-in history',
        'Description',
      ]) {
        await tester.tap(find.widgetWithText(SwitchListTile, label));
        await tester.pumpAndSettle();
      }
      expect(writes, [
        {
          'shareDescription': true,
          'shareSchedule': false,
          'shareCheckIns': false,
        },
        {
          'shareDescription': true,
          'shareSchedule': true,
          'shareCheckIns': false,
        },
        {
          'shareDescription': true,
          'shareSchedule': true,
          'shareCheckIns': true,
        },
        {
          'shareDescription': false,
          'shareSchedule': true,
          'shareCheckIns': true,
        },
      ]);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Description'),
            )
            .value,
        isFalse,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Schedule'),
            )
            .value,
        isTrue,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Check-in history'),
            )
            .value,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Failed make-private preserves sharing until retry succeeds', (
    tester,
  ) async {
    var attempts = 0;
    await openScreen(tester, (request) async {
      if (request.url.path == '/api/groups') return groupsResponse();
      if (request.method == 'GET') return sharesResponse();
      expect(request.method, 'DELETE');
      expect(request.url.path, '/api/habits/read/shares');
      attempts++;
      return attempts == 1
          ? http.Response('{"error":"Privacy update failed"}', 500)
          : http.Response('', 204);
    }, screen: sharingScreen);
    await tester.tap(find.text('Make private in all groups'));
    await tester.pumpAndSettle();
    expect(find.text('Privacy update failed'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Readers'),
          )
          .value,
      isTrue,
    );
    expect(find.byType(SwitchListTile), findsNWidgets(4));
    await tester.tap(find.text('Make private in all groups'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Readers'),
          )
          .value,
      isFalse,
    );
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.text('Make private in all groups'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget sharingScreen(HabitApi api) => HabitSharingScreen(
  api: api,
  habit: Habit('Read a chapter', 'Private description', false, id: 'read'),
);
http.Response groupsResponse() => http.Response(
  '{"groups":[{"id":"readers","name":"Readers","memberCount":1,"isOwner":true}]}',
  200,
);
http.Response sharesResponse() => http.Response(
  '{"shares":[{"groupId":"readers","shareDescription":false,"shareSchedule":false,"shareCheckIns":false}]}',
  200,
);
