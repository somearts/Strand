import 'package:flutter/material.dart';

import '../../auth/auth_scope.dart';
import '../../auth/auth_service.dart';
import '../widgets/auth_form.dart';

/// Create account: name, email, password, a real Firebase account.
class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;
  String? _validation;
  String? _method;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'Enter the name Strand should use.';
    final String email = _email.text.trim();
    if (email.isEmpty || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    if (_password.text.length < 6) {
      return 'Use a password with at least 6 characters.';
    }
    return null;
  }

  Future<void> _create(StrandAuth auth) async {
    final String? problem = _validate();
    if (problem != null) {
      setState(() => _validation = problem);
      return;
    }
    setState(() {
      _validation = null;
      _method = 'email';
    });
    final bool ok = await auth.createAccount(
      name: _name.text.trim(),
      email: _email.text.trim(),
      password: _password.text,
    );
    if (!mounted) return;
    setState(() => _method = null);
    if (!ok) return;
    Navigator.of(context).pushReplacementNamed('/health');
  }

  @override
  Widget build(BuildContext context) {
    final StrandAuth auth = AuthScope.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    final String? message = _validation ?? auth.error;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: auth,
          builder: (BuildContext context, Widget? _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (Navigator.of(context).canPop())
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.arrow_back,
                            size: 20,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    const SizedBox(height: 36),
                    Text('Create your account', style: t.headlineLarge),
                    const SizedBox(height: 10),
                    Text(
                      'Your name is what Strand greets you with. Your nights '
                      'stay on this device either way.',
                      style: t.bodyMedium?.copyWith(height: 1.55),
                    ),
                    const SizedBox(height: 26),
                    if (!auth.isConfigured) ...<Widget>[
                      AuthNotice(
                        text: auth.configurationNote ??
                            'Sign-in is not configured in this build.',
                      ),
                      const SizedBox(height: 22),
                    ],
                    AuthField(
                      controller: _name,
                      label: 'NAME',
                      textInputAction: TextInputAction.next,
                      autofillHints: const <String>[AutofillHints.name],
                    ),
                    const SizedBox(height: 18),
                    AuthField(
                      controller: _email,
                      label: 'EMAIL ADDRESS',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const <String>[AutofillHints.email],
                    ),
                    const SizedBox(height: 18),
                    AuthField(
                      controller: _password,
                      label: 'PASSWORD',
                      obscure: _obscure,
                      textInputAction: TextInputAction.done,
                      autofillHints: const <String>[AutofillHints.newPassword],
                      onToggleObscure: () =>
                          setState(() => _obscure = !_obscure),
                      onSubmitted: (_) {
                        if (auth.isConfigured) _create(auth);
                      },
                    ),
                    if (message != null) ...<Widget>[
                      const SizedBox(height: 14),
                      AuthErrorText(message: message),
                    ],
                    const SizedBox(height: 24),
                    AuthPrimaryButton(
                      label: 'CREATE ACCOUNT',
                      busy: auth.busy && _method == 'email',
                      enabled: auth.isConfigured && !auth.busy,
                      onPressed: auth.isConfigured ? () => _create(auth) : null,
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: <Widget>[
                        Text(
                          'Already have an account?',
                          style: t.bodySmall?.copyWith(fontSize: 12),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: () =>
                              Navigator.of(context).pushNamed('/login'),
                          child: const Text(
                            'Sign in here.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.black54,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => Navigator.of(context)
                            .pushReplacementNamed('/health'),
                        child: const Text(
                          'CONTINUE WITHOUT AN ACCOUNT',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
