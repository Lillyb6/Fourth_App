import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class Habit {
  Habit(this.name, this.description, this.weekdaysOnly);
  final String name;
  final String description;
  final bool weekdaysOnly;
  final Set<DateTime> checkIns = {};
  String get schedule => weekdaysOnly ? 'Weekdays' : 'Every day';
  bool due(DateTime date) => !weekdaysOnly || date.weekday <= 5;
}

DateTime day(DateTime date) => DateTime(date.year, date.month, date.day);
String dateLabel(DateTime date) => '${date.month}/${date.day}/${date.year}';

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'HabitApp',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff326b54)),
      scaffoldBackgroundColor: const Color(0xfff6f7f2),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.only(bottom: 12),
      ),
    ),
    home: const HabitHome(),
  );
}

class HabitHome extends StatefulWidget {
  const HabitHome({super.key});
  @override
  State<HabitHome> createState() => _HabitHomeState();
}

class _HabitHomeState extends State<HabitHome> {
  final List<Habit> habits = [];
  int selectedPage = 0;

  Future<void> createHabit() async {
    final habit = await Navigator.of(
      context,
    ).push<Habit>(MaterialPageRoute(builder: (_) => const CreateHabitScreen()));
    if (habit != null && mounted) setState(() => habits.add(habit));
  }

  void toggle(Habit habit) {
    final today = day(DateTime.now());
    setState(() {
      if (!habit.checkIns.remove(today)) habit.checkIns.add(today);
    });
  }

  @override
  Widget build(BuildContext context) {
    final today = day(DateTime.now());
    final due = habits.where((habit) => habit.due(today)).toList();
    final completed = due
        .where((habit) => habit.checkIns.contains(today))
        .length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('HabitApp'),
        actions: const [
          Padding(padding: EdgeInsets.all(16), child: Icon(Icons.spa_outlined)),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: selectedPage == 1
              ? const AccountabilityScreen()
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      dateLabel(today),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Small steps. Real progress.',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Make a little time for the things that matter.',
                    ),
                    const SizedBox(height: 24),
                    Card(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Today’s progress',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '$completed of ${due.length} scheduled habits complete',
                            ),
                            const SizedBox(height: 16),
                            LinearProgressIndicator(
                              value: due.isEmpty ? 0 : completed / due.length,
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Your habits',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    if (habits.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: Column(
                            children: [
                              Icon(Icons.eco_outlined, size: 48),
                              SizedBox(height: 12),
                              Text('Start with one small habit'),
                              SizedBox(height: 8),
                              Text(
                                'Tap New habit to create your first daily routine.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    for (final habit in habits)
                      Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: Icon(
                            habit.checkIns.contains(today)
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          title: Text(habit.name),
                          subtitle: Text(
                            '${habit.schedule}${habit.due(today) ? '' : ' · Rest day'}',
                          ),
                          trailing: IconButton(
                            tooltip: habit.checkIns.contains(today)
                                ? 'Undo check-in'
                                : 'Check in',
                            onPressed: habit.due(today)
                                ? () => toggle(habit)
                                : null,
                            icon: Icon(
                              habit.checkIns.contains(today)
                                  ? Icons.undo
                                  : Icons.add_task,
                            ),
                          ),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => HabitDetailsScreen(
                                  habit: habit,
                                  onToggle: () => toggle(habit),
                                ),
                              ),
                            );
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'Preview: habits and check-ins stay in memory for this session.',
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 90),
                  ],
                ),
        ),
      ),
      floatingActionButton: selectedPage == 0
          ? FloatingActionButton.extended(
              onPressed: createHabit,
              icon: const Icon(Icons.add),
              label: const Text('New habit'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedPage,
        onDestinationSelected: (index) => setState(() => selectedPage = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            label: 'Accountability',
          ),
        ],
      ),
    );
  }
}

class CreateHabitScreen extends StatefulWidget {
  const CreateHabitScreen({super.key});
  @override
  State<CreateHabitScreen> createState() => _CreateHabitScreenState();
}

class _CreateHabitScreenState extends State<CreateHabitScreen> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final description = TextEditingController();
  bool weekdaysOnly = false;
  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create habit')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Plant a new routine',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text('Keep it simple, specific, and achievable.'),
              const SizedBox(height: 28),
              TextFormField(
                controller: name,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: 'Habit name',
                  hintText: 'Read for 10 minutes',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a habit name.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: description,
                maxLength: 300,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'What will help you show up?',
                ),
              ),
              const SizedBox(height: 16),
              Text('Repeat', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                children: [
                  ChoiceChip(
                    label: const Text('Every day'),
                    selected: !weekdaysOnly,
                    onSelected: (_) => setState(() => weekdaysOnly = false),
                  ),
                  ChoiceChip(
                    label: const Text('Weekdays'),
                    selected: weekdaysOnly,
                    onSelected: (_) => setState(() => weekdaysOnly = true),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.lock_outline),
                title: Text('Private by default'),
                subtitle: Text(
                  'Your habit details are not shared with a group.',
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(
                      context,
                      Habit(
                        name.text.trim(),
                        description.text.trim(),
                        weekdaysOnly,
                      ),
                    );
                  }
                },
                child: const Text('Create habit'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class HabitDetailsScreen extends StatefulWidget {
  const HabitDetailsScreen({
    super.key,
    required this.habit,
    required this.onToggle,
  });
  final Habit habit;
  final VoidCallback onToggle;
  @override
  State<HabitDetailsScreen> createState() => _HabitDetailsScreenState();
}

class _HabitDetailsScreenState extends State<HabitDetailsScreen> {
  @override
  Widget build(BuildContext context) {
    final habit = widget.habit;
    final today = day(DateTime.now());
    final history = habit.checkIns.toList()..sort((a, b) => b.compareTo(a));
    final done = habit.checkIns.contains(today);
    return Scaffold(
      appBar: AppBar(title: const Text('Habit details')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Icon(Icons.spa_outlined, size: 48),
              ),
              const SizedBox(height: 20),
              Text(
                habit.name,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                habit.description.isEmpty
                    ? 'One small step at a time.'
                    : habit.description,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  Chip(label: Text(habit.schedule)),
                  const Chip(
                    avatar: Icon(Icons.lock_outline, size: 16),
                    label: Text('Private'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: habit.due(today)
                    ? () {
                        widget.onToggle();
                        setState(() {});
                      }
                    : null,
                icon: Icon(done ? Icons.undo : Icons.check),
                label: Text(
                  !habit.due(today)
                      ? 'Today is a rest day'
                      : done
                      ? 'Undo today’s check-in'
                      : 'Check in today',
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Check-in history',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (history.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Your first check-in starts your story.'),
                  ),
                ),
              for (final date in history)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(dateLabel(date)),
                    subtitle: const Text('Completed'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class AccountabilityScreen extends StatelessWidget {
  const AccountabilityScreen({super.key});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text('Grow together', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      const Text('A little encouragement can make a big difference.'),
      const SizedBox(height: 24),
      const Card(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            children: [
              Icon(Icons.people_outline, size: 56),
              SizedBox(height: 16),
              Text('Your accountability circle'),
              SizedBox(height: 12),
              Text(
                'Create a group or join friends to celebrate consistent progress.',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20),
              OutlinedButton(onPressed: null, child: Text('Create a group')),
              OutlinedButton(onPressed: null, child: Text('Join with a code')),
              SizedBox(height: 12),
              Text(
                'Groups will be available after accounts and the backend are connected.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
      const ListTile(
        leading: Icon(Icons.shield_outlined),
        title: Text('You control what you share'),
        subtitle: Text(
          'Habit details stay private unless you choose to share them.',
        ),
      ),
    ],
  );
}
