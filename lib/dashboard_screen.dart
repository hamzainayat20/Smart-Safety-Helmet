import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'user_role.dart';
import 'supervisor_dashboard_page.dart';
import 'worker_dashboard_page.dart';
import 'worker_alerts_page.dart';
import 'worker_profile_page.dart';
import 'gps_map_page.dart';
import 'alerts_page.dart';
import 'helmets_page.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  final AuthService _authService = AuthService();
  late Future<DocumentSnapshot?> _userFuture;

  @override
  void initState() {
    super.initState();
    _userFuture = _authService.getUserData();
  }

  @override
  Widget build(BuildContext context) {
    const bgBottom = Color(0xFF07152C);

    return FutureBuilder<DocumentSnapshot?>(
      future: _userFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: bgBottom,
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF2F80ED)),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: bgBottom,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Error: ${snapshot.error}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () => _authService.signOut(),
                    child: const Text('Sign Out'),
                  ),
                ],
              ),
            ),
          );
        }

        var userData = snapshot.data?.data() as Map<String, dynamic>?;
        if (userData == null || !snapshot.data!.exists) {
          return Scaffold(
            backgroundColor: bgBottom,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'User profile not found in database.',
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () => _authService.signOut(),
                    child: const Text('Sign Out'),
                  ),
                ],
              ),
            ),
          );
        }

        final String name = userData['name'] ?? 'User';
        final String site = userData['organization'] ?? 'Main Site';
        
        // Safely parse role handling both legacy (int) and new (String) formats
        final dynamic roleData = userData['role'];
        String roleStr;
        if (roleData is int) {
          roleStr = UserRole.values[roleData].name;
        } else {
          roleStr = roleData?.toString() ?? 'worker';
        }

        final bool isSupervisor = roleStr.toLowerCase() == 'supervisor';

        List<Widget> pages;
        List<BottomNavigationBarItem> navItems;

        if (isSupervisor) {
          pages = [
            SupervisorDashboardPage(name: name, site: site),
            GpsMapPage(site: site),
            const AlertsPage(),
            const HelmetsPage(),
          ];
          navItems = const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined, size: 20), label: 'Dashboard'),
            BottomNavigationBarItem(icon: Icon(Icons.location_on_outlined, size: 20), label: 'GPS Map'),
            BottomNavigationBarItem(icon: Icon(Icons.notifications_none_rounded, size: 20), label: 'Alerts'),
            BottomNavigationBarItem(icon: Icon(Icons.settings_input_component_outlined, size: 20), label: 'Helmets'),
          ];
        } else {
          pages = [
            WorkerDashboardPage(name: name, site: site),
            const WorkerAlertsPage(),
            WorkerProfilePage(userData: userData),
          ];
          navItems = const [
            BottomNavigationBarItem(icon: Icon(Icons.home_outlined, size: 20), label: 'Status'),
            BottomNavigationBarItem(icon: Icon(Icons.notifications_none_rounded, size: 20), label: 'My Alerts'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline, size: 20), label: 'Profile'),
          ];
          
          if (_currentIndex >= pages.length) {
            _currentIndex = 0;
          }
        }

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
              unselectedItemColor: Colors.white.withOpacity(0.5),
              selectedFontSize: 10,
              unselectedFontSize: 10,
              items: navItems,
            ),
          ),
        );
      },
    );
  }
}
