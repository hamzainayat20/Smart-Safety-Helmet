import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/admin_repository.dart';
import '../../domain/models.dart';
import '../../user_role.dart';
import '../design_system/design_system.dart';
import 'admin_shared.dart';

/// Create form (no [user]) and edit form for one user record.
///
/// Create returns a one-time password setup link from the backend; it is
/// shown once, with a copy button, and never stored. Edit covers profile,
/// role, active state and assignments. When the target is the signed-in
/// administrator, the role / active / delete controls are hidden — the
/// backend enforces the same guards.
class AdminUserEditScreen extends StatefulWidget {
  const AdminUserEditScreen({
    super.key,
    required this.admin,
    required this.currentUser,
    this.user,
  });

  final AdminRepository admin;
  final UserProfile currentUser;
  final UserProfile? user;

  @override
  State<AdminUserEditScreen> createState() => _AdminUserEditScreenState();
}

class _AdminUserEditScreenState extends State<AdminUserEditScreen> {
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _organizationController = TextEditingController();

  UserRole _role = UserRole.worker;
  bool _active = true;
  Set<String> _siteIds = {};
  Set<String> _helmetIds = {};
  Set<String> _supervisorIds = {};
  bool _assignmentsLoaded = false;

  List<Site> _sites = const [];
  List<HelmetMetaRecord> _helmets = const [];
  List<UserProfile> _users = const [];
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  bool _saving = false;
  String? _error;
  CreatedUserResult? _created;

  bool get _isCreate => widget.user == null;
  bool get _isSelf =>
      widget.user != null && widget.user!.uid == widget.currentUser.uid;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    if (user != null) {
      _nameController.text = user.displayName;
      _organizationController.text = user.organizationName ?? '';
      _role = user.role;
      _active = user.active;
      _siteIds = user.siteIds.toSet();
      _helmetIds = user.authorizedHelmetIds.toSet();
      unawaited(_loadAssignments(user.uid));
    } else {
      _assignmentsLoaded = true;
    }
    _subscriptions.add(
      widget.admin.watchSites().listen((sites) {
        if (mounted) setState(() => _sites = sites);
      }, onError: (_) {}),
    );
    _subscriptions.add(
      widget.admin.watchHelmetsMeta().listen((helmets) {
        if (mounted) setState(() => _helmets = helmets);
      }, onError: (_) {}),
    );
    _subscriptions.add(
      widget.admin.watchUsers().listen((users) {
        if (mounted) setState(() => _users = users);
      }, onError: (_) {}),
    );
  }

  Future<void> _loadAssignments(String uid) async {
    try {
      final assignments = await widget.admin.getUserAssignments(uid);
      if (!mounted) return;
      setState(() {
        _siteIds = assignments.siteIds.toSet();
        _helmetIds = assignments.authorizedHelmetIds.toSet();
        _supervisorIds = assignments.authorizedSupervisorIds.toSet();
        _assignmentsLoaded = true;
      });
    } on Object {
      if (mounted) setState(() => _assignmentsLoaded = true);
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _emailController.dispose();
    _nameController.dispose();
    _organizationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_created != null) return _buildCreated(context);
    return AdminSubScreen(
      title: _isCreate ? 'Create user' : 'Edit user',
      subtitle: _isCreate
          ? 'The new user sets their password from a setup link'
          : widget.user!.email,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (_error != null) ...[
            ResultBanner(succeeded: false, message: _error!),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_isCreate) ...[
            AuthTextField(
              label: 'Email',
              controller: _emailController,
              hintText: 'name@example.com',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          AuthTextField(
            label: 'Full name',
            controller: _nameController,
            hintText: 'e.g. Ayesha Khan',
            icon: Icons.person_outline_rounded,
            autofillHints: const [AutofillHints.name],
          ),
          const SizedBox(height: AppSpacing.md),
          AuthTextField(
            label: 'Organization (optional)',
            controller: _organizationController,
            hintText: 'e.g. Smart Safety',
            icon: Icons.business_outlined,
          ),
          const SizedBox(height: AppSpacing.md),
          if (_isSelf)
            const ResultBanner(
              succeeded: true,
              message:
                  'This is your own account. Role, active state and '
                  'deletion are locked for the signed-in administrator.',
            )
          else ...[
            Text(
              'Role',
              style: AppTypography.label.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<UserRole>(
              initialValue: _role,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              items: [
                for (final role in UserRole.values)
                  DropdownMenuItem(value: role, child: Text(role.label)),
              ],
              onChanged: (role) {
                if (role != null) setState(() => _role = role);
              },
            ),
            if (!_isCreate) ...[
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                title: const Text('Account active'),
                subtitle: const Text(
                  'Inactive accounts are blocked everywhere.',
                ),
                value: _active,
                onChanged: (value) => setState(() => _active = value),
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.md),
          if (!_assignmentsLoaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            MultiSelectField(
              label: 'Sites',
              options: [for (final site in _sites) (site.siteId, site.name)],
              selectedIds: _siteIds,
              onChanged: (ids) => setState(() => _siteIds = ids),
              emptyOptionsMessage: 'No sites exist yet.',
            ),
            if (!_isCreate && _role == UserRole.supervisor) ...[
              const SizedBox(height: AppSpacing.md),
              MultiSelectField(
                label: 'Authorized helmets',
                options: [
                  for (final helmet in _helmets)
                    (
                      helmet.helmetId,
                      helmet.label == null
                          ? helmet.helmetId
                          : '${helmet.helmetId} — ${helmet.label}',
                    ),
                ],
                selectedIds: _helmetIds,
                onChanged: (ids) => setState(() => _helmetIds = ids),
                emptyOptionsMessage: 'No helmets are registered yet.',
              ),
            ],
            if (!_isCreate && _role == UserRole.worker) ...[
              const SizedBox(height: AppSpacing.md),
              MultiSelectField(
                label: 'Authorized supervisors',
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
            ],
          ],
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: _isCreate ? 'Create user' : 'Save changes',
            icon: _isCreate ? Icons.person_add_rounded : Icons.save_rounded,
            loading: _saving,
            onPressed: _saving || !_assignmentsLoaded
                ? null
                : (_isCreate ? _create : _save),
          ),
          if (!_isCreate) ...[
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Send password reset email',
              icon: Icons.mark_email_read_outlined,
              variant: AppButtonVariant.secondary,
              loading: _saving,
              onPressed: _saving ? null : _sendPasswordReset,
            ),
            if (!_isSelf) ...[
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'Delete user',
                icon: Icons.delete_outline_rounded,
                variant: AppButtonVariant.destructive,
                loading: _saving,
                onPressed: _saving ? null : _delete,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildCreated(BuildContext context) {
    final created = _created!;
    return AdminSubScreen(
      title: 'User created',
      subtitle: created.user.email,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          ResultBanner(
            succeeded: true,
            message:
                '${created.user.displayName} was created as '
                '${created.user.role.label}. Share the setup link below so '
                'they can set their password.',
          ),
          const SizedBox(height: AppSpacing.md),
          const ResultBanner(
            succeeded: false,
            message:
                'This setup link is shown exactly once. Copy it now and '
                'send it to the user through a trusted channel.',
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: SelectableText(
              created.passwordSetupLink,
              style: AppTypography.body,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Copy setup link',
            icon: Icons.copy_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: created.passwordSetupLink),
              );
              if (context.mounted) {
                showAdminMessage(context, 'Setup link copied.');
              }
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Done',
            icon: Icons.check_rounded,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  String? _validateCreate() {
    final email = _emailController.text.trim();
    if (email.isEmpty) return 'Email is required.';
    if (!email.contains('@') || !email.contains('.')) {
      return 'Enter a valid email address.';
    }
    if (_nameController.text.trim().isEmpty) return 'Name is required.';
    return null;
  }

  Future<void> _create() async {
    final validationError = _validateCreate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.admin.createUser(
        email: _emailController.text.trim(),
        name: _nameController.text.trim(),
        role: _role,
        organizationName: _organizationController.text.trim().isEmpty
            ? null
            : _organizationController.text.trim(),
        siteIds: _siteIds.toList(),
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _created = result;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = adminErrorMessage(error);
      });
    }
  }

  Future<void> _save() async {
    final user = widget.user!;
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final organization = _organizationController.text.trim();
      await widget.admin.updateUserProfile(
        uid: user.uid,
        name: _nameController.text.trim(),
        organizationName: organization.isEmpty ? null : organization,
      );
      if (!_isSelf && _role != user.role) {
        await widget.admin.setUserRole(uid: user.uid, role: _role);
      }
      if (!_isSelf && _active != user.active) {
        await widget.admin.setUserActive(uid: user.uid, active: _active);
      }
      await widget.admin.updateUserAssignments(
        uid: user.uid,
        siteIds: _siteIds.toList(),
        authorizedHelmetIds: _role == UserRole.supervisor
            ? _helmetIds.toList()
            : null,
        authorizedSupervisorIds: _role == UserRole.worker
            ? _supervisorIds.toList()
            : null,
      );
      if (!mounted) return;
      showAdminMessage(context, 'User saved.');
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = adminErrorMessage(error);
      });
    }
  }

  Future<void> _sendPasswordReset() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.admin.sendPasswordReset(widget.user!.email);
      if (!mounted) return;
      setState(() => _saving = false);
      showAdminMessage(context, 'Password reset email sent.');
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = adminErrorMessage(error);
      });
    }
  }

  Future<void> _delete() async {
    final user = widget.user!;
    final confirmed = await showAdminConfirmDialog(
      context,
      title: 'Delete user',
      message:
          'Delete ${user.displayName} (${user.email})? Their account and '
          'profile are removed. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.admin.deleteUser(uid: user.uid);
      if (!mounted) return;
      showAdminMessage(context, 'User deleted.');
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
