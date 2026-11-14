import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'components/app_card.dart';
import 'components/status_chip.dart';
import 'design_system/app_tokens.dart';
import 'design_system/safety_status.dart';
import 'assessment_text.dart';
import 'formatters.dart';

class SafetyAssessmentCard extends StatelessWidget {
  const SafetyAssessmentCard({
    super.key,
    required this.reading,
    required this.assessment,
    this.compact = false,
  });

  final SensorReading? reading;
  final SafetyAssessment? assessment;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final current = assessment;
    final presentation = _presentation(current);
    final status = presentation.status;
    return AppCard(
      status: status,
      padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.psychology_outlined,
                size: AppSizes.iconLg,
                color: status.palette.strong,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'AI SAFETY ASSESSMENT',
                  style: AppTypography.overline.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusChip(status: status, label: presentation.label),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            presentation.message,
            style: AppTypography.body.copyWith(color: AppColors.textPrimary),
          ),
          if (!compact && current != null) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _EvidenceChip(
                  label: 'Fall',
                  value: current.fall.probability == null
                      ? _statusLabel(current.fall.status)
                      : '${(current.fall.probability! * 100).toStringAsFixed(1)}%',
                ),
                _EvidenceChip(
                  label: 'Gas',
                  value: current.gas.status == InferenceStatus.completed
                      ? _gasClassLabel(current.gas.gasClass)
                      : _statusLabel(current.gas.status),
                ),
                _EvidenceChip(
                  label: 'Assessed',
                  value: formatRelativeTime(current.assessedAt),
                ),
              ],
            ),
            if (current.reasonCodes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'WHY THIS RESULT',
                style: AppTypography.overline.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              for (final code in current.reasonCodes)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    describeReasonCode(code),
                    style: AppTypography.body.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
            ],
            if (current.recommendations.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'RECOMMENDED ACTIONS',
                style: AppTypography.overline.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              for (final recommendation in current.recommendations)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Icon(
                          Icons.arrow_right_rounded,
                          color: status.palette.strong,
                          size: AppSizes.iconMd,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          recommendation,
                          style: AppTypography.body.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  _AssessmentPresentation _presentation(SafetyAssessment? value) {
    if (reading == null) {
      return const _AssessmentPresentation(
        label: 'UNAVAILABLE',
        message: 'A current sensor reading is required before assessment.',
        status: SafetyStatus.unknown,
      );
    }
    if (value == null) {
      return const _AssessmentPresentation(
        label: 'PENDING',
        message: 'Waiting for an assessment of the current sensor event.',
        status: SafetyStatus.pending,
      );
    }
    if (value.status == InferenceStatus.error) {
      return const _AssessmentPresentation(
        label: 'ERROR',
        message: 'The assessment failed. Do not treat this result as safe.',
        status: SafetyStatus.critical,
      );
    }
    if (value.status == InferenceStatus.outOfDistribution ||
        value.gas.outOfDistribution) {
      return const _AssessmentPresentation(
        label: 'OUT OF RANGE',
        message: 'Sensor values are outside the model’s validated range.',
        status: SafetyStatus.warning,
      );
    }
    if (value.status == InferenceStatus.unavailable) {
      return const _AssessmentPresentation(
        label: 'UNAVAILABLE',
        message: 'There is not enough valid sensor data for an assessment.',
        status: SafetyStatus.unknown,
      );
    }
    if (value.status == InferenceStatus.pending) {
      return const _AssessmentPresentation(
        label: 'PENDING',
        message: 'The current sensor event is still being assessed.',
        status: SafetyStatus.pending,
      );
    }
    return switch (value.displayRisk) {
      AssessmentRisk.safe => const _AssessmentPresentation(
        label: 'SAFE',
        message: 'No modeled hazard was detected in the current event.',
        status: SafetyStatus.normal,
      ),
      AssessmentRisk.warning => const _AssessmentPresentation(
        label: 'WARNING',
        message: 'The current readings need attention. Follow site procedures.',
        status: SafetyStatus.warning,
      ),
      AssessmentRisk.critical => const _AssessmentPresentation(
        label: 'CRITICAL',
        message: 'A serious risk was detected. Take immediate approved action.',
        status: SafetyStatus.critical,
      ),
      AssessmentRisk.unknown => const _AssessmentPresentation(
        label: 'UNKNOWN',
        message: 'The available result is not sufficient to declare safety.',
        status: SafetyStatus.unknown,
      ),
    };
  }

  static String _statusLabel(InferenceStatus status) => switch (status) {
    InferenceStatus.pending => 'Pending',
    InferenceStatus.completed => 'Complete',
    InferenceStatus.unavailable => 'Unavailable',
    InferenceStatus.outOfDistribution => 'Out of range',
    InferenceStatus.error => 'Error',
  };

  static String _gasClassLabel(GasClass gasClass) => switch (gasClass) {
    GasClass.mixture => 'Mixture',
    GasClass.noGas => 'No gas',
    GasClass.perfume => 'Perfume',
    GasClass.smoke => 'Smoke',
    GasClass.unknown => 'Unknown',
  };
}

class _EvidenceChip extends StatelessWidget {
  const _EvidenceChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: AppSizes.chipHeight),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: AppColors.surfaceSunken,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      border: Border.all(color: AppColors.border),
    ),
    child: Text(
      '$label: $value',
      style: AppTypography.label.copyWith(color: AppColors.textPrimary),
    ),
  );
}

final class _AssessmentPresentation {
  const _AssessmentPresentation({
    required this.label,
    required this.message,
    required this.status,
  });

  final String label;
  final String message;
  final SafetyStatus status;
}
