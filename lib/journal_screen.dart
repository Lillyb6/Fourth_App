import 'package:flutter/material.dart';

import 'api.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key, required this.api});
  final HabitApi api;
  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  DateTime selected = day(DateTime.now());
  List<JournalEntry> entries = [];
  bool loading = true;
  String? error;
  int request = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final current = ++request;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.api.journal(selected);
      if (mounted && current == request) setState(() => entries = result);
    } on ApiException catch (e) {
      if (mounted && current == request) setState(() => error = e.message);
    } finally {
      if (mounted && current == request) setState(() => loading = false);
    }
  }

  void changeDate(DateTime date) {
    setState(() => selected = day(date));
    load();
  }

  Future<void> edit([JournalEntry? entry]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            JournalEditor(api: widget.api, date: selected, entry: entry),
      ),
    );
    if (saved == true && mounted) load();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        'Your daily journal',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      const Text('A little space for your thoughts, notes, and reminders.'),
      const SizedBox(height: 20),
      Row(
        children: [
          IconButton(
            tooltip: 'Previous day',
            onPressed: () => changeDate(
              DateTime(selected.year, selected.month, selected.day - 1),
            ),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(dateLabel(selected)),
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: selected,
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2200),
                );
                if (date != null && mounted) changeDate(date);
              },
            ),
          ),
          IconButton(
            tooltip: 'Next day',
            onPressed: () => changeDate(
              DateTime(selected.year, selected.month, selected.day + 1),
            ),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      Align(
        alignment: Alignment.center,
        child: TextButton(
          onPressed: () => changeDate(DateTime.now()),
          child: const Text('Today'),
        ),
      ),
      FilledButton.icon(
        onPressed: () => edit(),
        icon: const Icon(Icons.add),
        label: const Text('New entry'),
      ),
      const SizedBox(height: 20),
      if (loading)
        const Center(child: CircularProgressIndicator())
      else if (error != null) ...[
        Text(error!),
        TextButton(onPressed: load, child: const Text('Retry')),
      ] else if (entries.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Column(
              children: [
                Icon(Icons.auto_stories_outlined, size: 40),
                SizedBox(height: 12),
                Text('A fresh page for your day'),
                SizedBox(height: 8),
                Text(
                  'Add a note, a reminder, or a journal entry.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        )
      else
        for (final entry in entries)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        entry.kind == 'Reminder'
                            ? Icons.notifications_none
                            : entry.kind == 'Note'
                            ? Icons.sticky_note_2_outlined
                            : Icons.auto_stories_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.kind,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit entry',
                        onPressed: () => edit(entry),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(entry.body),
                ],
              ),
            ),
          ),
      const SizedBox(height: 16),
      const Text(
        'Saved privately to your account. Reminders are written notes for the selected day; they do not send notifications.',
        style: TextStyle(color: Colors.black54),
      ),
    ],
  );
}

class JournalEditor extends StatefulWidget {
  const JournalEditor({
    super.key,
    required this.api,
    required this.date,
    this.entry,
  });
  final HabitApi api;
  final DateTime date;
  final JournalEntry? entry;
  @override
  State<JournalEditor> createState() => _JournalEditorState();
}

class _JournalEditorState extends State<JournalEditor> {
  late final text = TextEditingController(text: widget.entry?.body ?? '');
  late String kind = widget.entry?.kind ?? 'Journal';
  final form = GlobalKey<FormState>();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> save({bool deleting = false}) async {
    if (busy || (!deleting && !form.currentState!.validate())) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (deleting) {
        await widget.api.deleteEntry(widget.entry!.id);
      } else {
        await widget.api.saveEntry(
          widget.date,
          kind,
          text.text.trim(),
          id: widget.entry?.id,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.entry == null ? 'New entry' : 'Edit entry'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  dateLabel(widget.date),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final value in ['Note', 'Reminder', 'Journal'])
                      ChoiceChip(
                        label: Text(value),
                        selected: kind == value,
                        onSelected: busy
                            ? null
                            : (_) => setState(() => kind = value),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: text,
                  enabled: !busy,
                  minLines: 6,
                  maxLines: 12,
                  maxLength: 4000,
                  decoration: const InputDecoration(
                    labelText: 'Your words',
                    alignLabelWithHint: true,
                    hintText: 'What is on your mind today?',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Write something before saving.'
                      : null,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(error!),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: busy ? null : () => save(),
                  child: Text(busy ? 'Saving…' : 'Save entry'),
                ),
                if (widget.entry != null)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete entry'),
                    onPressed: busy
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete this entry?'),
                                content: const Text(
                                  'This will permanently remove this entry.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true && mounted) {
                              save(deleting: true);
                            }
                          },
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
