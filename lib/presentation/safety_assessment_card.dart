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
                  'AI safety assessment',
                  style: AppTypography.bodyStrong.copyWith(
                    color: AppColors.textPrimary,
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
            for (final check in _checks(current))
              _CheckRow(check: check),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _EvidenceChip(
                  label: 'Assessed',
                  value: formatRelativeTime(current.assessedAt),
                ),
              ],
            ),
            if (current.reasonCodes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Why this result',
                style: AppTypography.label.copyWith(
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
                'Recommended actions',
                style: AppTypography.label.copyWith(
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
    // "Unavailable" only when no check produced a result at all. A missing
    // gas model (no MQ-135) must never hide a fall or environment result.
    if (value.status == InferenceStatus.unavailable &&
        value.fall.status != InferenceStatus.completed &&
        value.environmentStatus != InferenceStatus.completed) {
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
      AssessmentRisk.unknown when _isPartialCheck(value) =>
        const _AssessmentPresentation(
          label: 'PARTIAL CHECK',
          message:
              'No fall or environmental hazard was detected. Gas was not '
              'assessed, so the helmet is not marked safe.',
          status: SafetyStatus.unknown,
        ),
      AssessmentRisk.unknown => const _AssessmentPresentation(
        label: 'UNKNOWN',
        message: 'The available result is not sufficient to declare safety.',
        status: SafetyStatus.unknown,
      ),
    };
  }

  /// Fall and environment were assessed without a hazard; only gas is
  /// missing. This changes wording only: the result is still not "safe".
  static bool _isPartialCheck(SafetyAssessment value) =>
      _fallCheck(value).status == SafetyStatus.normal &&
      _environmentCheck(value).status == SafetyStatus.normal &&
      value.gas.status != InferenceStatus.completed;

  List<_Check> _checks(SafetyAssessment value) => [
    _fallCheck(value),
    _environmentCheck(value),
    _gasCheck(value, reading),
  ];

  static _Check _fallCheck(SafetyAssessment value) {
    final fall = value.fall;
    final probability = fall.probability;
    if (fall.status != InferenceStatus.completed || probability == null) {
      return const _Check(
        'Fall',
        'Not assessed — motion data unavailable',
        SafetyStatus.unknown,
      );
    }
    final percent = '${(probability * 100).toStringAsFixed(1)}%';
    final threshold = fall.threshold;
    return threshold != null && probability >= threshold
        ? _Check('Fall', 'Fall detected ($percent)', SafetyStatus.critical)
        : _Check('Fall', 'No fall detected ($percent)', SafetyStatus.normal);
  }

  static _Check _environmentCheck(SafetyAssessment value) {
    final risks = [
      value.temperatureRisk,
      value.humidityRisk,
      value.heatIndexRisk,
    ];
    if (value.environmentStatus != InferenceStatus.completed ||
        risks.contains(ComponentRisk.unavailable)) {
      if (risks.contains(ComponentRisk.critical)) {
        return const _Check('Environment', 'Critical', SafetyStatus.critical);
      }
      if (risks.contains(ComponentRisk.warning)) {
        return const _Check(
          'Environment',
          'Needs attention',
          SafetyStatus.warning,
        );
      }
      return const _Check(
        'Environment',
        'Not assessed — temperature/humidity sensor not reading',
        SafetyStatus.unknown,
      );
    }
    if (risks.contains(ComponentRisk.critical)) {
      return const _Check('Environment', 'Critical', SafetyStatus.critical);
    }
    if (risks.contains(ComponentRisk.warning)) {
      return const _Check('Environment', 'Needs attention', SafetyStatus.warning);
    }
    return const _Check('Environment', 'Normal', SafetyStatus.normal);
  }

  static _Check _gasCheck(SafetyAssessment value, SensorReading? reading) {
    final gas = value.gas;
    if (gas.status == InferenceStatus.completed &&
        gas.gasClass != GasClass.unknown) {
      return _Check('Gas', _gasClassLabel(gas.gasClass), switch (gas.gasClass) {
        GasClass.smoke => SafetyStatus.critical,
        GasClass.mixture => SafetyStatus.warning,
        _ => SafetyStatus.normal,
      });
    }
    final faults = reading?.sensorFaults ?? const <SensorFault>[];
    final reason = faults.contains(SensorFault.mq135ReadFailed)
        ? 'MQ-135 not fitted'
        : faults.contains(SensorFault.mq7ReadFailed)
        ? 'MQ-7 not reading'
        : gas.status == InferenceStatus.completed
        ? 'no classification produced'
        : 'gas sensors not ready';
    return _Check('Gas', 'Not assessed — $reason', SafetyStatus.unknown);
  }

  static String _gasClassLabel(GasClass gasClass) => switch (gasClass) {
    GasClass.mixture => 'Mixture',
    GasClass.noGas => 'No gas',
    GasClass.perfume => 'Perfume',
    GasClass.smoke => 'Smoke',
    GasClass.unknown => 'Unknown',
  };
}

final class _Check {
  const _Check(this.label, this.value, this.status);

  final String label;
  final String value;
  final SafetyStatus status;
}

/// One component of the assessment: a coloured marker plus plain text.
class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});

  final _Check check;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Icon(
            Icons.circle,
            size: 12,
            color: check.status.palette.strong,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            '${check.label}: ${check.value}',
            style: AppTypography.body.copyWith(color: AppColors.textPrimary),
          ),
        ),
      ],
    ),
  );
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
