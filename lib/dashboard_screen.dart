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

  List<AppNavItem> _navItems(bool isSupervisor) {
    if (isSupervisor) {
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
          ];

    if (_currentIndex >= pages.length) _currentIndex = 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kNavigationRailBreakpoint;
        final navigation = AnimatedBuilder(
          animation: _viewModel,
          builder: (context, _) {
            final items = _navItems(isSupervisor);
            void select(int index) => setState(() => _currentIndex = index);
            return wide
                ? AppNavigationRail(
                    items: items,
                    currentIndex: _currentIndex,
                    onSelected: select,
                  )
                : AppNavigationBar(
                    items: items,
                    currentIndex: _currentIndex,
                    onSelected: select,
                  );
          },
        );
        final page = pages[_currentIndex];
        return Scaffold(
          backgroundColor: AppColors.ink,
          body: wide
              ? Row(
                  children: [
                    navigation,
                    Expanded(child: page),
                  ],
                )
              : page,
          bottomNavigationBar: wide ? null : navigation,
        );
      },
    );
  }
}
