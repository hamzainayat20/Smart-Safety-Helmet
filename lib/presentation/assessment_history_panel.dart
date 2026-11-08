import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';
import 'formatters.dart';

class AssessmentHistoryPanel extends StatefulWidget {
  const AssessmentHistoryPanel({
    super.key,
    required this.repository,
    required this.actor,
    required this.helmetId,
    this.maximumVisible = 5,
  });

  final AssessmentRepository repository;
  final UserProfile actor;
  final String helmetId;
  final int maximumVisible;

  @override
  State<AssessmentHistoryPanel> createState() => _AssessmentHistoryPanelState();
}

class _AssessmentHistoryPanelState extends State<AssessmentHistoryPanel> {
  late Stream<List<SafetyAssessment>> _history;

  @override
  void initState() {
    super.initState();
    _history = _watch();
  }

  @override
  void didUpdateWidget(covariant AssessmentHistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.actor.uid != widget.actor.uid ||
        oldWidget.helmetId != widget.helmetId) {
      _history = _watch();
    }
  }

  Stream<List<SafetyAssessment>> _watch() =>
      widget.repository.watchHelmetAssessments(widget.actor, widget.helmetId);

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'RECENT AI ASSESSMENTS',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<SafetyAssessment>>(
          stream: _history,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text(
                'Assessment history is temporarily unavailable.',
                style: TextStyle(color: Colors.red, fontSize: 12),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snapshot.data!.take(widget.maximumVisible).toList();
            if (items.isEmpty) {
              return const Text(
                'No assessment history yet.',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              );
            }
            return Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  _AssessmentHistoryRow(assessment: items[index]),
                  if (index != items.length - 1) const Divider(height: 20),
                ],
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _AssessmentHistoryRow extends StatelessWidget {
  const _AssessmentHistoryRow({required this.assessment});

  final SafetyAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final risk = assessment.displayRisk;
    final color = switch (risk) {
      AssessmentRisk.safe => Colors.green,
      AssessmentRisk.warning => Colors.orange,
      AssessmentRisk.critical => Colors.red,
      AssessmentRisk.unknown => Colors.grey,
    };
    final label = switch (risk) {
      AssessmentRisk.safe => 'SAFE',
      AssessmentRisk.warning => 'WARNING',
      AssessmentRisk.critical => 'CRITICAL',
      AssessmentRisk.unknown => 'UNKNOWN',
    };
    final gas = switch (assessment.gas.gasClass) {
      GasClass.mixture => 'Mixture',
      GasClass.noGas => 'No gas',
      GasClass.perfume => 'Perfume',
      GasClass.smoke => 'Smoke',
      GasClass.unknown => 'Unavailable',
    };
    final fall = assessment.fall.probability == null
        ? 'Unavailable'
        : '${(assessment.fall.probability! * 100).toStringAsFixed(1)}%';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fall: $fall • Gas: $gas',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${formatRelativeTime(assessment.assessedAt)} • '
                '${_utcTimestamp(assessment.assessedAt)}',
                style: const TextStyle(color: Colors.black54, fontSize: 10),
              ),
              if (assessment.recommendations.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  assessment.recommendations.first,
                  style: const TextStyle(fontSize: 10, height: 1.3),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

String _utcTimestamp(DateTime value) {
  final iso = value.toUtc().toIso8601String();
  return '${iso.substring(0, 19).replaceFirst('T', ' ')} UTC';
}
