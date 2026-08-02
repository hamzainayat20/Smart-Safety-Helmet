import 'package:flutter/material.dart';
import 'auth_service.dart';

class AlertsPage extends StatelessWidget {
  const AlertsPage({super.key});

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
                  _AlertCard(
                    title: "Gas Level Critical — Zain Ahmed",
                    subtitle: "MQ135: CO₂ = 850 ppm (limit: 500 ppm) • Helmet H-11 • Zone C",
                    time: "2m ago",
                    color: Colors.red,
                    icon: Icons.warning_amber_rounded,
                    actions: [
                      _AlertButton(label: "Respond", color: Colors.black),
                      _AlertButton(label: "View Map", color: Colors.black),
                    ],
                  ),
                  _AlertCard(
                    title: "High Temperature — Faisal Khan",
                    subtitle: "Temp: 42°C (limit: 38°C) • Helmet H-07 • Zone B",
                    time: "7m ago",
                    color: Colors.orange,
                    icon: Icons.thermostat_rounded,
                    actions: [
                      _AlertButton(label: "Acknowledge", color: Colors.black),
                      _AlertButton(label: "Details", color: Colors.black),
                    ],
                  ),
                  _AlertCard(
                    title: "Low Battery — Helmet H-05",
                    subtitle: "Battery: 18% • Worker: Omar Farooq • Zone A",
                    time: "22m ago",
                    color: Colors.blue,
                    icon: Icons.battery_alert_rounded,
                    actions: [
                      _AlertButton(label: "Dismiss", color: Colors.black),
                    ],
                  ),
                  const _AlertCard(
                    title: "Fall Detected — Resolved",
                    subtitle: "Worker OK • Helmet H-09 • Zone D • Auto-resolved",
                    time: "1h ago",
                    color: Colors.grey,
                    icon: Icons.check_circle_outline_rounded,
                    isResolved: true,
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
              const Text(
                "Alert Centre",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
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
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 12),
              SizedBox(width: 4),
              Text(
                "2 active • 5 today",
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final String title, subtitle, time;
  final Color color;
  final IconData icon;
  final List<Widget>? actions;
  final bool isResolved;

  const _AlertCard({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.color,
    required this.icon,
    this.actions,
    this.isResolved = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: isResolved ? Colors.grey : Colors.black,
                    ),
                  ),
                ),
                Text(
                  time,
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.black.withOpacity(0.6),
                fontSize: 12,
                height: 1.3,
              ),
            ),
            if (actions != null) ...[
              const SizedBox(height: 16),
              Row(children: actions!),
            ]
          ],
        ),
      ),
    );
  }
}

class _AlertButton extends StatelessWidget {
  final String label;
  final Color color;

  const _AlertButton({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: OutlinedButton(
        onPressed: () {},
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: Colors.black.withOpacity(0.1)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ),
    );
  }
}
