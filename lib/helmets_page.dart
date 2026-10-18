import 'package:flutter/material.dart';

import 'application/dashboard_view_model.dart';
import 'domain/models.dart';
import 'presentation/formatters.dart';
import 'presentation/monitoring_state.dart';
import 'sensor_detail_screen.dart';

class HelmetsPage extends StatelessWidget {
  const HelmetsPage({
    super.key,
    required this.viewModel,
    required this.onSignOut,
  });

  final DashboardViewModel viewModel;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
    builder: (context, _) => SafeArea(
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
              child: _buildBody(),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildBody() {
    if (viewModel.loadState == MonitoringState.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (viewModel.loadState == MonitoringState.permissionDenied ||
        viewModel.loadState == MonitoringState.backendError) {
      return MonitoringStatePanel(
        state: viewModel.loadState,
        title: viewModel.loadState == MonitoringState.permissionDenied
            ? 'Helmet permission denied'
            : 'Helmet backend unavailable',
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
      children: viewModel.sortedHelmets
          .map(
            (helmet) => _HelmetCard(
              helmet: helmet,
              workerName: viewModel.workerNameFor(helmet),
              reading: viewModel.readingFor(helmet.helmetId),
              stateLabel: viewModel.stateLabelFor(helmet),
              monitoringState: viewModel.monitoringStateFor(helmet),
              lastUpdatedAt: viewModel.lastUpdateFor(helmet),
              viewModel: viewModel,
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildHeader() {
    final active = viewModel.activeHelmets.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 20, 25, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Helmet Management',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
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
          Text(
            '${viewModel.helmets.length} registered • $active active • '
            '${viewModel.helmets.length - active} inactive • ${viewModel.dataSourceLabel}',
            style: const TextStyle(
              color: Color(0xFF77A6D7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() => Padding(
    padding: const EdgeInsets.fromLTRB(25, 20, 25, 0),
    child: TextField(
      decoration: InputDecoration(
        hintText: 'Search helmet ID or worker...',
        hintStyle: TextStyle(
          color: Colors.black.withValues(alpha: 0.3),
          fontSize: 13,
        ),
        prefixIcon: Icon(
          Icons.search,
          color: Colors.black.withValues(alpha: 0.3),
          size: 20,
        ),
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

class _HelmetCard extends StatelessWidget {
  const _HelmetCard({
    required this.helmet,
    required this.workerName,
    required this.reading,
    required this.stateLabel,
    required this.monitoringState,
    required this.lastUpdatedAt,
    required this.viewModel,
  });
  final Helmet helmet;
  final String workerName;
  final SensorReading? reading;
  final String stateLabel;
  final MonitoringState monitoringState;
  final DateTime? lastUpdatedAt;
  final DashboardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final statusColor = monitoringStateColor(monitoringState);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SensorDetailScreen(
            helmetId: helmet.helmetId,
            workerName: workerName,
            viewModel: viewModel,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.engineering, color: statusColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Helmet ${helmet.helmetId}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '$workerName • ${viewModel.siteNameFor(helmet)} • '
                        '${helmet.zone ?? 'Zone unavailable'}\n'
                        '${lastUpdatedAt == null ? 'Never updated' : 'Last update ${formatRelativeTime(lastUpdatedAt!)}'}',
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.5),
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    stateLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _metric(
                  formatMeasurement(
                    reading?.temperatureC,
                    SensorUnit.degreesCelsius,
                  ),
                  'Temp',
                  statusColor,
                ),
                _metric(
                  formatMeasurement(
                    reading?.humidityPct,
                    SensorUnit.percentRelativeHumidity,
                  ),
                  'Humidity',
                  statusColor,
                ),
                _battery(reading?.batteryPct),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String value, String label, Color color) => Column(
    children: [
      Text(
        value,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 15,
          color: color,
        ),
      ),
      Text(
        label,
        style: TextStyle(
          color: Colors.black.withValues(alpha: 0.4),
          fontSize: 10,
        ),
      ),
    ],
  );

  Widget _battery(int? value) {
    final color = value == null
        ? Colors.grey
        : value > 50
        ? Colors.green
        : value > 20
        ? Colors.orange
        : Colors.red;
    return Column(
      children: [
        Text(
          formatMeasurement(value, SensorUnit.percent, fractionDigits: 0),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        Text(
          'Battery',
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.4),
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 80,
          child: LinearProgressIndicator(
            value: value == null ? 0 : value / 100,
            backgroundColor: Colors.black.withValues(alpha: 0.05),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}
