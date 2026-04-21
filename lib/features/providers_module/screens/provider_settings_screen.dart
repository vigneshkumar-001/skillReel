import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geocoding/geocoding.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/services/location_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../skills/widgets/skill_picker_bottom_sheet.dart';
import '../providers/provider_state_provider.dart';

enum ProviderSettingsMode { create, edit }

class ProviderSettingsScreen extends ConsumerStatefulWidget {
  final ProviderSettingsMode mode;
  const ProviderSettingsScreen({super.key, ProviderSettingsMode? mode})
      : mode = mode ?? ProviderSettingsMode.edit;

  @override
  ConsumerState<ProviderSettingsScreen> createState() =>
      _ProviderSettingsScreenState();
}

class _ProviderSettingsScreenState
    extends ConsumerState<ProviderSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _bio = TextEditingController();
  final _experienceYears = TextEditingController();
  final _serviceRadiusKm = TextEditingController(text: '25');
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _country = TextEditingController(text: 'IN');
  final _lat = TextEditingController();
  final _lng = TextEditingController();

  Map<String, String> _skillsById = {};

  bool _callEnabled = true;
  bool _chatOnlyMode = false;

  bool _loading = false;
  bool _submitted = false;

  @override
  void dispose() {
    _displayName.dispose();
    _bio.dispose();
    _experienceYears.dispose();
    _serviceRadiusKm.dispose();
    _city.dispose();
    _state.dispose();
    _country.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  int? _parseInt(String v) => int.tryParse(v.trim());
  double? _parseDouble(String v) => double.tryParse(v.trim());

  bool get _canSave {
    if (_loading) return false;
    if (_skillsById.isEmpty) return false;
    return true;
  }

  String? _requiredText(String? v) {
    if ((v ?? '').trim().isEmpty) return 'Required';
    return null;
  }

  String? _requiredNonNegativeInt(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Required';
    final n = int.tryParse(t);
    if (n == null) return 'Enter a number';
    if (n < 0) return 'Must be 0 or more';
    return null;
  }

  String? _requiredPositiveInt(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Required';
    final n = int.tryParse(t);
    if (n == null) return 'Enter a number';
    if (n <= 0) return 'Must be greater than 0';
    return null;
  }

  String? _requiredDouble(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Required';
    final n = double.tryParse(t);
    if (n == null) return 'Enter a number';
    return null;
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

  Future<void> _useCurrentLocation() async {
    HapticFeedback.selectionClick();
    final res = await LocationService.instance.getCurrentPosition();
    if (!mounted) return;

    if (!res.isSuccess) {
      final msg = switch (res.failure!) {
        LocationFailure.serviceDisabled => 'Enable location services',
        LocationFailure.permissionDenied => 'Location permission denied',
        LocationFailure.permissionDeniedForever =>
          'Location permission permanently denied',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    final p = res.position!;
    setState(() {
      _lat.text = p.latitude.toStringAsFixed(6);
      _lng.text = p.longitude.toStringAsFixed(6);
    });

    try {
      final list = await placemarkFromCoordinates(p.latitude, p.longitude);
      if (!mounted || list.isEmpty) return;
      final place = list.first;

      final bestCity = _firstNonEmpty([
        place.locality,
        place.subAdministrativeArea,
        place.subLocality,
        place.name,
      ]);
      final bestState = _firstNonEmpty([
        place.administrativeArea,
        place.subAdministrativeArea,
      ]);
      final bestCountry = _firstNonEmpty([
        place.isoCountryCode,
        place.country,
      ]);

      setState(() {
        if (_city.text.trim().isEmpty && bestCity.isNotEmpty) {
          _city.text = bestCity;
        }
        if (_state.text.trim().isEmpty && bestState.isNotEmpty) {
          _state.text = bestState;
        }
        if (_country.text.trim().isEmpty && bestCountry.isNotEmpty) {
          _country.text = bestCountry;
        }
      });
    } catch (_) {
      // Ignore reverse-geocode failures.
    }
  }

  void _setCallEnabled(bool v) {
    HapticFeedback.selectionClick();
    setState(() {
      _callEnabled = v;
      if (v) _chatOnlyMode = false;
    });
  }

  void _setChatOnlyMode(bool v) {
    HapticFeedback.selectionClick();
    setState(() {
      _chatOnlyMode = v;
      if (v) _callEnabled = false;
    });
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid || !_canSave) return;

    setState(() => _loading = true);
    try {
      final experience = _parseInt(_experienceYears.text) ?? 0;
      final radius = _parseInt(_serviceRadiusKm.text) ?? 25;
      final lat = _parseDouble(_lat.text) ?? 0;
      final lng = _parseDouble(_lng.text) ?? 0;

      final payload = <String, dynamic>{
        'displayName': _displayName.text.trim(),
        'skills': _skillsById.keys.toList(growable: false),
        'experienceYears': experience,
        'bio': _bio.text.trim(),
        'location': {
          'city': _city.text.trim(),
          'state': _state.text.trim(),
          'country': _country.text.trim(),
          'lat': lat,
          'lng': lng,
        },
        'serviceRadiusKm': radius,
        'callEnabled': _callEnabled,
        'chatOnlyMode': _chatOnlyMode,
      };

      if (widget.mode == ProviderSettingsMode.create) {
        try {
          await ref.read(providerActionProvider).becomeProvider(payload);
        } on DioException catch (e) {
          final msg = apiErrorMessage(e).toLowerCase();
          final code = e.response?.statusCode;
          final looksLikeAlreadyExists = code == 409 || msg.contains('already');
          if (looksLikeAlreadyExists && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Provider profile already exists')),
            );
            context.go('/provider/settings');
            return;
          }
          rethrow;
        }
      } else {
        try {
          await ref
              .read(providerActionProvider)
              .updateMyProviderProfile(payload);
        } on DioException catch (e) {
          final code = e.response?.statusCode;
          if (code == 404 && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Provider profile not found. Create one first.'),
              ),
            );
            context.go('/provider/become');
            return;
          }
          rethrow;
        }
      }

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved')),
      );
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
    final theme = Theme.of(context);
    final title = widget.mode == ProviderSettingsMode.create
        ? 'Become a Provider'
        : 'Provider settings';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Form(
        key: _formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _displayName,
              textInputAction: TextInputAction.next,
              validator: _requiredText,
              decoration: const InputDecoration(labelText: 'Display name *'),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _skillsById.isEmpty
                        ? (_submitted ? 'Select at least 1 skill' : 'Skills *')
                        : 'Skills (${_skillsById.length})',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: (_submitted && _skillsById.isEmpty)
                          ? AppColors.error
                          : null,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _pickSkills,
                  child: Text(_skillsById.isEmpty ? 'Select' : 'Edit'),
                ),
              ],
            ),
            if (_skillsById.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _skillsById.entries
                    .map((e) => e.value.isNotEmpty ? e.value : e.key)
                    .join(', '),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _experienceYears,
                    keyboardType: TextInputType.number,
                    validator: _requiredNonNegativeInt,
                    decoration: const InputDecoration(
                      labelText: 'Experience (years) *',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _serviceRadiusKm,
                    keyboardType: TextInputType.number,
                    validator: _requiredPositiveInt,
                    decoration: const InputDecoration(
                      labelText: 'Service radius (km) *',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _bio,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Bio'),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _city,
              validator: _requiredText,
              decoration: const InputDecoration(labelText: 'City *'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _state,
              validator: _requiredText,
              decoration: const InputDecoration(labelText: 'State *'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _country,
              validator: _requiredText,
              decoration: const InputDecoration(labelText: 'Country *'),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _lat,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                    validator: _requiredDouble,
                    decoration: const InputDecoration(labelText: 'Latitude *'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lng,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                    validator: _requiredDouble,
                    decoration: const InputDecoration(labelText: 'Longitude *'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _useCurrentLocation,
                icon: const Icon(Icons.my_location_rounded),
                label: const Text('Use current location'),
              ),
            ),
            const SizedBox(height: 18),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _callEnabled,
              onChanged: _chatOnlyMode ? null : _setCallEnabled,
              title: const Text('Call enabled'),
              activeThumbColor: AppColors.primary,
              activeTrackColor: AppColors.primary.withAlpha(60),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _chatOnlyMode,
              onChanged: _setChatOnlyMode,
              title: const Text('Chat only mode'),
              activeThumbColor: AppColors.primary,
              activeTrackColor: AppColors.primary.withAlpha(60),
            ),
            const SizedBox(height: 20),
            AppButton(
              label: 'Save',
              isLoading: _loading,
              onTap: _canSave ? _save : null,
            ),
          ],
        ),
      ),
    );
  }
}

String _firstNonEmpty(List<String?> values) {
  for (final v in values) {
    final t = (v ?? '').trim();
    if (t.isNotEmpty) return t;
  }
  return '';
}
