import 'package:flutter/material.dart';

import 'application/alert_detail_view_model.dart';
import 'application/app_dependencies.dart';
import 'domain/models.dart';
import 'presentation/design_system/design_system.dart';
import 'presentation/formatters.dart';
import 'presentation/monitoring_state.dart';
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
    backgroundColor: AppColors.ink,
    body: SafeArea(
      bottom: false,
      child: AnimatedBuilder(
        animation: _viewModel,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPageHeader(
              title: 'Alert Detail',
              compact: true,
              subtitle: 'Authenticated incident record',
              leading: HeaderIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Expanded(child: ContentSheet(child: _body(context))),
          ],
        ),
      ),
    ),
  );

  Widget _body(BuildContext context) {
    if (_viewModel.isLoading) {
      return const StateView(
        kind: StateViewKind.loading,
        title: 'Loading incident',
        message: 'Fetching the authenticated alert record…',
      );
    }
    final alert = _viewModel.alert;
    if (alert == null) {
      return StateView(
        kind: _viewModel.permissionDenied
            ? StateViewKind.permissionDenied
            : StateViewKind.empty,
        title: _viewModel.permissionDenied
            ? 'Access denied'
            : 'Alert unavailable',
        message:
            _viewModel.errorMessage ??
            'This alert does not exist or is outside your assigned scope.',
      );
    }
    final status = safetyStatusForSeverity(alert.severity);
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final content = ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        AppCard(
          status: status,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconTile(
                    icon: alertTypeIcon(alert.type),
                    status: status,
                    size: AppSizes.touchTarget,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alertTypeLabel(alert.type),
                          style: AppTypography.title.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Received ${formatRelativeTime(alert.serverReceivedAt)}',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              StatusChip(
                status: status,
                label: alert.severity.name.toUpperCase(),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Divider(),
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
        const SizedBox(height: AppSpacing.md),
        _section(
          title: 'Response timeline',
          icon: Icons.timeline_rounded,
          children: [_LifecycleTimeline(alert: alert)],
        ),
        const SizedBox(height: AppSpacing.md),
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
        const SizedBox(height: AppSpacing.md),
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
              value: _deliveryStatus(alert),
            ),
            _DetailRow(
              label: 'Viewed',
              value: alert.viewedAt == null
                  ? 'Not recorded'
                  : '${_utc(alert.viewedAt!)} by ${alert.viewedBy}',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _section(
          title: 'Location',
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
                value: alert.location!.source == 'phoneGps'
                    ? 'Phone GPS'
                    : alert.location!.isLastKnown
                    ? 'Last known location'
                    : 'Incident-time fix',
              ),
              if (alert.location!.accuracyM != null)
                _DetailRow(
                  label: 'Accuracy',
                  value:
                      '${alert.location!.accuracyM!.toStringAsFixed(0)} m',
                ),
            ],
            const Divider(),
            if (_viewModel.latestPhoneLocation == null)
              const _DetailRow(
                label: 'Latest phone location',
                value: 'Location unavailable',
              )
            else ...[
              _DetailRow(
                label: 'Latest phone location',
                value:
                    '${_viewModel.latestPhoneLocation!.latitudeDegrees.toStringAsFixed(5)}, '
                    '${_viewModel.latestPhoneLocation!.longitudeDegrees.toStringAsFixed(5)}',
              ),
              _DetailRow(
                label: 'Phone GPS updated',
                value: _utc(_viewModel.latestPhoneLocation!.updatedAt),
              ),
              _DetailRow(
                label: 'Accuracy',
                value:
                    '${_viewModel.latestPhoneLocation!.accuracyM.toStringAsFixed(0)} m',
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.md),
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
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: SafetyStatus.critical.palette.tint,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: SafetyStatus.critical.palette.line),
            ),
            child: Text(
              _viewModel.errorMessage!,
              key: const Key('alert-operation-error'),
              style: AppTypography.label.copyWith(
                color: SafetyStatus.critical.palette.text,
              ),
            ),
          ),
        ],
        if (!isMobile && widget.profile.role != UserRole.worker) ...[
          const SizedBox(height: AppSpacing.lg),
          _responseActions(context, alert),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Acknowledgement records that the incident was seen. It never changes the original evidence or marks an ongoing hazard safe.',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
    if (!isMobile || widget.profile.role == UserRole.worker) return content;
    return Column(
      children: [
        Expanded(child: content),
        _PinnedActions(child: _responseActions(context, alert, compact: true)),
      ],
    );
  }

  Widget _responseActions(
    BuildContext context,
    SafetyAlert alert, {
    bool compact = false,
  }) {
    final actions = <Widget>[
      if (_viewModel.canAcknowledge)
        AppButton(
          key: const Key('acknowledge-alert-button'),
          label: _viewModel.isAcknowledging
              ? 'Confirming with backend...'
              : 'Acknowledge',
          icon: Icons.done_rounded,
          loading: _viewModel.isAcknowledging,
          onPressed: () => _confirmAcknowledgement(context),
        ),
      if (alert.status == AlertStatus.acknowledged)
        AppButton(
          label: _viewModel.isResolving
              ? 'Checking hazard...'
              : 'Resolve after clear',
          icon: Icons.health_and_safety_outlined,
          variant: AppButtonVariant.secondary,
          loading: _viewModel.isResolving,
          onPressed: () => _requestResolution(context),
        ),
      if (alert.deliveredAt == null)
        AppButton(
          label: _viewModel.isRetryingDelivery
              ? 'Retrying...'
              : 'Retry notification',
          icon: Icons.refresh_rounded,
          variant: AppButtonVariant.secondary,
          loading: _viewModel.isRetryingDelivery,
          onPressed: () => _retryDelivery(context),
        ),
    ];
    if (actions.isEmpty) {
      return Text(
        'No response action is currently required.',
        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
      );
    }
    if (!compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.sm),
            SizedBox(height: 56, child: actions[index]),
          ],
        ],
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            if (index > 0) const SizedBox(width: AppSpacing.sm),
            SizedBox(height: AppSizes.touchTarget, child: actions[index]),
          ],
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: AppSizes.iconMd, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: AppTypography.subtitle.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        const Divider(),
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
    // The dialog owns its TextEditingController and disposes it in its own
    // State.dispose(), after the close animation has finished. Disposing it
    // here right after showDialog returned crashed while the TextField was
    // still mounted ('_dependents.isEmpty' assertion).
    final note = await showDialog<String>(
      context: context,
      builder: (_) => const _ResolutionNoteDialog(),
    );
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

class _ResolutionNoteDialog extends StatefulWidget {
  const _ResolutionNoteDialog();

  @override
  State<_ResolutionNoteDialog> createState() => _ResolutionNoteDialogState();
}

class _ResolutionNoteDialogState extends State<_ResolutionNoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Resolve incident?'),
    content: TextField(
      key: const Key('resolution-note-field'),
      controller: _controller,
      maxLength: 500,
      decoration: const InputDecoration(
        labelText: 'Resolution note',
        hintText: 'Describe the verified response and cleared condition',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Check and resolve'),
      ),
    ],
  );
}

class _PinnedActions extends StatelessWidget {
  const _PinnedActions({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: child,
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => KeyValueRow(label: label, value: value);
}

/// Lifecycle built only from timestamps already on the alert record.
class _LifecycleTimeline extends StatelessWidget {
  const _LifecycleTimeline({required this.alert});

  final SafetyAlert alert;

  @override
  Widget build(BuildContext context) {
    final steps = <(String, DateTime?, IconData, String)>[
      ('Raised', alert.serverReceivedAt, Icons.notification_add_outlined, ''),
      ('Delivered', alert.deliveredAt, Icons.send_outlined, _deliveryStatus(alert)),
      ('Seen', alert.viewedAt, Icons.visibility_outlined, 'Pending'),
      ('Acknowledged', alert.acknowledgedAt, Icons.task_alt_rounded, 'Pending'),
      ('Closed', alert.resolvedAt, Icons.verified_outlined, 'Pending'),
    ];
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _TimelineStep(
            label: steps[i].$1,
            at: steps[i].$2,
            icon: steps[i].$3,
            incompleteLabel: steps[i].$4,
            isLast: i == steps.length - 1,
            nextDone: i < steps.length - 1 && steps[i + 1].$2 != null,
          ),
      ],
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.label,
    required this.at,
    required this.icon,
    required this.isLast,
    required this.nextDone,
    required this.incompleteLabel,
  });

  final String label;
  final DateTime? at;
  final IconData icon;
  final bool isLast;
  final bool nextDone;
  final String incompleteLabel;

  @override
  Widget build(BuildContext context) {
    final time = at;
    final done = time != null;
    return MergeSemantics(
      child: SizedBox(
        height: isLast ? 40 : 56,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 32,
              child: Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: done ? AppColors.ink : AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: done ? AppColors.ink : AppColors.borderControl,
                      ),
                    ),
                    child: Icon(
                      done ? icon : Icons.more_horiz_rounded,
                      size: AppSizes.iconSm,
                      color: done ? AppColors.onInk : AppColors.textSecondary,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: done && nextDone
                            ? AppColors.ink
                            : AppColors.border,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: AppTypography.label.copyWith(
                          color: done
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      time != null ? formatRelativeTime(time) : incompleteLabel,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
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
}

String _utc(DateTime value) => formatUtcTimestamp(value);

String _deliveryStatus(SafetyAlert alert) {
  if (alert.deliveredAt != null) return _utc(alert.deliveredAt!);
  return formatAlertDeliveryStatus(alert);
}

String _evidenceLabel(String value) => value
    .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}')
    .replaceAll('_', ' ')
    .trim();
