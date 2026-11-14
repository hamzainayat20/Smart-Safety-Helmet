import 'package:flutter/material.dart';

import '../application/dashboard_view_model.dart';

/// Confirms, then acknowledges [alertId] through the existing
/// [DashboardViewModel.acknowledge]. Shared by every screen that offers the
/// action so the wording and backend call stay identical.
Future<void> confirmAndAcknowledgeAlert(
  BuildContext context, {
  required DashboardViewModel viewModel,
  required String alertId,
}) async {
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
    await viewModel.acknowledge(alertId);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Alert acknowledged.')));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Acknowledgement failed: $error')),
      );
    }
  }
}
