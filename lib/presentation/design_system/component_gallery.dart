import 'package:flutter/material.dart';

import '../../domain/models.dart';
import 'design_system.dart';

/// Design review page showing every shared component in every state.
///
/// Uses fixed sample values for review only. It is not part of the app's
/// navigation, never touches Firebase, and labels its values as samples.
class ComponentGalleryPage extends StatelessWidget {
  const ComponentGalleryPage({super.key, this.referenceTime});

  /// Fixed clock for deterministic "updated" labels (tests pass one).
  final DateTime? referenceTime;

  @override
  Widget build(BuildContext context) {
    final now = (referenceTime ?? DateTime.now()).toUtc();
    final twoMinutesAgo = now.subtract(const Duration(minutes: 2));
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPageHeader(
              eyebrow: 'DESIGN SYSTEM',
              title: 'Component gallery',
              subtitle: 'Sample values for design review — not live data',
              leading: const BrandMark(size: AppSizes.touchTarget),
              actions: [
                HeaderIconButton(
                  icon: Icons.info_outline_rounded,
                  tooltip: 'About this page',
                  onPressed: () {},
                ),
              ],
            ),
            Expanded(
              child: ContentSheet(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    const SectionHeader(
                      title: 'Status roles',
                      subtitle: 'Colour, icon and text — never colour alone',
                    ),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final status in SafetyStatus.values)
                          StatusChip(status: status),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const SectionHeader(title: 'Typography'),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final entry in AppTypography.all.entries)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.sm,
                              ),
                              child: Text(
                                '${entry.key} · ${entry.value.fontSize!.round()}sp',
                                style: entry.value.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const SectionHeader(title: 'Sensor cards'),
                    ResponsiveTileGrid(
                      children: [
                        SensorCard(
                          label: 'Temperature',
                          icon: Icons.thermostat_rounded,
                          value: 31.2,
                          unit: SensorUnit.degreesCelsius,
                          status: SafetyStatus.normal,
                          updatedAt: twoMinutesAgo,
                          gauge: const ThresholdGauge(
                            value: 31.2,
                            max: 60,
                            warningAt: 40,
                            criticalAt: 50,
                            status: SafetyStatus.normal,
                            unit: ' °C',
                          ),
                        ),
                        SensorCard(
                          label: 'Gas level',
                          icon: Icons.air_rounded,
                          value: 142,
                          fractionDigits: 0,
                          unit: SensorUnit.partsPerMillion,
                          status: SafetyStatus.warning,
                          updatedAt: twoMinutesAgo,
                          gauge: const ThresholdGauge(
                            value: 142,
                            max: 300,
                            warningAt: 100,
                            criticalAt: 200,
                            status: SafetyStatus.warning,
                            unit: ' ppm',
                          ),
                        ),
                        SensorCard(
                          label: 'Humidity',
                          icon: Icons.water_drop_outlined,
                          value: 94,
                          fractionDigits: 0,
                          unit: SensorUnit.percentRelativeHumidity,
                          status: SafetyStatus.critical,
                          updatedAt: twoMinutesAgo,
                        ),
                        SensorCard(
                          label: 'Battery',
                          icon: Icons.battery_unknown_rounded,
                          value: null,
                          unit: SensorUnit.percent,
                          status: SafetyStatus.normal,
                        ),
                        SensorCard(
                          label: 'Temperature',
                          icon: Icons.thermostat_rounded,
                          value: 29.8,
                          unit: SensorUnit.degreesCelsius,
                          status: SafetyStatus.stale,
                          updatedAt: now.subtract(const Duration(minutes: 9)),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const SectionHeader(title: 'Metric tiles'),
                    const ResponsiveTileGrid(
                      children: [
                        MetricTile(
                          label: 'Workers online',
                          value: '4',
                          suffix: '/5',
                          icon: Icons.wifi_tethering_rounded,
                          status: SafetyStatus.normal,
                        ),
                        MetricTile(
                          label: 'Active alerts',
                          value: '2',
                          icon: Icons.notification_important_outlined,
                          status: SafetyStatus.critical,
                        ),
                        MetricTile(
                          label: 'Low battery',
                          value: null,
                          icon: Icons.battery_alert_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const SectionHeader(title: 'Buttons'),
                    AppButton(label: 'Acknowledge alert', onPressed: () {}),
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      label: 'View details',
                      icon: Icons.open_in_new_rounded,
                      variant: AppButtonVariant.secondary,
                      onPressed: () {},
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      label: 'Sign out',
                      icon: Icons.logout_rounded,
                      variant: AppButtonVariant.destructive,
                      onPressed: () {},
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      label: 'Confirming…',
                      loading: true,
                      onPressed: () {},
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const SectionHeader(title: 'Record rows'),
                    const AppCard(
                      child: Column(
                        children: [
                          KeyValueRow(label: 'Helmet ID', value: 'H-00'),
                          Divider(),
                          KeyValueRow(label: 'Firmware', value: 'sample'),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const SectionHeader(title: 'Screen states'),
                    for (final kind in StateViewKind.values)
                      StateView(
                        kind: kind,
                        title: _stateTitle(kind),
                        message: 'Sample message for the ${kind.name} state.',
                        onAction:
                            kind == StateViewKind.error ||
                                kind == StateViewKind.offline
                            ? () {}
                            : null,
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

  static String _stateTitle(StateViewKind kind) => switch (kind) {
    StateViewKind.loading => 'Loading',
    StateViewKind.empty => 'Nothing assigned',
    StateViewKind.error => 'Service unavailable',
    StateViewKind.offline => 'Connection lost',
    StateViewKind.stale => 'Showing last known values',
    StateViewKind.permissionDenied => 'Access denied',
  };
}
