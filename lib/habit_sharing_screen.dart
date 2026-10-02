import 'package:flutter/material.dart';

import 'api.dart';
import 'group.dart';
import 'habit_share.dart';

class HabitSharingScreen extends StatefulWidget {
  const HabitSharingScreen({super.key, required this.api, required this.habit});
  final HabitApi api;
  final Habit habit;
  @override
  State<HabitSharingScreen> createState() => _HabitSharingScreenState();
}

class _HabitSharingScreenState extends State<HabitSharingScreen> {
  List<AccountabilityGroup> groups = [];
  Map<String, HabitShare> shares = {};
  bool loading = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.api.groups();
      final saved = await widget.api.habitShares(widget.habit.id);
      if (mounted) {
        setState(() {
          groups = result;
          shares = saved;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> save(String groupId, HabitShare? value) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.saveHabitShare(widget.habit.id, groupId, value);
      if (mounted) {
        setState(() {
          if (value == null) {
            shares.remove(groupId);
          } else {
            shares[groupId] = value;
          }
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Manage sharing')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.habit.name,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            const Text(
              'Habits are private by default. Sharing a habit shares its name; choose any additional details below.',
            ),
            const SizedBox(height: 20),
            if (error != null) Text(error!),
            if (loading)
              const Center(child: CircularProgressIndicator())
            else if (error != null && groups.isEmpty)
              TextButton(onPressed: load, child: const Text('Retry')),
            if (!loading && error == null && groups.isEmpty)
              const Text('Join a group in Accountability to share a habit.'),
            for (final group in groups)
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: Text(group.name),
                      subtitle: const Text('Share habit name'),
                      value: shares.containsKey(group.id),
                      onChanged: busy
                          ? null
                          : (enabled) => save(
                              group.id,
                              enabled ? const HabitShare() : null,
                            ),
                    ),
                    if (shares[group.id] case final HabitShare share) ...[
                      CheckboxListTile(
                        title: const Text('Description'),
                        value: share.description,
                        onChanged: busy
                            ? null
                            : (value) => save(
                                group.id,
                                HabitShare(
                                  description: value!,
                                  schedule: share.schedule,
                                  checkIns: share.checkIns,
                                ),
                              ),
                      ),
                      CheckboxListTile(
                        title: const Text('Schedule'),
                        value: share.schedule,
                        onChanged: busy
                            ? null
                            : (value) => save(
                                group.id,
                                HabitShare(
                                  description: share.description,
                                  schedule: value!,
                                  checkIns: share.checkIns,
                                ),
                              ),
                      ),
                      CheckboxListTile(
                        title: const Text('Check-in history'),
                        value: share.checkIns,
                        onChanged: busy
                            ? null
                            : (value) => save(
                                group.id,
                                HabitShare(
                                  description: share.description,
                                  schedule: share.schedule,
                                  checkIns: value!,
                                ),
                              ),
                      ),
                    ],
                  ],
                ),
              ),
            if (shares.isNotEmpty)
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await widget.api.makeHabitPrivate(widget.habit.id);
                          if (mounted) setState(() => shares.clear());
                        } on ApiException catch (e) {
                          if (mounted) setState(() => error = e.message);
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: const Text('Make private in all groups'),
              ),
          ],
        ),
      ),
    ),
  );
}
