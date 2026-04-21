import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/profile_provider.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_button.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _bio = TextEditingController();
  bool _loading = false;
  bool _prefilled = false;
  ProviderSubscription<AsyncValue<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.listenManual<AsyncValue<Map<String, dynamic>>>(
      myProfileProvider,
      (_, next) {
        final user = next.valueOrNull;
        if (user == null || _prefilled) return;

        _prefilled = true;
        _name.text = (user['userName'] ?? user['name'] ?? '').toString();
        _email.text = (user['email'] ?? '').toString();
        _bio.text = (user['bio'] ?? '').toString();
      },
    );
  }

  @override
  void dispose() {
    _sub?.close();
    _name.dispose();
    _email.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      await ref.read(appRepoProvider).updateMyProfile({
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'bio': _bio.text.trim(),
      });
      ref.invalidate(myProfileProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _bio,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Bio'),
            ),
            const SizedBox(height: 28),
            AppButton(label: 'Save changes', isLoading: _loading, onTap: _save),
          ],
        ),
      ),
    );
  }
}
