// Run explicitly: flutter test test/api_live_test.dart --dart-define=RUN_LIVE_API_TEST=true
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fourthapp/api.dart';

void main() {
  test(
    'Flutter client saves and reloads habits through the real REST API',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'habitapp-flutter-',
      );
      Process? server;
      HabitApi? first;
      HabitApi? second;
      try {
        server = await Process.start(
          'node',
          [
            '--input-type=module',
            '-e',
            '''
        import {createApp} from './src/app.js';
        const {app} = createApp({databasePath: process.env.TEST_DATABASE});
        const server = app.listen(0, '127.0.0.1', () => console.log(server.address().port));
      ''',
          ],
          workingDirectory: 'server',
          environment: {'TEST_DATABASE': '${directory.path}/test.sqlite'},
        );
        server.stderr.drain<void>();
        final port = await server.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 20));
        first = HabitApi(baseUrl: 'http://127.0.0.1:$port');
        await first.authenticate(
          'flutter@example.com',
          'local-test-password',
          register: true,
        );
        final habit = await first.create('Read a chapter', 'Before bed', false);
        await first.checkIn(habit, DateTime(2026, 9, 28), completed: true);
        await first.logout();
        second = HabitApi(baseUrl: 'http://127.0.0.1:$port');
        await second.authenticate('flutter@example.com', 'local-test-password');
        final saved = await second.habits();
        expect(saved.single.name, 'Read a chapter');
        expect(saved.single.checkIns, {DateTime(2026, 9, 28)});
        await second.checkIn(
          saved.single,
          DateTime(2026, 9, 28),
          completed: false,
        );
        expect((await second.habits()).single.checkIns, isEmpty);
        await second.logout();
      } finally {
        first?.dispose();
        second?.dispose();
        if (server != null) {
          server.kill();
          await server.exitCode;
        }
        await directory.delete(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('RUN_LIVE_API_TEST'),
  );
}
