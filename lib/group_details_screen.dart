import 'package:flutter/material.dart';

import 'api.dart';
import 'group.dart';
import 'group_activity.dart';

class GroupDetailsScreen extends StatefulWidget {
  const GroupDetailsScreen({super.key, required this.api, required this.group});
  final HabitApi api;
  final AccountabilityGroup group;
  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  List<MemberProgress> members = [];
  List<SharedHabit> habits = [];
  List<GroupJoinRequest> requests = [];
  DateTime selected = day(DateTime.now());
  bool loading = true, busy = false;
  late bool notice = widget.group.ownershipChanged;
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
      final progress = await widget.api.groupProgress(
        widget.group.id,
        selected,
      );
      final shared = await widget.api.sharedHabits(widget.group.id);
      final pending = widget.group.isOwner
          ? await widget.api.groupRequests(widget.group.id)
          : <GroupJoinRequest>[];
      if (mounted) {
        setState(() {
          members = progress;
          habits = shared;
          requests = pending;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> action(
    Future<void> Function() work, {
    bool leaving = false,
  }) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
      if (!mounted) return;
      if (leaving) {
        Navigator.pop(context);
      } else {
        await load();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.group.name),
      actions: [
        IconButton(
          tooltip: 'Refresh group',
          onPressed: loading || busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (notice && widget.group.isOwner)
              Card(
                child: ListTile(
                  title: const Text('You are now the owner'),
                  trailing: TextButton(
                    onPressed: busy
                        ? null
                        : () => action(() async {
                            await widget.api.acknowledgeOwnership(
                              widget.group.id,
                            );
                            if (mounted) setState(() => notice = false);
                          }),
                    child: const Text('Dismiss'),
                  ),
                ),
              ),
            if (widget.group.isOwner && widget.group.inviteCode != null)
              SelectableText('Invite code: ${widget.group.inviteCode}'),
            const SizedBox(height: 16),
            if (error != null) ...[
              Text(error!),
              TextButton(
                onPressed: busy || loading ? null : load,
                child: const Text('Retry'),
              ),
            ],
            if (loading)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (widget.group.isOwner) ...[
                Text(
                  'Join requests',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (requests.isEmpty) const Text('No pending requests.'),
                for (final request in requests)
                  Card(
                    child: ListTile(
                      title: Text(request.email),
                      subtitle: Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => action(
                                    () => widget.api.decideGroupRequest(
                                      widget.group.id,
                                      request.userId,
                                      approve: true,
                                    ),
                                  ),
                            child: const Text('Approve'),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => action(
                                    () => widget.api.decideGroupRequest(
                                      widget.group.id,
                                      request.userId,
                                      approve: false,
                                    ),
                                  ),
                            child: const Text('Decline'),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
              ],
              Text(
                'Group progress',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              TextButton.icon(
                icon: const Icon(Icons.calendar_month),
                label: Text(dateLabel(selected)),
                onPressed: busy
                    ? null
                    : () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selected,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (date != null && mounted) {
                          setState(() => selected = date);
                          load();
                        }
                      },
              ),
              for (final member in members)
                ListTile(
                  title: Text(member.email),
                  subtitle: Text(
                    member.percentage == null
                        ? 'No habits scheduled'
                        : '${member.percentage}% complete',
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                'Shared habits',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'Only details each member chose to share appear here.',
              ),
              if (habits.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No habits shared yet.'),
                ),
              for (final habit in habits)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          habit.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(habit.email),
                        if (habit.description != null) Text(habit.description!),
                        if (habit.schedule != null)
                          Text(
                            habit.schedule == 'weekdays'
                                ? 'Weekdays'
                                : 'Every day',
                          ),
                        if (habit.checkIns != null)
                          Text(
                            habit.checkIns!.isEmpty
                                ? 'No check-ins yet.'
                                : 'Check-ins: ${habit.checkIns!.join(', ')}',
                          ),
                      ],
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: busy || loading
                  ? null
                  : () async {
                      final leave = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Leave this group?'),
                          content: Text(
                            widget.group.isOwner
                                ? 'Ownership will pass to the next member. If you are the last member, the group will be deleted.'
                                : 'Your habit sharing with this group will stop.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Leave group'),
                            ),
                          ],
                        ),
                      );
                      if (leave == true && mounted) {
                        action(
                          () => widget.api.leaveGroup(widget.group.id),
                          leaving: true,
                        );
                      }
                    },
              child: const Text('Leave group'),
            ),
          ],
        ),
      ),
    ),
  );
}
