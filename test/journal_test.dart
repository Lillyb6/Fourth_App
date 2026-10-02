import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fourthapp/api.dart';
import 'package:fourthapp/journal_screen.dart';

void main() {
  testWidgets('journal saves, reloads, edits and separates days', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final entries = <Map<String, dynamic>>[];
    bool failSave = true;
    final api = HabitApi(
      client: MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          return http.Response('{"token":"test"}', 200);
        }
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'entries': entries
                  .where(
                    (e) => e['date'] == request.url.queryParameters['date'],
                  )
                  .toList(),
            }),
            200,
          );
        }
        if (failSave) return http.Response('{"error":"Could not save"}', 500);
        final data = jsonDecode(request.body) as Map<String, dynamic>;
        entries.clear();
        entries.add({...data, 'id': 'one'});
        return http.Response('{}', 200);
      }),
    );
    addTearDown(api.dispose);
    await api.authenticate('me@example.com', 'long-password');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: JournalScreen(api: api)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'A lovely morning');
    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save'), findsOneWidget);
    expect(find.text('A lovely morning'), findsOneWidget);
    failSave = false;
    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();
    expect(find.text('A lovely morning'), findsOneWidget);
    await tester.tap(find.byTooltip('Next day'));
    await tester.pumpAndSettle();
    expect(find.text('A lovely morning'), findsNothing);
    await tester.tap(find.byTooltip('Previous day'));
    await tester.pumpAndSettle();
    expect(find.text('A lovely morning'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit entry'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField),
      'An even better afternoon',
    );
    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();
    expect(find.text('An even better afternoon'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
