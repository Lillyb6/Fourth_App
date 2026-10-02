import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fourthapp/api.dart';
import 'package:fourthapp/main.dart';

Future<void> launch(WidgetTester tester, HabitApi api) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(api.dispose);
  await tester.pumpWidget(MyApp(api: api));
  await tester.pumpAndSettle();
}

Future<void> enterCredentials(
  WidgetTester tester, {
  String email = 'me@example.com',
  String password = 'a-long-password',
}) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Password'),
    password,
  );
}

void main() {
  testWidgets('App starts at sign-in without requesting private data', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final api = HabitApi(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 500);
      }),
    );
    await launch(tester, api);

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(find.text('Your habits'), findsNothing);
    expect(api.authenticated, isFalse);
    expect(requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Invalid email and empty password block sign-in requests', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final api = HabitApi(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 500);
      }),
    );
    await launch(tester, api);
    await enterCredentials(tester, email: 'invalid-email', password: '');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(requests, isEmpty);
    expect(api.authenticated, isFalse);
  });

  testWidgets(
    'Signup enforces password limits and opens dashboard on success',
    (tester) async {
      final registrations = <http.Request>[];
      final api = HabitApi(
        client: MockClient((request) async {
          if (request.url.path == '/api/auth/register') {
            registrations.add(request);
            return http.Response('{"token":"new-account-token"}', 201);
          }
          expect(request.url.path, '/api/habits');
          expect(request.headers['authorization'], 'Bearer new-account-token');
          return http.Response('{"habits":[]}', 200);
        }),
      );
      await launch(tester, api);
      await tester.tap(find.text('New here? Create an account'));
      await tester.pumpAndSettle();

      for (final length in [11, 129]) {
        await enterCredentials(tester, password: 'a' * length);
        await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
        await tester.pumpAndSettle();
        expect(registrations, isEmpty);
        expect(api.authenticated, isFalse);
        final field = tester.state<FormFieldState<String>>(
          find.widgetWithText(TextFormField, 'Password'),
        );
        expect(field.errorText, 'Use 12–128 characters.');
      }

      await enterCredentials(
        tester,
        email: ' me@example.com ',
        password: 'a' * 12,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();

      expect(registrations, hasLength(1));
      expect(registrations.single.method, 'POST');
      expect(jsonDecode(registrations.single.body), {
        'email': 'me@example.com',
        'password': 'a' * 12,
      });
      expect(api.authenticated, isTrue);
      expect(find.text('Start with one small habit'), findsOneWidget);
      expect(find.text('Start your next chapter'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Failed login displays error and allows successful retry', (
    tester,
  ) async {
    var attempts = 0;
    final api = HabitApi(
      client: MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          attempts++;
          return attempts == 1
              ? http.Response('{"error":"Invalid email or password"}', 401)
              : http.Response('{"token":"retry-token"}', 200);
        }
        expect(request.url.path, '/api/habits');
        return http.Response('{"habits":[]}', 200);
      }),
    );
    await launch(tester, api);
    await enterCredentials(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid email or password'), findsOneWidget);
    expect(api.authenticated, isFalse);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Sign in'))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(api.authenticated, isTrue);
    expect(find.text('Invalid email or password'), findsNothing);
    expect(find.text('Start with one small habit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Pending login disables controls and prevents duplicate requests',
    (tester) async {
      final response = Completer<http.Response>();
      var attempts = 0;
      final api = HabitApi(
        client: MockClient((request) async {
          if (request.url.path == '/api/auth/login') {
            attempts++;
            return response.future;
          }
          expect(request.url.path, '/api/habits');
          return http.Response('{"habits":[]}', 200);
        }),
      );
      await launch(tester, api);
      await enterCredentials(tester);
      final signIn = find.widgetWithText(FilledButton, 'Sign in');
      await tester.tap(signIn);
      await tester.tap(signIn);
      await tester.pump();

      expect(attempts, 1);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
      for (final field in tester.widgetList<TextFormField>(
        find.byType(TextFormField),
      )) {
        expect(field.enabled, isFalse);
      }

      response.complete(http.Response('{"token":"single-token"}', 200));
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(api.authenticated, isTrue);
      expect(find.text('Start with one small habit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
