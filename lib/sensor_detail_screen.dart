import 'package:flutter/material.dart';

import 'application/dashboard_view_model.dart';
import 'domain/models.dart';
import 'presentation/formatters.dart';
import 'presentation/monitoring_state.dart';
import 'presentation/safety_assessment_card.dart';

class SensorDetailScreen extends StatelessWidget {
  const SensorDetailScreen({
    super.key,
    required this.helmetId,
    required this.workerName,
    required this.viewModel,
  });

  final String helmetId;
  final String workerName;
  final DashboardViewModel viewModel;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
    builder: (context, _) {
      final helmet = viewModel.helmets
          .where((item) => item.helmetId == helmetId)
          .firstOrNull;
      final reading = viewModel.readingFor(helmetId);
      final state = helmet == null
          ? viewModel.loadState
          : viewModel.monitoringStateFor(helmet);
      return Scaffold(
        backgroundColor: const Color(0xFF07152C),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, reading, state),
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
                  child:
                      state == MonitoringState.loading ||
                          state == MonitoringState.permissionDenied ||
                          state == MonitoringState.backendError ||
                          reading == null
                      ? MonitoringStatePanel(
                          state: state,
                          title: state == MonitoringState.permissionDenied
                              ? 'Sensor permission denied'
                              : state == MonitoringState.backendError
                              ? 'Sensor backend unavailable'
                              : reading == null
                              ? 'No current reading'
                              : 'Loading sensor data',
                          message: viewModel.errorMessage,
                          onRetry:
                              state == MonitoringState.permissionDenied ||
                                  state == MonitoringState.backendError
                              ? viewModel.retry
                              : null,
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              SafetyAssessmentCard(
                                reading: reading,
                                assessment: viewModel.assessmentFor(helmetId),
                              ),
                              const SizedBox(height: 12),
                              _buildBatteryCard(reading),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _smallMetric(
                                      formatMeasurement(
                                        reading.temperatureC,
                                        SensorUnit.degreesCelsius,
                                      ),
                                      'Temperature (DHT22)',
                                      _sensorStatus(
                                        reading.temperatureC,
                                        40,
                                        50,
                                      ),
                                      Icons.thermostat,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _smallMetric(
                                      formatMeasurement(
                                        reading.humidityPct,
                                        SensorUnit.percentRelativeHumidity,
                                      ),
                                      'Humidity (DHT22)',
                                      _humidityStatus(reading.humidityPct),
                                      Icons.water_drop,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _smallMetric(
                                      formatMeasurement(
                                        reading.gasPpm,
                                        SensorUnit.partsPerMillion,
                                      ),
                                      'Gas Level (MQ-7)',
                                      reading.gasWarmUp
                                          ? 'Sensor Warming Up'
                                          : _sensorStatus(
                                              reading.gasPpm,
                                              100,
                                              200,
                                            ),
                                      Icons.cloud_outlined,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _smallMetric(
                                      _gpsValue(reading),
                                      'GPS Status',
                                      _gpsStatus(reading),
                                      Icons.location_on_outlined,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _motionCard(
                                reading,
                                viewModel.hasActiveAlert(
                                  helmetId,
                                  AlertType.fall,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _buildHeader(
    BuildContext context,
    SensorReading? reading,
    MonitoringState state,
  ) => Padding(
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
                '$helmetId - $workerName',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Sensor Data',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          reading == null
              ? '${_stateLabel(state)} • ${viewModel.dataSourceLabel}'
              : '${_stateLabel(state)} • Last update '
                    '${formatRelativeTime(reading.serverReceivedAt)} • '
                    '${viewModel.dataSourceLabel}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
          ),
        ),
      ],
    ),
  );

  Widget _buildBatteryCard(SensorReading reading) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
    ),
    child: Column(
      children: [
        Text(
          'DEVICE BATTERY',
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.4),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          formatNumber(reading.batteryPct, fractionDigits: 0),
          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900),
        ),
        const Text(
          'percent',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Text(
          reading.batteryPct == null
              ? 'Battery reading unavailable'
              : 'Low-battery warning below 20%',
          style: const TextStyle(
            fontSize: 11,
            color: Colors.green,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  Widget _smallMetric(
    String value,
    String label,
    String status,
    IconData icon,
  ) {
    final color = status == 'Critical'
        ? Colors.red
        : status == 'Warning' || status == 'Sensor Warming Up'
        ? Colors.orange
        : status == 'Unavailable'
        ? Colors.grey
        : Colors.green;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.black.withValues(alpha: 0.2), size: 24),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.4),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            status,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _motionCard(SensorReading reading, bool activeFallAlert) => Container(
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
          'IMU / Motion (MPU6050)',
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.4),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _axis(reading.accelXG, 'Accel X'),
            _axis(reading.accelYG, 'Accel Y'),
            _axis(reading.accelZG, 'Accel Z'),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: (activeFallAlert ? Colors.red : Colors.green).withValues(
                  alpha: 0.1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    'Rule-based',
                    style: TextStyle(
                      color: activeFallAlert ? Colors.red : Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    activeFallAlert
                        ? 'Confirmed fall alert'
                        : 'No active fall alert',
                    style: TextStyle(
                      color: activeFallAlert ? Colors.red : Colors.green,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _axis(double? value, String label) => Padding(
    padding: const EdgeInsets.only(right: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatMeasurement(value, SensorUnit.standardGravity),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.4),
            fontSize: 9,
          ),
        ),
      ],
    ),
  );

  String _sensorStatus(double? value, double warning, double critical) {
    if (value == null) return 'Unavailable';
    if (value > critical) return 'Critical';
    if (value >= warning) return 'Warning';
    return 'Safe';
  }

  String _humidityStatus(double? value) {
    if (value == null) return 'Unavailable';
    if (value < 20 || value > 90) return 'Critical';
    if (value < 30 || value > 80) return 'Warning';
    return 'Safe';
  }

  String _gpsValue(SensorReading reading) => switch (reading.gpsStatus) {
    GpsStatus.valid when reading.location != null => 'Valid',
    GpsStatus.acquiring => 'Acquiring',
    GpsStatus.lost => 'Lost',
    GpsStatus.invalid || GpsStatus.valid => 'Unavailable',
  };

  String _gpsStatus(SensorReading reading) => switch (reading.gpsStatus) {
    GpsStatus.valid when reading.location != null =>
      reading.location!.isLastKnown ? 'Last known' : 'Current fix',
    GpsStatus.acquiring => 'Acquiring',
    GpsStatus.lost when reading.location?.isLastKnown == true => 'Last known',
    GpsStatus.lost => 'GPS lost',
    GpsStatus.invalid || GpsStatus.valid => 'Unavailable',
  };

  String _stateLabel(MonitoringState state) => switch (state) {
    MonitoringState.loading => 'Loading',
    MonitoringState.empty => 'No Data',
    MonitoringState.safe => 'Safe',
    MonitoringState.warning => 'Warning',
    MonitoringState.critical => 'Critical',
    MonitoringState.stale => 'Stale • Last known values',
    MonitoringState.offline => 'Offline',
    MonitoringState.sensorFault => 'Sensor Fault',
    MonitoringState.warmingUp => 'MQ135 Warming Up',
    MonitoringState.permissionDenied => 'Permission Denied',
    MonitoringState.backendError => 'Backend Error',
  };
}
