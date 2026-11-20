import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/admin_repository.dart';
import '../../domain/models.dart';
import '../../user_role.dart';
import '../design_system/design_system.dart';
import 'admin_shared.dart';

/// Site list plus create/edit. Supervisor assignment is edited on the same
/// form and saved through `adminSetSiteSupervisors`, which also syncs each
/// supervisor's `siteIds` on the backend.
class AdminSitesScreen extends StatefulWidget {
  const AdminSitesScreen({
    super.key,
    required this.admin,
    required this.onSignOut,
  });

  final AdminRepository admin;
  final VoidCallback onSignOut;

  @override
  State<AdminSitesScreen> createState() => _AdminSitesScreenState();
}

class _AdminSitesScreenState extends State<AdminSitesScreen> {
  @override
  Widget build(BuildContext context) => AdminPageFrame(
    title: 'Sites',
    eyebrow: 'Administrator',
    subtitle: 'Work sites and their supervisors',
    actions: [
      HeaderIconButton(
        icon: Icons.add_rounded,
        tooltip: 'Create site',
        onPressed: _openCreate,
      ),
      HeaderIconButton(
        icon: Icons.logout_rounded,
        tooltip: 'Sign out',
        onPressed: widget.onSignOut,
      ),
    ],
    child: StreamBuilder<List<Site>>(
      stream: widget.admin.watchSites(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return StateView(
            kind: StateViewKind.error,
            title: 'Sites unavailable',
            message: adminErrorMessage(snapshot.error!),
          );
        }
        final sites = snapshot.data;
        if (sites == null) {
          return const StateView(
            kind: StateViewKind.loading,
            title: 'Loading sites',
            message: 'Reading site records…',
          );
        }
        if (sites.isEmpty) {
          return const StateView(
            kind: StateViewKind.empty,
            title: 'No sites yet',
            message:
                'Create the first site with the add button above. Sites '
                'group helmets and supervisors.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: sites.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) {
            final site = sites[index];
            return AppCard(
              onTap: () => _openEdit(site),
              status: site.active ? SafetyStatus.normal : SafetyStatus.offline,
              child: Row(
                children: [
                  const IconTile(icon: Icons.location_city_rounded),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          site.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyStrong.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          site.organizationName ?? site.siteId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        StatusChip(
                          status: site.active
                              ? SafetyStatus.normal
                              : SafetyStatus.offline,
                          label: site.active ? 'Active' : 'Inactive',
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            );
          },
        );
      },
    ),
  );

  void _openCreate() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SiteEditScreen(admin: widget.admin),
      ),
    );
  }

  void _openEdit(Site site) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SiteEditScreen(admin: widget.admin, site: site),
      ),
    );
  }
}

class _SiteEditScreen extends StatefulWidget {
  const _SiteEditScreen({required this.admin, this.site});

  final AdminRepository admin;
  final Site? site;

  @override
  State<_SiteEditScreen> createState() => _SiteEditScreenState();
}

class _SiteEditScreenState extends State<_SiteEditScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  Set<String> _supervisorIds = {};
  List<UserProfile> _users = const [];
  StreamSubscription<List<UserProfile>>? _usersSubscription;
  bool _saving = false;
  String? _error;

  bool get _isCreate => widget.site == null;

  @override
  void initState() {
    super.initState();
    final site = widget.site;
    if (site != null) _nameController.text = site.name;
    _usersSubscription = widget.admin.watchUsers().listen((users) {
      if (mounted) setState(() => _users = users);
    }, onError: (_) {});
    if (site != null) unawaited(_loadSupervisors(site.siteId));
  }

  /// The app [Site] model does not carry the supervisors map, so current
  /// assignments are read from supervisors' own `siteIds` instead.
  Future<void> _loadSupervisors(String siteId) async {
    try {
      final users = await widget.admin.watchUsers().first;
      if (!mounted) return;
      setState(() {
        _supervisorIds = users
            .where(
              (user) =>
                  (user.role == UserRole.supervisor ||
                      user.role == UserRole.administrator) &&
                  user.siteIds.contains(siteId),
            )
            .map((user) => user.uid)
            .toSet();
      });
    } on Object {
      // Leave the selection empty; saving is an explicit admin action.
    }
  }

  @override
  void dispose() {
    unawaited(_usersSubscription?.cancel());
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdminSubScreen(
    title: _isCreate ? 'Create site' : 'Edit site',
    subtitle: _isCreate
        ? 'Sites group helmets and people'
        : widget.site!.siteId,
    child: ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (_error != null) ...[
          ResultBanner(succeeded: false, message: _error!),
          const SizedBox(height: AppSpacing.md),
        ],
        AuthTextField(
          label: 'Site name',
          controller: _nameController,
          hintText: 'e.g. Lahore Plant — Phase 2',
          icon: Icons.location_city_outlined,
        ),
        const SizedBox(height: AppSpacing.md),
        AuthTextField(
          label: 'Description (optional)',
          controller: _descriptionController,
          hintText: 'What happens at this site',
          icon: Icons.notes_outlined,
        ),
        const SizedBox(height: AppSpacing.md),
        MultiSelectField(
          label: 'Supervisors',
          options: [
            for (final user in _users)
              if (user.role == UserRole.supervisor ||
                  user.role == UserRole.administrator)
                (user.uid, '${user.displayName} (${user.email})'),
          ],
          selectedIds: _supervisorIds,
          onChanged: (ids) => setState(() => _supervisorIds = ids),
          emptyOptionsMessage: 'No supervisors exist yet.',
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: _isCreate ? 'Create site' : 'Save changes',
          icon: _isCreate ? Icons.add_rounded : Icons.save_rounded,
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    ),
  );

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Site name is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final site = await widget.admin.upsertSite(
        siteId: widget.site?.siteId,
        name: name,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );
      await widget.admin.setSiteSupervisors(
        siteId: site.siteId,
        supervisorUids: _supervisorIds.toList(),
      );
      if (!mounted) return;
      showAdminMessage(context, 'Site saved.');
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
