import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'application/session_controller.dart';
import 'login_screen.dart';
import 'presentation/design_system/design_system.dart';
import 'user_role.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  UserRole _role = UserRole.supervisor;

  void _continueToLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoginScreen(role: _role, session: widget.session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.enter): _continueToLogin,
          const SingleActivator(LogicalKeyboardKey.numpadEnter):
              _continueToLogin,
        },
        child: Focus(
          autofocus: true,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.lg,
                          AppSpacing.lg,
                          AppSpacing.md,
                        ),
                        children: [
                          const BrandLockup(),
                          const SizedBox(height: AppSpacing.xl),
                          Semantics(
                            header: true,
                            child: Text(
                              'Choose your workspace',
                              style: AppTypography.display.copyWith(
                                color: AppColors.onInk,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Select the view that matches your assigned account role.',
                            style: AppTypography.body.copyWith(
                              color: AppColors.onInkMuted,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          _RoleCard(
                            title: 'Supervisor',
                            description:
                                'Monitor workers, respond to alerts and manage helmets',
                            leading: Icons.supervisor_account_outlined,
                            selected: _role == UserRole.supervisor,
                            onTap: () =>
                                setState(() => _role = UserRole.supervisor),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _RoleCard(
                            title: 'Worker',
                            description:
                                'View your own helmet status and alerts',
                            leading: Icons.engineering_outlined,
                            selected: _role == UserRole.worker,
                            onTap: () =>
                                setState(() => _role = UserRole.worker),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _RoleCard(
                            title: 'Administrator',
                            description:
                                'Manage users, helmets, sites, thresholds and the audit log',
                            leading: Icons.admin_panel_settings_outlined,
                            selected: _role == UserRole.administrator,
                            onTap: () =>
                                setState(() => _role = UserRole.administrator),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.lg,
                        AppSpacing.lg,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: AppColors.inkBorder),
                        ),
                      ),
                      child: SizedBox(
                        height: 56,
                        child: FilledButton(
                          onPressed: _continueToLogin,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.onInk,
                            foregroundColor: AppColors.ink,
                            textStyle: AppTypography.bodyStrong,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  'Continue as ${_role.label}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: AppSizes.iconMd,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.description,
    required this.leading,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData leading;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: '$title portal',
      child: Material(
        color: selected ? AppColors.inkRaised : AppColors.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(
            color: selected ? AppColors.onInk : AppColors.inkBorder,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: AppSizes.touchTarget,
                  height: AppSizes.touchTarget,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.onInk : AppColors.inkRaised,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: selected ? AppColors.onInk : AppColors.inkBorder,
                    ),
                  ),
                  child: Icon(
                    leading,
                    size: AppSizes.iconLg,
                    color: selected ? AppColors.ink : AppColors.onInk,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: AppTypography.subtitle.copyWith(
                                color: AppColors.onInk,
                              ),
                            ),
                          ),
                          _SelectionMark(selected: selected),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        description,
                        style: AppTypography.body.copyWith(
                          color: AppColors.onInkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 160),
    width: AppSizes.iconLg,
    height: AppSizes.iconLg,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: selected ? AppColors.onInk : Colors.transparent,
      border: Border.all(
        color: selected ? AppColors.onInk : AppColors.onInkMuted,
        width: 2,
      ),
    ),
    child: selected
        ? const Icon(
            Icons.check_rounded,
            size: AppSizes.iconSm,
            color: AppColors.ink,
          )
        : null,
  );
}
