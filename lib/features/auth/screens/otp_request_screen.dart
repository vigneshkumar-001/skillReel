import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_state_provider.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';

class OtpRequestScreen extends ConsumerStatefulWidget {
  const OtpRequestScreen({super.key});

  @override
  ConsumerState<OtpRequestScreen> createState() => _OtpRequestScreenState();
}

class _OtpRequestScreenState extends ConsumerState<OtpRequestScreen> {
  final _controller = TextEditingController();
  bool _loading = false;

  Future<void> _submit() async {
    final mobile = _controller.text.trim();
    if (mobile.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid mobile number')));
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(authActionProvider).requestOtp(mobile);
      if (mounted) context.push('/auth/verify', extra: mobile);
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 80),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.work_outline,
                    color: AppColors.primary, size: 32),
              ),
              const SizedBox(height: 28),
              const Text(
                'Find skilled\nprofessionals',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Enter your mobile number to get started',
                style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                decoration: const InputDecoration(
                  labelText: 'Mobile number',
                  prefixText: '+91  ',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 24),
              AppButton(
                label: 'Send OTP',
                isLoading: _loading,
                onTap: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
