import 'package:flutter/material.dart';
import 'auth_service.dart';

class WorkerProfilePage extends StatelessWidget {
  final Map<String, dynamic> userData;

  const WorkerProfilePage({super.key, required this.userData});

  @override
  Widget build(BuildContext context) {
    const bgBottom = Color(0xFF07152C);
    final AuthService authService = AuthService();

    final String name = userData['name'] ?? 'User';
    final String email = userData['email'] ?? 'No email';
    final String site = userData['organization'] ?? 'Not assigned';
    final String initials = name.split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase();

    return Scaffold(
      backgroundColor: bgBottom,
      body: SafeArea(
        child: Column(
          children: [
            _buildProfileHeader(name, site, initials),
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
                    _buildQuickStats(),
                    const SizedBox(height: 20),
                    _buildSection(
                      "Personal Info",
                      [
                        _InfoRow(Icons.person_outline, "Full Name", name),
                        _InfoRow(Icons.email_outlined, "Work Email", email),
                        _InfoRow(Icons.badge_outlined, "User ID", userData['uid']?.toString().substring(0, 8) ?? 'N/A'),
                        _InfoRow(Icons.business_outlined, "Site / Organization", site),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildSection(
                      "Assigned Helmet",
                      [
                        const _InfoRow(Icons.engineering, "Helmet ID", "H-03", trailing: "Active"),
                        const _InfoRow(Icons.battery_std, "Battery", "87% — Good"),
                        const _InfoRow(Icons.wifi, "Connectivity", "Wi-Fi • Firebase Connected"),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildSection(
                      "Notification Settings",
                      [
                        const _SwitchRow(Icons.notifications_none, "Push Alerts", "Receive safety alerts instantly", true),
                        const _SwitchRow(Icons.warning_amber_rounded, "Critical Alerts Only", "Suppress warnings below threshold", false),
                        const _SwitchRow(Icons.vibration, "Vibration", "Haptic feedback on alerts", true),
                      ],
                    ),
                    const SizedBox(height: 30),
                    OutlinedButton(
                      onPressed: () => authService.signOut(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout_rounded, size: 20),
                          SizedBox(width: 10),
                          Text("Sign Out", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(String name, String site, String initials) {
    return Column(
      children: [
        const SizedBox(height: 20),
        CircleAvatar(
          radius: 40,
          backgroundColor: const Color(0xFF2F80ED),
          child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 12),
        Text(name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
        Text(
          "Worker • $site",
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, color: Colors.green, size: 8),
              SizedBox(width: 8),
              Text("Online • Shift Active", style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStats() {
    return Row(
      children: [
        Expanded(child: _StatBox("18", "Safe Days")),
        const SizedBox(width: 12),
        Expanded(child: _StatBox("6h 12m", "Shift Time")),
        const SizedBox(width: 12),
        Expanded(child: _StatBox("H-03", "My Helmet")),
      ],
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String value, label;
  const _StatBox(this.value, this.label, {super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          Text(label, style: const TextStyle(color: Colors.black38, fontSize: 10, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final String? trailing;
  const _InfoRow(this.icon, this.label, this.value, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF2F80ED)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.black38, fontSize: 10, fontWeight: FontWeight.w700)),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              ],
            ),
          ),
          if (trailing != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
              child: Text(trailing!, style: const TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.w900)),
            ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final bool value;
  const _SwitchRow(this.icon, this.label, this.sub, this.value, {super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.black45),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                Text(sub, style: const TextStyle(color: Colors.black38, fontSize: 10)),
              ],
            ),
          ),
          Switch(value: value, onChanged: (_) {}, activeColor: const Color(0xFF2F80ED)),
        ],
      ),
    );
  }
}
