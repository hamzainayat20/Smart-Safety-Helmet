import 'package:flutter/material.dart';

import '../../data/admin_repository.dart';
import '../design_system/design_system.dart';
import '../formatters.dart';
import 'admin_shared.dart';

/// Reverse-chronological audit trail from `/adminAudit`, filterable by
/// target type. Entries are written by the backend inside every admin
/// operation; secret values are never part of an entry.
class AdminAuditScreen extends StatefulWidget {
  const AdminAuditScreen({
    super.key,
    required this.admin,
    required this.onSignOut,
  });

  final AdminRepository admin;
  final VoidCallback onSignOut;

  @override
  State<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

class _AdminAuditScreenState extends State<AdminAuditScreen> {
  String? _targetFilter;

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('user', 'Users'),
    ('helmet', 'Helmets'),
    ('site', 'Sites'),
    ('config', 'Config'),
  ];

  @override
  Widget build(BuildContext context) => AdminPageFrame(
    title: 'Audit log',
    eyebrow: 'Administrator',
    subtitle: 'Every admin action, newest first',
    actions: [
      HeaderIconButton(
        icon: Icons.logout_rounded,
        tooltip: 'Sign out',
        onPressed: widget.onSignOut,
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            0,
          ),
          child: SegmentedFilter<String?>(
            values: [for (final filter in _filters) filter.$1],
            selected: _targetFilter,
            labelOf: (value) =>
                _filters.firstWhere((filter) => filter.$1 == value).$2,
            onSelected: (value) => setState(() => _targetFilter = value),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<AuditLogEntry>>(
            stream: widget.admin.watchAuditLog(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return StateView(
                  kind: StateViewKind.error,
                  title: 'Audit log unavailable',
                  message: adminErrorMessage(snapshot.error!),
                );
              }
              final entries = snapshot.data;
              if (entries == null) {
                return const StateView(
                  kind: StateViewKind.loading,
                  title: 'Loading audit log',
                  message: 'Reading recorded admin actions…',
                );
              }
              final visible = _targetFilter == null
                  ? entries
                  : entries
                        .where((entry) => entry.targetType == _targetFilter)
                        .toList();
              if (visible.isEmpty) {
                return StateView(
                  kind: StateViewKind.empty,
                  title: entries.isEmpty
                      ? 'No actions recorded'
                      : 'No matching actions',
                  message: entries.isEmpty
                      ? 'Admin actions appear here as they happen.'
                      : 'No audit entries match this target type.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: visible.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) =>
                    _AuditCard(entry: visible[index]),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _AuditCard extends StatelessWidget {
  const _AuditCard({required this.entry});

  final AuditLogEntry entry;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                entry.action.isEmpty ? 'Admin action' : entry.action,
                style: AppTypography.bodyStrong.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            StatusChip(
              status: SafetyStatus.pending,
              label: entry.targetType.isEmpty
                  ? 'Target unavailable'
                  : '${entry.targetType}: ${entry.targetId}',
            ),
          ],
        ),
        if (entry.summary.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            entry.summary,
            style: AppTypography.body.copyWith(color: AppColors.textPrimary),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Text(
          'By ${entry.actorUid.isEmpty ? 'Unavailable' : entry.actorUid}'
          ' • ${entry.at == null ? 'Time unavailable' : '${formatRelativeTime(entry.at!)} (${formatUtcTimestamp(entry.at!)})'}',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}
