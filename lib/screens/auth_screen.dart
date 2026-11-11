import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/glass.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _user = TextEditingController();
  final _usernameRe = RegExp(r'^[a-z0-9_.]{3,20}$');
  bool _signUp = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _user.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final client = Supabase.instance.client;
    try {
      if (_signUp) {
        final u = _user.text.trim().toLowerCase();
        if (!_usernameRe.hasMatch(u)) {
          throw 'Username: 3 to 20 letters, numbers, _ or .';
        }
        final ok = await client.rpc('username_available', params: {'u': u});
        if (ok != true) throw 'That username is taken';
        await client.auth.signUp(
          email: _email.text.trim(),
          password: _pass.text,
          data: {'username': u},
        );
      } else {
        await client.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _pass.text,
        );
      }
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: GlassBox(
              radius: 32,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _signUp ? 'Create account' : 'Welcome back',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 20),
                  if (_signUp) ...[
                    TextField(
                      controller: _user,
                      autocorrect: false,
                      decoration: const InputDecoration(hintText: 'Username'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(hintText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: 'Password'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_busy
                        ? 'Please wait'
                        : (_signUp ? 'Sign up' : 'Sign in')),
                  ),
                  TextButton(
                    onPressed:
                        _busy ? null : () => setState(() => _signUp = !_signUp),
                    child: Text(_signUp
                        ? 'I already have an account'
                        : 'Create a new account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
