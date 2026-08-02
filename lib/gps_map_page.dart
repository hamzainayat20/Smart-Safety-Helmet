import 'package:flutter/material.dart';
import 'auth_service.dart';

class GpsMapPage extends StatelessWidget {
  final String site;
  const GpsMapPage({super.key, required this.site});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _buildMapHeader(),
          _buildMapArea(),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFFF4F6FA),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: const [
                  Text(
                    "Worker Locations",
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  SizedBox(height: 15),
                  _LocationTile(
                    name: "Ali Shah",
                    id: "H-03",
                    coords: "31.4628° N, 74.3183° E",
                    zone: "Zone A",
                    status: "Safe",
                    color: Colors.green,
                  ),
                  _LocationTile(
                    name: "Faisal Khan",
                    id: "H-07",
                    coords: "31.4631° N, 74.3190° E",
                    zone: "Zone B",
                    status: "Warning",
                    color: Colors.orange,
                  ),
                  _LocationTile(
                    name: "Zain Ahmed",
                    id: "H-11",
                    coords: "31.4619° N, 74.3175° E",
                    zone: "Zone C",
                    status: "Critical",
                    color: Colors.red,
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMapHeader() {
    final AuthService authService = AuthService();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.arrow_back, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text(
                    "GPS Tracking",
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  )
                ],
              ),
              IconButton(
                onPressed: () => authService.signOut(),
                icon: const Icon(Icons.logout, color: Colors.white, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            "Live Worker Map",
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            "14 helmets • 12 online • $site",
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildMapArea() {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0C2346),
        border: Border.symmetric(
          horizontal: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Stack(
        children: [
          // Simulated Grid Lines
          Column(
            children: [
              const Spacer(),
              Divider(color: Colors.white.withOpacity(0.1)),
              const Spacer(),
              Divider(color: Colors.white.withOpacity(0.1)),
              const Spacer()
            ],
          ),
          Row(
            children: [
              const Spacer(),
              VerticalDivider(color: Colors.white.withOpacity(0.1)),
              const Spacer(),
              VerticalDivider(color: Colors.white.withOpacity(0.1)),
              const Spacer()
            ],
          ),
          // Zones
          _buildZone("Zone A", 20, 30, ["Ali S.", "Usman B."], Colors.green),
          _buildZone("Zone B", 140, 30, ["Faisal K."], Colors.orange),
          _buildZone("Zone C", 20, 110, ["Zain A."], Colors.red),
          _buildZone("Zone D", 240, 30, ["Hamza R."], Colors.green),
          
          // Live Indicator
          Positioned(
            right: 15,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.circle, size: 6, color: Colors.green),
                  const SizedBox(width: 6),
                  Text(
                    "Live - Firebase",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZone(String name, double left, double top, List<String> workers, Color color) {
    return Positioned(
      left: left,
      top: top,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9),
          ),
          const SizedBox(height: 8),
          Row(
            children: workers
                .map((w) => Padding(
                      padding: const EdgeInsets.only(right: 15),
                      child: Column(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            w,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _LocationTile extends StatelessWidget {
  final String name, id, coords, zone, status;
  final Color color;
  const _LocationTile({
    required this.name,
    required this.id,
    required this.coords,
    required this.zone,
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
                  "$name • $id",
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                ),
                Text(
                  "$coords • $zone",
                  style: TextStyle(
                    fontSize: 10,
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
