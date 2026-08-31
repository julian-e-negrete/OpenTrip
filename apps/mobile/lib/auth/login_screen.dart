import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';
import '../theme/ph_icons.dart';
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
    await AuthService.instance.verifyEmailCode(email: _emailController.text.trim(), code: code);
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Noct.bg,
      body: Stack(
        children: [
          const Positioned(
            top: -90,
            right: -70,
            child: IgnorePointer(child: _AmbientGlow()),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                children: [
                  const Spacer(),
                  const _BrandBlock(),
                  const SizedBox(height: 34),
                  if (AppConfig.isSupabaseConfigured) ..._buildLoginOptions() else _buildNotConfiguredNotice(),
                  const SizedBox(height: 24),
                  const _OrDivider(),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: widget.onContinueAsGuest,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Noct.n800),
                        foregroundColor: Noct.n300,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Continue without an account'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Vehicles and trips stay on this device only, until you sign in.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, height: 1.55, color: Noct.n600),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 16),
                    const Center(child: CircularProgressIndicator(color: Noct.accent)),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotConfiguredNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Noct.surface,
        borderRadius: BorderRadius.circular(Noct.rMd),
        border: Border.all(color: Noct.n800),
      ),
      child: const Column(
        children: [
          Icon(Ph.gearSix, color: Noct.n400, size: 20),
          SizedBox(height: 8),
          Text(
            'Google/email sign-in isn\'t configured for this build yet — '
            'see docs/AUTH_SETUP.md. Everything else works without it:',
            textAlign: TextAlign.center,
            style: TextStyle(color: Noct.n400, fontSize: 11.5, height: 1.5),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildLoginOptions() {
    return [
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _busy ? null : _signInWithGoogle,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Noct.accent, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Ph.googleLogo, size: 16, color: Noct.a200),
              SizedBox(width: 10),
              Text('Continue with Google', style: TextStyle(fontSize: 13.5)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 11),
      if (_step == _EmailStep.enterEmail) ...[
        Container(
          decoration: BoxDecoration(
            color: Noct.surface,
            borderRadius: BorderRadius.circular(Noct.rMd),
            border: Border.all(color: Noct.divider),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 2),
          child: Row(
            children: [
              const Icon(Ph.envelopeSimple, size: 15, color: Noct.n500),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  cursorColor: Noct.accent,
                  style: const TextStyle(fontSize: 13, color: Noct.text),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                    hintText: 'Email',
                    hintStyle: TextStyle(fontSize: 13, color: Noct.n500),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 11),
        _PlainOutlinedButton(label: 'Send sign-in code', onPressed: _busy ? null : _sendCode),
      ] else ...[
        Text(
          'Enter the code sent to ${_emailController.text.trim()}',
          style: const TextStyle(fontSize: 12.5, color: Noct.n400),
        ),
        const SizedBox(height: 11),
        Container(
          decoration: BoxDecoration(
            color: Noct.surface,
            borderRadius: BorderRadius.circular(Noct.rMd),
            border: Border.all(color: Noct.divider),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            cursorColor: Noct.accent,
            style: const TextStyle(fontSize: 13, color: Noct.text),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 14),
              hintText: '6-digit code',
              hintStyle: TextStyle(fontSize: 13, color: Noct.n500),
            ),
          ),
        ),
        const SizedBox(height: 11),
        _PlainOutlinedButton(label: 'Verify & sign in', onPressed: _busy ? null : _verifyCode),
        Center(
          child: TextButton(
            onPressed: _busy ? null : () => setState(() => _step = _EmailStep.enterEmail),
            child: const Text('Use a different email', style: TextStyle(fontSize: 12, color: Noct.n400)),
          ),
        ),
      ],
    ];
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      height: 280,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [Noct.accent.withValues(alpha: 0.22), Colors.transparent],
          stops: const [0.0, 0.68],
        ),
      ),
    );
  }
}

class _BrandBlock extends StatelessWidget {
  const _BrandBlock();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Ph.path, size: 26, color: Noct.accent),
        const SizedBox(height: 14),
        const Text(
          'OpenTrip',
          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w500, letterSpacing: -0.68, color: Noct.text),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: const Text(
            'Track every ride across your vehicles. Free, open, and yours — '
            'no subscription, no locked features.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.6, color: Noct.n400, fontWeight: FontWeight.w400),
          ),
        ),
      ],
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Noct.n800, Colors.transparent]),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('or', style: TextStyle(fontSize: 11, color: Noct.n600, fontWeight: FontWeight.w400)),
        ),
        Expanded(
          child: Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Colors.transparent, Noct.n800]),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlainOutlinedButton extends StatelessWidget {
  const _PlainOutlinedButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Noct.divider),
          foregroundColor: Noct.n300,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}
