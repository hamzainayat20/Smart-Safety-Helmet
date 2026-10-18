import 'package:flutter/material.dart';

import '../domain/models.dart';
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
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: presentation.color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_outlined, color: presentation.color),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'AI SAFETY ASSESSMENT',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: presentation.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  presentation.label,
                  style: TextStyle(
                    color: presentation.color,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            presentation.message,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          if (!compact && current != null) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
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
            if (current.recommendations.isNotEmpty) ...[
              const SizedBox(height: 14),
              for (final recommendation in current.recommendations)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.arrow_right_rounded,
                        color: presentation.color,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          recommendation,
                          style: const TextStyle(fontSize: 12, height: 1.3),
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
        color: Colors.grey,
      );
    }
    if (value == null) {
      return const _AssessmentPresentation(
        label: 'PENDING',
        message: 'Waiting for an assessment of the current sensor event.',
        color: Colors.blueGrey,
      );
    }
    if (value.status == InferenceStatus.error) {
      return const _AssessmentPresentation(
        label: 'ERROR',
        message: 'The assessment failed. Do not treat this result as safe.',
        color: Colors.red,
      );
    }
    if (value.status == InferenceStatus.outOfDistribution ||
        value.gas.outOfDistribution) {
      return const _AssessmentPresentation(
        label: 'OUT OF RANGE',
        message: 'Sensor values are outside the model’s validated range.',
        color: Colors.orange,
      );
    }
    if (value.status == InferenceStatus.unavailable) {
      return const _AssessmentPresentation(
        label: 'UNAVAILABLE',
        message: 'There is not enough valid sensor data for an assessment.',
        color: Colors.grey,
      );
    }
    if (value.status == InferenceStatus.pending) {
      return const _AssessmentPresentation(
        label: 'PENDING',
        message: 'The current sensor event is still being assessed.',
        color: Colors.blueGrey,
      );
    }
    return switch (value.displayRisk) {
      AssessmentRisk.safe => const _AssessmentPresentation(
        label: 'SAFE',
        message: 'No modeled hazard was detected in the current event.',
        color: Colors.green,
      ),
      AssessmentRisk.warning => const _AssessmentPresentation(
        label: 'WARNING',
        message: 'The current readings need attention. Follow site procedures.',
        color: Colors.orange,
      ),
      AssessmentRisk.critical => const _AssessmentPresentation(
        label: 'CRITICAL',
        message: 'A serious risk was detected. Take immediate approved action.',
        color: Colors.red,
      ),
      AssessmentRisk.unknown => const _AssessmentPresentation(
        label: 'UNKNOWN',
        message: 'The available result is not sufficient to declare safety.',
        color: Colors.grey,
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
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFF4F6FA),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      '$label: $value',
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
    ),
  );
}

final class _AssessmentPresentation {
  const _AssessmentPresentation({
    required this.label,
    required this.message,
    required this.color,
  });

  final String label;
  final String message;
  final Color color;
}
