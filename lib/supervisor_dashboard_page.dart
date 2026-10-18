import 'package:flutter/material.dart';

import 'application/dashboard_view_model.dart';
import 'domain/models.dart';
import 'presentation/formatters.dart';
import 'presentation/monitoring_state.dart';

class SupervisorDashboardPage extends StatelessWidget {
  const SupervisorDashboardPage({
    super.key,
    required this.viewModel,
    required this.onSignOut,
  });

  final DashboardViewModel viewModel;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (context, _) => SafeArea(
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
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (viewModel.loadState == MonitoringState.loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF2F80ED)),
      );
    }
    if (viewModel.loadState == MonitoringState.permissionDenied ||
        viewModel.loadState == MonitoringState.backendError) {
      return MonitoringStatePanel(
        state: viewModel.loadState,
        title: viewModel.loadState == MonitoringState.permissionDenied
            ? 'Monitoring permission denied'
            : 'Monitoring backend unavailable',
        message: viewModel.errorMessage,
        onRetry: viewModel.retry,
      );
    }
    if (viewModel.helmets.isEmpty) {
      return const MonitoringStatePanel(
        state: MonitoringState.empty,
        title: 'No assigned helmets',
        message: 'No helmets are assigned to this supervisor.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildStatsGrid(),
        const SizedBox(height: 25),
        const Text(
          'Worker Status',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 15),
        ...viewModel.sortedHelmets.map((helmet) {
          final updatedAt = viewModel.lastUpdateFor(helmet);
          return _WorkerTile(
            name: viewModel.workerNameFor(helmet),
            subtitle:
                '${viewModel.siteNameFor(helmet)} • ${helmet.zone ?? 'Zone unavailable'} • '
                'Helmet #${helmet.helmetId}\n'
                '${updatedAt == null ? 'Never updated' : 'Last update ${formatRelativeTime(updatedAt)}'}',
            status: viewModel.stateLabelFor(helmet),
            state: viewModel.monitoringStateFor(helmet),
          );
        }),
      ],
    );
  }

  Widget _buildHeader() {
    final profile = viewModel.profile;
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 20, 25, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Welcome back,',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
              IconButton(
                onPressed: onSignOut,
                icon: const Icon(Icons.logout, color: Colors.white, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Flexible(
                child: Text(
                  profile.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Text(
                ' — Supervisor',
                style: TextStyle(
                  color: Color(0xFF2F80ED),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Text(
            'Site: ${profile.organizationName ?? 'Not assigned'} • ${viewModel.dataSourceLabel}',
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

  Widget _buildStatsGrid() => GridView.count(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    crossAxisCount: 2,
    childAspectRatio: 2.2,
    mainAxisSpacing: 12,
    crossAxisSpacing: 12,
    children: [
      _StatCard(
        title: 'Workers Online',
        value: viewModel.statisticsAreLive
            ? '${viewModel.onlineHelmetCount}/${viewModel.activeHelmets.length}'
            : '—',
        color: Colors.green,
        icon: Icons.circle,
      ),
      _StatCard(
        title: 'Active Alerts',
        value: viewModel.statisticsAreLive
            ? '${viewModel.activeAlertCount}'
            : '—',
        color: Colors.red,
        icon: Icons.error,
      ),
      _StatCard(
        title: 'Helmets Active',
        value: viewModel.statisticsAreLive
            ? '${viewModel.activeHelmets.length}'
            : '—',
        color: const Color(0xFF2F80ED),
        icon: Icons.badge,
      ),
      _StatCard(
        title: 'Low Battery',
        value: viewModel.statisticsAreLive
            ? '${viewModel.lowBatteryCount}'
            : '—',
        color: Colors.orange,
        icon: Icons.battery_alert,
      ),
    ],
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
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
                '/${value.split('/')[1]}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black.withValues(alpha: 0.3),
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
                color: Colors.black.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _WorkerTile extends StatelessWidget {
  const _WorkerTile({
    required this.name,
    required this.subtitle,
    required this.status,
    required this.state,
  });
  final String name;
  final String subtitle;
  final String status;
  final MonitoringState state;

  @override
  Widget build(BuildContext context) {
    final color = monitoringStateColor(state);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.black.withValues(alpha: 0.5),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
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
          ),
        ],
      ),
    );
  }
}
