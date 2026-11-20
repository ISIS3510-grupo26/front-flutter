import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../repositories/api_exception.dart';
import '../services/auth_session.dart';
import '../services/password_rules.dart';
import '../theme/app_colors.dart';

class LoginScreen extends StatefulWidget {
  static const offlineMessage = "You're offline. Connect to sign in.";
  static const serverMessage = 'CampusBites is having trouble. Try again in a moment.';

  final AuthSession session;

  /// `Connectivity().onConnectivityChanged`: when the connection comes back,
  /// the offline error goes away on its own. Tests pass their own stream.
  final Stream<List<ConnectivityResult>>? connectivity;

  const LoginScreen({super.key, required this.session, this.connectivity});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  bool _creatingAccount = false;
  bool _submitting = false;

  /// The only place this screen shows an error: inline, under the fields.
  String? _error;

  /// True while [_error] is the offline one, so only that one is cleared
  /// when the connection comes back.
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _connectivity = widget.connectivity?.listen(_onConnectivityChanged);
    // A snackbar left by the screen before signing out would show over this
    // one; errors here are inline only.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    });
  }

  @override
  void dispose() {
    _connectivity?.cancel();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online && _offline) _setError(null);
  }

  String? _validate(String email, String password) {
    if (!email.contains('@')) return 'Enter a valid email address.';
    if (_creatingAccount) {
      if (passwordProblem(password) case final problem?) return problem;
    }
    if (password.isEmpty) return 'Enter your password.';
    return null;
  }

  Future<void> _submit() async {
    // The button is disabled while submitting, but Enter on the keyboard or
    // two taps in the same frame can still get here: only one request.
    if (_submitting) return;
    final email = _email.text.trim();
    final password = _password.text;
    if (_validate(email, password) case final invalid?) return _setError(invalid);

    setState(() {
      _submitting = true;
      _error = null;
      _offline = false;
    });
    try {
      await (_creatingAccount
          ? widget.session.signUp(email, password)
          : widget.session.logIn(email, password));
      // Signed in: main.dart replaces this screen, so _submitting stays true.
    } on ApiException catch (e) {
      _setError(switch (e.statusCode) {
        409 => 'That email is already in use. Try signing in instead.',
        401 => 'Incorrect email or password.',
        422 => 'Enter a valid email and a password of 8 to 128 characters.',
        _ => LoginScreen.serverMessage,
      });
    } on Exception catch (e) {
      if (isNetworkError(e)) {
        _setError(LoginScreen.offlineMessage, offline: true);
      } else {
        // A response the app couldn't read: the server's side, not the phone's.
        _setError(LoginScreen.serverMessage);
      }
    }
  }

  void _setError(String? message, {bool offline = false}) {
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = message;
      _offline = offline;
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
                      helper: _creatingAccount ? '8 to 128 characters' : null,
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
                        : () {
                            setState(() => _creatingAccount = !_creatingAccount);
                            _setError(null);
                          },
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
