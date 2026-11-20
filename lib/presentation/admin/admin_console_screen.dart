import 'package:flutter/material.dart';

import '../../application/app_dependencies.dart';
import '../../domain/models.dart';
import '../design_system/design_system.dart';
import 'admin_audit_screen.dart';
import 'admin_helmets_screen.dart';
import 'admin_live_screen.dart';
import 'admin_overview.dart';
import 'admin_sites_screen.dart';
import 'admin_thresholds_screen.dart';
import 'admin_users_screen.dart';

/// Administrator console shell: Overview, Live, Users, Helmets, Sites,
/// Thresholds and Audit over the live admin repository, in the same
/// adaptive navigation pattern as the supervisor/worker shells.
class AdminConsoleScreen extends StatefulWidget {
  const AdminConsoleScreen({
    super.key,
    required this.dependencies,
    required this.profile,
    required this.onSignOut,
  });

  final AppDependencies dependencies;
  final UserProfile profile;
  final VoidCallback onSignOut;

  @override
  State<AdminConsoleScreen> createState() => _AdminConsoleScreenState();
}

class _AdminConsoleScreenState extends State<AdminConsoleScreen> {
  int _currentIndex = 0;

  static const _items = [
    AppNavItem(
      icon: Icons.space_dashboard_outlined,
      selectedIcon: Icons.space_dashboard_rounded,
      label: 'Overview',
    ),
    AppNavItem(
      icon: Icons.sensors_outlined,
      selectedIcon: Icons.sensors_rounded,
      label: 'Live',
    ),
    AppNavItem(
      icon: Icons.people_outline_rounded,
      selectedIcon: Icons.people_rounded,
      label: 'Users',
    ),
    AppNavItem(
      icon: Icons.engineering_outlined,
      selectedIcon: Icons.engineering_rounded,
      label: 'Helmets',
    ),
    AppNavItem(
      icon: Icons.location_city_outlined,
      selectedIcon: Icons.location_city_rounded,
      label: 'Sites',
    ),
    AppNavItem(
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune_rounded,
      label: 'Thresholds',
    ),
    AppNavItem(
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
      label: 'Audit',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final admin = widget.dependencies.admin;
    if (!admin.isLive) {
      return Scaffold(
        backgroundColor: AppColors.ink,
        body: AdminLiveBackendRequired(onSignOut: widget.onSignOut),
      );
    }
    final pages = <Widget>[
      AdminOverviewScreen(admin: admin, onSignOut: widget.onSignOut),
      AdminLiveScreen(admin: admin, onSignOut: widget.onSignOut),
      AdminUsersScreen(
        admin: admin,
        currentUser: widget.profile,
        onSignOut: widget.onSignOut,
      ),
      AdminHelmetsScreen(admin: admin, onSignOut: widget.onSignOut),
      AdminSitesScreen(admin: admin, onSignOut: widget.onSignOut),
      AdminThresholdsScreen(
        admin: admin,
        currentUser: widget.profile,
        onSignOut: widget.onSignOut,
      ),
      AdminAuditScreen(admin: admin, onSignOut: widget.onSignOut),
    ];
    if (_currentIndex >= pages.length) _currentIndex = 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kNavigationRailBreakpoint;
        final navigation = wide
            ? AppNavigationRail(
                items: _items,
                currentIndex: _currentIndex,
                onSelected: (index) => setState(() => _currentIndex = index),
              )
            : AppNavigationBar(
                items: _items,
                currentIndex: _currentIndex,
                onSelected: (index) => setState(() => _currentIndex = index),
              );
        final page = AnimatedSwitcher(
          duration: AppMotion.of(context, AppMotion.quick),
          switchInCurve: AppMotion.enter,
          switchOutCurve: AppMotion.exit,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: KeyedSubtree(
            key: ValueKey(_currentIndex),
            child: pages[_currentIndex],
          ),
        );
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

/// Shown instead of the console when the app runs without a live backend
/// (demo mode). Administrative data is never faked, so the only honest
/// state here is an explanation plus sign out.
class AdminLiveBackendRequired extends StatelessWidget {
  const AdminLiveBackendRequired({super.key, required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPageHeader(
          title: 'Admin console',
          eyebrow: 'Administrator',
          actions: [
            HeaderIconButton(
              icon: Icons.logout_rounded,
              tooltip: 'Sign out',
              onPressed: onSignOut,
            ),
          ],
        ),
        Expanded(
          child: ContentSheet(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: const [
                StateView(
                  kind: StateViewKind.offline,
                  title: 'Connect a live backend',
                  message:
                      'The admin console manages real users, helmets and '
                      'configuration, so it is unavailable in demo mode. '
                      'Run the app against the live Firebase backend to '
                      'use it.',
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
