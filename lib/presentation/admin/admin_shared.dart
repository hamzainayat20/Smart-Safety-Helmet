import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/admin_repository.dart';
import '../../domain/repositories.dart';
import '../design_system/design_system.dart';

/// Human-readable message for an admin failure.
String adminErrorMessage(Object error) {
  if (error is RepositoryAccessException) return error.message;
  return 'Something went wrong. Try again.';
}

/// The standard admin page frame: dark header on ink, light work surface.
/// Mirrors the frame used by the supervisor and worker shells.
class AdminPageFrame extends StatelessWidget {
  const AdminPageFrame({
    super.key,
    required this.title,
    required this.child,
    this.eyebrow,
    this.subtitle,
    this.titleSuffix,
    this.actions = const [],
    this.headerBottom,
    this.compact = false,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Widget? titleSuffix;
  final List<Widget> actions;
  final Widget? headerBottom;
  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPageHeader(
          title: title,
          eyebrow: eyebrow,
          subtitle: subtitle,
          titleSuffix: titleSuffix,
          actions: actions,
          bottom: headerBottom,
          compact: compact,
        ),
        Expanded(child: ContentSheet(child: child)),
      ],
    ),
  );
}

/// Scaffold for screens pushed on top of the console (edit forms, detail).
class AdminSubScreen extends StatelessWidget {
  const AdminSubScreen({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.ink,
    body: AdminPageFrame(
      title: title,
      subtitle: subtitle,
      compact: true,
      actions: actions,
      child: child,
    ),
  );
}

void showAdminMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> showAdminConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: destructive
              ? TextButton.styleFrom(
                  foregroundColor: SafetyStatus.critical.palette.text,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Shows a device secret exactly once. The value exists only in this sheet;
/// leaving it discards the only copy the app will ever display.
Future<void> showDeviceSecretSheet(
  BuildContext context, {
  required String helmetId,
  required HelmetSecretResult secret,
  required String intro,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  isDismissible: false,
  enableDrag: false,
  builder: (sheetContext) => Padding(
    padding: EdgeInsets.only(
      left: AppSpacing.md,
      right: AppSpacing.md,
      top: AppSpacing.lg,
      bottom: MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.lg,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.key_rounded,
              size: AppSizes.iconLg,
              color: SafetyStatus.warning.palette.strong,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Device secret for $helmetId',
                style: AppTypography.subtitle.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(intro, style: AppTypography.body),
        const SizedBox(height: AppSpacing.sm),
        const ResultBanner(
          succeeded: false,
          message:
              'This secret is shown exactly once and cannot be retrieved '
              'again. Store it in the helmet\'s secrets header now — if it '
              'is lost, rotate the secret to issue a new one.',
        ),
        const SizedBox(height: AppSpacing.md),
        KeyValueRow(label: 'Key version', value: secret.keyVersion),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.border),
          ),
          child: SelectableText(
            secret.secretBase64,
            style: AppTypography.body.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: 'Copy secret',
          icon: Icons.copy_rounded,
          variant: AppButtonVariant.secondary,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: secret.secretBase64));
            if (sheetContext.mounted) {
              showAdminMessage(sheetContext, 'Secret copied.');
            }
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: 'I have stored it',
          icon: Icons.check_rounded,
          onPressed: () => Navigator.of(sheetContext).pop(),
        ),
      ],
    ),
  ),
);

/// Multi-select over `(id, label)` options, rendered as chips with a picker
/// sheet. Used for site assignments, authorized helmets and supervisors.
class MultiSelectField extends StatelessWidget {
  const MultiSelectField({
    super.key,
    required this.label,
    required this.options,
    required this.selectedIds,
    required this.onChanged,
    this.emptyOptionsMessage = 'No options available.',
  });

  final String label;
  final List<(String id, String label)> options;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;
  final String emptyOptionsMessage;

  @override
  Widget build(BuildContext context) {
    final selectedLabels = [
      for (final option in options)
        if (selectedIds.contains(option.$1)) option.$2,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: AppTypography.label.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (selectedLabels.isEmpty)
          Text(
            'None selected',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          )
        else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final text in selectedLabels)
                Chip(
                  label: Text(text),
                  labelStyle: AppTypography.label,
                  backgroundColor: AppColors.surfaceSunken,
                  side: const BorderSide(color: AppColors.border),
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: 'Choose',
          icon: Icons.checklist_rounded,
          variant: AppButtonVariant.secondary,
          onPressed: options.isEmpty ? null : () => _openPicker(context),
        ),
        if (options.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              emptyOptionsMessage,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final working = Set<String>.of(selectedIds);
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Text(label, style: AppTypography.subtitle),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final option in options)
                      CheckboxListTile(
                        value: working.contains(option.$1),
                        title: Text(option.$2),
                        subtitle: Text(option.$1),
                        onChanged: (checked) => setSheetState(() {
                          if (checked ?? false) {
                            working.add(option.$1);
                          } else {
                            working.remove(option.$1);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: AppButton(
                  label: 'Done',
                  onPressed: () => Navigator.of(sheetContext).pop(working),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null) onChanged(result);
  }
}
