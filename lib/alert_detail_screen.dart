import 'package:flutter/material.dart';

import 'application/alert_detail_view_model.dart';
import 'application/app_dependencies.dart';
import 'domain/models.dart';
import 'presentation/formatters.dart';
import 'user_role.dart';

class AlertDetailScreen extends StatefulWidget {
  const AlertDetailScreen({
    super.key,
    required this.profile,
    required this.alertId,
    required this.dependencies,
  });

  final UserProfile profile;
  final String alertId;
  final AppDependencies dependencies;

  @override
  State<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends State<AlertDetailScreen> {
  late final AlertDetailViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = AlertDetailViewModel(
      profile: widget.profile,
      alertId: widget.alertId,
      dependencies: widget.dependencies,
    )..start();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF07152C),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: _viewModel,
        builder: (context, _) => Column(
          children: [
            _header(context),
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
                child: _body(context),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _header(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 24, 18),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        const SizedBox(width: 4),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Alert Detail',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'Authenticated incident record',
                style: TextStyle(color: Color(0xFF77A6D7), fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _body(BuildContext context) {
    if (_viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final alert = _viewModel.alert;
    if (alert == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _viewModel.permissionDenied
                    ? Icons.lock_outline_rounded
                    : Icons.notification_important_outlined,
                size: 42,
                color: Colors.blueGrey,
              ),
              const SizedBox(height: 12),
              Text(
                _viewModel.permissionDenied
                    ? 'Access denied'
                    : 'Alert unavailable',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _viewModel.errorMessage ??
                    'This alert does not exist or is outside your assigned scope.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final color = alert.severity == SafetySeverity.critical
        ? Colors.red
        : Colors.orange;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border(left: BorderSide(color: color, width: 5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_iconFor(alert.type), color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      alertTypeLabel(alert.type),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _StatusPill(label: alert.severity.name, color: color),
                ],
              ),
              const SizedBox(height: 16),
              _DetailRow(label: 'Event ID', value: alert.eventId),
              _DetailRow(label: 'Helmet ID', value: alert.helmetId),
              _DetailRow(
                label: 'Worker reference',
                value: alert.workerId ?? 'Unassigned',
              ),
              _DetailRow(label: 'Site reference', value: alert.siteId),
              _DetailRow(label: 'Lifecycle', value: alert.status.name),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _section(
          title: 'Incident evidence',
          icon: Icons.analytics_outlined,
          children: [
            _DetailRow(
              label: 'Sensor value',
              value: alert.sensorValue == null || alert.unit == null
                  ? 'Not applicable'
                  : formatMeasurement(alert.sensorValue, alert.unit!),
            ),
            _DetailRow(
              label: 'Threshold',
              value: alert.threshold == null || alert.unit == null
                  ? 'Not applicable'
                  : formatMeasurement(alert.threshold, alert.unit!),
            ),
            ...alert.evidence.entries.map(
              (entry) => _DetailRow(
                label: _evidenceLabel(entry.key),
                value: entry.value?.toString() ?? 'Unavailable',
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _section(
          title: 'Timestamps and delivery',
          icon: Icons.schedule_outlined,
          children: [
            _DetailRow(
              label: 'Device time',
              value: _utc(alert.deviceTimestamp),
            ),
            _DetailRow(
              label: 'Server received',
              value: _utc(alert.serverReceivedAt),
            ),
            _DetailRow(
              label: 'Delivered',
              value: alert.deliveredAt == null
                  ? 'Remote delivery not confirmed'
                  : _utc(alert.deliveredAt!),
            ),
            _DetailRow(
              label: 'Viewed',
              value: alert.viewedAt == null
                  ? 'Not recorded'
                  : '${_utc(alert.viewedAt!)} by ${alert.viewedBy}',
            ),
          ],
        ),
        const SizedBox(height: 14),
        _section(
          title: 'GPS location',
          icon: Icons.location_on_outlined,
          children: [
            if (alert.location == null)
              const _DetailRow(
                label: 'Status',
                value: 'No valid incident location available',
              )
            else ...[
              _DetailRow(
                label: 'Coordinates',
                value:
                    '${alert.location!.latitudeDegrees.toStringAsFixed(5)}, '
                    '${alert.location!.longitudeDegrees.toStringAsFixed(5)}',
              ),
              _DetailRow(
                label: 'Captured',
                value: _utc(alert.location!.capturedAt),
              ),
              _DetailRow(
                label: 'Fix',
                value: alert.location!.isLastKnown
                    ? 'Last known location'
                    : 'Incident-time fix',
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        _section(
          title: 'Response audit',
          icon: Icons.fact_check_outlined,
          children: [
            _DetailRow(
              label: 'Acknowledged',
              value: alert.acknowledgedAt == null
                  ? 'Awaiting supervisor acknowledgement'
                  : '${_utc(alert.acknowledgedAt!)} by ${alert.acknowledgedBy}',
            ),
            _DetailRow(
              label: 'Resolved',
              value: alert.resolvedAt == null
                  ? 'Not resolved'
                  : '${_utc(alert.resolvedAt!)} by ${alert.resolvedBy}',
            ),
            if (alert.resolutionNote != null)
              _DetailRow(
                label: 'Resolution note',
                value: alert.resolutionNote!,
              ),
          ],
        ),
        if (_viewModel.errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _viewModel.errorMessage!,
            key: const Key('alert-operation-error'),
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (widget.profile.role != UserRole.worker) ...[
          const SizedBox(height: 18),
          if (_viewModel.canAcknowledge)
            FilledButton.icon(
              key: const Key('acknowledge-alert-button'),
              onPressed: _viewModel.isAcknowledging
                  ? null
                  : () => _confirmAcknowledgement(context),
              icon: _viewModel.isAcknowledging
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.done_rounded),
              label: Text(
                _viewModel.isAcknowledging
                    ? 'Confirming with backend...'
                    : 'Acknowledge',
              ),
            ),
          if (alert.status == AlertStatus.acknowledged) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _viewModel.isResolving
                  ? null
                  : () => _requestResolution(context),
              icon: const Icon(Icons.health_and_safety_outlined),
              label: Text(
                _viewModel.isResolving
                    ? 'Checking live hazard state...'
                    : 'Resolve after hazard clears',
              ),
            ),
          ],
          if (alert.deliveredAt == null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _viewModel.isRetryingDelivery
                  ? null
                  : () => _retryDelivery(context),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(
                _viewModel.isRetryingDelivery
                    ? 'Retrying notification...'
                    : 'Retry supervisor notification',
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Acknowledgement records that the incident was seen. It never changes the original evidence or marks an ongoing hazard safe.',
            style: TextStyle(color: Colors.black54, fontSize: 12, height: 1.35),
          ),
        ],
      ],
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 19, color: const Color(0xFF2F80ED)),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        const Divider(height: 24),
        ...children,
      ],
    ),
  );

  Future<void> _confirmAcknowledgement(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Acknowledge alert?'),
        content: const Text(
          'This records that you have seen the incident. It does not mark the physical hazard as resolved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Acknowledge'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await _viewModel.acknowledge();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Acknowledgement confirmed by backend.'),
          ),
        );
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Acknowledgement failed; the alert remains unacknowledged.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _requestResolution(BuildContext context) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resolve incident?'),
        content: TextField(
          controller: controller,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Resolution note',
            hintText: 'Describe the verified response and cleared condition',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Check and resolve'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null || note.isEmpty || !context.mounted) return;
    try {
      await _viewModel.resolve(note);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Resolution confirmed by backend.')),
        );
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_viewModel.errorMessage ?? 'Resolution failed.'),
          ),
        );
      }
    }
  }

  Future<void> _retryDelivery(BuildContext context) async {
    try {
      await _viewModel.retryDelivery();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification delivery retry completed.'),
          ),
        );
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification delivery retry failed.')),
        );
      }
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(
            label,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 10),
    ),
  );
}

String _utc(DateTime value) => value.toUtc().toIso8601String();

String _evidenceLabel(String value) => value
    .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}')
    .replaceAll('_', ' ')
    .trim();

IconData _iconFor(AlertType type) => switch (type) {
  AlertType.temperature => Icons.thermostat_rounded,
  AlertType.humidity => Icons.water_drop_outlined,
  AlertType.battery => Icons.battery_alert_rounded,
  AlertType.fall => Icons.personal_injury_outlined,
  AlertType.sensorFault => Icons.sensors_off_outlined,
  AlertType.connectivity => Icons.wifi_off_outlined,
  AlertType.gas => Icons.warning_amber_rounded,
};
