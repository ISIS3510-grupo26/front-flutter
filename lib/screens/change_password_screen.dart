import 'dart:convert';

import 'package:flutter/material.dart';

import '../repositories/api_exception.dart';
import '../services/auth_session.dart';
import '../theme/app_colors.dart';

class ChangePasswordScreen extends StatefulWidget {
  final AuthSession session;

  const ChangePasswordScreen({super.key, required this.session});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// Valida los campos de contraseña. Devuelve un mensaje de error si hay un problema, o null si todo está bien.
  String? _validate(String current, String next, String confirm) {
    if (current.isEmpty) return 'Enter your current password.';
    final bytes = utf8.encode(next).length;
    if (bytes < 8 || bytes > 72) return 'Use a new password between 8 and 72 characters.';
    if (next != confirm) return "The new passwords don't match.";
    if (next == current) return 'The new password must be different from the current one.';
    return null;
  }

  Future<void> _submit() async {
    final invalid = _validate(_current.text, _new.text, _confirm.text);
    if (invalid != null) return setState(() => _error = invalid);

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.session.changePassword(_current.text, _new.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated. Other devices were signed out.')),
      );
      Navigator.pop(context);
    } on ApiException catch (e) {
      _fail(switch (e.statusCode) {
        400 => 'Your current password is incorrect.',
        401 => 'Your session expired. Sign in again.',
        422 => 'Use a new password between 8 and 72 characters.',
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
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.espresso,
        elevation: 0,
        title: const Text(
          'Change password',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "You'll stay signed in here. Any other device using your account will be signed out.",
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _current,
                  enabled: !_submitting,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.next,
                  decoration: _fieldDecoration('Current password'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _new,
                  enabled: !_submitting,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  decoration: _fieldDecoration('New password', helper: 'At least 8 characters'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  enabled: !_submitting,
                  obscureText: true,
                  onSubmitted: (_) => _submit(),
                  decoration: _fieldDecoration('Confirm new password'),
                ),
                if (_error case final error?) ...[
                  const SizedBox(height: 12),
                  Text(error, style: const TextStyle(color: AppColors.tomato, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.tomato,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _submitting
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Update password'),
                ),
              ],
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
