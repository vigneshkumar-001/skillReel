import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../repositories/enquiry_repository.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_button.dart';

final _enquiryRepoProvider = Provider((_) => EnquiryRepository());

class EnquiryFormScreen extends ConsumerStatefulWidget {
  final String providerId;
  const EnquiryFormScreen({super.key, required this.providerId});

  @override
  ConsumerState<EnquiryFormScreen> createState() => _EnquiryFormScreenState();
}

class _EnquiryFormScreenState extends ConsumerState<EnquiryFormScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;

  Future<void> _submit() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await ref.read(_enquiryRepoProvider).createEnquiry(
            widget.providerId,
            _ctrl.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Enquiry sent!')));
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
      appBar: AppBar(title: const Text('Send Enquiry')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text('Describe your requirement'),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'I need a photographer for...',
              ),
            ),
            const SizedBox(height: 24),
            AppButton(
                label: 'Send Enquiry', isLoading: _loading, onTap: _submit),
          ],
        ),
      ),
    );
  }
}
