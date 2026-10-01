import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fourthapp/api.dart';

void main() {
  test(
    'Registration, local dates, failed writes and expired sessions',
    () async {
      var failSave = true;
      var expired = false;
      final api = HabitApi(
        client: MockClient((request) async {
          if (request.url.path == '/api/auth/register') {
            expect(jsonDecode(request.body)['email'], 'me@example.com');
            return http.Response('{"token":"example"}', 201);
          }
          expect(request.headers['authorization'], 'Bearer example');
          if (expired) return http.Response('{"error":"Expired"}', 401);
          expect(request.url.path, '/api/habits/one/check-ins/2026-09-28');
          return failSave
              ? http.Response('{"error":"Save failed"}', 500)
              : http.Response('{}', 200);
        }),
      );
      addTearDown(api.dispose);
      await api.authenticate(
        ' me@example.com ',
        'long-password',
        register: true,
      );
      final habit = Habit('Read', '', false, id: 'one');
      final date = DateTime(2026, 9, 28, 23, 30);
      await expectLater(
        api.checkIn(habit, date, completed: true),
        throwsA(isA<ApiException>()),
      );
      expect(habit.checkIns, isEmpty);
      failSave = false;
      await api.checkIn(habit, date, completed: true);
      expect(habit.checkIns, {DateTime(2026, 9, 28)});
      await api.checkIn(habit, date, completed: false);
      expect(habit.checkIns, isEmpty);
      expired = true;
      await expectLater(api.habits(), throwsA(isA<ApiException>()));
      expect(api.authenticated, isFalse);
    },
  );

  test('Connection errors, rate limits, malformed responses and timeout are readable', () async {
    for (final mode in ['network', 'rate', 'json', 'timeout']) {
      final api = HabitApi(
        timeout: const Duration(milliseconds: 10),
        client: MockClient((request) async {
          if (mode == 'network') throw http.ClientException('socket error');
          if (mode == 'timeout') {
            await Future<void>.delayed(const Duration(milliseconds: 40));
          }
          if (mode == 'rate') return http.Response('Too many requests', 429);
          return http.Response('not JSON', 200);
        }),
      );
      await expectLater(
        api.authenticate('me@example.com', 'long-password'),
        throwsA(isA<ApiException>()),
      );
      expect(api.authenticated, isFalse);
      api.dispose();
    }
  });
}
