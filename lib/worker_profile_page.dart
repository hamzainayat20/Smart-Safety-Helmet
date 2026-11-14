import 'package:flutter/material.dart';

import 'application/dashboard_view_model.dart';
import 'domain/models.dart';
import 'presentation/design_system/design_system.dart';
import 'presentation/formatters.dart';

class WorkerProfilePage extends StatelessWidget {
  const WorkerProfilePage({
    super.key,
    required this.viewModel,
    required this.onSignOut,
  });

  final DashboardViewModel viewModel;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
    builder: (context, _) {
      final profile = viewModel.profile;
      final helmet = viewModel.helmets.firstOrNull;
      final reading = helmet == null
          ? null
          : viewModel.readingFor(helmet.helmetId);
      final site = profile.organizationName ?? 'Not assigned';
      return Scaffold(
        backgroundColor: AppColors.ink,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppPageHeader(
                eyebrow: 'MY PROFILE',
                title: profile.displayName,
                titleSuffix: const RoleTag(label: 'Worker'),
                subtitle: 'Worker • $site',
                leading: InitialsAvatar(
                  name: profile.displayName,
                  size: AppSizes.touchTarget,
                ),
                bottom: Align(
                  alignment: Alignment.centerLeft,
                  child: StatusChip(
                    status: helmet == null
                        ? SafetyStatus.unknown
                        : SafetyStatus.normal,
                    label: helmet == null
                        ? 'No helmet assigned'
                        : 'Assigned • ${viewModel.dataSourceLabel}',
                    onInk: true,
                  ),
                ),
              ),
              Expanded(
                child: ContentSheet(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.xl,
                    ),
                    children: [
                      ResponsiveTileGrid(
                        minTileWidth: 120,
                        maxColumns: 3,
                        children: [
                          MetricTile(
                            label: 'Safety State',
                            value: reading?.severity.name,
                            icon: Icons.health_and_safety_outlined,
                            status: reading == null
                                ? null
                                : safetyStatusForSeverity(reading.severity),
                          ),
                          MetricTile(
                            label: 'Last Update',
                            value: reading == null
                                ? null
                                : formatRelativeTime(reading.serverReceivedAt),
                            icon: Icons.schedule_rounded,
                          ),
                          MetricTile(
                            label: 'My Helmet',
                            value: helmet?.helmetId,
                            icon: Icons.engineering_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const SectionHeader(title: 'Personal Info'),
                      AppCard(
                        child: Column(
                          children: [
                            _InfoRow(
                              Icons.person_outline,
                              'Full Name',
                              profile.displayName,
                            ),
                            const Divider(),
                            _InfoRow(
                              Icons.email_outlined,
                              'Work Email',
                              profile.email,
                            ),
                            const Divider(),
                            _InfoRow(
                              Icons.badge_outlined,
                              'User ID',
                              _shortId(profile.uid),
                            ),
                            const Divider(),
                            _InfoRow(
                              Icons.business_outlined,
                              'Site / Organization',
                              site,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const SectionHeader(title: 'Assigned Helmet'),
                      AppCard(
                        child: Column(
                          children: [
                            _InfoRow(
                              Icons.engineering_outlined,
                              'Helmet ID',
                              helmet?.helmetId ?? 'Not assigned',
                              trailing: helmet?.active == true
                                  ? const StatusChip(
                                      status: SafetyStatus.normal,
                                      label: 'Active',
                                    )
                                  : null,
                            ),
                            const Divider(),
                            _InfoRow(
                              Icons.battery_std_rounded,
                              'Battery',
                              formatMeasurement(
                                reading?.batteryPct,
                                SensorUnit.percent,
                                fractionDigits: 0,
                              ),
                            ),
                            const Divider(),
                            _InfoRow(
                              Icons.wifi_rounded,
                              'Connectivity',
                              reading?.connectivity.name ?? 'Unavailable',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const SectionHeader(title: 'Notification Settings'),
                      AppCard(
                        child: Column(
                          children: [
                            _SwitchRow(
                              icon: Icons.notifications_none_rounded,
                              label: 'Push Alerts',
                              description: 'Receive safety alerts instantly',
                              value: profile.pushAlertsEnabled,
                              onChanged: (value) => _savePreference(
                                context,
                                () => viewModel.updateNotificationPreferences(
                                  pushAlertsEnabled: value,
                                ),
                              ),
                            ),
                            const Divider(),
                            _SwitchRow(
                              icon: Icons.warning_amber_rounded,
                              label: 'Critical Alerts Only',
                              description:
                                  'Suppress non-critical warning notifications',
                              value: profile.criticalAlertsOnly,
                              onChanged: (value) => _savePreference(
                                context,
                                () => viewModel.updateNotificationPreferences(
                                  criticalAlertsOnly: value,
                                ),
                              ),
                            ),
                            const Divider(),
                            _SwitchRow(
                              icon: Icons.vibration,
                              label: 'Vibration',
                              description: 'Haptic feedback on alerts',
                              value: profile.vibrationEnabled,
                              onChanged: (value) => _savePreference(
                                context,
                                () => viewModel.updateNotificationPreferences(
                                  vibrationEnabled: value,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SizedBox(
                        height: 56,
                        child: AppButton(
                          label: 'Sign Out',
                          icon: Icons.logout_rounded,
                          variant: AppButtonVariant.destructive,
                          onPressed: onSignOut,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  /// Saves a preference and reports a failure instead of failing silently.
  Future<void> _savePreference(
    BuildContext context,
    Future<void> Function() save,
  ) async {
    try {
      await save();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save preference: $error')),
        );
      }
    }
  }

  String _shortId(String uid) => uid.length <= 8 ? uid : uid.substring(0, 8);
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.label, this.value, {this.trailing});

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          Icon(icon, size: AppSizes.iconMd, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: AppTypography.bodyStrong.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Row(
        children: [
          Icon(icon, size: AppSizes.iconMd, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.bodyStrong.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  description,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    ),
  );
}
