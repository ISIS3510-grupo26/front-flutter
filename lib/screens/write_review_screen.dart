import 'package:flutter/material.dart';

import '../models/spot_detail.dart';
import '../repositories/api_exception.dart';
import '../repositories/spots_repository.dart';
import '../theme/app_colors.dart';

/// Pantalla para escribir una reseña de un restaurante.
class WriteReviewScreen extends StatefulWidget {
  final String spotId;
  final String spotName;
  final SpotsRepository repository;

  const WriteReviewScreen({
    super.key,
    required this.spotId,
    required this.spotName,
    required this.repository,
  });

  @override
  State<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

class _WriteReviewScreenState extends State<WriteReviewScreen> {
  static const _maxLength = 500; // same limit as the backend
  static const _labels = ['', 'Bad', 'Meh', 'Good', 'Very good', 'Loved it'];

  final _text = TextEditingController();
  int _stars = 0;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (_stars == 0) return setState(() => _error = 'Pick a rating from 1 to 5 stars.');
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.repository.postReview(widget.spotId, _stars, _text.text.trim());
      if (!mounted) return;
      Navigator.pop(context, result);
    } on ApiException catch (e) {
      _fail(switch (e.statusCode) {
        409 => 'You already reviewed this place.',
        401 => 'Sign in with your account to leave a review.',
        404 => 'This place is no longer available.',
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
              Text(
                widget.spotName,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.espresso,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'How was it? Your rating helps other students choose.',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      onPressed: _submitting ? null : () => setState(() => _stars = i),
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
                onPressed: _submitting ? null : _publish,
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
                    : const Text('Publish review'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
