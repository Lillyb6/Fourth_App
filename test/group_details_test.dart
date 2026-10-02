import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fourthapp/api.dart';
import 'package:fourthapp/group.dart';
import 'package:fourthapp/group_details_screen.dart';
import 'package:fourthapp/habit_sharing_screen.dart';

void main() {
  testWidgets('owner can approve requests and inspect shared progress', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var approved = false;
    final api = HabitApi(
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/login')) {
          return http.Response('{"token":"test"}', 200);
        }
        if (path == '/api/groups') {
          return http.Response(
            jsonEncode({
              'groups': [
                {
                  'id': 'g',
                  'name': 'Readers',
                  'memberCount': approved ? 2 : 1,
                  'isOwner': true,
                  'inviteCode': 'READ42',
                },
              ],
            }),
            200,
          );
        }
        if (path.endsWith('/approve')) {
          approved = true;
          return http.Response('', 204);
        }
        if (path.endsWith('/requests')) {
          return http.Response(
            jsonEncode({
              'requests': approved
                  ? []
                  : [
                      {'userId': 'b', 'email': 'pending@example.com'},
                    ],
            }),
            200,
          );
        }
        if (path.endsWith('/progress')) {
          return http.Response(
            '{"members":[{"userId":"a","email":"member@example.com","completionPercentage":50}]}',
            200,
          );
        }
        if (path.endsWith('/shared-habits')) {
          return http.Response(
            '{"habits":[{"id":"h1","userId":"a","name":"Read","email":"member@example.com"}]}',
            200,
          );
        }
        throw StateError(path);
      }),
    );
    addTearDown(api.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await api.authenticate('a@example.com', 'test-password');
    await tester.pumpWidget(
      MaterialApp(
        home: GroupDetailsScreen(
          api: api,
          group: AccountabilityGroup.fromJson({
            'id': 'g',
            'name': 'Readers',
            'memberCount': 1,
            'isOwner': true,
            'inviteCode': 'READ42',
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('50% overall'), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
    await tester.ensureVisible(find.text('Approve'));
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(approved, isFalse);
    await tester.tap(find.text('Confirm approval'));
    await tester.pumpAndSettle();
    expect(approved, isTrue);
    expect(find.text('No pending requests.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed sharing save stays private and retry shares name only', (
    tester,
  ) async {
    var fail = true;
    Map<String, dynamic>? written;
    final api = HabitApi(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return http.Response('{"token":"test"}', 200);
        }
        if (request.url.path == '/api/groups') {
          return http.Response(
            '{"groups":[{"id":"g","name":"Readers","memberCount":1,"isOwner":true}]}',
            200,
          );
        }
        if (request.method == 'GET') return http.Response('{"shares":[]}', 200);
        if (fail) return http.Response('{"error":"Save failed"}', 500);
        written = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(api.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await api.authenticate('a@example.com', 'test-password');
    await tester.pumpWidget(
      MaterialApp(
        home: HabitSharingScreen(
          api: api,
          habit: Habit('Read', 'Private words', false, id: 'h'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Save failed'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Readers'),
          )
          .value,
      isFalse,
    );
    fail = false;
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(written, {
      'shareDescription': false,
      'shareSchedule': false,
      'shareCheckIns': false,
    });
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Readers'),
          )
          .value,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
