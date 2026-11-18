import 'package:flutter/material.dart';

import 'alerts_page.dart';
import 'application/dashboard_view_model.dart';
import 'application/gps_map_view_model.dart';
import 'application/session_controller.dart';
import 'domain/models.dart';
import 'gps_map_page.dart';
import 'helmets_page.dart';
import 'presentation/design_system/design_system.dart';
import 'supervisor_dashboard_page.dart';
import 'user_role.dart';
import 'worker_alerts_page.dart';
import 'worker_dashboard_page.dart';
import 'worker_profile_page.dart';
import 'safety_assistant_page.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.session,
    required this.profile,
    required this.mapFocusController,
  });

  final SessionController session;
  final UserProfile profile;
  final MapFocusController mapFocusController;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  late final DashboardViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = DashboardViewModel(
      profile: widget.profile,
      dependencies: widget.session.dependencies,
    )..start();
    widget.mapFocusController.addListener(_handleMapFocus);
    if (widget.mapFocusController.current != null) {
      _currentIndex = 1;
    }
  }

  void _handleMapFocus() {
    if (!mounted ||
        widget.profile.role != UserRole.supervisor ||
        widget.mapFocusController.current == null) {
      return;
    }
    setState(() => _currentIndex = 1);
  }

  @override
  void dispose() {
    widget.mapFocusController.removeListener(_handleMapFocus);
    _viewModel.dispose();
    super.dispose();
  }

  List<AppNavItem> _navItems(bool isSupervisor, {required bool wide}) {
    if (isSupervisor) {
      if (!wide) {
        return [
          const AppNavItem(
            icon: Icons.space_dashboard_outlined,
            selectedIcon: Icons.space_dashboard_rounded,
            label: 'Dashboard',
          ),
          AppNavItem(
            icon: Icons.notifications_none_rounded,
            selectedIcon: Icons.notifications_rounded,
            label: 'Alerts',
            badgeCount: _viewModel.activeAlertCount,
          ),
          const AppNavItem(
            icon: Icons.map_outlined,
            selectedIcon: Icons.map_rounded,
            label: 'Map',
          ),
          const AppNavItem(
            icon: Icons.more_horiz_rounded,
            selectedIcon: Icons.apps_rounded,
            label: 'More',
          ),
        ];
      }
      return [
        const AppNavItem(
          icon: Icons.space_dashboard_outlined,
          selectedIcon: Icons.space_dashboard_rounded,
          label: 'Dashboard',
        ),
        const AppNavItem(
          icon: Icons.map_outlined,
          selectedIcon: Icons.map_rounded,
          label: 'GPS Map',
        ),
        AppNavItem(
          icon: Icons.notifications_none_rounded,
          selectedIcon: Icons.notifications_rounded,
          label: 'Alerts',
          badgeCount: _viewModel.activeAlertCount,
        ),
        const AppNavItem(
          icon: Icons.engineering_outlined,
          selectedIcon: Icons.engineering_rounded,
          label: 'Helmets',
        ),
        const AppNavItem(
          icon: Icons.support_agent_outlined,
          selectedIcon: Icons.support_agent_rounded,
          label: 'Assistant',
        ),
      ];
    }
    final openAlerts = _viewModel.alerts
        .where((alert) => alert.status != AlertStatus.resolved)
        .length;
    return [
      const AppNavItem(
        icon: Icons.health_and_safety_outlined,
        selectedIcon: Icons.health_and_safety_rounded,
        label: 'Status',
      ),
      AppNavItem(
        icon: Icons.notifications_none_rounded,
        selectedIcon: Icons.notifications_rounded,
        label: 'My Alerts',
        badgeCount: openAlerts,
      ),
      const AppNavItem(
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
        label: 'Profile',
      ),
      const AppNavItem(
        icon: Icons.support_agent_outlined,
        selectedIcon: Icons.support_agent_rounded,
        label: 'Assistant',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isSupervisor = widget.profile.role == UserRole.supervisor;

    final pages = isSupervisor
        ? <Widget>[
            SupervisorDashboardPage(
              viewModel: _viewModel,
              onSignOut: widget.session.signOut,
              onLocate: widget.mapFocusController.focus,
            ),
            GpsMapPage(
              viewModel: _viewModel,
              onSignOut: widget.session.signOut,
              focusController: widget.mapFocusController,
            ),
            AlertsPage(
              viewModel: _viewModel,
              onSignOut: widget.session.signOut,
            ),
            HelmetsPage(
              viewModel: _viewModel,
              onSignOut: widget.session.signOut,
            ),
            SafetyAssistantPage(
              viewModel: _viewModel,
              onSignOut: widget.session.signOut,
            ),
            _SupervisorMorePage(
              profile: widget.profile,
              onOpenHelmets: () => setState(() => _currentIndex = 3),
              onOpenAssistant: () => setState(() => _currentIndex = 4),
              onSignOut: widget.session.signOut,
            ),
          ]
        : <Widget>[
            WorkerDashboardPage(
              viewModel: _viewModel,
              onSignOut: widget.session.signOut,
              onOpenAlerts: () => setState(() => _currentIndex = 1),
            ),
            WorkerAlertsPage(viewModel: _viewModel),
            WorkerProfilePage(
              viewModel: _viewModel,
              onSignOut: widget.session.signOut,
            ),
            SafetyAssistantPage(
              viewModel: _viewModel,
              onSignOut: widget.session.signOut,
            ),
          ];

    if (_currentIndex >= pages.length) _currentIndex = 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kNavigationRailBreakpoint;
        final navigation = AnimatedBuilder(
          animation: _viewModel,
          builder: (context, _) {
            final items = _navItems(isSupervisor, wide: wide);
            final selectedIndex = isSupervisor && !wide
                ? switch (_currentIndex) {
                    0 => 0,
                    2 => 1,
                    1 => 2,
                    _ => 3,
                  }
                : _currentIndex;
            void select(int index) => setState(
              () => _currentIndex = isSupervisor && !wide
                  ? const [0, 2, 1, 5][index]
                  : index,
            );
            return wide
                ? AppNavigationRail(
                    items: items,
                    currentIndex: selectedIndex,
                    onSelected: select,
                  )
                : AppNavigationBar(
                    items: items,
                    currentIndex: selectedIndex,
                    onSelected: select,
                  );
          },
        );
        final page = pages[_currentIndex];
        final duration = AppMotion.of(context, AppMotion.quick);
        final animatedPage = AnimatedSwitcher(
          duration: duration,
          switchInCurve: AppMotion.enter,
          switchOutCurve: AppMotion.exit,
          transitionBuilder: (child, animation) {
            final fade = FadeTransition(opacity: animation, child: child);
            if (AppMotion.reduced(context)) return fade;
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.015, 0),
                end: Offset.zero,
              ).animate(animation),
              child: fade,
            );
          },
          child: KeyedSubtree(key: ValueKey(_currentIndex), child: page),
        );
        return Scaffold(
          backgroundColor: AppColors.ink,
          body: wide
              ? Row(
                  children: [
                    navigation,
                    Expanded(child: animatedPage),
                  ],
                )
              : animatedPage,
          bottomNavigationBar: wide ? null : navigation,
        );
      },
    );
  }
}

class _SupervisorMorePage extends StatelessWidget {
  const _SupervisorMorePage({
    required this.profile,
    required this.onOpenHelmets,
    required this.onOpenAssistant,
    required this.onSignOut,
  });

  final UserProfile profile;
  final VoidCallback onOpenHelmets;
  final VoidCallback onOpenAssistant;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppPageHeader(
          title: 'More',
          compact: true,
          subtitle: 'Fleet tools and account access',
        ),
        Expanded(
          child: ContentSheet(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                _MoreDestination(
                  icon: Icons.engineering_outlined,
                  title: 'Helmets',
                  description: 'Search and inspect assigned devices',
                  onTap: onOpenHelmets,
                ),
                const Divider(),
                _MoreDestination(
                  icon: Icons.support_agent_outlined,
                  title: 'Safety Assistant',
                  description: 'Explain verified assessments and readings',
                  onTap: onOpenAssistant,
                ),
                const SizedBox(height: AppSpacing.lg),
                SectionHeader(title: 'Signed in account'),
                AppCard(
                  child: Column(
                    children: [
                      KeyValueRow(label: 'Name', value: profile.displayName),
                      const KeyValueRow(label: 'Role', value: 'Supervisor'),
                      KeyValueRow(
                        label: 'Organization',
                        value: profile.organizationName ?? 'Not assigned',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'Sign out',
                  icon: Icons.logout_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: onSignOut,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _MoreDestination extends StatelessWidget {
  const _MoreDestination({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Row(
          children: [
            IconTile(icon: icon, status: SafetyStatus.pending),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: AppTypography.bodyStrong),
                  Text(
                    description,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    ),
  );
}
