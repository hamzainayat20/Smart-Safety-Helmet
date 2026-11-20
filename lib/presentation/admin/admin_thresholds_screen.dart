import 'package:flutter/material.dart';

import '../../data/admin_repository.dart';
import '../../domain/models.dart';
import '../design_system/design_system.dart';
import '../formatters.dart';
import 'admin_shared.dart';

/// Per-helmet threshold editor for `/config/helmets/{helmetId}`.
///
/// Validation mirrors the RTDB rules and the [HelmetConfiguration]
/// constructor: temperature warning < critical, humidity critical-low <
/// warning-low < warning-high < critical-high, gas warning < critical, and
/// the positive/zero bounds on the remaining fields. Invalid forms are
/// rejected locally and never reach the callable.
class AdminThresholdsScreen extends StatefulWidget {
  const AdminThresholdsScreen({
    super.key,
    required this.admin,
    required this.currentUser,
    required this.onSignOut,
  });

  final AdminRepository admin;
  final UserProfile currentUser;
  final VoidCallback onSignOut;

  @override
  State<AdminThresholdsScreen> createState() => _AdminThresholdsScreenState();
}

class _AdminThresholdsScreenState extends State<AdminThresholdsScreen> {
  String? _helmetId;
  String? _loadedFor;
  HelmetConfiguration? _loadedConfig;
  bool _saving = false;
  String? _error;
  String? _notice;

  final _temperatureWarning = TextEditingController();
  final _temperatureCritical = TextEditingController();
  final _humidityCriticalLow = TextEditingController();
  final _humidityWarningLow = TextEditingController();
  final _humidityWarningHigh = TextEditingController();
  final _humidityCriticalHigh = TextEditingController();
  final _gasWarning = TextEditingController();
  final _gasCritical = TextEditingController();
  final _fallImpact = TextEditingController();
  final _fallCooldown = TextEditingController();
  final _pollingInterval = TextEditingController();
  final _gasWarmUp = TextEditingController();

  List<TextEditingController> get _controllers => [
    _temperatureWarning,
    _temperatureCritical,
    _humidityCriticalLow,
    _humidityWarningLow,
    _humidityWarningHigh,
    _humidityCriticalHigh,
    _gasWarning,
    _gasCritical,
    _fallImpact,
    _fallCooldown,
    _pollingInterval,
    _gasWarmUp,
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdminPageFrame(
    title: 'Thresholds',
    eyebrow: 'Administrator',
    subtitle: 'Per-helmet safety limits',
    actions: [
      HeaderIconButton(
        icon: Icons.logout_rounded,
        tooltip: 'Sign out',
        onPressed: widget.onSignOut,
      ),
    ],
    child: StreamBuilder<List<HelmetMetaRecord>>(
      stream: widget.admin.watchHelmetsMeta(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return StateView(
            kind: StateViewKind.error,
            title: 'Helmets unavailable',
            message: adminErrorMessage(snapshot.error!),
          );
        }
        final helmets = snapshot.data;
        if (helmets == null) {
          return const StateView(
            kind: StateViewKind.loading,
            title: 'Loading helmets',
            message: 'Reading helmet records…',
          );
        }
        if (helmets.isEmpty) {
          return const StateView(
            kind: StateViewKind.empty,
            title: 'No helmets registered',
            message:
                'Register a helmet first — thresholds are stored per '
                'helmet.',
          );
        }
        _helmetId ??= helmets.first.helmetId;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                0,
              ),
              child: DropdownButtonFormField<String>(
                initialValue: _helmetId,
                decoration: const InputDecoration(
                  labelText: 'Helmet',
                  prefixIcon: Icon(Icons.engineering_outlined),
                ),
                items: [
                  for (final helmet in helmets)
                    DropdownMenuItem(
                      value: helmet.helmetId,
                      child: Text(
                        helmet.label == null
                            ? helmet.helmetId
                            : '${helmet.helmetId} — ${helmet.label}',
                      ),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _helmetId = value;
                  _loadedFor = null;
                  _loadedConfig = null;
                  _error = null;
                  _notice = null;
                }),
              ),
            ),
            Expanded(child: _buildForm(context)),
          ],
        );
      },
    ),
  );

  Widget _buildForm(BuildContext context) {
    final helmetId = _helmetId;
    if (helmetId == null) return const SizedBox.shrink();
    return StreamBuilder<HelmetConfiguration?>(
      stream: widget.admin.watchThresholds(helmetId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return StateView(
            kind: StateViewKind.error,
            title: 'Thresholds unavailable',
            message: adminErrorMessage(snapshot.error!),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            _loadedFor != helmetId) {
          return const StateView(
            kind: StateViewKind.loading,
            title: 'Loading thresholds',
            message: 'Reading the stored configuration…',
          );
        }
        final config = snapshot.data;
        if (_loadedFor != helmetId) {
          _loadedFor = helmetId;
          _loadedConfig = config;
          _fillControllers(config);
          _notice = config == null
              ? 'No configuration is stored for this helmet yet. The '
                    'values below are starter values — saving writes the '
                    'first configuration.'
              : null;
        }
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (_error != null) ...[
              ResultBanner(succeeded: false, message: _error!),
              const SizedBox(height: AppSpacing.md),
            ],
            if (_notice != null) ...[
              ResultBanner(succeeded: true, message: _notice!),
              const SizedBox(height: AppSpacing.md),
            ],
            if (_loadedConfig != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  'Last updated by ${_loadedConfig!.updatedBy} • '
                  '${formatRelativeTime(_loadedConfig!.updatedAt)}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            const SectionHeader(
              title: 'Temperature',
              subtitle: 'Degrees Celsius',
            ),
            const SizedBox(height: AppSpacing.md),
            _numberField(
              key: const ValueKey('temperatureWarningC'),
              label: 'Temperature warning °C',
              controller: _temperatureWarning,
            ),
            _numberField(
              key: const ValueKey('temperatureCriticalC'),
              label: 'Temperature critical °C',
              controller: _temperatureCritical,
            ),
            const SectionHeader(
              title: 'Humidity',
              subtitle: 'Percent relative humidity, low to high',
            ),
            const SizedBox(height: AppSpacing.md),
            _numberField(
              key: const ValueKey('humidityCriticalLowPct'),
              label: 'Humidity critical low %',
              controller: _humidityCriticalLow,
            ),
            _numberField(
              key: const ValueKey('humidityWarningLowPct'),
              label: 'Humidity warning low %',
              controller: _humidityWarningLow,
            ),
            _numberField(
              key: const ValueKey('humidityWarningHighPct'),
              label: 'Humidity warning high %',
              controller: _humidityWarningHigh,
            ),
            _numberField(
              key: const ValueKey('humidityCriticalHighPct'),
              label: 'Humidity critical high %',
              controller: _humidityCriticalHigh,
            ),
            const SectionHeader(title: 'Gas', subtitle: 'MQ sensor limits'),
            const SizedBox(height: AppSpacing.md),
            _numberField(
              key: const ValueKey('gasWarningPpm'),
              label: 'Gas warning ppm',
              controller: _gasWarning,
            ),
            _numberField(
              key: const ValueKey('gasCriticalPpm'),
              label: 'Gas critical ppm',
              controller: _gasCritical,
            ),
            const SectionHeader(
              title: 'Fall and device',
              subtitle: 'Impact, cooldowns and polling',
            ),
            const SizedBox(height: AppSpacing.md),
            _numberField(
              key: const ValueKey('fallImpactThresholdG'),
              label: 'Fall impact threshold (g)',
              controller: _fallImpact,
            ),
            _numberField(
              key: const ValueKey('fallDuplicateCooldownSeconds'),
              label: 'Fall duplicate cooldown (seconds)',
              controller: _fallCooldown,
              integer: true,
            ),
            _numberField(
              key: const ValueKey('normalPollingIntervalSeconds'),
              label: 'Normal polling interval (seconds)',
              controller: _pollingInterval,
              integer: true,
            ),
            _numberField(
              key: const ValueKey('gasWarmUpHours'),
              label: 'Gas warm-up (hours)',
              controller: _gasWarmUp,
              integer: true,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Save thresholds',
              icon: Icons.save_rounded,
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        );
      },
    );
  }

  Widget _numberField({
    required Key key,
    required String label,
    required TextEditingController controller,
    bool integer = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: AuthTextField(
      key: key,
      label: label,
      controller: controller,
      hintText: integer ? '0' : '0.0',
      icon: Icons.numbers_rounded,
      keyboardType: TextInputType.numberWithOptions(
        decimal: !integer,
        signed: false,
      ),
    ),
  );

  void _fillControllers(HelmetConfiguration? config) {
    final values = config ?? _starterValues;
    _temperatureWarning.text = _format(values.temperatureWarningC);
    _temperatureCritical.text = _format(values.temperatureCriticalC);
    _humidityCriticalLow.text = _format(values.humidityCriticalLowPct);
    _humidityWarningLow.text = _format(values.humidityWarningLowPct);
    _humidityWarningHigh.text = _format(values.humidityWarningHighPct);
    _humidityCriticalHigh.text = _format(values.humidityCriticalHighPct);
    _gasWarning.text = _format(values.gasWarningPpm);
    _gasCritical.text = _format(values.gasCriticalPpm);
    _fallImpact.text = _format(values.fallImpactThresholdG);
    _fallCooldown.text = '${values.fallDuplicateCooldownSeconds}';
    _pollingInterval.text = '${values.normalPollingIntervalSeconds}';
    _gasWarmUp.text = '${values.gasWarmUpHours}';
  }

  static String _format(double value) =>
      value == value.roundToDouble() ? '${value.toInt()}' : '$value';

  HelmetConfiguration get _starterValues => HelmetConfiguration(
    helmetId: _helmetId ?? '',
    configVersion: '1.0',
    temperatureWarningC: 35,
    temperatureCriticalC: 40,
    humidityWarningLowPct: 40,
    humidityCriticalLowPct: 30,
    humidityWarningHighPct: 70,
    humidityCriticalHighPct: 85,
    gasWarningPpm: 50,
    gasCriticalPpm: 100,
    fallImpactThresholdG: 2,
    fallDuplicateCooldownSeconds: 30,
    normalPollingIntervalSeconds: 5,
    gasWarmUpHours: 0,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    updatedBy: widget.currentUser.uid,
  );

  double? _parseDouble(TextEditingController controller) =>
      double.tryParse(controller.text.trim());

  int? _parseInt(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  Future<void> _save() async {
    final helmetId = _helmetId;
    if (helmetId == null) return;
    final temperatureWarning = _parseDouble(_temperatureWarning);
    final temperatureCritical = _parseDouble(_temperatureCritical);
    final humidityCriticalLow = _parseDouble(_humidityCriticalLow);
    final humidityWarningLow = _parseDouble(_humidityWarningLow);
    final humidityWarningHigh = _parseDouble(_humidityWarningHigh);
    final humidityCriticalHigh = _parseDouble(_humidityCriticalHigh);
    final gasWarning = _parseDouble(_gasWarning);
    final gasCritical = _parseDouble(_gasCritical);
    final fallImpact = _parseDouble(_fallImpact);
    final fallCooldown = _parseInt(_fallCooldown);
    final pollingInterval = _parseInt(_pollingInterval);
    final gasWarmUp = _parseInt(_gasWarmUp);

    final errors = <String>[];
    if ([
      temperatureWarning,
      temperatureCritical,
      humidityCriticalLow,
      humidityWarningLow,
      humidityWarningHigh,
      humidityCriticalHigh,
      gasWarning,
      gasCritical,
      fallImpact,
      fallCooldown,
      pollingInterval,
      gasWarmUp,
    ].any((value) => value == null)) {
      errors.add('Enter a number in every field.');
    } else {
      if (temperatureWarning! >= temperatureCritical!) {
        errors.add('Temperature warning must be below temperature critical.');
      }
      if (humidityCriticalLow! >= humidityWarningLow!) {
        errors.add('Humidity critical low must be below warning low.');
      }
      if (humidityWarningLow >= humidityWarningHigh!) {
        errors.add('Humidity warning low must be below warning high.');
      }
      if (humidityWarningHigh >= humidityCriticalHigh!) {
        errors.add('Humidity warning high must be below critical high.');
      }
      if (gasWarning! >= gasCritical!) {
        errors.add('Gas warning must be below gas critical.');
      }
      if (fallImpact! <= 0) {
        errors.add('Fall impact threshold must be above zero.');
      }
      if (fallCooldown! <= 0) {
        errors.add('Fall duplicate cooldown must be above zero.');
      }
      if (pollingInterval! <= 0) {
        errors.add('Polling interval must be above zero.');
      }
      if (gasWarmUp! < 0) {
        errors.add('Gas warm-up cannot be negative.');
      }
    }
    if (errors.isNotEmpty) {
      setState(() => _error = errors.join(' '));
      return;
    }

    final HelmetConfiguration configuration;
    try {
      configuration = HelmetConfiguration(
        helmetId: helmetId,
        configVersion: _loadedConfig?.configVersion ?? '1.0',
        temperatureWarningC: temperatureWarning!,
        temperatureCriticalC: temperatureCritical!,
        humidityWarningLowPct: humidityWarningLow!,
        humidityCriticalLowPct: humidityCriticalLow!,
        humidityWarningHighPct: humidityWarningHigh!,
        humidityCriticalHighPct: humidityCriticalHigh!,
        gasWarningPpm: gasWarning!,
        gasCriticalPpm: gasCritical!,
        fallImpactThresholdG: fallImpact!,
        fallDuplicateCooldownSeconds: fallCooldown!,
        normalPollingIntervalSeconds: pollingInterval!,
        gasWarmUpHours: gasWarmUp!,
        updatedAt: DateTime.now().toUtc(),
        updatedBy: widget.currentUser.uid,
      );
    } on ModelValidationException catch (error) {
      setState(() => _error = error.message);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.admin.setHelmetThresholds(
        helmetId: helmetId,
        thresholds: configuration,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _loadedConfig = saved;
        _notice = null;
      });
      showAdminMessage(context, 'Thresholds saved for $helmetId.');
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = adminErrorMessage(error);
      });
    }
  }
}
