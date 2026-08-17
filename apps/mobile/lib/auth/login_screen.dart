import 'package:flutter/material.dart';

import '../config/app_config.dart';
import 'auth_service.dart';

enum _EmailStep { enterEmail, enterCode }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onContinueAsGuest});

  /// Called when the user chooses to skip login and use the app with
  /// on-device-only data. See auth/current_user.dart.
  final VoidCallback onContinueAsGuest;

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
                if (AppConfig.isSupabaseConfigured) ..._buildLoginOptions() else _buildNotConfiguredNotice(context),
                const SizedBox(height: 24),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('or')),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: widget.onContinueAsGuest,
                  child: const Text('Continue without an account'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Vehicles and trips stay on this device only, until you sign in.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotConfiguredNotice(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(Icons.settings_outlined),
            const SizedBox(height: 8),
            Text(
              'Google/email sign-in isn\'t configured for this build yet — '
              'see docs/AUTH_SETUP.md. Everything else works without it:',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildLoginOptions() {
    return [
      FilledButton.icon(
        onPressed: _busy ? null : _signInWithGoogle,
        icon: const Icon(Icons.account_circle_outlined),
        label: const Text('Continue with Google'),
      ),
      const SizedBox(height: 24),
      if (_step == _EmailStep.enterEmail) ...[
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _busy ? null : _sendCode, child: const Text('Send sign-in code')),
      ] else ...[
        Text('Enter the code sent to ${_emailController.text.trim()}'),
        const SizedBox(height: 12),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '6-digit code', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _busy ? null : _verifyCode, child: const Text('Verify & sign in')),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _step = _EmailStep.enterEmail),
          child: const Text('Use a different email'),
        ),
      ],
    ];
  }
}
