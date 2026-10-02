import 'package:flutter/material.dart';

import 'api.dart';
import 'accountability_screen.dart';
import 'auth_screen.dart';
import 'habit_sharing_screen.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.api});
  final HabitApi? api;
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final HabitApi api = widget.api ?? HabitApi();
  @override
  void initState() {
    super.initState();
    api.addListener(sessionChanged);
  }

  void sessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    api.removeListener(sessionChanged);
    if (widget.api == null) api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    key: ValueKey(api.authenticated),
    title: 'HabitApp',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff3569b0)),
      scaffoldBackgroundColor: const Color(0xfff3f6fc),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.only(bottom: 12),
      ),
    ),
    home: api.authenticated ? HabitHome(api: api) : AuthScreen(api: api),
  );
}

class HabitHome extends StatefulWidget {
  const HabitHome({super.key, required this.api});
  final HabitApi api;
  @override
  State<HabitHome> createState() => _HabitHomeState();
}

class _HabitHomeState extends State<HabitHome> {
  List<Habit> habits = [];
  bool loading = true;
  bool signingOut = false;
  String? loadError;
  final Set<String> pending = {};
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      final saved = await widget.api.habits();
      if (mounted) setState(() => habits = saved);
    } on ApiException catch (e) {
      if (mounted) setState(() => loadError = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> logout() async {
    setState(() => signingOut = true);
    try {
      await widget.api.logout();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => signingOut = false);
    }
  }

  int selectedPage = 0;

  Future<void> createHabit() async {
    final habit = await Navigator.of(context).push<Habit>(
      MaterialPageRoute(builder: (_) => CreateHabitScreen(api: widget.api)),
    );
    if (habit != null && mounted) setState(() => habits.add(habit));
  }

  Future<void> toggle(Habit habit) async {
    if (pending.contains(habit.id)) return;
    final today = day(DateTime.now());
    setState(() => pending.add(habit.id));
    try {
      await widget.api.checkIn(
        habit,
        today,
        completed: !habit.checkIns.contains(today),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => pending.remove(habit.id));
    }
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
        actions: [
          IconButton(
            tooltip: 'Refresh habits',
            onPressed: loading || pending.isNotEmpty ? null : load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: signingOut ? null : logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: selectedPage == 1
              ? AccountabilityScreen(api: widget.api)
              : loading
              ? const Center(child: CircularProgressIndicator())
              : loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
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
                            onPressed:
                                habit.due(today) && !pending.contains(habit.id)
                                ? () => toggle(habit)
                                : null,
                            icon: Icon(
                              habit.checkIns.contains(today)
                                  ? Icons.undo
                                  : Icons.add_task,
                            ),
                          ),
                          onTap: pending.contains(habit.id)
                              ? null
                              : () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => HabitDetailsScreen(
                                        api: widget.api,
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
                      'Your habits and check-ins are saved to your account.',
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 90),
                  ],
                ),
        ),
      ),
      floatingActionButton: selectedPage == 0
          ? FloatingActionButton.extended(
              onPressed: loading || loadError != null ? null : createHabit,
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
  const CreateHabitScreen({super.key, required this.api});
  final HabitApi api;
  @override
  State<CreateHabitScreen> createState() => _CreateHabitScreenState();
}

class _CreateHabitScreenState extends State<CreateHabitScreen> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final description = TextEditingController();
  bool weekdaysOnly = false;
  bool saving = false;
  String? error;
  Future<void> save() async {
    if (!formKey.currentState!.validate() || saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final saved = await widget.api.create(
        name.text.trim(),
        description.text.trim(),
        weekdaysOnly,
      );
      if (mounted) Navigator.pop(context, saved);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

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
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(error!),
                ),
              FilledButton(
                onPressed: saving ? null : save,
                child: Text(saving ? 'Saving…' : 'Create habit'),
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
    required this.api,
    required this.onToggle,
  });
  final Habit habit;
  final HabitApi api;
  final Future<void> Function() onToggle;
  @override
  State<HabitDetailsScreen> createState() => _HabitDetailsScreenState();
}

class _HabitDetailsScreenState extends State<HabitDetailsScreen> {
  bool saving = false;
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
                  ActionChip(
                    avatar: const Icon(Icons.shield_outlined, size: 16),
                    label: const Text('Manage sharing'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => HabitSharingScreen(api: widget.api, habit: habit),
                    )),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: habit.due(today) && !saving
                    ? () async {
                        setState(() => saving = true);
                        await widget.onToggle();
                        if (mounted) setState(() => saving = false);
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
