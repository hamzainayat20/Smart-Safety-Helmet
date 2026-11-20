import 'package:flutter/material.dart';

import '../../data/admin_repository.dart';
import '../../domain/models.dart';
import '../../user_role.dart';
import '../design_system/design_system.dart';
import '../formatters.dart';
import 'admin_shared.dart';

/// Fleet list plus registration and per-helmet actions (assign worker, set
/// site, rotate secret, retire). Device secrets returned by register and
/// rotate are shown exactly once via [showDeviceSecretSheet].
class AdminHelmetsScreen extends StatefulWidget {
  const AdminHelmetsScreen({
    super.key,
    required this.admin,
    required this.onSignOut,
  });

  final AdminRepository admin;
  final VoidCallback onSignOut;

  @override
  State<AdminHelmetsScreen> createState() => _AdminHelmetsScreenState();
}

class _AdminHelmetsScreenState extends State<AdminHelmetsScreen> {
  @override
  Widget build(BuildContext context) => AdminPageFrame(
    title: 'Helmets',
    eyebrow: 'Administrator',
    subtitle: 'Fleet registration and assignment',
    actions: [
      HeaderIconButton(
        icon: Icons.add_rounded,
        tooltip: 'Register helmet',
        onPressed: _openRegister,
      ),
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
                'Register the first helmet with the add button above. '
                'Registration issues the helmet\'s device secret.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: helmets.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) => _HelmetCard(
            helmet: helmets[index],
            onTap: () => _openDetail(helmets[index]),
          ),
        );
      },
    ),
  );

  void _openRegister() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _RegisterHelmetScreen(admin: widget.admin),
      ),
    );
  }

  void _openDetail(HelmetMetaRecord helmet) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _HelmetDetailScreen(admin: widget.admin, helmet: helmet),
      ),
    );
  }
}

SafetyStatus _provisioningStatus(HelmetMetaRecord helmet) =>
    switch (helmet.provisioningStatus) {
      'provisioned' => SafetyStatus.normal,
      'revoked' => SafetyStatus.critical,
      _ => SafetyStatus.unknown,
    };

String _provisioningLabel(HelmetMetaRecord helmet) =>
    switch (helmet.provisioningStatus) {
      'provisioned' => 'Provisioned',
      'revoked' => 'Revoked',
      null => 'Status unavailable',
      final other => other,
    };

class _HelmetCard extends StatelessWidget {
  const _HelmetCard({required this.helmet, required this.onTap});

  final HelmetMetaRecord helmet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    status: _provisioningStatus(helmet),
    child: Row(
      children: [
        const IconTile(icon: Icons.engineering_rounded),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                helmet.label ?? helmet.helmetId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyStrong.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                helmet.label == null
                    ? helmet.helmetId
                    : '${helmet.helmetId} • ${helmet.assignedWorkerId == null ? 'Unassigned' : 'Assigned'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  StatusChip(
                    status: _provisioningStatus(helmet),
                    label: _provisioningLabel(helmet),
                  ),
                  StatusChip(
                    status: helmet.siteId == null
                        ? SafetyStatus.unknown
                        : SafetyStatus.pending,
                    label: helmet.siteId == null
                        ? 'No site'
                        : 'Site: ${helmet.siteId}',
                  ),
                ],
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
      ],
    ),
  );
}

class _RegisterHelmetScreen extends StatefulWidget {
  const _RegisterHelmetScreen({required this.admin});

  final AdminRepository admin;

  @override
  State<_RegisterHelmetScreen> createState() => _RegisterHelmetScreenState();
}

class _RegisterHelmetScreenState extends State<_RegisterHelmetScreen> {
  static final _helmetIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  final _helmetIdController = TextEditingController();
  final _labelController = TextEditingController();
  String? _siteId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _helmetIdController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdminSubScreen(
    title: 'Register helmet',
    subtitle: 'Issues a new device secret',
    child: ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (_error != null) ...[
          ResultBanner(succeeded: false, message: _error!),
          const SizedBox(height: AppSpacing.md),
        ],
        AuthTextField(
          label: 'Helmet ID',
          controller: _helmetIdController,
          hintText: 'e.g. helmet001',
          icon: Icons.badge_outlined,
        ),
        const SizedBox(height: AppSpacing.md),
        AuthTextField(
          label: 'Label (optional)',
          controller: _labelController,
          hintText: 'e.g. Gate A — unit 1',
          icon: Icons.label_outline_rounded,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Site (optional)',
          style: AppTypography.label.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        StreamBuilder<List<Site>>(
          stream: widget.admin.watchSites(),
          builder: (context, snapshot) {
            final sites = snapshot.data ?? const <Site>[];
            return DropdownButtonFormField<String?>(
              initialValue: _siteId,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.location_city_outlined),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('No site'),
                ),
                for (final site in sites)
                  DropdownMenuItem<String?>(
                    value: site.siteId,
                    child: Text(site.name),
                  ),
              ],
              onChanged: (value) => setState(() => _siteId = value),
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'Register helmet',
          icon: Icons.add_rounded,
          loading: _saving,
          onPressed: _saving ? null : _register,
        ),
      ],
    ),
  );

  Future<void> _register() async {
    final helmetId = _helmetIdController.text.trim();
    if (!_helmetIdPattern.hasMatch(helmetId)) {
      setState(
        () => _error =
            'Helmet ID must be 1–64 letters, digits, dashes or underscores.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.admin.registerHelmet(
        helmetId: helmetId,
        siteId: _siteId,
        label: _labelController.text.trim().isEmpty
            ? null
            : _labelController.text.trim(),
      );
      if (!mounted) return;
      await showDeviceSecretSheet(
        context,
        helmetId: result.helmet.helmetId,
        secret: result.secret,
        intro:
            'Helmet ${result.helmet.helmetId} is registered. Put this '
            'secret in the helmet\'s secrets header so it can sign its '
            'telemetry.',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = adminErrorMessage(error);
      });
    }
  }
}

class _HelmetDetailScreen extends StatefulWidget {
  const _HelmetDetailScreen({required this.admin, required this.helmet});

  final AdminRepository admin;
  final HelmetMetaRecord helmet;

  @override
  State<_HelmetDetailScreen> createState() => _HelmetDetailScreenState();
}

class _HelmetDetailScreenState extends State<_HelmetDetailScreen> {
  late HelmetMetaRecord _helmet;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _helmet = widget.helmet;
  }

  @override
  Widget build(BuildContext context) => AdminSubScreen(
    title: _helmet.label ?? _helmet.helmetId,
    subtitle: _helmet.helmetId,
    child: ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (_error != null) ...[
          ResultBanner(succeeded: false, message: _error!),
          const SizedBox(height: AppSpacing.md),
        ],
        AppCard(
          status: _provisioningStatus(_helmet),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KeyValueRow(label: 'Status', value: _provisioningLabel(_helmet)),
              KeyValueRow(
                label: 'Site',
                value: _helmet.siteId ?? 'Unavailable',
              ),
              KeyValueRow(
                label: 'Assigned worker',
                value: _helmet.assignedWorkerId ?? 'Unassigned',
              ),
              KeyValueRow(
                label: 'Registered',
                value: _helmet.registeredAt == null
                    ? 'Unavailable'
                    : formatUtcTimestamp(_helmet.registeredAt!),
              ),
              KeyValueRow(
                label: 'Registered by',
                value: _helmet.registeredBy ?? 'Unavailable',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (!_helmet.isRevoked) ...[
          AppButton(
            label: 'Assign worker',
            icon: Icons.person_add_alt_rounded,
            variant: AppButtonVariant.secondary,
            loading: _busy,
            onPressed: _busy ? null : _assignWorker,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Set site',
            icon: Icons.location_city_outlined,
            variant: AppButtonVariant.secondary,
            loading: _busy,
            onPressed: _busy ? null : _setSite,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Rotate device secret',
            icon: Icons.key_rounded,
            variant: AppButtonVariant.secondary,
            loading: _busy,
            onPressed: _busy ? null : _rotateSecret,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Retire helmet',
            icon: Icons.block_rounded,
            variant: AppButtonVariant.destructive,
            loading: _busy,
            onPressed: _busy ? null : _retire,
          ),
        ] else
          const ResultBanner(
            succeeded: false,
            message:
                'This helmet is revoked. Its device secret was deleted '
                'and it can no longer send telemetry.',
          ),
      ],
    ),
  );

  Future<void> _run(Future<HelmetMetaRecord> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await action();
      if (!mounted) return;
      setState(() {
        _helmet = updated;
        _busy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = adminErrorMessage(error);
      });
    }
  }

  Future<void> _assignWorker() async {
    final workers = await widget.admin
        .watchUsers()
        .first
        .then(
          (users) => users
              .where((user) => user.role == UserRole.worker && user.active)
              .toList(),
        )
        .catchError((_) => const <UserProfile>[]);
    if (!mounted) return;
    // (chosen, uid): a dismissed sheet returns null and changes nothing,
    // while "Unassigned" is an explicit choice of a null uid.
    final result = await showModalBottomSheet<(bool, String?)>(
      context: context,
      builder: (sheetContext) => SafeArea(
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
              child: Text('Assign worker', style: AppTypography.subtitle),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.person_off_outlined),
                    title: const Text('Unassigned'),
                    selected: _helmet.assignedWorkerId == null,
                    onTap: () => Navigator.of(sheetContext).pop((true, null)),
                  ),
                  for (final worker in workers)
                    ListTile(
                      leading: const Icon(Icons.person_outline_rounded),
                      title: Text(worker.displayName),
                      subtitle: Text(worker.email),
                      selected: _helmet.assignedWorkerId == worker.uid,
                      onTap: () =>
                          Navigator.of(sheetContext).pop((true, worker.uid)),
                    ),
                  if (workers.isEmpty)
                    const ListTile(
                      title: Text('No active worker accounts exist yet.'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || result == null || !result.$1) return;
    await _run(
      () => widget.admin.assignHelmet(
        helmetId: _helmet.helmetId,
        workerUid: result.$2,
      ),
    );
  }

  Future<void> _setSite() async {
    final sites = await widget.admin.watchSites().first.catchError(
      (_) => const <Site>[],
    );
    if (!mounted) return;
    final result = await showModalBottomSheet<(bool, String?)>(
      context: context,
      builder: (sheetContext) => SafeArea(
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
              child: Text('Set site', style: AppTypography.subtitle),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.location_off_outlined),
                    title: const Text('No site'),
                    selected: _helmet.siteId == null,
                    onTap: () => Navigator.of(sheetContext).pop((true, null)),
                  ),
                  for (final site in sites)
                    ListTile(
                      leading: const Icon(Icons.location_city_outlined),
                      title: Text(site.name),
                      subtitle: Text(site.siteId),
                      selected: _helmet.siteId == site.siteId,
                      onTap: () =>
                          Navigator.of(sheetContext).pop((true, site.siteId)),
                    ),
                  if (sites.isEmpty)
                    const ListTile(title: Text('No sites exist yet.')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || result == null || !result.$1) return;
    await _run(
      () => widget.admin.setHelmetSite(
        helmetId: _helmet.helmetId,
        siteId: result.$2,
      ),
    );
  }

  Future<void> _rotateSecret() async {
    final confirmed = await showAdminConfirmDialog(
      context,
      title: 'Rotate device secret',
      message:
          'A new secret is issued for ${_helmet.helmetId} and the old one '
          'stops working immediately. Update the helmet\'s secrets header '
          'before it reconnects.',
      confirmLabel: 'Rotate',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final secret = await widget.admin.rotateHelmetSecret(
        helmetId: _helmet.helmetId,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await showDeviceSecretSheet(
        context,
        helmetId: _helmet.helmetId,
        secret: secret,
        intro:
            'New secret (${secret.keyVersion}) for ${_helmet.helmetId}. '
            'The previous secret no longer works.',
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = adminErrorMessage(error);
      });
    }
  }

  Future<void> _retire() async {
    final confirmed = await showAdminConfirmDialog(
      context,
      title: 'Retire helmet',
      message:
          'Retire ${_helmet.helmetId}? It is unassigned, its device '
          'secret is deleted, and it can no longer send telemetry.',
      confirmLabel: 'Retire',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run(() => widget.admin.retireHelmet(helmetId: _helmet.helmetId));
  }
}
