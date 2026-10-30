import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_config.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// Passwordless sign-in with Supabase email OTP: request a code, then verify it.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref.read(repositoryProvider).sendEmailOtp(_email.text.trim()),
      success: 'Code sent. Check your email.',
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _codeSent = true;
    });
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ref.read(repositoryProvider).verifyEmailOtp(_email.text.trim(), _code.text.trim()),
    );
    // On success the auth stream fires and the router redirects to /home.
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(AppConfig.appName, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                    const SizedBox(height: 6),
                    Text(AppConfig.tagline, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _email,
                      enabled: !_codeSent && !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (v) {
                        final value = (v ?? '').trim();
                        return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)
                            ? null
                            : 'Enter a valid email address';
                      },
                    ),
                    if (_codeSent) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _code,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'One-time code'),
                        validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the code from your email' : null,
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (!_codeSent)
                      GradientButton(label: 'Send code', icon: Icons.mail_outline, onPressed: _sendCode, busy: _busy)
                    else ...[
                      GradientButton(label: 'Verify and continue', icon: Icons.login, onPressed: _verify, busy: _busy),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy ? null : () => setState(() { _codeSent = false; _code.clear(); }),
                        child: const Text('Use a different email'),
                      ),
                    ],
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
