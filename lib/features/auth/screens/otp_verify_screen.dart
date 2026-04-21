import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_state_provider.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_button.dart';

class OtpVerifyScreen extends ConsumerStatefulWidget {
  final String mobile;
  const OtpVerifyScreen({super.key, required this.mobile});

  @override
  ConsumerState<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends ConsumerState<OtpVerifyScreen> {
  final _controller = TextEditingController();
  bool _loading = false;

  Future<void> _verify() async {
    final otp = _controller.text.trim();
    if (otp.length != 6) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter 6-digit OTP')));
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(authActionProvider).verifyOtp(widget.mobile, otp);
      if (mounted) context.go('/home');
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
      appBar: AppBar(title: const Text('Verify OTP')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            Text(
              'OTP sent to +91 ${widget.mobile}',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use 123456 for testing',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Enter OTP',
                counterText: '',
              ),
            ),
            const SizedBox(height: 24),
            AppButton(
              label: 'Verify & Login',
              isLoading: _loading,
              onTap: _verify,
            ),
          ],
        ),
      ),
    );
  }
}
