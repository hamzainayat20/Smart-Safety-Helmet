import 'package:flutter/material.dart';

import '../../data/admin_repository.dart';
import '../design_system/design_system.dart';
import 'admin_shared.dart';

/// Console landing section: fleet and account counts from the admin
/// repository. Unknown counts (alert totals that could not be read) render
/// as "—" via [MetricTile], never as zero.
class AdminOverviewScreen extends StatefulWidget {
  const AdminOverviewScreen({
    super.key,
    required this.admin,
    required this.onSignOut,
  });

  final AdminRepository admin;
  final VoidCallback onSignOut;

  @override
  State<AdminOverviewScreen> createState() => _AdminOverviewScreenState();
}

class _AdminOverviewScreenState extends State<AdminOverviewScreen> {
  late Stream<AdminOverview> _overview;

  @override
  void initState() {
    super.initState();
    _overview = widget.admin.watchOverview();
  }

  void _retry() => setState(() => _overview = widget.admin.watchOverview());

  @override
  Widget build(BuildContext context) => AdminPageFrame(
    title: 'Admin console',
    eyebrow: 'Administrator',
    subtitle: 'Accounts, fleet and safety totals',
    actions: [
      HeaderIconButton(
        icon: Icons.logout_rounded,
        tooltip: 'Sign out',
        onPressed: widget.onSignOut,
      ),
    ],
    child: StreamBuilder<AdminOverview>(
      stream: _overview,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return StateView(
            kind: StateViewKind.error,
            title: 'Overview unavailable',
            message: adminErrorMessage(snapshot.error!),
            onAction: _retry,
          );
        }
        final overview = snapshot.data;
        if (overview == null) {
          return const StateView(
            kind: StateViewKind.loading,
            title: 'Loading overview',
            message: 'Counting accounts, helmets and alerts…',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const SectionHeader(
              title: 'Accounts',
              subtitle: 'Registered users by role and state',
            ),
            const SizedBox(height: AppSpacing.md),
            ResponsiveTileGrid(
              children: [
                MetricTile(
                  label: 'Users',
                  value: '${overview.totalUsers}',
                  icon: Icons.people_rounded,
                ),
                MetricTile(
                  label: 'Active users',
                  value: '${overview.activeUsers}',
                  icon: Icons.how_to_reg_rounded,
                  status: SafetyStatus.normal,
                ),
                MetricTile(
                  label: 'Supervisors',
                  value: '${overview.supervisors}',
                  icon: Icons.supervisor_account_rounded,
                ),
                MetricTile(
                  label: 'Workers',
                  value: '${overview.workers}',
                  icon: Icons.engineering_rounded,
                ),
                MetricTile(
                  label: 'Administrators',
                  value: '${overview.administrators}',
                  icon: Icons.admin_panel_settings_rounded,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(
              title: 'Helmets',
              subtitle: 'Registered fleet by provisioning state',
            ),
            const SizedBox(height: AppSpacing.md),
            ResponsiveTileGrid(
              children: [
                MetricTile(
                  label: 'Helmets',
                  value: '${overview.totalHelmets}',
                  icon: Icons.construction_rounded,
                ),
                MetricTile(
                  label: 'Assigned',
                  value: '${overview.assignedHelmets}',
                  icon: Icons.link_rounded,
                  status: SafetyStatus.normal,
                ),
                MetricTile(
                  label: 'Unassigned',
                  value: '${overview.unassignedHelmets}',
                  icon: Icons.link_off_rounded,
                  status: overview.unassignedHelmets > 0
                      ? SafetyStatus.warning
                      : SafetyStatus.normal,
                ),
                MetricTile(
                  label: 'Revoked',
                  value: '${overview.revokedHelmets}',
                  icon: Icons.block_rounded,
                  status: overview.revokedHelmets > 0
                      ? SafetyStatus.critical
                      : SafetyStatus.normal,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(
              title: 'Alerts',
              subtitle: 'Stored in-app alerts (UTC day)',
            ),
            const SizedBox(height: AppSpacing.md),
            ResponsiveTileGrid(
              children: [
                MetricTile(
                  label: 'Alerts today',
                  value: overview.alertsToday?.toString(),
                  icon: Icons.notifications_rounded,
                ),
                MetricTile(
                  label: 'Critical unacknowledged',
                  value: overview.criticalUnacknowledged?.toString(),
                  icon: Icons.error_rounded,
                  status: (overview.criticalUnacknowledged ?? 0) > 0
                      ? SafetyStatus.critical
                      : SafetyStatus.normal,
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}
