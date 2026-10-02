import 'package:flutter/material.dart';

import 'branding.dart';

String dashboardDate(DateTime date) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
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
  final day = date.day;
  final suffix = day >= 11 && day <= 13
      ? 'th'
      : switch (day % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return 'Today is ${weekdays[date.weekday - 1]}, ${months[date.month - 1]} $day$suffix';
}

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({super.key, required this.today});
  final DateTime today;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 28),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        final words = Column(
          crossAxisAlignment: narrow
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Text(
              dashboardDate(today),
              textAlign: narrow ? TextAlign.center : TextAlign.left,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Small steps. Real progress.',
              textAlign: narrow ? TextAlign.center : TextAlign.left,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Make a little time for the things that matter.',
              textAlign: narrow ? TextAlign.center : TextAlign.left,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
        return narrow
            ? Column(
                children: [
                  const BerryLogo(size: 112),
                  const SizedBox(height: 8),
                  words,
                ],
              )
            : Row(
                children: [
                  const BerryLogo(size: 140),
                  const SizedBox(width: 24),
                  Expanded(child: words),
                ],
              );
      },
    ),
  );
}
