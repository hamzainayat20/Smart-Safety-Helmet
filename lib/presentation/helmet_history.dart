import 'package:flutter/widgets.dart';

import '../application/dashboard_view_model.dart';
import '../domain/models.dart';

/// Values of one sensor channel from [history], oldest first.
///
/// [history] is the real reading history from `ReadingRepository`; missing
/// and non-finite values are skipped rather than filled in.
List<double> trendSeries(
  List<SensorReading> history,
  num? Function(SensorReading reading) select,
) {
  final ordered = [...history]
    ..sort((a, b) => a.serverReceivedAt.compareTo(b.serverReceivedAt));
  final values = <double>[];
  for (final reading in ordered) {
    final value = select(reading)?.toDouble();
    if (value != null && value.isFinite) values.add(value);
  }
  return values;
}

/// Streams a helmet's recent reading history from the existing
/// `ReadingRepository.watchHelmetReadings` (read-only, scoped by the same
/// security rules as live readings).
///
/// Builds with an empty list while loading, when there is no history, or if
/// the read is refused — trends then simply do not appear.
class HelmetHistoryBuilder extends StatefulWidget {
  const HelmetHistoryBuilder({
    super.key,
    required this.viewModel,
    required this.helmetId,
    required this.builder,
  });

  final DashboardViewModel viewModel;
  final String helmetId;
  final Widget Function(BuildContext context, List<SensorReading> history)
  builder;

  @override
  State<HelmetHistoryBuilder> createState() => _HelmetHistoryBuilderState();
}

class _HelmetHistoryBuilderState extends State<HelmetHistoryBuilder> {
  late Stream<List<SensorReading>> _history;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant HelmetHistoryBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.helmetId != widget.helmetId ||
        oldWidget.viewModel != widget.viewModel) {
      _subscribe();
    }
  }

  void _subscribe() {
    _history = widget.viewModel.dependencies.readings.watchHelmetReadings(
      widget.viewModel.profile,
      widget.helmetId,
    );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<SensorReading>>(
    stream: _history,
    builder: (context, snapshot) => widget.builder(
      context,
      snapshot.hasError ? const [] : snapshot.data ?? const [],
    ),
  );
}
