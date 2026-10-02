import 'package:flutter/material.dart';

import 'group_activity.dart';

class GroupActivitySection extends StatelessWidget {
  const GroupActivitySection({
    super.key,
    required this.members,
    required this.habits,
    this.title = 'Today’s group progress',
    this.periodLabel = 'today',
  });
  final String title;
  final String periodLabel;
  final List<MemberProgress> members;
  final List<SharedHabit> habits;

  @override
  Widget build(BuildContext context) {
    final percentages = members
        .map((member) => member.percentage)
        .whereType<int>()
        .toList();
    final overall = percentages.isEmpty
        ? null
        : (percentages.reduce((a, b) => a + b) / percentages.length).round();
    final byPerson = <String, List<SharedHabit>>{};
    for (final habit in habits) {
      byPerson.putIfAbsent(habit.userId, () => []).add(habit);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ExpansionTile(
            key: const PageStorageKey('group-progress'),
            title: Text(title),
            subtitle: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    overall == null
                        ? 'No habits scheduled'
                        : '$overall% overall',
                  ),
                  const SizedBox(height: 8),
                  if (overall != null)
                    LinearProgressIndicator(
                      value: overall / 100,
                      semanticsLabel: 'Overall group progress',
                      semanticsValue: '$overall%',
                    ),
                  const SizedBox(height: 8),
                  const Text('Tap to see member progress'),
                ],
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Average of members with habits scheduled $periodLabel.',
                ),
              ),
              for (final member in members)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member.email),
                      Text(
                        member.percentage == null
                            ? 'No habits scheduled'
                            : '${member.percentage}%',
                      ),
                      if (member.percentage != null) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: member.percentage! / 100,
                          semanticsLabel: '${member.email} progress',
                          semanticsValue: '${member.percentage}%',
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Shared habits', style: Theme.of(context).textTheme.titleLarge),
        if (habits.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No habits shared with this group yet.'),
          ),
        for (final person in byPerson.values) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              person.first.email,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final habit in person)
            Card(
              key: ValueKey(habit.id),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (habit.description != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          habit.description!.isEmpty
                              ? 'No description'
                              : habit.description!,
                        ),
                      ),
                    if (habit.schedule != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          habit.schedule == 'weekdays'
                              ? 'Weekdays'
                              : 'Every day',
                        ),
                      ),
                    if (habit.checkIns != null)
                      ExpansionTile(
                        key: PageStorageKey('history-${habit.id}'),
                        title: const Text('Check-in history'),
                        children: [
                          if (habit.checkIns!.isEmpty)
                            const ListTile(title: Text('No check-ins yet.')),
                          for (final date in habit.checkIns!)
                            ListTile(
                              leading: const Icon(Icons.check_circle_outline),
                              title: Text(date),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}
