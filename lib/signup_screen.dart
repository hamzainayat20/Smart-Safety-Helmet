import 'package:flutter/material.dart';
import 'application/session_controller.dart';
import 'presentation/design_system/design_system.dart';

class SignUpScreen extends StatefulWidget {
  final SessionController session;

  const SignUpScreen({super.key, required this.session});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _orgController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  SessionActionResult? _result;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _orgController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleSignUp() async {
    if (_emailController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        _nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final result = await widget.session.registerWorker(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
      displayName: _nameController.text.trim(),
      organizationName: _orgController.text.trim(),
    );

    if (mounted) {
      setState(() => _isLoading = false);
      setState(() => _result = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPageHeader(
              eyebrow: 'CREATE ACCOUNT',
              title: 'Get started',
              subtitle: 'Set up your worker profile',
              leading: HeaderIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back to sign in',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            Expanded(
              child: ContentSheet(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppCard(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const IconTile(
                                  icon: Icons.badge_outlined,
                                  status: SafetyStatus.pending,
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Worker account',
                                        style: AppTypography.bodyStrong
                                            .copyWith(
                                              color: AppColors.textPrimary,
                                            ),
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        'Supervisor access requires an administrator invitation.',
                                        style: AppTypography.caption.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          AuthTextField(
                            label: 'Full name',
                            controller: _nameController,
                            hintText: 'Enter your name',
                            icon: Icons.person_outline_rounded,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AuthTextField(
                            label: 'Email address',
                            controller: _emailController,
                            hintText: 'name@example.com',
                            icon: Icons.alternate_email_rounded,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AuthTextField(
                            label: 'Password',
                            controller: _passwordController,
                            hintText: 'Create a password',
                            icon: Icons.lock_outline_rounded,
                            obscureText: true,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.newPassword],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AuthTextField(
                            label: 'Site / Organization',
                            controller: _orgController,
                            hintText: 'Enter site name…',
                            icon: Icons.apartment_rounded,
                            textInputAction: TextInputAction.done,
                          ),
                          if (result != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            ResultBanner(
                              key: const Key('signup-result'),
                              succeeded: result.succeeded,
                              message: result.message,
                              action: result.succeeded
                                  ? TextButton(
                                      key: const Key('return-to-login'),
                                      onPressed: () =>
                                          Navigator.of(context).maybePop(),
                                      child: const Text('Return to sign in'),
                                    )
                                  : null,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          SizedBox(
                            height: 56,
                            child: AppButton(
                              label: 'Continue',
                              icon: Icons.arrow_forward_rounded,
                              loading: _isLoading,
                              onPressed: _handleSignUp,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Use the email registered for worker access.',
                            textAlign: TextAlign.center,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
