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
  bool loading = true;
  bool saving = false;
  String? error;
  bool loaded = false;

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
      final available = await widget.api.groups();
      final saved = await widget.api.habitShares(widget.habit.id);
      if (mounted) {
        setState(() {
          groups = available;
          shares = saved;
          loaded = true;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> save(String groupId, HabitShare? options) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.api.saveHabitShare(widget.habit.id, groupId, options);
      if (mounted) {
        setState(() {
          if (options == null) {
            shares.remove(groupId);
          } else {
            shares[groupId] = options;
          }
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> makePrivate() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.api.makeHabitPrivate(widget.habit.id);
      if (mounted) setState(() => shares.clear());
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('Manage sharing')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.habit.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Share with selected groups. The habit name is included; other details are your choice. Changes save immediately.',
              ),
              const SizedBox(height: 16),
              if (loading) const Center(child: CircularProgressIndicator()),
              if (saving) const LinearProgressIndicator(),
              if (error != null) ...[
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: saving || loading ? null : load,
                  child: const Text('Reload sharing'),
                ),
              ],
              if (!loading && loaded) ...[
                Text(
                  shares.isEmpty
                      ? 'Private — not shared with any group'
                      : 'Shared with ${shares.length} ${shares.length == 1 ? 'group' : 'groups'}',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Group members can still see your overall daily completion percentage.',
                ),
                if (shares.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: saving ? null : makePrivate,
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Make private in all groups'),
                  ),
                if (groups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Join or create a group in Accountability to share a habit.',
                    ),
                  ),
                for (final group in groups)
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: Text(group.name),
                          subtitle: const Text('Share habit name'),
                          value: shares.containsKey(group.id),
                          onChanged: saving
                              ? null
                              : (enabled) => save(
                                  group.id,
                                  enabled ? const HabitShare() : null,
                                ),
                        ),
                        if (shares[group.id] case final options?) ...[
                          SwitchListTile(
                            title: const Text('Description'),
                            value: options.description,
                            onChanged: saving
                                ? null
                                : (value) => save(
                                    group.id,
                                    options.copyWith(description: value),
                                  ),
                          ),
                          SwitchListTile(
                            title: const Text('Schedule'),
                            value: options.schedule,
                            onChanged: saving
                                ? null
                                : (value) => save(
                                    group.id,
                                    options.copyWith(schedule: value),
                                  ),
                          ),
                          SwitchListTile(
                            title: const Text('Check-in history'),
                            subtitle: const Text(
                              'Includes all saved check-in dates.',
                            ),
                            value: options.checkIns,
                            onChanged: saving
                                ? null
                                : (value) => save(
                                    group.id,
                                    options.copyWith(checkIns: value),
                                  ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
