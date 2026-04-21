import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../repositories/review_repository.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';

final _reviewRepoProvider = Provider((_) => ReviewRepository());

class ReviewScreen extends ConsumerStatefulWidget {
  final String providerId;
  const ReviewScreen({super.key, required this.providerId});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  int _rating = 5;
  final _ctrl = TextEditingController();
  bool _loading = false;

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      await ref.read(_reviewRepoProvider).createReview(
            widget.providerId,
            _rating,
            _ctrl.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Review submitted!')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leave a Review')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rating', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Row(
              children: List.generate(
                5,
                (i) => GestureDetector(
                  onTap: () => setState(() => _rating = i + 1),
                  child: Icon(
                    i < _rating ? Icons.star : Icons.star_border,
                    color: AppColors.star,
                    size: 36,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Comment',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            TextField(
              controller: _ctrl,
              maxLines: 4,
              decoration:
                  const InputDecoration(hintText: 'Share your experience...'),
            ),
            const SizedBox(height: 24),
            AppButton(
                label: 'Submit Review', isLoading: _loading, onTap: _submit),
          ],
        ),
      ),
    );
  }
}
