import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'group.dart';
import 'group_activity.dart';
import 'group_activity_section.dart';

class GroupDetailsScreen extends StatefulWidget {
  const GroupDetailsScreen({super.key, required this.api, required this.group});
  final HabitApi api;
  final AccountabilityGroup group;

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  AccountabilityGroup? group;
  List<GroupJoinRequest> requests = [];
  List<MemberProgress> progress = [];
  List<SharedHabit> sharedHabits = [];
  bool loading = true;
  bool deciding = false;
  String? error;
  Timer? refreshTimer;
  bool fetching = false;
  DateTime? selectedDate;

  @override
  void initState() {
    super.initState();
    load();
    refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!deciding &&
          ModalRoute.of(context)?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        load(silent: true);
      }
    });
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> load({bool silent = false}) async {
    if (fetching) return;
    fetching = true;
    setState(() {
      if (!silent) {
        loading = true;
        group = null;
        requests = [];
      }
      error = null;
    });
    try {
      // Refresh ownership before requesting owner-only data.
      final groups = await widget.api.groups();
      final matches = groups.where((item) => item.id == widget.group.id);
      if (matches.isEmpty) {
        throw const ApiException(
          'This group is no longer available to your account.',
        );
      }
      final current = matches.first;
      final memberProgress = await widget.api.groupProgress(
        current.id,
        selectedDate ?? DateTime.now(),
      );
      final shared = await widget.api.sharedHabits(current.id);
      final pending = current.isOwner
          ? await widget.api.groupRequests(current.id)
          : <GroupJoinRequest>[];
      if (current.ownershipChanged &&
          mounted &&
          ModalRoute.of(context)?.isCurrent == true) {
        await widget.api.acknowledgeOwnership(current.id);
      }
      if (mounted) {
        setState(() {
          group = current;
          requests = pending;
          progress = memberProgress;
          sharedHabits = shared;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          error = e.message;
          group = null;
          requests = [];
        });
      }
    } finally {
      fetching = false;
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> decide(GroupJoinRequest request, {required bool approve}) async {
    if (deciding || loading || fetching) return;
    setState(() => deciding = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Approve request?' : 'Reject request?'),
        content: Text(
          approve
              ? 'Add ${request.email} to ${group!.name}?'
              : 'Reject the request from ${request.email}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(approve ? 'Confirm approval' : 'Confirm rejection'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => deciding = false);
      return;
    }
    setState(() => error = null);
    try {
      await widget.api.decideGroupRequest(
        widget.group.id,
        request.userId,
        approve: approve,
      );
      if (mounted) await load();
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => deciding = false);
    }
  }

  Future<void> leave() async {
    if (deciding || fetching || group == null) return;
    final current = group!;
    setState(() => deciding = true);
    final explanation = current.isOwner
        ? (current.memberCount == 1
              ? 'You are the only member, so this group will be deleted.'
              : 'Ownership will transfer to the earliest remaining member.')
        : 'You will need owner approval to join again.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave group?'),
        content: Text(
          '$explanation Your habits will stop being shared with this group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm leave'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => deciding = false);
      return;
    }
    setState(() => error = null);
    try {
      await widget.api.leaveGroup(current.id);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => deciding = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.group.name),
      actions: [
        IconButton(
          tooltip: 'Refresh group details',
          onPressed: loading || deciding ? null : load,
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
            if (loading) const Center(child: CircularProgressIndicator()),
            if (error != null) ...[
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: loading || deciding ? null : load,
                child: const Text('Retry'),
              ),
            ],
            if (!loading && group != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: deciding || fetching ? null : leave,
                  icon: const Icon(Icons.exit_to_app),
                  label: const Text('Leave group'),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${group!.memberCount} ${group!.memberCount == 1 ? 'member' : 'members'}',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.calendar_month),
                    label: Text(dateLabel(selectedDate ?? DateTime.now())),
                    onPressed: deciding || fetching
                        ? null
                        : () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: selectedDate ?? day(DateTime.now()),
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now(),
                            );
                            if (date != null && mounted) {
                              setState(() => selectedDate = date);
                              await load();
                            }
                          },
                  ),
                  if (selectedDate != null)
                    TextButton(
                      onPressed: deciding || fetching
                          ? null
                          : () {
                              setState(() => selectedDate = null);
                              load();
                            },
                      child: const Text('Today'),
                    ),
                ],
              ),
              GroupActivitySection(
                members: progress,
                habits: sharedHabits,
                title: selectedDate == null
                    ? 'Today’s group progress'
                    : 'Group progress',
                periodLabel: selectedDate == null
                    ? 'today'
                    : 'on the selected date',
              ),
              if (group!.isOwner) ...[
                const SizedBox(height: 12),
                const Text('♛ Owner', semanticsLabel: 'Group owner'),
                const SizedBox(height: 16),
                const Text('Invite code'),
                SelectableText(
                  group!.inviteCode ?? '',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                Text(
                  'Pending requests',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (requests.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No pending requests.'),
                  ),
                for (final request in requests)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(request.email),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            children: [
                              FilledButton(
                                onPressed: deciding || fetching
                                    ? null
                                    : () => decide(request, approve: true),
                                child: const Text('Approve'),
                              ),
                              OutlinedButton(
                                onPressed: deciding || fetching
                                    ? null
                                    : () => decide(request, approve: false),
                                child: const Text('Reject'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    ),
  );
}
