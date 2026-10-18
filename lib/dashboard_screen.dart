import 'package:flutter/material.dart';

import 'alerts_page.dart';
import 'application/dashboard_view_model.dart';
import 'application/gps_map_view_model.dart';
import 'application/session_controller.dart';
import 'domain/models.dart';
import 'gps_map_page.dart';
import 'helmets_page.dart';
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

  @override
  Widget build(BuildContext context) {
    const bgBottom = Color(0xFF07152C);
    final isSupervisor = widget.profile.role == UserRole.supervisor;

    final pages = isSupervisor
        ? <Widget>[
            SupervisorDashboardPage(
              viewModel: _viewModel,
              onSignOut: widget.session.signOut,
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
            ),
            WorkerAlertsPage(viewModel: _viewModel),
            WorkerProfilePage(
              viewModel: _viewModel,
              onSignOut: widget.session.signOut,
            ),
          ];

    final navItems = isSupervisor
        ? const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined, size: 20),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.location_on_outlined, size: 20),
              label: 'GPS Map',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.notifications_none_rounded, size: 20),
              label: 'Alerts',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_input_component_outlined, size: 20),
              label: 'Helmets',
            ),
          ]
        : const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined, size: 20),
              label: 'Status',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.notifications_none_rounded, size: 20),
              label: 'My Alerts',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline, size: 20),
              label: 'Profile',
            ),
          ];

    if (_currentIndex >= pages.length) _currentIndex = 0;

    return Scaffold(
      backgroundColor: bgBottom,
      body: pages[_currentIndex],
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(canvasColor: bgBottom),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF2F80ED),
          unselectedItemColor: Colors.white.withValues(alpha: 0.5),
          selectedFontSize: 10,
          unselectedFontSize: 10,
          items: navItems,
        ),
      ),
    );
  }
}
