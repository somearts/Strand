import 'package:flutter/material.dart';

import '../../auth/auth_scope.dart';
import '../../auth/auth_service.dart';
import '../widgets/auth_form.dart';

/// Sign in to an existing account. Never asks for the name again.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.returnOnSuccess = false});

  /// When opened from Settings, a successful sign-in should close this screen
  /// and reveal the refreshed Settings page rather than restart onboarding.
  final bool returnOnSuccess;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;
  String? _validation;
  String? _method;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validate() {
    final String email = _email.text.trim();
    if (email.isEmpty || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    if (_password.text.isEmpty) return 'Enter your password.';
    return null;
  }

  Future<void> _signIn(StrandAuth auth) async {
    final String? problem = _validate();
    if (problem != null) {
      setState(() => _validation = problem);
      return;
    }
    setState(() {
      _validation = null;
      _method = 'email';
    });
    final bool ok = await auth.signIn(
      email: _email.text.trim(),
      password: _password.text,
    );
    if (!mounted) return;
    setState(() => _method = null);
    if (!ok) return;
    _done();
  }

  void _done() {
    if (widget.returnOnSuccess) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacementNamed('/health');
    }
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
                    const SizedBox(height: 40),
                    Text('Welcome back', style: t.headlineLarge),
                    const SizedBox(height: 10),
                    Text(
                      'Sign in and Strand will pick up where your nights left off.',
                      style: t.bodyMedium?.copyWith(height: 1.55),
                    ),
                    const SizedBox(height: 28),
                    if (!auth.isConfigured) ...<Widget>[
                      AuthNotice(
                        text: auth.configurationNote ??
                            'Sign-in is not configured in this build.',
                      ),
                      const SizedBox(height: 22),
                    ],
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
                      autofillHints: const <String>[AutofillHints.password],
                      onToggleObscure: () =>
                          setState(() => _obscure = !_obscure),
                      onSubmitted: (_) {
                        if (auth.isConfigured) _signIn(auth);
                      },
                    ),
                    if (message != null) ...<Widget>[
                      const SizedBox(height: 14),
                      AuthErrorText(message: message),
                    ],
                    const SizedBox(height: 24),
                    AuthPrimaryButton(
                      label: 'SIGN IN',
                      busy: auth.busy && _method == 'email',
                      enabled: auth.isConfigured && !auth.busy,
                      onPressed: auth.isConfigured ? () => _signIn(auth) : null,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: <Widget>[
                        Text(
                          'New to Strand?',
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
                              Navigator.of(context).pushNamed('/account'),
                          child: const Text(
                            'Create an account.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
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
