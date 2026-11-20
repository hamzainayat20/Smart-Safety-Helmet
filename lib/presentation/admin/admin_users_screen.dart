import 'package:flutter/material.dart';

import '../../data/admin_repository.dart';
import '../../domain/models.dart';
import '../../user_role.dart';
import '../design_system/design_system.dart';
import 'admin_shared.dart';
import 'admin_user_edit_screen.dart';

/// Searchable, role-filterable list of every user record. Tapping a user
/// opens the editor; the button in the header opens the create form.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({
    super.key,
    required this.admin,
    required this.currentUser,
    required this.onSignOut,
  });

  final AdminRepository admin;
  final UserProfile currentUser;
  final VoidCallback onSignOut;

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String _query = '';
  UserRole? _roleFilter;

  @override
  Widget build(BuildContext context) => AdminPageFrame(
    title: 'Users',
    eyebrow: 'Administrator',
    subtitle: 'Accounts, roles and assignments',
    actions: [
      HeaderIconButton(
        icon: Icons.person_add_rounded,
        tooltip: 'Create user',
        onPressed: _openCreate,
      ),
      HeaderIconButton(
        icon: Icons.logout_rounded,
        tooltip: 'Sign out',
        onPressed: widget.onSignOut,
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                onChanged: (value) => setState(() => _query = value),
                style: AppTypography.body.copyWith(
                  color: AppColors.textPrimary,
                ),
                decoration: const InputDecoration(
                  hintText: 'Search name or email',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedFilter<UserRole?>(
                values: const [null, ...UserRole.values],
                selected: _roleFilter,
                labelOf: (role) => role?.label ?? 'All roles',
                onSelected: (role) => setState(() => _roleFilter = role),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<UserProfile>>(
            stream: widget.admin.watchUsers(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return StateView(
                  kind: StateViewKind.error,
                  title: 'Users unavailable',
                  message: adminErrorMessage(snapshot.error!),
                );
              }
              final users = snapshot.data;
              if (users == null) {
                return const StateView(
                  kind: StateViewKind.loading,
                  title: 'Loading users',
                  message: 'Reading user records…',
                );
              }
              final visible = users.where(_matches).toList();
              if (visible.isEmpty) {
                return StateView(
                  kind: StateViewKind.empty,
                  title: users.isEmpty ? 'No users yet' : 'No matches',
                  message: users.isEmpty
                      ? 'Create the first supervisor or worker account '
                            'with the add button above.'
                      : 'No user matches the current search and filter.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: visible.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) =>
                    _UserCard(user: visible[index], onTap: _openEdit),
              );
            },
          ),
        ),
      ],
    ),
  );

  bool _matches(UserProfile user) {
    if (_roleFilter != null && user.role != _roleFilter) return false;
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return user.displayName.toLowerCase().contains(query) ||
        user.email.toLowerCase().contains(query);
  }

  void _openCreate() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminUserEditScreen(
          admin: widget.admin,
          currentUser: widget.currentUser,
        ),
      ),
    );
  }

  void _openEdit(UserProfile user) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminUserEditScreen(
          admin: widget.admin,
          currentUser: widget.currentUser,
          user: user,
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.onTap});

  final UserProfile user;
  final ValueChanged<UserProfile> onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    onTap: () => onTap(user),
    status: user.active ? SafetyStatus.normal : SafetyStatus.offline,
    child: Row(
      children: [
        InitialsAvatar(name: user.displayName),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyStrong.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                user.email,
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
                  RoleTag(label: user.role.label),
                  StatusChip(
                    status: user.active
                        ? SafetyStatus.normal
                        : SafetyStatus.offline,
                    label: user.active ? 'Active' : 'Inactive',
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
