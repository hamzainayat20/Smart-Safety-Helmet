import 'package:flutter/material.dart';
import 'auth_service.dart';

class WorkerDashboardPage extends StatelessWidget {
  final String name;
  final String site;

  const WorkerDashboardPage({super.key, required this.name, required this.site});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF2F80ED);
    final AuthService authService = AuthService();

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 20, 25, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Welcome back,", style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
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
                    Text(name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                    const Text(" — Worker", style: TextStyle(color: Color(0xFF2F80ED), fontWeight: FontWeight.bold)),
                  ],
                ),
                Text("Site: $site", style: const TextStyle(color: Color(0xFF2F80ED), fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(top: 20),
              decoration: const BoxDecoration(
                color: Color(0xFFF4F6FA),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
              ),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                   Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Colors.green, size: 60),
                        const SizedBox(height: 10),
                        const Text("You are SAFE", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.green)),
                        const SizedBox(height: 5),
                        Text("Active Monitoring in Progress", style: TextStyle(color: Colors.black.withOpacity(0.4), fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text("Your Helmet Status", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 15),
                  _StatusRow(label: "Battery", value: "87%", icon: Icons.battery_full, color: Colors.green),
                  _StatusRow(label: "Heart Rate", value: "72 bpm", icon: Icons.favorite, color: Colors.red),
                  _StatusRow(label: "Temperature", value: "36.8°C", icon: Icons.thermostat, color: Colors.orange),
                  _StatusRow(label: "Gas Level", value: "210 ppm", icon: Icons.cloud, color: accent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;

  const _StatusRow({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.black.withOpacity(0.05))),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 15),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        ],
      ),
    );
  }
}
