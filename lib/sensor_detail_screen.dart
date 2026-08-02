import 'package:flutter/material.dart';

class SensorDetailScreen extends StatelessWidget {
  final String helmetId;
  final String workerName;

  const SensorDetailScreen({super.key, required this.helmetId, required this.workerName});

  @override
  Widget build(BuildContext context) {
    const bgBottom = Color(0xFF07152C);
    
    return Scaffold(
      backgroundColor: bgBottom,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildHeartRateCard(),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _buildSmallMetricCard("36.8°C", "Temperature (DHT22)", "Normal", Colors.green, Icons.thermostat)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildSmallMetricCard("58%", "Humidity (DHT22)", "Normal", Colors.green, Icons.water_drop)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _buildSmallMetricCard("210 ppm", "Gas Level (MQ135)", "Safe", Colors.green, Icons.cloud_outlined)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildSmallMetricCard("-68 dBm", "Wi-Fi Signal", "Good", Colors.green, Icons.settings_input_antenna)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildMotionCard(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Row(
              children: [
                const Icon(Icons.arrow_back, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Text(
                  "$helmetId - $workerName",
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                )
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Live Sensor Data",
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            "Real-time • Updated every 5s • Firebase",
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildHeartRateCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Text(
            "HEART RATE (MAX30100)",
            style: TextStyle(color: Colors.black.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text("72", style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900)),
          const Text("beats per minute", style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          const Text("Normal range: 60-100 bpm ✓", style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(15, (index) {
              double height = 10.0 + (index % 5) * 5.0;
              return Container(
                width: 6,
                height: height,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          )
        ],
      ),
    );
  }

  Widget _buildSmallMetricCard(String value, String label, String status, Color statusColor, IconData icon) {
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
          Icon(icon, color: Colors.black.withOpacity(0.2), size: 24),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
          Text(label, style: TextStyle(color: Colors.black.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(status, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildMotionCard() {
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
          Text(
            "IMU / Motion (MPU6050)",
            style: TextStyle(color: Colors.black.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildAxisData("0.12g", "Accel X"),
              _buildAxisData("0.08g", "Accel Y"),
              _buildAxisData("9.78g", "Accel Z"),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  children: [
                    Text("Normal", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                    Text("No fall", style: TextStyle(color: Colors.green, fontSize: 10)),
                  ],
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildAxisData(String value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          Text(label, style: TextStyle(color: Colors.black.withOpacity(0.4), fontSize: 9)),
        ],
      ),
    );
  }
}
