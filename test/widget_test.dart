import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fourthapp/main.dart';
import 'package:fourthapp/api.dart';

void main() {
  testWidgets('Sign in, create, check in, undo, reload and sign out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final saved = <Map<String, dynamic>>[];
    final calls = <String>[];
    final api = HabitApi(
      client: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        final path = request.url.path;
        if (path == '/api/groups') return http.Response('{"groups":[]}', 200);
        if (path == '/api/auth/login') {
          return http.Response('{"token":"test-token"}', 200);
        }
        expect(request.headers['authorization'], 'Bearer test-token');
        if (path == '/api/auth/logout') return http.Response('', 204);
        if (path == '/api/habits') {
          if (request.method == 'GET') {
            return http.Response(jsonEncode({'habits': saved}), 200);
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          saved.add({...body, 'id': 'one', 'checkIns': <String>[]});
          return http.Response(jsonEncode({'habit': saved.last}), 201);
        }
        final dates = saved.first['checkIns'] as List<String>;
        if (request.method == 'PUT') {
          dates.add(request.url.pathSegments.last);
        } else {
          dates.clear();
        }
        return request.method == 'PUT'
            ? http.Response(jsonEncode({'habit': saved.first}), 201)
            : http.Response('', 204);
      }),
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(MyApp(api: api));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'me@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'a-long-password',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New habit'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create habit'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a habit name.'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Habit name'),
      'Read a book',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create habit'));
    await tester.pumpAndSettle();
    expect(find.text('Read a book'), findsOneWidget);
    await tester.tap(find.byTooltip('Check in'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1 scheduled habits complete'), findsOneWidget);
    await tester.tap(find.text('Progress'));
    await tester.pumpAndSettle();
    expect(find.text('Read a book'), findsOneWidget);
    expect(find.text('1 habit completions this month'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('Read a book'), findsNothing);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('Read a book'), findsOneWidget);
    await tester.tap(find.text('Accountability'));
    await tester.pumpAndSettle();
    expect(find.text('Your accountability circle'), findsOneWidget);
    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read a book'));
    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsOneWidget);
    await tester.tap(find.text('Undo today’s check-in'));
    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Refresh habits'));
    await tester.pumpAndSettle();
    expect(find.text('0 of 1 scheduled habits complete'), findsOneWidget);
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Read a book'), findsNothing);
    expect(calls, contains('POST /api/habits'));
    expect(
      calls,
      contains('DELETE /api/habits/one/check-ins/${apiDate(DateTime.now())}'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Failed load offers retry; expired session removes private routes',
    (tester) async {
      var failed = true;
      var expired = false;
      final api = HabitApi(
        client: MockClient((request) async {
          if (request.url.path == '/api/auth/login') {
            return http.Response('{"token":"token"}', 200);
          }
          if (expired) return http.Response('{"error":"Session expired"}', 401);
          if (failed) {
            return http.Response('{"error":"Server unavailable"}', 503);
          }
          if (request.method == 'POST') {
            return http.Response('{"error":"Cannot save"}', 500);
          }
          return http.Response('{"habits":[]}', 200);
        }),
      );
      addTearDown(api.dispose);
      await api.authenticate('me@example.com', 'a-long-password');
      await tester.pumpWidget(MyApp(api: api));
      await tester.pumpAndSettle();
      expect(find.text('Server unavailable'), findsOneWidget);
      failed = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New habit'));
      await tester.pumpAndSettle();
      expired = true;
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Habit name'),
        'Private habit',
      );
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Create habit'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create habit'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
      expect(
        find.text('Your session expired. Please sign in again.'),
        findsOneWidget,
      );
      expect(find.text('Plant a new routine'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
