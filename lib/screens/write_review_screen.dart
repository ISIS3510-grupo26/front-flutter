import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../repositories/api_exception.dart';
import '../services/hive_store.dart';
import '../services/review_submitter.dart';
import '../theme/app_colors.dart';
import '../widgets/offline_banner.dart';

/// Pantalla para escribir una reseña de un restaurante.  what the student writes is saved as a draft on the 
/// phone (Hive) while they type, so it survives losing the signal, a failed send or the app closing. 
/// Without connection the Publish button waits and turns back on by itself when the connection returns. 
/// Nothing is ever shown as published until the backend answers 201.
class WriteReviewScreen extends StatefulWidget {
  final String spotId;
  final String spotName;
  final ReviewSubmitter submitter;

  /// Tests pass their own; the app uses the real one.
  final Connectivity? connectivity;

  const WriteReviewScreen({
    super.key,
    required this.spotId,
    required this.spotName,
    required this.submitter,
    this.connectivity,
  });

  @override
  State<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

class _WriteReviewScreenState extends State<WriteReviewScreen> {
  static const _maxLength = 500; // same limit as the backend
  static const _labels = ['', 'Bad', 'Meh', 'Good', 'Very good', 'Loved it'];

  /// The draft is saved this long after the last key, not on every key.
  static const _saveDelay = Duration(milliseconds: 500);

  late final TextEditingController _text;
  late int _stars;
  late final DateTime? _restoredFrom;
  bool _submitting = false;
  bool _published = false;
  bool _online = true;
  String? _error;
  Timer? _saveTimer;
  late final StreamSubscription<List<ConnectivityResult>> _connectionChanges;

  HiveStore get _store => widget.submitter.store;

  @override
  void initState() {
    super.initState();
    // Hive already has the box in memory, so this read doesn't need await.
    final draft = _store.draft(widget.spotId);
    _stars = draft?.stars ?? 0;
    _text = TextEditingController(text: draft?.text ?? '')..addListener(_saveSoon);
    _restoredFrom = draft?.savedAt;

    final connectivity = widget.connectivity ?? Connectivity();
    _connectionChanges = connectivity.onConnectivityChanged.listen(_onConnectivity);
    connectivity.checkConnectivity().then(_onConnectivity);
  }

  @override
  void dispose() {
    // If the student leaves before the timer fires, the last words are saved now.
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _saveDraft();
    }
    _connectionChanges.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onConnectivity(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (!mounted || online == _online) return;
    setState(() {
      _online = online;
      if (online) _error = null;
    });
  }

  /// Debounce: every key restarts the timer, so while typing nothing is  written and the draft is saved once when the student pauses.
  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, _saveDraft);
  }

  Future<void> _saveDraft() async {
    if (_published) return; // the submitter already deleted it
    await _store.saveDraft(
      widget.spotId,
      ReviewDraft(stars: _stars, text: _text.text, savedAt: DateTime.now()),
    );
  }

  void _pickStars(int stars) {
    setState(() => _stars = stars);
    _saveTimer?.cancel();
    _saveDraft();
  }

  Future<void> _publish() async {
    if (_stars == 0) return setState(() => _error = 'Pick a rating from 1 to 5 stars.');
    setState(() {
      _submitting = true;
      _error = null;
    });
    // The draft is up to date before sending, in case the app closes mid-request.
    _saveTimer?.cancel();
    await _saveDraft();
    try {
      final result = await widget.submitter.submit(widget.spotId, _stars, _text.text.trim());
      _published = true;
      if (!mounted) return;
      Navigator.pop(context, result);
    } on ApiException catch (e) {
      _fail(switch (e.statusCode) {
        409 => 'You already reviewed this place.',
        401 => 'Sign in with your account to leave a review.',
        404 => 'This place is no longer available.',
        _ => 'Something went wrong on our side. Your draft is saved, try again.',
      });
    } on Exception {
      _fail("We couldn't publish it. Your review is saved on this phone, try again when you have signal.");
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
    final canPublish = !_submitting && _online;
    final restoredFrom = _restoredFrom;
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.espresso,
        elevation: 0,
        title: const Text(
          'Write a review',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_online) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: OfflineBanner(message: "You're offline · your review stays saved here"),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                widget.spotName,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.espresso,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                restoredFrom != null
                    ? 'We kept the draft you started at ${hourMinute(restoredFrom)}.'
                    : 'How was it? Your rating helps other students choose.',
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      onPressed: _submitting ? null : () => _pickStars(i),
                      iconSize: 40,
                      tooltip: '$i star${i == 1 ? '' : 's'}',
                      icon: Icon(
                        i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: AppColors.tomato,
                      ),
                    ),
                ],
              ),
              Center(
                child: Text(
                  _labels[_stars],
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.espresso,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _text,
                enabled: !_submitting,
                maxLines: 5,
                maxLength: _maxLength,
                decoration: InputDecoration(
                  hintText: 'What did you order? Was it worth it? (optional)',
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.tomato, width: 1.5),
                  ),
                ),
              ),
              if (_error case final error?) ...[
                const SizedBox(height: 8),
                Text(error, style: const TextStyle(color: AppColors.tomato, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: canPublish ? _publish : null,
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
                    : Text(_online ? 'Publish review' : 'Waiting for connection…'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
