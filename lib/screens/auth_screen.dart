import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/animations.dart';
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
            child: FadeSlideIn(
              offset: const Offset(0, 0.08),
              duration: const Duration(milliseconds: 600),
              child: GlassBox(
              radius: 32,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      _signUp ? 'Create account' : 'Welcome back',
                      key: ValueKey(_signUp),
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 20),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: _signUp
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                controller: _user,
                                autocorrect: false,
                                decoration:
                                    const InputDecoration(hintText: 'Username'),
                              ),
                              const SizedBox(height: 12),
                            ],
                          )
                        : const SizedBox(width: double.infinity),
                  ),
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
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: _error == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error),
                            ),
                          ),
                  ),
                  const SizedBox(height: 20),
                  PressScale(
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _busy
                            ? SizedBox(
                                key: const ValueKey('busy'),
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Theme.of(context).colorScheme.onPrimary,
                                ),
                              )
                            : Text(_signUp ? 'Sign up' : 'Sign in',
                                key: ValueKey(_signUp)),
                      ),
                    ),
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
      ),
    );
  }
}
