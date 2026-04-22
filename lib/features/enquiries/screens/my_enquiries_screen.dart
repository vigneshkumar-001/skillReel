import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../repositories/enquiry_repository.dart';

class MyEnquiriesScreen extends StatefulWidget {
  const MyEnquiriesScreen({super.key});

  @override
  State<MyEnquiriesScreen> createState() => _MyEnquiriesScreenState();
}

class _MyEnquiriesScreenState extends State<MyEnquiriesScreen> {
  final _repo = EnquiryRepository();
  List<dynamic> _enquiries = [];
  bool _loading = true;
  Object? _error;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final e = await _repo.getMyEnquiries();
      if (mounted) setState(() => _enquiries = e);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final useFallbackData = _error != null && _enquiries.isEmpty;
    final listRaw = useFallbackData ? _demoEnquiries : _enquiries;
    final list = _applyStatusFilter(listRaw, _statusFilter);

    return LayoutBuilder(
      builder: (context, constraints) {
        const hPad = 16.0;

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: RefreshIndicator(
            onRefresh: _load,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 170,
                  backgroundColor: AppColors.bg,
                  surfaceTintColor: AppColors.bg,
                  foregroundColor: AppColors.textPrimary,
                  iconTheme: const IconThemeData(color: AppColors.textPrimary),
                  scrolledUnderElevation: 0,
                  systemOverlayStyle: SystemUiOverlayStyle.dark,
                  titleSpacing: hPad,
                  title: const Text(
                    'My enquiries',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    background: CustomPaint(
                      painter: _EnquiryHeaderPainter(),
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(hPad, 58, hPad, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Track requests',
                                      style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      'Status updates in one clean timeline',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(hPad, 10, hPad, 10),
                    child: _StatusFilters(
                      selected: _statusFilter,
                      onChanged: (v) => setState(() => _statusFilter = v),
                      counts: _statusCounts(listRaw),
                    ),
                  ),
                ),
                if (_loading && !useFallbackData)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (!useFallbackData && _enquiries.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Container(
                        margin: EdgeInsets.fromLTRB(hPad, 16, hPad, 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox_outlined,
                                color: AppColors.textSecondary),
                            SizedBox(width: 12),
                            Text(
                              'No enquiries yet',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (list.isEmpty) {
                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.filter_alt_off_rounded,
                                      color: AppColors.textSecondary),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'No enquiries yet',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          final e = list[index];
                          final status = (e['status'] ?? 'new').toString();
                          final card = _EnquiryCard(
                            message:
                                (e['message'] ?? e['title'] ?? '').toString(),
                            status: status,
                            createdAt: (e['createdAt'] ?? e['created'] ?? '')
                                .toString(),
                            providerName: (e['providerName'] ??
                                    e['provider'] ??
                                    'Provider')
                                .toString(),
                          );

                          return Padding(
                            padding: EdgeInsets.only(
                                bottom: index == list.length - 1 ? 0 : 14),
                            child: card,
                          );
                        },
                        childCount: list.isEmpty ? 1 : list.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

List<dynamic> _applyStatusFilter(List<dynamic> list, String key) {
  final k = key.trim().toLowerCase();
  if (k.isEmpty || k == 'all') return list;
  String norm(String? s) {
    final v = (s ?? '').trim().toLowerCase();
    if (v == 'in_progress') return 'in progress';
    if (v == 'inprogress') return 'in progress';
    return v;
  }

  return list.where((e) {
    if (e is! Map) return true;
    final status = norm(e['status']?.toString());
    return status == k;
  }).toList(growable: false);
}

Map<String, int> _statusCounts(List<dynamic> list) {
  final out = <String, int>{
    'all': list.length,
    'new': 0,
    'confirmed': 0,
    'in progress': 0,
    'closed': 0,
  };
  String norm(String? s) {
    final v = (s ?? '').trim().toLowerCase();
    if (v == 'in_progress') return 'in progress';
    if (v == 'inprogress') return 'in progress';
    return v;
  }

  for (final e in list) {
    if (e is! Map) continue;
    final status = norm(e['status']?.toString());
    if (out.containsKey(status)) out[status] = (out[status] ?? 0) + 1;
  }
  return out;
}

class _StatusFilters extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  final Map<String, int> counts;

  const _StatusFilters({
    required this.selected,
    required this.onChanged,
    required this.counts,
  });

  @override
  Widget build(BuildContext context) {
    final items = const <String>[
      'all',
      'new',
      'confirmed',
      'in progress',
      'closed',
    ];

    String labelOf(String key) {
      switch (key) {
        case 'all':
          return 'All';
        case 'in progress':
          return 'In progress';
        default:
          return key[0].toUpperCase() + key.substring(1);
      }
    }

    final sel = selected.trim().toLowerCase();
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, i) {
          final k = items[i];
          final isSelected = sel == k;
          final n = counts[k] ?? 0;
          return _FilterPill(
            label: '${labelOf(k)}${k == 'all' ? '' : ' ($n)'}',
            selected: isSelected,
            onTap: () => onChanged(k),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: items.length,
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.textPrimary;
    return Material(
      color: selected ? AppColors.textPrimary : AppColors.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? Colors.transparent : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _EnquiryHeaderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = AppColors.bg;
    canvas.drawRect(Offset.zero & size, bg);

    void blob({
      required Offset center,
      required double radius,
      required Color a,
      required Color b,
    }) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final shader = RadialGradient(
        colors: [a, b],
        stops: const [0.0, 1.0],
      ).createShader(rect);
      final p = Paint()..shader = shader;
      canvas.drawCircle(center, radius, p);
    }

    blob(
      center: Offset(size.width * 0.15, size.height * 0.30),
      radius: size.width * 0.45,
      a: AppColors.primary.withAlpha(34),
      b: AppColors.primary.withAlpha(0),
    );
    blob(
      center: Offset(size.width * 0.90, size.height * 0.15),
      radius: size.width * 0.40,
      a: AppColors.secondary.withAlpha(28),
      b: AppColors.secondary.withAlpha(0),
    );
    blob(
      center: Offset(size.width * 0.72, size.height * 0.72),
      radius: size.width * 0.34,
      a: const Color(0xFF3B82F6).withAlpha(22),
      b: const Color(0xFF3B82F6).withAlpha(0),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EnquiryCard extends StatelessWidget {
  final String message;
  final String status;
  final String createdAt;
  final String providerName;

  const _EnquiryCard({
    required this.message,
    required this.status,
    required this.createdAt,
    required this.providerName,
  });

  Color get _statusColor {
    final s = status.trim().toLowerCase();
    if (s.contains('accept') || s.contains('approved'))
      return AppColors.secondary;
    if (s.contains('reject') || s.contains('declin') || s.contains('cancel')) {
      return AppColors.error;
    }
    if (s.contains('close') || s.contains('done') || s.contains('resolve')) {
      return const Color(0xFF3B82F6);
    }
    if (s.contains('progress') || s.contains('working')) {
      return const Color(0xFF06B6D4);
    }
    return const Color(0xFFF59E0B);
  }

  String get _statusLabel {
    final s = status.trim().toLowerCase();
    if (s.contains('accept') || s.contains('approved')) return 'Confirmed';
    if (s.contains('reject') || s.contains('declin') || s.contains('cancel')) {
      return 'Declined';
    }
    if (s.contains('close') || s.contains('done') || s.contains('resolve')) {
      return 'Closed';
    }
    if (s.contains('progress') || s.contains('working')) {
      return 'In progress';
    }
    return 'New';
  }

  String get _when {
    final dt = DateTime.tryParse(createdAt);
    if (dt == null) return '';
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$y \u2022 $hh:$mm';
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'PR';
    final a = parts.first.trim();
    final b = parts.length >= 2 ? parts[1].trim() : '';
    final first = a.isEmpty ? 'P' : a[0];
    final second = b.isNotEmpty ? b[0] : (a.length >= 2 ? a[1] : 'R');
    return (first + second).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final provider =
        providerName.trim().isEmpty ? 'Provider' : providerName.trim();
    final c = _statusColor;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(14),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      c.withAlpha(190),
                      AppColors.primary.withAlpha(160)
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Center(
                          child: Text(
                            _initials(provider),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              provider,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                            if (_when.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                _when,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: c.withAlpha(18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: c.withAlpha(45)),
                        ),
                        child: Text(
                          _statusLabel,
                          style: TextStyle(
                            color: c,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message.trim().isEmpty ? 'Enquiry message' : message.trim(),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.28,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _demoEnquiries = <Map<String, dynamic>>[
  {
    'providerName': 'Ravi Interiors',
    'message': 'Hi, kitchen modular work estimate venum. Budget 60k-80k.',
    'status': 'new',
    'createdAt': '2026-04-12T10:30:00Z',
  },
  {
    'providerName': 'Siva Electricals',
    'message': '2 ceiling lights + fan wiring. Tomorrow possible ah?',
    'status': 'confirmed',
    'createdAt': '2026-04-11T16:15:00Z',
  },
  {
    'providerName': 'AquaFix',
    'message': 'Bathroom pipe leak. Urgent service venum.',
    'status': 'in progress',
    'createdAt': '2026-04-10T08:10:00Z',
  },
  {
    'providerName': 'PaintHub',
    'message': '2BHK full painting cost details share pannunga.',
    'status': 'closed',
    'createdAt': '2026-04-09T12:05:00Z',
  },
];
