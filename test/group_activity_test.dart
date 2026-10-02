import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:fourthapp/api.dart';
import 'package:fourthapp/group_activity.dart';
import 'package:fourthapp/group_activity_section.dart';

import 'accountability_test.dart' show openAccountability;
import 'group_details_recovery_test.dart' show jsonResponse;

void main() {
  testWidgets(
    'overall progress expands to member details and optional shared history stays collapsed',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GroupActivitySection(
                members: [
                  MemberProgress(
                    userId: 'a',
                    email: 'a@example.com',
                    percentage: 100,
                  ),
                  MemberProgress(
                    userId: 'b',
                    email: 'b@example.com',
                    percentage: 50,
                  ),
                  MemberProgress(userId: 'c', email: 'c@example.com'),
                ],
                habits: [
                  SharedHabit(
                    id: 'h1',
                    userId: 'x',
                    email: 'reader@example.com',
                    name: 'Read',
                    description: 'One chapter',
                    schedule: 'daily',
                    checkIns: ['2026-01-05'],
                  ),
                  SharedHabit(
                    id: 'h2',
                    userId: 'x',
                    email: 'reader@example.com',
                    name: 'Exercise',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('75% overall'), findsOneWidget);
      expect(find.text('a@example.com'), findsNothing);
      expect(find.text('reader@example.com'), findsOneWidget);
      expect(find.text('2026-01-05'), findsNothing);
      expect(find.text('Check-in history'), findsOneWidget);
      expect(find.text('Every day'), findsOneWidget);
      expect(find.text('One chapter'), findsOneWidget);
      await tester.tap(find.text('Today’s group progress'));
      await tester.pumpAndSettle();
      expect(find.text('a@example.com'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('No habits scheduled'), findsOneWidget);
      final bars = tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .map((bar) => bar.value)
          .toList();
      expect(bars, [0.75, 1.0, 0.5]);
      await tester.tap(find.text('Check-in history'));
      await tester.pumpAndSettle();
      expect(find.text('2026-01-05'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty progress is not presented as zero percent', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GroupActivitySection(
            members: [MemberProgress(userId: 'a', email: 'a@example.com')],
            habits: [],
          ),
        ),
      ),
    );
    expect(find.text('No habits scheduled'), findsOneWidget);
    expect(find.text('0% overall'), findsNothing);
    expect(find.text('No habits shared with this group yet.'), findsOneWidget);
  });

  testWidgets(
    'group refresh removes unshared details and lost access hides all group data',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var shared = true;
      var allowed = true;
      final api = await openAccountability(
        tester,
        (request) async {
          if (request.url.path == '/api/groups') {
            return jsonResponse({
              'groups': [
                {
                  'id': 'g1',
                  'name': 'Study',
                  'memberCount': 2,
                  'isOwner': false,
                },
              ],
            });
          }
          if (!allowed) {
            return http.Response('{"error":"Group not found."}', 404);
          }
          if (request.url.path.endsWith('/progress')) {
            expect(
              request.url.queryParameters['date'],
              apiDate(DateTime.now()),
            );
            return jsonResponse({
              'members': [
                {
                  'userId': 'a',
                  'email': 'member@example.com',
                  'completionPercentage': 50,
                },
              ],
            });
          }
          expect(request.url.path, '/api/groups/g1/shared-habits');
          return jsonResponse({
            'habits': shared
                ? [
                    {
                      'id': 'h1',
                      'userId': 'a',
                      'email': 'member@example.com',
                      'name': 'Shared routine',
                    },
                  ]
                : [],
          });
        },
        handleGroups: true,
        handleActivity: true,
      );
      addTearDown(api.dispose);
      await tester.tap(find.text('Study'));
      await tester.pumpAndSettle();
      expect(find.text('Shared routine'), findsOneWidget);
      expect(find.text('50% overall'), findsOneWidget);
      shared = false;
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('Shared routine'), findsNothing);
      expect(
        find.text('No habits shared with this group yet.'),
        findsOneWidget,
      );
      allowed = false;
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('Group not found.'), findsOneWidget);
      expect(find.text('50% overall'), findsNothing);
      expect(find.text('member@example.com'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
