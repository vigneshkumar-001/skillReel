import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/skill_model.dart';
import '../providers/skills_provider.dart';

class SkillPickerBottomSheet extends ConsumerStatefulWidget {
  final Map<String, String> initialSelectedById;

  const SkillPickerBottomSheet({
    super.key,
    required this.initialSelectedById,
  });

  static Future<Map<String, String>?> open(
    BuildContext context, {
    required Map<String, String> initialSelectedById,
  }) {
    return showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SkillPickerBottomSheet(
        initialSelectedById: initialSelectedById,
      ),
    );
  }

  @override
  ConsumerState<SkillPickerBottomSheet> createState() =>
      _SkillPickerBottomSheetState();
}

class _SkillPickerBottomSheetState
    extends ConsumerState<SkillPickerBottomSheet> {
  late final Map<String, String> _selectedById;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedById = Map<String, String>.from(widget.initialSelectedById);
    _search.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(SkillModel skill) {
    setState(() {
      if (_selectedById.containsKey(skill.id)) {
        _selectedById.remove(skill.id);
      } else {
        _selectedById[skill.id] = skill.name;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncSkills = ref.watch(skillsProvider);
    final query = _search.text.trim().toLowerCase();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        top: 6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              Text(
                'Select skills',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(_selectedById),
                child: const Text('Done'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search skills',
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: asyncSkills.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Failed to load skills',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      e.toString(),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: () => ref.invalidate(skillsProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (skills) {
                final filtered = query.isEmpty
                    ? skills
                    : skills.where((s) {
                        final name = s.name.toLowerCase();
                        final aliases = s.aliases.join(' ').toLowerCase();
                        return name.contains(query) || aliases.contains(query);
                      }).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('No skills found'));
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final skill = filtered[index];
                    final selected = _selectedById.containsKey(skill.id);
                    return ListTile(
                      onTap: () => _toggle(skill),
                      title: Text(skill.name),
                      subtitle: (skill.aliases.isEmpty)
                          ? null
                          : Text(
                              skill.aliases.take(3).join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: selected
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : const Icon(Icons.circle_outlined),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
