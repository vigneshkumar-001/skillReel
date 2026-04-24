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
import '../providers/profile_provider.dart';

class _EditProfilePalette {
  // Match the warm premium system used in `profile_screen.dart`.
  static const bg = Color(0xFFF5EDE3);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceTint = Color(0xFFFCF8F2);
  static const border = Color(0xFFEAE2D7);

  static const accent = Color(0xFFF6A23A);
  static const accentSoft = Color(0xFFFFF1DF);
  static const cardShadow = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 30,
      offset: Offset(0, 12),
    ),
  ];
  static const softShadow = [
    BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 22,
      offset: Offset(0, 10),
    ),
  ];
}

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _displayName = TextEditingController();
  final _name = TextEditingController();
  final _headline = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _websiteUrl = TextEditingController();
  final _bio = TextEditingController();
  final _availability = TextEditingController();
  bool _loading = false;
  bool _prefilled = false;
  ProviderSubscription<AsyncValue<Map<String, dynamic>>>? _sub;
  String? _avatarUrl;
  Uint8List? _avatarBytes;
  String? _avatarFilename;

  void _prefillFromUser(Map<String, dynamic> user) {
    if (_prefilled) return;
    _prefilled = true;

    _displayName.text = (user['name'] ?? user['displayName'] ?? '').toString();
    _name.text =
        (user['userName'] ?? user['username'] ?? user['name'] ?? '').toString();
    _headline.text = (user['headline'] ?? '').toString();
    _mobile.text = (user['mobileNumber'] ??
            user['mobile'] ??
            user['phoneNumber'] ??
            user['phone'] ??
            user['contact'] ??
            '')
        .toString();
    _email.text = (user['email'] ?? '').toString();
    _websiteUrl.text = (user['websiteUrl'] ?? '').toString();
    _bio.text = (user['bio'] ?? '').toString();
    _availability.text =
        (user['availability'] ?? user['availabilityText'] ?? '').toString();
    _avatarUrl = (user['avatar'] ?? user['avatarUrl'] ?? '').toString();

    if (mounted) setState(() {});
  }

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

    // Ensure we prefill even when the provider already has a cached value
    // (listenManual may not fire immediately).
    final current = ref.read(myProfileProvider).valueOrNull;
    if (current != null) {
      _prefillFromUser(current);
    } else {
      unawaited(ref.read(myProfileProvider.future).then(_prefillFromUser));
    }
  }

  @override
  void dispose() {
    _sub?.close();
    _displayName.dispose();
    _name.dispose();
    _headline.dispose();
    _mobile.dispose();
    _email.dispose();
    _websiteUrl.dispose();
    _bio.dispose();
    _availability.dispose();
    super.dispose();
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
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 26,
                  offset: Offset(0, 14),
                ),
              ],
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
                          colors: [AppColors.accent, AppColors.secondary],
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
                  'Choose a new photo for your profile.',
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
                          side: const BorderSide(color: AppColors.border),
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
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_avatarBytes != null ||
                    (_avatarUrl ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      setState(() => _avatarBytes = null);
                    },
                    child: const Text('Remove new photo'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final displayNameTrim = _displayName.text.trim();
      final nameTrim = _name.text.trim();
      final payload = <String, dynamic>{
        'displayName': displayNameTrim.isNotEmpty ? displayNameTrim : nameTrim,
        'name': nameTrim.isNotEmpty ? nameTrim : displayNameTrim,
        'email': _email.text.trim(),
        'bio': _bio.text.trim(),
        'websiteUrl': _websiteUrl.text.trim(),
        'availability': _availability.text.trim(),
      };

      if (_avatarBytes != null && _avatarBytes!.isNotEmpty) {
        try {
          await ref.read(appRepoProvider).updateMyProfileWithAvatar(
                data: payload,
                avatarBytes: _avatarBytes!,
                filename: (_avatarFilename ?? 'avatar.jpg').trim().isEmpty
                    ? 'avatar.jpg'
                    : _avatarFilename!.trim(),
              );
        } catch (e) {
          // Fallback: save text fields even if avatar upload is not supported.
          await ref.read(appRepoProvider).updateMyProfile(payload);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text('Saved changes, but could not update profile photo.'),
              ),
            );
          }
        }
      } else {
        await ref.read(appRepoProvider).updateMyProfile(payload);
      }

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

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final name = _displayName.text.trim();
    final usernameRaw = _name.text.trim();
    final username = usernameRaw.isEmpty
        ? ''
        : (usernameRaw.startsWith('@') ? usernameRaw : '@$usernameRaw');

    const bg = _EditProfilePalette.bg;
    const card = _EditProfilePalette.surface;
    const fieldFill = _EditProfilePalette.surfaceTint;
    const border = _EditProfilePalette.border;

    return Scaffold(
      backgroundColor: bg,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 12 + (bottomPad * 0.2)),
          child: SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _loading ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _EditProfilePalette.accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    _EditProfilePalette.accent.withAlpha(120),
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFF4E4),
              Color(0xFFF6D9B4),
              _EditProfilePalette.bg,
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: SizedBox(
                      height: 56,
                      child: Stack(
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _TopIconButton(
                              icon: Icons.arrow_back_ios_new_rounded,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                context.pop();
                              },
                            ),
                          ),
                          const Align(
                            alignment: Alignment.center,
                            child: Text(
                              'Edit profile',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 20,
                                color: AppColors.textPrimary,
                                height: 1.0,
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: _TopIconButton(
                              icon: Icons.check_rounded,
                              onTap: _loading ? null : _save,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 18),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(210),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.white.withAlpha(120),
                              ),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  _EditProfilePalette.accentSoft.withAlpha(220),
                                  card.withAlpha(220),
                                  _EditProfilePalette.surfaceTint
                                      .withAlpha(215),
                                ],
                                stops: const [0.0, 0.55, 1.0],
                              ),
                              boxShadow: _EditProfilePalette.cardShadow,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                InkWell(
                                  onTap: _openAvatarPicker,
                                  borderRadius: BorderRadius.circular(22),
                                  child: Container(
                                    padding: const EdgeInsets.fromLTRB(
                                        14, 14, 14, 14),
                                    decoration: BoxDecoration(
                                      color: _EditProfilePalette.surfaceTint,
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(
                                        color: _EditProfilePalette.border,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Container(
                                              width: 64,
                                              height: 64,
                                              padding: const EdgeInsets.all(2),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                gradient: const LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    AppColors.primary,
                                                    _EditProfilePalette.accent,
                                                  ],
                                                ),
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                child: Container(
                                                  color: card,
                                                  child: _avatarWidget(),
                                                ),
                                              ),
                                            ),
                                            Positioned(
                                              right: -2,
                                              bottom: -2,
                                              child: Container(
                                                width: 28,
                                                height: 28,
                                                decoration: BoxDecoration(
                                                  color: AppColors.textPrimary
                                                      .withAlpha(240),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          999),
                                                  border: Border.all(
                                                    color: card,
                                                    width: 2,
                                                  ),
                                                ),
                                                child: const Icon(
                                                  Icons.camera_alt_rounded,
                                                  size: 15,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      name.isEmpty
                                                          ? 'Your name'
                                                          : name,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        fontSize: 16,
                                                        color: AppColors
                                                            .textPrimary,
                                                        height: 1.0,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: _EditProfilePalette
                                                          .accentSoft,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        999,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      username.isEmpty
                                                          ? 'Profile'
                                                          : username,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        color: AppColors
                                                            .textPrimary,
                                                        fontSize: 12,
                                                        height: 1.0,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Tap to change profile photo',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: AppColors.textSecondary
                                                      .withAlpha(220),
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const _EditSectionHeader(title: 'Basics'),
                                const SizedBox(height: 10),
                                _BoxField(
                                  label: 'Display name',
                                  hint: 'Your public name',
                                  controller: _displayName,
                                  fillColor: fieldFill,
                                  borderColor: border,
                                  focusColor: _EditProfilePalette.accent,
                                  textInputAction: TextInputAction.next,
                                ),
                                const SizedBox(height: 12),
                                _BoxField(
                                  label: 'Username',
                                  hint: '@username',
                                  controller: _name,
                                  fillColor: fieldFill,
                                  borderColor: border,
                                  focusColor: _EditProfilePalette.accent,
                                  textInputAction: TextInputAction.next,
                                ),
                                const SizedBox(height: 12),
                                _BoxField(
                                  label: 'Headline',
                                  hint: 'What do you do?',
                                  controller: _headline,
                                  fillColor: fieldFill,
                                  borderColor: border,
                                  focusColor: _EditProfilePalette.accent,
                                  textInputAction: TextInputAction.next,
                                ),
                                const SizedBox(height: 12),
                                _BoxField(
                                  label: 'Email',
                                  hint: 'name@email.com',
                                  controller: _email,
                                  fillColor: fieldFill,
                                  borderColor: border,
                                  focusColor: _EditProfilePalette.accent,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                ),
                                const SizedBox(height: 12),
                                _BoxField(
                                  label: 'Mobile number',
                                  hint: 'Your contact number',
                                  controller: _mobile,
                                  fillColor: fieldFill,
                                  borderColor: border,
                                  focusColor: _EditProfilePalette.accent,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                ),
                                const SizedBox(height: 12),
                                _BoxField(
                                  label: 'Website',
                                  hint: 'https://your-site.com',
                                  controller: _websiteUrl,
                                  fillColor: fieldFill,
                                  borderColor: border,
                                  focusColor: _EditProfilePalette.accent,
                                  keyboardType: TextInputType.url,
                                  textInputAction: TextInputAction.next,
                                ),
                                const SizedBox(height: 14),
                                const _EditSectionHeader(title: 'About you'),
                                const SizedBox(height: 10),
                                _BoxField(
                                  label: 'Bio',
                                  hint: 'Tell people what you do',
                                  controller: _bio,
                                  fillColor: fieldFill,
                                  borderColor: border,
                                  focusColor: _EditProfilePalette.accent,
                                  maxLines: 4,
                                  textInputAction: TextInputAction.newline,
                                ),
                                const SizedBox(height: 14),
                                const _EditSectionHeader(title: 'Availability'),
                                const SizedBox(height: 10),
                                _AvailabilityPickerField(
                                  label: 'Availability',
                                  hint: 'Choose your availability',
                                  controller: _availability,
                                  fillColor: fieldFill,
                                  borderColor: border,
                                  focusColor: _EditProfilePalette.accent,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _TopIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _EditProfilePalette.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: _EditProfilePalette.softShadow,
          ),
          child: Icon(
            icon,
            size: 20,
            color: onTap == null
                ? AppColors.textSecondary.withAlpha(120)
                : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _EditSectionHeader extends StatelessWidget {
  final String title;
  const _EditSectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _AvailabilityPickerField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final Color fillColor;
  final Color borderColor;
  final Color focusColor;

  const _AvailabilityPickerField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.fillColor,
    required this.borderColor,
    required this.focusColor,
  });

  static const List<String> _options = <String>[
    'Available now',
    'Weekdays (Mon–Fri), 10 AM–6 PM',
    'Weekends (Sat–Sun), 10 AM–6 PM',
    'Evenings (6 PM–10 PM)',
    'By appointment only',
    'Currently unavailable',
  ];

  Future<void> _openPicker(BuildContext context) async {
    HapticFeedback.selectionClick();
    final selected = controller.text.trim();
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              color: AppColors.surface,
              child: DraggableScrollableSheet(
                initialChildSize: 0.62,
                minChildSize: 0.42,
                maxChildSize: 0.88,
                expand: false,
                builder: (context, scrollController) {
                  return ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
                    children: [
                      const Text(
                        'Choose availability',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final quick in _options.take(4))
                            _AvailabilityChip(
                              label: quick,
                              selected: quick == selected,
                              onTap: () => Navigator.of(ctx).pop(quick),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      ..._options.map(
                        (o) => _AvailabilityOptionTile(
                          title: o,
                          selected: o == selected,
                          onTap: () => Navigator.of(ctx).pop(o),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(''),
                        child: const Text(
                          'Clear availability',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    if (result == null) return;
    controller.text = result;
  }

  @override
  Widget build(BuildContext context) {
    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: borderColor, width: 1),
    );

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, v, _) {
        final value = v.text.trim();
        final display = value.isEmpty ? hint : value;
        final color = value.isEmpty
            ? AppColors.textSecondary.withAlpha(160)
            : AppColors.textPrimary;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary.withAlpha(230),
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _openPicker(context),
                child: Ink(
                  decoration: ShapeDecoration(
                    color: fillColor,
                    shape: baseBorder,
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            display,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          Icons.expand_more_rounded,
                          color: AppColors.textSecondary.withAlpha(200),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AvailabilityChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _AvailabilityChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tint = _EditProfilePalette.accent;
    final bg = selected ? _EditProfilePalette.accentSoft : AppColors.surface;
    final border = selected ? tint.withAlpha(160) : AppColors.border;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _AvailabilityOptionTile extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;
  const _AvailabilityOptionTile({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          color: AppColors.textPrimary,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check_circle_rounded, color: AppColors.accent)
          : Icon(Icons.circle_outlined, color: AppColors.textSecondary.withAlpha(140)),
    );
  }
}

class _BoxField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final int maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Color fillColor;
  final Color borderColor;
  final Color focusColor;

  const _BoxField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.fillColor,
    required this.borderColor,
    required this.focusColor,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: borderColor, width: 1),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary.withAlpha(230),
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: AppColors.textSecondary.withAlpha(160),
              fontWeight: FontWeight.w700,
            ),
            filled: true,
            fillColor: fillColor,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: baseBorder,
            enabledBorder: baseBorder,
            focusedBorder: baseBorder.copyWith(
              borderSide: BorderSide(color: focusColor, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }
}
