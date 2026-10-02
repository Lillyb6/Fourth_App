import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourthapp/api.dart';
import 'package:fourthapp/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<HabitApi> openAccountability(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handler, {
  bool handleGroups = false,
  bool handleActivity = false,
}) async {
  final api = HabitApi(
    client: MockClient((request) async {
      if (request.url.path == '/api/auth/login') {
        return http.Response('{"token":"test-session"}', 200);
      }
      expect(request.headers['authorization'], 'Bearer test-session');
      if (request.url.path == '/api/habits') {
        return http.Response('{"habits":[]}', 200);
      }
      if (!handleGroups &&
          request.url.path == '/api/groups' &&
          request.method == 'GET') {
        return http.Response('{"groups":[]}', 200);
      }
      if (!handleActivity && request.url.path.endsWith('/progress')) {
        return http.Response('{"members":[]}', 200);
      }
      if (!handleActivity && request.url.path.endsWith('/shared-habits')) {
        return http.Response('{"habits":[]}', 200);
      }
      return handler(request);
    }),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  await api.authenticate('test@example.com', 'test-password');
  await tester.pumpWidget(MyApp(api: api));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Accountability'));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets(
    'create validates, generates an editable code, preserves input on conflict and shows saved code',
    (tester) async {
      var calls = 0;
      final api = await openAccountability(tester, (request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/groups');
        final body = jsonDecode(request.body);
        expect(body['name'], 'Study buddies');
        calls++;
        if (calls == 1) {
          return http.Response(
            jsonEncode({'error': 'Invite code already taken—choose another.'}),
            409,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        expect(body['inviteCode'], 'STUDY42');
        return http.Response('{"group":{"inviteCode":"STUDY42"}}', 201);
      });
      addTearDown(api.dispose);
      await tester.tap(find.text('Create a group'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      final generated = tester
          .widget<TextFormField>(fields.last)
          .controller!
          .text;
      expect(generated, matches(RegExp(r'^[A-Z0-9]{8}$')));
      await tester.tap(find.text('Create group'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a group name.'), findsOneWidget);
      expect(calls, 0);
      await tester.enterText(fields.first, ' Study buddies ');
      await tester.enterText(fields.last, 'short');
      await tester.tap(find.text('Create group'));
      await tester.pumpAndSettle();
      expect(find.text('Use 6–15 letters or numbers.'), findsOneWidget);
      expect(calls, 0);
      await tester.enterText(fields.last, generated);
      await tester.tap(find.text('Create group'));
      await tester.pumpAndSettle();
      expect(
        find.text('Invite code already taken—choose another.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextFormField>(fields.first).controller!.text,
        ' Study buddies ',
      );
      await tester.enterText(fields.last, 'study42');
      await tester.tap(find.text('Create group'));
      await tester.pumpAndSettle();
      expect(find.text('Group created'), findsOneWidget);
      expect(find.text('STUDY42'), findsOneWidget);
      expect(calls, 2);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'join retries errors and blocks duplicate submissions while awaiting approval response',
    (tester) async {
      var calls = 0;
      final response = Completer<http.Response>();
      final api = await openAccountability(tester, (request) async {
        expect(request.url.path, '/api/groups/join');
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {'inviteCode': 'STUDY42'});
        calls++;
        if (calls == 1) {
          return http.Response(
            jsonEncode({'error': 'You’re already a member.'}),
            409,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return response.future;
      });
      addTearDown(api.dispose);
      await tester.tap(find.text('Join with a code'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'study42');
      await tester.tap(find.text('Request to join'));
      await tester.pumpAndSettle();
      expect(find.text('You’re already a member.'), findsOneWidget);
      expect(find.text('Request pending'), findsNothing);
      await tester.tap(find.text('Request to join'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Saving…'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      expect(calls, 2);
      response.complete(
        http.Response(
          '{"status":"pending","message":"Your request is pending approval."}',
          202,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your request is pending approval.'), findsOneWidget);
      expect(
        find.text(
          'The group will appear in your list after the owner approves you.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expired session dismisses the group form and returns to authentication',
    (tester) async {
      final api = await openAccountability(
        tester,
        (_) async => http.Response('{"error":"Session expired"}', 401),
      );
      addTearDown(api.dispose);
      await tester.tap(find.text('Join with a code'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'STUDY42');
      await tester.tap(find.text('Request to join'));
      await tester.pumpAndSettle();
      expect(api.authenticated, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.text('Your session expired. Please sign in again.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
