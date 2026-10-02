import 'dart:convert';

import 'package:flutter/material.dart';

import '../repositories/api_exception.dart';
import '../services/auth_session.dart';
import '../theme/app_colors.dart';

class LoginScreen extends StatefulWidget {
  final AuthSession session;

  const LoginScreen({super.key, required this.session});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creatingAccount = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validate(String email, String password) {
    if (!email.contains('@')) return 'Enter a valid email address.';
    final bytes = utf8.encode(password).length;
    if (_creatingAccount && (bytes < 8 || bytes > 72)) {
      return 'Use a password between 8 and 72 characters.';
    }
    if (password.isEmpty) return 'Enter your password.';
    return null;
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    final invalid = _validate(email, password);
    if (invalid != null) return setState(() => _error = invalid);

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await (_creatingAccount
          ? widget.session.signUp(email, password)
          : widget.session.logIn(email, password));
    } on ApiException catch (e) {
      _fail(switch (e.statusCode) {
        409 => 'That email is already in use. Try signing in instead.',
        401 => 'Incorrect email or password.',
        422 => 'Enter a valid email and a password of 8 to 72 characters.',
        _ => 'Something went wrong on our side. Try again.',
      });
    } on Exception {
      _fail("Couldn't reach CampusBites. Check your connection and try again.");
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'CampusBites',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppColors.tomato,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _creatingAccount ? 'Create your account' : 'Welcome back',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.espresso,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Save your favorite spots and find what is open nearby.',
                    style: TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _email,
                    enabled: !_submitting,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: _fieldDecoration('Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    enabled: !_submitting,
                    obscureText: true,
                    autofillHints: [
                      _creatingAccount
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    onSubmitted: (_) => _submit(),
                    decoration: _fieldDecoration(
                      'Password',
                      helper: _creatingAccount ? 'At least 8 characters' : null,
                    ),
                  ),
                  if (_error case final error?) ...[
                    const SizedBox(height: 12),
                    Text(
                      error,
                      style: const TextStyle(color: AppColors.tomato, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.tomato,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_creatingAccount ? 'Create account' : 'Sign in'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                              _creatingAccount = !_creatingAccount;
                              _error = null;
                            }),
                    child: Text(
                      _creatingAccount
                          ? 'Already have an account? Sign in'
                          : "New here? Create an account",
                    ),
                  ),
                  if (widget.session.canUseDevUser)
                    TextButton(
                      onPressed:
                          _submitting ? null : widget.session.continueAsDevUser,
                      child: const Text(
                        'Continue as dev user (DEV_USER_ID)',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String label, {String? helper}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.border),
    );
    return InputDecoration(
      labelText: label,
      helperText: helper,
      filled: true,
      fillColor: AppColors.card,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.tomato, width: 1.5),
      ),
    );
  }
}
