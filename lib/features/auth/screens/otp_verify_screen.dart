import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_state_provider.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/widgets/app_button.dart';
import '../../chat/providers/chat_provider.dart';
import '../../notifications/providers/notification_provider.dart';
import '../../profile/providers/my_provider_photos_provider.dart';
import '../../profile/providers/my_provider_reels_provider.dart';
import '../../profile/providers/my_saved_reels_provider.dart';
import '../../profile/providers/profile_provider.dart';
import '../../reels/providers/reels_viewer_provider.dart';
import '../../search/providers/search_provider.dart';

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
      final model = await ref.read(authActionProvider).verifyOtp(
            widget.mobile,
            otp,
          );

      // Token/user changed - ensure we don't show previous-account cached data.
      SocketService.instance.disconnect();
      ref.invalidate(myProfileProvider);
      ref.invalidate(notificationsProvider);
      ref.invalidate(searchCategoriesProvider);
      ref.invalidate(threadsProvider);
      ref.invalidate(myProviderReelsProvider);
      ref.invalidate(myProviderPhotosProvider);
      ref.invalidate(mySavedReelsProvider);
      ref.invalidate(
        reelsViewerControllerProvider(const ReelsFeedConfig(type: 'trending')),
      );

      final needsSignup = (model.user.name ?? '').toString().trim().isEmpty;
      if (!mounted) return;
      context.go(needsSignup ? '/signup' : '/home');
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
