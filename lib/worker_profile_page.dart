import 'package:flutter/material.dart';

import 'application/dashboard_view_model.dart';
import 'domain/models.dart';
import 'presentation/formatters.dart';

class WorkerProfilePage extends StatelessWidget {
  const WorkerProfilePage({
    super.key,
    required this.viewModel,
    required this.onSignOut,
  });

  final DashboardViewModel viewModel;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
    builder: (context, _) {
      final profile = viewModel.profile;
      final helmet = viewModel.helmets.firstOrNull;
      final reading = helmet == null
          ? null
          : viewModel.readingFor(helmet.helmetId);
      final initials = profile.displayName
          .split(' ')
          .where((part) => part.isNotEmpty)
          .take(2)
          .map((part) => part[0])
          .join()
          .toUpperCase();
      return Scaffold(
        backgroundColor: const Color(0xFF07152C),
        body: SafeArea(
          child: Column(
            children: [
              _header(
                profile.displayName,
                profile.organizationName ?? 'Not assigned',
                initials,
                helmet,
              ),
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
                      _quickStats(helmet, reading),
                      const SizedBox(height: 20),
                      _section('Personal Info', [
                        _InfoRow(
                          Icons.person_outline,
                          'Full Name',
                          profile.displayName,
                        ),
                        _InfoRow(
                          Icons.email_outlined,
                          'Work Email',
                          profile.email,
                        ),
                        _InfoRow(
                          Icons.badge_outlined,
                          'User ID',
                          _shortId(profile.uid),
                        ),
                        _InfoRow(
                          Icons.business_outlined,
                          'Site / Organization',
                          profile.organizationName ?? 'Not assigned',
                        ),
                      ]),
                      const SizedBox(height: 20),
                      _section('Assigned Helmet', [
                        _InfoRow(
                          Icons.engineering,
                          'Helmet ID',
                          helmet?.helmetId ?? 'Not assigned',
                          trailing: helmet?.active == true ? 'Active' : null,
                        ),
                        _InfoRow(
                          Icons.battery_std,
                          'Battery',
                          formatMeasurement(
                            reading?.batteryPct,
                            SensorUnit.percent,
                            fractionDigits: 0,
                          ),
                        ),
                        _InfoRow(
                          Icons.wifi,
                          'Connectivity',
                          reading?.connectivity.name ?? 'Unavailable',
                        ),
                      ]),
                      const SizedBox(height: 20),
                      _section('Notification Settings', [
                        _SwitchRow(
                          Icons.notifications_none,
                          'Push Alerts',
                          'Receive safety alerts instantly',
                          profile.pushAlertsEnabled,
                          (value) => viewModel.updateNotificationPreferences(
                            pushAlertsEnabled: value,
                          ),
                        ),
                        _SwitchRow(
                          Icons.warning_amber_rounded,
                          'Critical Alerts Only',
                          'Suppress non-critical warning notifications',
                          profile.criticalAlertsOnly,
                          (value) => viewModel.updateNotificationPreferences(
                            criticalAlertsOnly: value,
                          ),
                        ),
                        _SwitchRow(
                          Icons.vibration,
                          'Vibration',
                          'Haptic feedback on alerts',
                          profile.vibrationEnabled,
                          (value) => viewModel.updateNotificationPreferences(
                            vibrationEnabled: value,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 30),
                      OutlinedButton(
                        onPressed: onSignOut,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.logout_rounded, size: 20),
                            SizedBox(width: 10),
                            Text(
                              'Sign Out',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
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
    },
  );

  String _shortId(String uid) => uid.length <= 8 ? uid : uid.substring(0, 8);

  Widget _header(String name, String site, String initials, Helmet? helmet) =>
      Column(
        children: [
          const SizedBox(height: 20),
          CircleAvatar(
            radius: 40,
            backgroundColor: const Color(0xFF2F80ED),
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            'Worker • $site',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: (helmet == null ? Colors.grey : Colors.green).withValues(
                alpha: 0.15,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: (helmet == null ? Colors.grey : Colors.green).withValues(
                  alpha: 0.3,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.circle,
                  color: helmet == null ? Colors.grey : Colors.green,
                  size: 8,
                ),
                const SizedBox(width: 8),
                Text(
                  helmet == null
                      ? 'No helmet assigned'
                      : 'Assigned • ${viewModel.dataSourceLabel}',
                  style: TextStyle(
                    color: helmet == null ? Colors.grey : Colors.green,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _quickStats(Helmet? helmet, SensorReading? reading) => Row(
    children: [
      Expanded(
        child: _StatBox(
          reading?.severity.name ?? 'Unavailable',
          'Safety State',
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _StatBox(
          reading == null
              ? 'Unavailable'
              : formatRelativeTime(reading.serverReceivedAt),
          'Last Update',
        ),
      ),
      const SizedBox(width: 12),
      Expanded(child: _StatBox(helmet?.helmetId ?? 'None', 'My Helmet')),
    ],
  );

  Widget _section(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );
}

class _StatBox extends StatelessWidget {
  const _StatBox(this.value, this.label);
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
    ),
    child: Column(
      children: [
        FittedBox(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.black38,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.label, this.value, {this.trailing});
  final IconData icon;
  final String label;
  final String value;
  final String? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF2F80ED)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.black38,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              trailing!,
              style: const TextStyle(
                color: Colors.green,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
      ],
    ),
  );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow(this.icon, this.label, this.sub, this.value, this.onChanged);
  final IconData icon;
  final String label;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Icon(icon, size: 20, color: Colors.black45),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              Text(
                sub,
                style: const TextStyle(color: Colors.black38, fontSize: 10),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: const Color(0xFF2F80ED),
        ),
      ],
    ),
  );
}
