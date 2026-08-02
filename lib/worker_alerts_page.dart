import 'package:flutter/material.dart';

class WorkerAlertsPage extends StatelessWidget {
  const WorkerAlertsPage({super.key});

  @override
  Widget build(BuildContext context) {
    const bgBottom = Color(0xFF07152C);

    return Scaffold(
      backgroundColor: bgBottom,
      body: SafeArea(
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
                    _buildFilterTabs(),
                    const SizedBox(height: 20),
                    _AlertCard(
                      title: "High Humidity Detected",
                      subtitle: "Humidity level exceeded threshold",
                      detail: "Humidity: 78% (limit: 70%)",
                      time: "35m ago",
                      color: Colors.orange,
                      icon: Icons.water_drop_outlined,
                      statusLabel: "Warning",
                      statusSub: "Auto-monitoring...",
                      showAcknowledge: true,
                    ),
                    const _AlertCard(
                      title: "Gas Spike — Resolved",
                      subtitle: "Brief CO₂ elevation, returned to normal",
                      detail: "Peak: 310 ppm → Now: 198 ppm",
                      time: "2h ago",
                      color: Colors.green,
                      icon: Icons.check_circle_outline_rounded,
                      statusLabel: "Resolved",
                      statusSub: "Duration: 4 min",
                    ),
                    const _AlertCard(
                      title: "High Temp — Resolved",
                      subtitle: "Temperature briefly elevated during noon shift",
                      detail: "Peak: 39.2°C → Normal",
                      time: "Yesterday",
                      color: Colors.green,
                      icon: Icons.check_circle_outline_rounded,
                      statusLabel: "Resolved",
                      statusSub: "Duration: 12 min",
                    ),
                    const _AlertCard(
                      title: "Helmet Battery Low",
                      subtitle: "Battery dropped below 20% during shift",
                      detail: "Battery: 18% — Charged after shift",
                      time: "2 days ago",
                      color: Colors.blue,
                      icon: Icons.battery_alert_outlined,
                      statusLabel: "Resolved",
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(25, 20, 25, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "My Alerts",
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
          ),
          Text(
            "Helmet H-03 • Ali Shah",
            style: TextStyle(color: Color(0xFF77A6D7), fontSize: 12, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatMini(label: "Active", value: "0", color: Colors.red),
              _StatMini(label: "Today", value: "1", color: Colors.orange),
              _StatMini(label: "This Week", value: "3", color: Colors.green),
              _StatMini(label: "Total", value: "12", color: Colors.blue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Row(
      children: [
        _FilterTab(label: "All", isSelected: true),
        const SizedBox(width: 8),
        _FilterTab(label: "Active", isSelected: false),
        const SizedBox(width: 8),
        _FilterTab(label: "Resolved", isSelected: false),
      ],
    );
  }
}

class _StatMini extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatMini({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 75,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF16324F),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _FilterTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  const _FilterTab({required this.label, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white : Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.black : Colors.black54,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final String title, subtitle, detail, time, statusLabel;
  final String? statusSub;
  final Color color;
  final IconData icon;
  final bool showAcknowledge;

  const _AlertCard({
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.time,
    required this.color,
    required this.icon,
    required this.statusLabel,
    this.statusSub,
    this.showAcknowledge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              ),
              Text(time, style: const TextStyle(color: Colors.grey, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 12),
          Text(detail, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text(statusLabel, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
                  ),
                  if (statusSub != null) ...[
                    const SizedBox(height: 4),
                    Text(statusSub!, style: const TextStyle(color: Colors.black38, fontSize: 10)),
                  ]
                ],
              ),
              if (showAcknowledge)
                ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    side: const BorderSide(color: Colors.black12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text("Acknowledge", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
