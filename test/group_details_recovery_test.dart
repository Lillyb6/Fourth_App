import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'accountability_test.dart' show openAccountability;

http.Response jsonResponse(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  testWidgets(
    'owner confirms both actions, cancel does nothing, errors retain requests and counts refresh',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = [
        {'userId': 'alice', 'email': 'alice@example.com'},
        {'userId': 'bob', 'email': 'bob@example.com'},
      ];
      var count = 1;
      var mutations = 0;
      var failApprove = true;
      final api = await openAccountability(tester, (request) async {
        if (request.url.path == '/api/groups') {
          return jsonResponse({
            'groups': [
              {
                'id': 'g1',
                'name': 'Study',
                'memberCount': count,
                'isOwner': true,
                'inviteCode': 'STUDY42',
              },
            ],
          });
        }
        if (request.url.path == '/api/groups/g1/requests') {
          return jsonResponse({'requests': pending});
        }
        mutations++;
        if (request.method == 'POST') {
          expect(request.url.path, '/api/groups/g1/requests/alice/approve');
          if (failApprove) {
            return http.Response('{"error":"Try again later."}', 500);
          }
          pending.removeAt(0);
          count++;
        } else {
          expect(request.method, 'DELETE');
          expect(request.url.path, '/api/groups/g1/requests/bob');
          pending.clear();
        }
        return http.Response('', 204);
      }, handleGroups: true);
      addTearDown(api.dispose);
      expect(find.text('♛ Owner'), findsOneWidget);
      await tester.tap(find.text('Study'));
      await tester.pumpAndSettle();
      expect(find.text('STUDY42'), findsOneWidget);
      expect(find.text('1 member'), findsOneWidget);
      await tester.tap(find.text('Approve').first);
      await tester.pumpAndSettle();
      expect(find.text('Add alice@example.com to Study?'), findsOneWidget);
      expect(mutations, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(mutations, 0);
      await tester.tap(find.text('Approve').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm approval'));
      await tester.pumpAndSettle();
      expect(find.text('Try again later.'), findsOneWidget);
      expect(find.text('alice@example.com'), findsOneWidget);
      expect(find.text('1 member'), findsOneWidget);
      failApprove = false;
      await tester.tap(find.text('Approve').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm approval'));
      await tester.pumpAndSettle();
      expect(find.text('alice@example.com'), findsNothing);
      expect(find.text('2 members'), findsOneWidget);
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      expect(
        find.text('Reject the request from bob@example.com?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(mutations, 2);
      expect(find.text('bob@example.com'), findsOneWidget);
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm rejection'));
      await tester.pumpAndSettle();
      expect(mutations, 3);
      expect(find.text('No pending requests.'), findsOneWidget);
      expect(find.text('2 members'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('2 members'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'group list retries and members never request or see owner-only data',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var failLoad = true;
      var requestCount = 0;
      final api = await openAccountability(tester, (request) async {
        expect(request.url.path, '/api/groups');
        requestCount++;
        if (failLoad) {
          return http.Response('{"error":"Cannot load groups."}', 500);
        }
        return jsonResponse({
          'groups': [
            {'id': 'g1', 'name': 'Study', 'memberCount': 2, 'isOwner': false},
          ],
        });
      }, handleGroups: true);
      addTearDown(api.dispose);
      expect(find.text('Cannot load groups.'), findsOneWidget);
      failLoad = false;
      await tester.ensureVisible(find.text('Retry groups'));
      await tester.tap(find.text('Retry groups'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Study'));
      await tester.tap(find.text('Study'));
      await tester.pumpAndSettle();
      expect(find.text('2 members'), findsOneWidget);
      expect(find.text('Invite code'), findsNothing);
      expect(find.text('Pending requests'), findsNothing);
      expect(find.text('Approve'), findsNothing);
      expect(requestCount, 3);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'notices refresh automatically and opening a group acknowledges new ownership',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var pendingCount = 0;
      var newOwner = false;
      var acknowledgments = 0;
      var listCalls = 0;
      final api = await openAccountability(tester, (request) async {
        if (request.url.path == '/api/groups') {
          listCalls++;
          return jsonResponse({
            'groups': [
              {
                'id': 'g1',
                'name': 'Study',
                'memberCount': 2,
                'isOwner': true,
                'inviteCode': 'STUDY42',
                'pendingRequestCount': pendingCount,
                'ownershipChanged': newOwner,
              },
            ],
          });
        }
        if (request.url.path.endsWith('/owner-notice')) {
          expect(request.method, 'DELETE');
          acknowledgments++;
          newOwner = false;
          return http.Response('', 204);
        }
        expect(request.url.path, '/api/groups/g1/requests');
        return jsonResponse({'requests': []});
      }, handleGroups: true);
      addTearDown(api.dispose);
      expect(find.text('You’re now the owner'), findsNothing);
      pendingCount = 2;
      newOwner = true;
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('Action needed · 2 requests'), findsOneWidget);
      expect(find.text('You’re now the owner'), findsOneWidget);
      expect(acknowledgments, 0);
      await tester.tap(find.text('Study'));
      await tester.pumpAndSettle();
      expect(acknowledgments, 1);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('You’re now the owner'), findsNothing);
      expect(find.text('Action needed · 2 requests'), findsOneWidget);
      pendingCount = 0;
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('Action needed · 2 requests'), findsNothing);
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      final stoppedAt = listCalls;
      await tester.pump(const Duration(seconds: 20));
      expect(listCalls, stoppedAt);
      expect(tester.takeException(), isNull);
    },
  );
  for (final scenario in ['member', 'owner', 'alone']) {
    testWidgets(
      'leave $scenario confirms, preserves membership on error, and refreshes after success',
      (tester) async {
        tester.view.physicalSize = const Size(900, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var left = false;
        var fail = true;
        var deletes = 0;
        final api = await openAccountability(tester, (request) async {
          if (request.url.path == '/api/groups') {
            return jsonResponse({
              'groups': left
                  ? []
                  : [
                      {
                        'id': 'g1',
                        'name': 'Study',
                        'memberCount': scenario == 'alone' ? 1 : 2,
                        'isOwner': scenario != 'member',
                        'inviteCode': 'STUDY42',
                      },
                    ],
            });
          }
          if (request.url.path.endsWith('/requests')) {
            return jsonResponse({'requests': []});
          }
          expect(request.url.path, '/api/groups/g1/membership');
          expect(request.method, 'DELETE');
          deletes++;
          if (fail) {
            return http.Response('{"error":"Could not leave."}', 500);
          }
          left = true;
          return http.Response('', 204);
        }, handleGroups: true);
        addTearDown(api.dispose);
        await tester.tap(find.text('Study'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Leave group'));
        await tester.pumpAndSettle();
        final explanation = scenario == 'alone'
            ? 'this group will be deleted'
            : scenario == 'owner'
            ? 'Ownership will transfer'
            : 'owner approval';
        expect(find.textContaining(explanation), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(deletes, 0);
        await tester.tap(find.text('Leave group'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm leave'));
        await tester.pumpAndSettle();
        expect(find.text('Could not leave.'), findsOneWidget);
        expect(left, false);
        fail = false;
        await tester.tap(find.text('Leave group'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm leave'));
        await tester.pumpAndSettle();
        expect(left, true);
        expect(find.text('You haven’t joined any groups yet.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
