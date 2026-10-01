import 'package:flutter/material.dart';

import 'api.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.api});
  final HabitApi api;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  bool register = false;
  bool busy = false;
  String? error;
  Future<void> submit() async {
    if (!form.currentState!.validate() || busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.authenticate(
        email.text,
        password.text,
        register: register,
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('HabitApp')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.spa_outlined, size: 60),
              const SizedBox(height: 24),
              Text(
                register ? 'Start your next chapter' : 'Welcome back',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text('Your habits, saved with your account.'),
              const SizedBox(height: 24),
              TextFormField(
                controller: email,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (value) =>
                    value == null ||
                        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                            .hasMatch(value.trim())
                    ? 'Enter a valid email address.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: password,
                enabled: !busy,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: register ? 'Use 12–128 characters.' : null,
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Enter your password.'
                    : register && (value.length < 12 || value.length > 128)
                    ? 'Use 12–128 characters.'
                    : null,
                onFieldSubmitted: (_) => submit(),
              ),
              if (error ?? widget.api.sessionMessage case final String message)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Semantics(liveRegion: true, child: Text(message)),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Text(
                  busy
                      ? 'Please wait…'
                      : register
                      ? 'Create account'
                      : 'Sign in',
                ),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        register = !register;
                        error = null;
                        password.clear();
                        form.currentState!.reset();
                      }),
                child: Text(
                  register
                      ? 'Already have an account? Sign in'
                      : 'New here? Create an account',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
