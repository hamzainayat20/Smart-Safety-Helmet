import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'sensor_detail_screen.dart';

class HelmetsPage extends StatelessWidget {
  const HelmetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          _buildSearchBar(),
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
                  _HelmetCard(
                    id: "Helmet H-03",
                    worker: "Ali Shah - Zone A - Online",
                    temp: "36.8°C",
                    heartRate: "72 bpm",
                    battery: 87,
                    status: "Active",
                    statusColor: Colors.green,
                  ),
                  _HelmetCard(
                    id: "Helmet H-07",
                    worker: "Faisal Khan - Zone B - Online",
                    temp: "42°C",
                    heartRate: "88 bpm",
                    battery: 45,
                    status: "Warning",
                    statusColor: Colors.orange,
                  ),
                  _HelmetCard(
                    id: "Helmet H-11",
                    worker: "Zain Ahmed - Zone C - Online",
                    temp: "37.2°C",
                    gas: "850 ppm",
                    battery: 62,
                    status: "Critical",
                    statusColor: Colors.red,
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
                "Helmet Management",
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
          const Text(
            "14 registered • 12 active • 2 offline",
            style: TextStyle(
              color: Color(0xFF77A6D7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 20, 25, 0),
      child: TextField(
        decoration: InputDecoration(
          hintText: "Search helmet ID or worker...",
          hintStyle: TextStyle(color: Colors.black.withOpacity(0.3), fontSize: 13),
          prefixIcon: Icon(Icons.search, color: Colors.black.withOpacity(0.3), size: 20),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _HelmetCard extends StatelessWidget {
  final String id, worker, temp, status;
  final String? heartRate, gas;
  final int battery;
  final Color statusColor;

  const _HelmetCard({
    required this.id,
    required this.worker,
    required this.temp,
    this.heartRate,
    this.gas,
    required this.battery,
    required this.status,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SensorDetailScreen(helmetId: id, workerName: worker.split(' - ')[0]),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withOpacity(0.05)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.engineering, color: statusColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(id, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                      Text(worker, style: TextStyle(color: Colors.black.withOpacity(0.5), fontSize: 11)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetric(temp, "Temp", color: const Color(0xFF1E7A34)),
                if (heartRate != null) _buildMetric(heartRate!, "Heart Rate", color: const Color(0xFF1E7A34)),
                if (gas != null) _buildMetric(gas!, "Gas Level", color: Colors.red),
                _buildBatteryMetric(battery),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(String value, String label, {required Color color}) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: color)),
        Text(label, style: TextStyle(color: Colors.black.withOpacity(0.4), fontSize: 10)),
      ],
    );
  }

  Widget _buildBatteryMetric(int value) {
    Color color = value > 50 ? Colors.green : (value > 20 ? Colors.orange : Colors.red);
    return Column(
      children: [
        Text("$value%", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        Text("Battery", style: TextStyle(color: Colors.black.withOpacity(0.4), fontSize: 10)),
        const SizedBox(height: 4),
        SizedBox(
          width: 80,
          child: LinearProgressIndicator(
            value: value / 100,
            backgroundColor: Colors.black.withOpacity(0.05),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            borderRadius: BorderRadius.circular(2),
          ),
        )
      ],
    );
  }
}
