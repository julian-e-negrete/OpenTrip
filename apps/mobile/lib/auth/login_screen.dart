import 'package:flutter/material.dart';

import 'auth_service.dart';

enum _EmailStep { enterEmail, enterCode }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  _EmailStep _step = _EmailStep.enterEmail;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() => _run(() async {
    await AuthService.instance.signInWithGoogle();
    // On success, the auth-state listener in main.dart navigates away from
    // this screen — nothing else to do here.
  });

  Future<void> _sendCode() => _run(() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) throw const FormatException('Enter an email address first.');
    await AuthService.instance.sendEmailCode(email);
    setState(() => _step = _EmailStep.enterCode);
  });

  Future<void> _verifyCode() => _run(() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) throw const FormatException('Enter the code from your email.');
    await AuthService.instance.verifyEmailCode(
      email: _emailController.text.trim(),
      code: code,
    );
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'OpenTrip',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sign in to track trips across your vehicles.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _busy ? null : _signInWithGoogle,
                  icon: const Icon(Icons.account_circle_outlined),
                  label: const Text('Continue with Google'),
                ),
                const SizedBox(height: 24),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('or')),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 24),
                if (_step == _EmailStep.enterEmail) ...[
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _busy ? null : _sendCode,
                    child: const Text('Send sign-in code'),
                  ),
                ] else ...[
                  Text('Enter the code sent to ${_emailController.text.trim()}'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '6-digit code',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _busy ? null : _verifyCode,
                    child: const Text('Verify & sign in'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _step = _EmailStep.enterEmail),
                    child: const Text('Use a different email'),
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
