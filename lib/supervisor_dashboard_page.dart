import 'package:flutter/material.dart';
import 'auth_service.dart';

class SupervisorDashboardPage extends StatelessWidget {
  final String name;
  final String site;

  const SupervisorDashboardPage({super.key, required this.name, required this.site});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(top: 20),
              decoration: const BoxDecoration(
                color: Color(0xFFF4F6FA),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildStatsGrid(),
                  const SizedBox(height: 25),
                  const Text(
                    "Worker Status",
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 15),
                  const _WorkerTile(
                    name: "Ali Shah",
                    subtitle: "Zone A - Helmet #H-03",
                    status: "Safe",
                    color: Colors.green,
                  ),
                  const _WorkerTile(
                    name: "Faisal Khan",
                    subtitle: "Zone B - Helmet #H-07",
                    status: "Warning",
                    color: Colors.orange,
                  ),
                  const _WorkerTile(
                    name: "Zain Ahmed",
                    subtitle: "Zone C - Helmet #H-11",
                    status: "Critical",
                    color: Colors.red,
                  ),
                  const _WorkerTile(
                    name: "Usman Baig",
                    subtitle: "Zone A - Helmet #H-02",
                    status: "Safe",
                    color: Colors.green,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final AuthService authService = AuthService();
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 20, 25, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Welcome back,",
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
              ),
              IconButton(
                onPressed: () => authService.signOut(),
                icon: const Icon(Icons.logout, color: Colors.white, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text(
                " — Supervisor",
                style: TextStyle(
                  color: Color(0xFF2F80ED),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Text(
            "Site: $site - Live",
            style: const TextStyle(
              color: Color(0xFF2F80ED),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: const [
        _StatCard(
          title: "Workers Online",
          value: "12/14",
          color: Colors.green,
          icon: Icons.circle,
        ),
        _StatCard(
          title: "Active Alerts",
          value: "2",
          color: Colors.red,
          icon: Icons.error,
        ),
        _StatCard(
          title: "Helmets Active",
          value: "14",
          color: Color(0xFF2F80ED),
          icon: Icons.badge,
        ),
        _StatCard(
          title: "Low Battery",
          value: "1",
          color: Colors.orange,
          icon: Icons.battery_alert,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title, value;
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Text(
                value.split('/')[0],
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              if (value.contains('/'))
                Text(
                  "/${value.split('/')[1]}",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black.withOpacity(0.3),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(icon, size: 10, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.black.withOpacity(0.6),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}

class _WorkerTile extends StatelessWidget {
  final String name, subtitle, status;
  final Color color;

  const _WorkerTile({
    required this.name,
    required this.subtitle,
    required this.status,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF0C2346),
            radius: 18,
            child: Text(
              name[0],
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.black.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        ],
      ),
    );
  }
}
