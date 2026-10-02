import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'group.dart';
import 'group_activity.dart';
import 'habit_share.dart';

DateTime day(DateTime date) => DateTime(date.year, date.month, date.day);
String dateLabel(DateTime date) => '${date.month}/${date.day}/${date.year}';
String apiDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class Habit {
  Habit(
    this.name,
    this.description,
    this.weekdaysOnly, {
    this.id = '',
    Set<DateTime>? checkIns,
  }) : checkIns = checkIns ?? {};
  final String id;
  final String name;
  final String description;
  final bool weekdaysOnly;
  final Set<DateTime> checkIns;
  String get schedule => weekdaysOnly ? 'Weekdays' : 'Every day';
  bool due(DateTime date) => !weekdaysOnly || date.weekday <= 5;
  factory Habit.fromJson(Map<String, dynamic> json) => Habit(
    json['name'] as String,
    json['description'] as String,
    json['schedule'] == 'weekdays',
    id: json['id'] as String,
    checkIns: (json['checkIns'] as List)
        .map((value) => day(DateTime.parse(value as String)))
        .toSet(),
  );
}

class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.date,
    required this.kind,
    required this.body,
  });
  final String id;
  final DateTime date;
  final String kind;
  final String body;
  factory JournalEntry.fromJson(Map<String, dynamic> data) => JournalEntry(
    id: data['id'] as String,
    date: DateTime.parse(data['date'] as String),
    kind: data['kind'] as String,
    body: data['body'] as String,
  );
}

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class HabitApi extends ChangeNotifier {
  HabitApi({
    http.Client? client,
    String? baseUrl,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       baseUrl =
           (baseUrl ??
                   const String.fromEnvironment(
                     'API_BASE_URL',
                     defaultValue: '',
                   ))
               .replaceAll(RegExp(r'/+$'), '');
  final http.Client _client;
  final String baseUrl;
  final Duration timeout;
  String? _token;
  String? sessionMessage;
  bool get authenticated => _token != null;
  String get endpoint => baseUrl.isNotEmpty
      ? baseUrl
      : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android
            ? 'http://10.0.2.2:3000'
            : 'http://127.0.0.1:3000');

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool protected = true,
  }) async {
    final uri = Uri.parse('$endpoint$path');
    if (kReleaseMode && uri.scheme != 'https') {
      throw const ApiException('This build needs a secure server address.');
    }
    final token = _token;
    if (protected && token == null) {
      throw const ApiException('Please sign in again.');
    }
    try {
      final request = http.Request(method, uri)..followRedirects = false;
      request.headers['Content-Type'] = 'application/json';
      if (protected) request.headers['Authorization'] = 'Bearer $token';
      if (body != null) request.body = jsonEncode(body);
      final response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(timeout);
      if (response.statusCode == 401 && protected && _token == token) {
        _token = null;
        sessionMessage = 'Your session expired. Please sign in again.';
        notifyListeners();
      }
      Map<String, dynamic> data = {};
      if (response.body.isNotEmpty) {
        try {
          data = jsonDecode(response.body) as Map<String, dynamic>;
        } on FormatException {
          if (response.statusCode < 400) rethrow;
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          response.statusCode == 429
              ? 'Too many attempts. Please try again later.'
              : (data['error'] as String? ??
                    'The server could not complete the request. Try again.'),
        );
      }
      return data;
    } on TimeoutException {
      throw const ApiException('The server took too long. Try again.');
    } on http.ClientException {
      throw const ApiException(
        'Cannot reach the server. Check your connection and try again.',
      );
    } on FormatException {
      throw const ApiException('The server returned an unexpected response.');
    }
  }

  Future<void> authenticate(
    String email,
    String password, {
    bool register = false,
  }) async {
    final data = await _request(
      'POST',
      '/api/auth/${register ? 'register' : 'login'}',
      protected: false,
      body: {'email': email.trim(), 'password': password},
    );
    _token = data['token'] as String;
    sessionMessage = null;
    notifyListeners();
  }

  Future<void> logout() async {
    await _request('POST', '/api/auth/logout');
    _token = null;
    sessionMessage = null;
    notifyListeners();
  }

  Future<String> createGroup(String name, String inviteCode) async {
    final data = await _request(
      'POST',
      '/api/groups',
      body: {
        'name': name.trim(),
        'inviteCode': inviteCode.trim().toUpperCase(),
      },
    );
    return (data['group'] as Map<String, dynamic>)['inviteCode'] as String;
  }

  Future<void> requestToJoinGroup(String inviteCode) async {
    await _request(
      'POST',
      '/api/groups/join',
      body: {'inviteCode': inviteCode.trim().toUpperCase()},
    );
  }

  Future<List<AccountabilityGroup>> groups() async =>
      ((await _request('GET', '/api/groups'))['groups'] as List)
          .map(
            (value) =>
                AccountabilityGroup.fromJson(value as Map<String, dynamic>),
          )
          .toList();

  Future<List<MemberProgress>> groupProgress(
    String groupId,
    DateTime date,
  ) async =>
      ((await _request(
                'GET',
                '/api/groups/${Uri.encodeComponent(groupId)}/progress?date=${apiDate(date)}',
              ))['members']
              as List)
          .map(
            (value) => MemberProgress.fromJson(value as Map<String, dynamic>),
          )
          .toList();

  Future<List<SharedHabit>> sharedHabits(String groupId) async =>
      ((await _request(
                'GET',
                '/api/groups/${Uri.encodeComponent(groupId)}/shared-habits',
              ))['habits']
              as List)
          .map((value) => SharedHabit.fromJson(value as Map<String, dynamic>))
          .toList();

  Future<void> acknowledgeOwnership(String groupId) async {
    await _request(
      'DELETE',
      '/api/groups/${Uri.encodeComponent(groupId)}/owner-notice',
    );
  }

  Future<List<GroupJoinRequest>> groupRequests(String groupId) async =>
      ((await _request(
                'GET',
                '/api/groups/${Uri.encodeComponent(groupId)}/requests',
              ))['requests']
              as List)
          .map(
            (value) => GroupJoinRequest.fromJson(value as Map<String, dynamic>),
          )
          .toList();

  Future<void> decideGroupRequest(
    String groupId,
    String userId, {
    required bool approve,
  }) async {
    final path =
        '/api/groups/${Uri.encodeComponent(groupId)}/requests/${Uri.encodeComponent(userId)}';
    await _request(
      approve ? 'POST' : 'DELETE',
      approve ? '$path/approve' : path,
    );
  }

  Future<List<Habit>> habits() async =>
      ((await _request('GET', '/api/habits'))['habits'] as List)
          .map((value) => Habit.fromJson(value as Map<String, dynamic>))
          .toList();

  Future<void> leaveGroup(String groupId) async {
    await _request(
      'DELETE',
      '/api/groups/${Uri.encodeComponent(groupId)}/membership',
    );
  }

  Future<Map<String, HabitShare>> habitShares(String habitId) async {
    final data = await _request(
      'GET',
      '/api/habits/${Uri.encodeComponent(habitId)}/shares',
    );
    return {
      for (final share in data['shares'] as List)
        share['groupId'] as String: HabitShare.fromJson(
          share as Map<String, dynamic>,
        ),
    };
  }

  Future<void> saveHabitShare(
    String habitId,
    String groupId,
    HabitShare? options,
  ) async {
    await _request(
      options == null ? 'DELETE' : 'PUT',
      '/api/habits/${Uri.encodeComponent(habitId)}/shares/${Uri.encodeComponent(groupId)}',
      body: options?.toJson(),
    );
  }

  Future<void> makeHabitPrivate(String habitId) async {
    await _request(
      'DELETE',
      '/api/habits/${Uri.encodeComponent(habitId)}/shares',
    );
  }

  Future<Habit> create(String name, String description, bool weekdays) async =>
      Habit.fromJson(
        (await _request(
              'POST',
              '/api/habits',
              body: {
                'name': name,
                'description': description,
                'schedule': weekdays ? 'weekdays' : 'daily',
              },
            ))['habit']
            as Map<String, dynamic>,
      );
  Future<void> checkIn(
    Habit habit,
    DateTime date, {
    required bool completed,
  }) async {
    await _request(
      completed ? 'PUT' : 'DELETE',
      '/api/habits/${Uri.encodeComponent(habit.id)}/check-ins/${apiDate(date)}',
    );
    if (completed) {
      habit.checkIns.add(day(date));
    } else {
      habit.checkIns.remove(day(date));
    }
  }

  Future<List<JournalEntry>> journal(DateTime date) async =>
      ((await _request('GET', '/api/journal?date=${apiDate(date)}'))['entries']
              as List)
          .map((value) => JournalEntry.fromJson(value as Map<String, dynamic>))
          .toList();

  Future<void> saveEntry(
    DateTime date,
    String kind,
    String text, {
    String? id,
  }) async {
    await _request(
      id == null ? 'POST' : 'PUT',
      id == null ? '/api/journal' : '/api/journal/${Uri.encodeComponent(id)}',
      body: {'date': apiDate(date), 'kind': kind, 'body': text},
    );
  }

  Future<void> deleteEntry(String id) async {
    await _request('DELETE', '/api/journal/${Uri.encodeComponent(id)}');
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}
