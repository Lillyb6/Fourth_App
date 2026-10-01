import 'dart:math';

import 'package:flutter/material.dart';

import 'api.dart';

class AccountabilityScreen extends StatelessWidget {
  const AccountabilityScreen({super.key, required this.api});
  final HabitApi api;

  void openForm(BuildContext context, {required bool creating}) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GroupForm(api: api, creating: creating),
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text('Grow together', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      const Text('A little encouragement can make a big difference.'),
      const SizedBox(height: 24),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Icon(Icons.people_outline, size: 56),
              const SizedBox(height: 16),
              const Text('Your accountability circle'),
              const SizedBox(height: 12),
              const Text(
                'Create a group or join friends to celebrate consistent progress.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () => openForm(context, creating: true),
                child: const Text('Create a group'),
              ),
              OutlinedButton(
                onPressed: () => openForm(context, creating: false),
                child: const Text('Join with a code'),
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

class _GroupForm extends StatefulWidget {
  const _GroupForm({required this.api, required this.creating});
  final HabitApi api;
  final bool creating;

  @override
  State<_GroupForm> createState() => _GroupFormState();
}

class _GroupFormState extends State<_GroupForm> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final code = TextEditingController();
  bool saving = false;
  bool succeeded = false;
  String? error;
  String? savedCode;

  @override
  void initState() {
    super.initState();
    if (widget.creating) {
      final random = Random.secure();
      code.text = List.generate(
        4,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join().toUpperCase();
    }
  }

  @override
  void dispose() {
    name.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (saving || !formKey.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (widget.creating) {
        savedCode = await widget.api.createGroup(name.text, code.text);
      } else {
        await widget.api.requestToJoinGroup(code.text);
      }
      if (mounted) setState(() => succeeded = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      scrollable: true,
      title: Text(
        succeeded
            ? (widget.creating ? 'Group created' : 'Request pending')
            : (widget.creating ? 'Create a group' : 'Join with a code'),
      ),
      content: succeeded
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: widget.creating
                  ? [
                      Text('You are the owner of ${name.text.trim()}.'),
                      const SizedBox(height: 12),
                      const Text('Invite code'),
                      SelectableText(
                        savedCode!,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Share this code with friends. You approve who joins.',
                      ),
                    ]
                  : [
                      const Text('Your request is pending approval.'),
                      const SizedBox(height: 12),
                      const Text(
                        'The group will appear in your list after the owner approves you.',
                      ),
                    ],
            )
          : Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.creating) ...[
                    TextFormField(
                      controller: name,
                      enabled: !saving,
                      maxLength: 60,
                      decoration: const InputDecoration(
                        labelText: 'Group name',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter a group name.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: code,
                    enabled: !saving,
                    maxLength: 15,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Invite code',
                      helperText: widget.creating
                          ? 'Use this code or edit it. 6–15 letters or numbers.'
                          : 'Enter the code from the group owner.',
                      helperMaxLines: 2,
                    ),
                    validator: (value) =>
                        RegExp(r'^[a-zA-Z0-9]{6,15}$')
                            .hasMatch(value?.trim() ?? '')
                        ? null
                        : 'Use 6–15 letters or numbers.',
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
      actions: succeeded
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ]
          : [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving ? null : submit,
                child: Text(
                  saving
                      ? 'Saving…'
                      : widget.creating
                      ? 'Create group'
                      : 'Request to join',
                ),
              ),
            ],
    ),
  );
}
