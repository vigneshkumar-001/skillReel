import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/url_utils.dart';
import '../../../core/widgets/app_button.dart';
import '../../profile/providers/profile_provider.dart';
import '../../providers_module/providers/provider_state_provider.dart';
import '../../skills/widgets/skill_picker_bottom_sheet.dart';

class _SignupPalette {
  static const bg = Color(0xFFF5EDE3);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceTint = Color(0xFFFCF8F2);
  static const border = Color(0xFFEAE2D7);
  static const accent = Color(0xFFF6A23A);
  static const accentSoft = Color(0xFFFFF1DF);
  static const softShadow = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 26,
      offset: Offset(0, 14),
    ),
  ];
}

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _city = TextEditingController();
  final _experienceYears = TextEditingController();

  Map<String, String> _skillsById = {};
  bool _loading = false;
  bool _prefilled = false;
  ProviderSubscription<AsyncValue<Map<String, dynamic>>>? _sub;

  Uint8List? _avatarBytes;
  String? _avatarFilename;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _sub = ref.listenManual<AsyncValue<Map<String, dynamic>>>(
      myProfileProvider,
      (_, next) {
        final user = next.valueOrNull;
        if (user == null) return;
        _prefillFromUser(user);
      },
    );

    final current = ref.read(myProfileProvider).valueOrNull;
    if (current != null) {
      _prefillFromUser(current);
    } else {
      unawaited(ref.read(myProfileProvider.future).then(_prefillFromUser));
    }
  }

  void _prefillFromUser(Map<String, dynamic> user) {
    if (_prefilled) return;
    _prefilled = true;
    _fullName.text = (user['name'] ?? '').toString();
    final loc = user['location'];
    if (loc is Map) _city.text = (loc['city'] ?? '').toString();
    _avatarUrl = (user['avatar'] ?? user['avatarUrl'] ?? '').toString();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sub?.close();
    _fullName.dispose();
    _city.dispose();
    _experienceYears.dispose();
    super.dispose();
  }

  int? _parseInt(String v) => int.tryParse(v.trim());

  String? _required(String? v) {
    if ((v ?? '').trim().isEmpty) return 'Required';
    return null;
  }

  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1024,
      );
      if (!mounted || file == null) return;
      HapticFeedback.selectionClick();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _avatarBytes = bytes;
        _avatarFilename = file.name.isEmpty ? 'avatar.jpg' : file.name;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
    }
  }

  Future<void> _openAvatarPicker() async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            decoration: BoxDecoration(
              color: _SignupPalette.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _SignupPalette.border),
              boxShadow: _SignupPalette.softShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_SignupPalette.accent, Color(0xFFEF7A2E)],
                        ),
                      ),
                      child: const Icon(Icons.camera_alt_rounded,
                          color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Profile photo',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close_rounded),
                      color: AppColors.textSecondary,
                      tooltip: 'Close',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Add a photo so providers can recognize you.',
                  style: TextStyle(
                    color: AppColors.textSecondary.withAlpha(230),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _pickAvatar(ImageSource.camera);
                        },
                        icon: const Icon(Icons.photo_camera_rounded),
                        label: const Text('Camera'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: BorderSide(
                            color: _SignupPalette.border.withAlpha(230),
                          ),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _pickAvatar(ImageSource.gallery);
                        },
                        icon: const Icon(Icons.photo_library_rounded),
                        label: const Text('Gallery'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: _SignupPalette.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatarWidget() {
    final bytes = _avatarBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(bytes, fit: BoxFit.cover);
    }

    final u = UrlUtils.normalizeMediaUrl((_avatarUrl ?? '').trim());
    if (u.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: u,
        fit: BoxFit.cover,
        placeholder: (_, __) => const DecoratedBox(
          decoration: BoxDecoration(color: Color(0x0F000000)),
        ),
        errorWidget: (_, __, ___) => const Icon(Icons.person_rounded),
      );
    }

    return const Icon(Icons.person_rounded);
  }

  Future<void> _pickSkills() async {
    HapticFeedback.selectionClick();
    final res = await SkillPickerBottomSheet.open(
      context,
      initialSelectedById: _skillsById,
    );
    if (!mounted || res == null) return;
    setState(() => _skillsById = res);
  }

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;
    if (_skillsById.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least 1 skill')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final name = _fullName.text.trim();
      final city = _city.text.trim();
      final experience = _parseInt(_experienceYears.text) ?? 0;

      final profilePayload = <String, dynamic>{
        'displayName': name,
        'name': name,
      };

      if (_avatarBytes != null && _avatarBytes!.isNotEmpty) {
        try {
          await ref.read(appRepoProvider).updateMyProfileWithAvatar(
                data: profilePayload,
                avatarBytes: _avatarBytes!,
                filename: (_avatarFilename ?? 'avatar.jpg').trim().isEmpty
                    ? 'avatar.jpg'
                    : _avatarFilename!.trim(),
              );
        } catch (_) {
          // Fallback: save text fields even if avatar upload is not supported.
          await ref.read(appRepoProvider).updateMyProfile(profilePayload);
        }
      } else {
        await ref.read(appRepoProvider).updateMyProfile(profilePayload);
      }

      // Create provider profile (skills required) with safe defaults.
      final providerPayload = <String, dynamic>{
        'displayName': name,
        'skills': _skillsById.keys.toList(growable: false),
        'experienceYears': experience,
        'bio': '',
        'location': {
          'city': city,
          'state': '',
          'country': 'IN',
          'lat': 0,
          'lng': 0,
        },
        'serviceRadiusKm': 25,
        'callEnabled': true,
        'chatOnlyMode': false,
      };

      try {
        await ref.read(providerActionProvider).becomeProvider(providerPayload);
      } catch (e) {
        final msg = apiErrorMessage(e).toLowerCase();
        final looksLikeAlreadyExists = msg.contains('already');
        if (!looksLikeAlreadyExists) rethrow;
        await ref
            .read(providerActionProvider)
            .updateMyProviderProfile(providerPayload);
      }

      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final skillsCount = _skillsById.length;

    return Scaffold(
      backgroundColor: _SignupPalette.bg,
      appBar: AppBar(
        backgroundColor: _SignupPalette.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Complete signup'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottomPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _SignupPalette.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _SignupPalette.border),
                  boxShadow: _SignupPalette.softShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [_SignupPalette.accent, Color(0xFFEF7A2E)],
                            ),
                          ),
                          child: const Icon(Icons.person_rounded,
                              color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Let’s set up your profile',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Name, city, and skills help you get better enquiries and chat faster.',
                      style: TextStyle(
                        color: AppColors.textSecondary.withAlpha(235),
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        InkWell(
                          onTap: _openAvatarPicker,
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: _SignupPalette.border),
                              color: _SignupPalette.surfaceTint,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Center(child: _avatarWidget()),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Profile photo (optional)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tap to add a photo',
                                style: TextStyle(
                                  color: AppColors.textSecondary.withAlpha(235),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.chevron_right_rounded,
                            color: AppColors.textSecondary.withAlpha(220)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _fullName,
                            textInputAction: TextInputAction.next,
                            validator: _required,
                            decoration: const InputDecoration(
                              labelText: 'Full name *',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _city,
                            textInputAction: TextInputAction.next,
                            validator: _required,
                            decoration: const InputDecoration(
                              labelText: 'City *',
                            ),
                          ),
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: _pickSkills,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 14),
                              decoration: BoxDecoration(
                                color: _SignupPalette.surfaceTint,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: _SignupPalette.border),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: _SignupPalette.accentSoft,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                          color:
                                              _SignupPalette.accent.withAlpha(40)),
                                    ),
                                    child: const Icon(
                                      Icons.handyman_rounded,
                                      color: AppColors.textPrimary,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Skills *',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          skillsCount == 0
                                              ? 'Select your services'
                                              : '$skillsCount selected',
                                          style: TextStyle(
                                            color: AppColors.textSecondary
                                                .withAlpha(235),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right_rounded,
                                      color:
                                          AppColors.textSecondary.withAlpha(220)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _experienceYears,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'Experience (years)',
                              hintText: 'Optional',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    decoration: BoxDecoration(
                      color: _SignupPalette.surface.withAlpha(235),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: _SignupPalette.border),
                    ),
                    child: AppButton(
                      label: 'Finish',
                      isLoading: _loading,
                      onTap: _submit,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
