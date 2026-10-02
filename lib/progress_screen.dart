import 'package:flutter/material.dart';

import 'api.dart';

const monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
String monthLabel(DateTime date) =>
    '${monthNames[date.month - 1]} ${date.year}';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, required this.habits});
  final List<Habit> habits;
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  DateTime selected = day(DateTime.now());
  late DateTime month = DateTime(selected.year, selected.month);
  void move(int offset) => setState(() {
    month = DateTime(month.year, month.month + offset);
    selected = month;
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final count = DateTime(month.year, month.month + 1, 0).day;
    final start = month.weekday % 7;
    final completed = widget.habits
        .where((h) => h.checkIns.contains(selected))
        .toList();
    final total = widget.habits.fold<int>(
      0,
      (sum, h) =>
          sum +
          h.checkIns
              .where((d) => d.year == month.year && d.month == month.month)
              .length,
    );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Your progress',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Little by little, watch your habits grow. Select a day to revisit your completed habits.',
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous month',
                      onPressed: () => move(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        monthLabel(month),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next month',
                      onPressed: () => move(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                Text('$total habit completions this month'),
                TextButton(
                  onPressed: () => setState(() {
                    selected = day(DateTime.now());
                    month = DateTime(selected.year, selected.month);
                  }),
                  child: const Text('Today'),
                ),
                Row(
                  children: [
                    for (final label in [
                      'Sun',
                      'Mon',
                      'Tue',
                      'Wed',
                      'Thu',
                      'Fri',
                      'Sat',
                    ])
                      Expanded(
                        child: Center(
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisExtent: 60,
                    crossAxisSpacing: 3,
                    mainAxisSpacing: 3,
                  ),
                  itemCount: ((start + count + 6) ~/ 7) * 7,
                  itemBuilder: (context, index) {
                    final number = index - start + 1;
                    if (number < 1 || number > count) {
                      return const SizedBox.shrink();
                    }
                    final date = DateTime(month.year, month.month, number);
                    final amount = widget.habits
                        .where((h) => h.checkIns.contains(date))
                        .length;
                    final active = date == selected;
                    final today = date == day(DateTime.now());
                    return Semantics(
                      label: '${apiDate(date)}, $amount completed habits',
                      selected: active,
                      child: Material(
                        color: active
                            ? colors.primary
                            : amount > 0
                            ? colors.primaryContainer
                            : colors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: today ? colors.primary : Colors.transparent,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => selected = date),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$number',
                                style: TextStyle(
                                  color: active
                                      ? colors.onPrimary
                                      : colors.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (amount > 0)
                                Icon(
                                  Icons.circle,
                                  size: 7,
                                  color: active
                                      ? colors.onPrimary
                                      : colors.primary,
                                )
                              else
                                const SizedBox(height: 7),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                const Text('A berry dot marks a day with completed habits.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Completed on ${dateLabel(selected)}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (completed.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No completed habits on this day. Every new day is a fresh start.',
              ),
            ),
          ),
        for (final habit in completed)
          Card(
            child: ListTile(
              leading: Icon(Icons.check_circle, color: colors.primary),
              title: Text(habit.name),
              subtitle: Text(
                habit.description.isEmpty ? 'Completed' : habit.description,
              ),
            ),
          ),
      ],
    );
  }
}
