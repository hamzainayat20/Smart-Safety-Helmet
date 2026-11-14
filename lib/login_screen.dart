import 'package:flutter/material.dart';
import 'application/session_controller.dart';
import 'presentation/design_system/design_system.dart';
import 'signup_screen.dart';
import 'user_role.dart';

class LoginScreen extends StatefulWidget {
  final UserRole role;
  final SessionController session;

  const LoginScreen({super.key, required this.role, required this.session});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  SessionActionResult? _result;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleSignIn() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter email and password')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final result = await widget.session.signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
      expectedRole: widget.role,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (result.succeeded) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        setState(() => _result = result);
      }
    }
  }

  Future<void> _handlePasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(
        () => _result = const SessionActionResult.failure(
          SessionIssue.invalidEmail,
          'Enter your email address first.',
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    final result = await widget.session.sendPasswordReset(email);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _result = result;
    });
  }

  Future<void> _handleResendVerification() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      setState(
        () => _result = const SessionActionResult.failure(
          SessionIssue.invalidCredentials,
          'Enter your email and password to request another verification email.',
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    final result = await widget.session.resendVerification(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWorker = widget.role == UserRole.worker;
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPageHeader(
              eyebrow: widget.role.accessLabel.toUpperCase(),
              title: 'Welcome back',
              subtitle: 'Sign in to monitor your site',
              leading: HeaderIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
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
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
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
                              hintText: 'Your password',
                              icon: Icons.lock_outline_rounded,
                              obscureText: _obscure,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              onSubmitted: (_) {
                                if (!_isLoading) _handleSignIn();
                              },
                              suffix: IconButton(
                                tooltip: _obscure
                                    ? 'Show password'
                                    : 'Hide password',
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: AppSizes.iconMd,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                key: const Key('forgot-password'),
                                onPressed: _isLoading
                                    ? null
                                    : _handlePasswordReset,
                                child: const Text('Forgot password?'),
                              ),
                            ),
                            if (_result != null) ...[
                              const SizedBox(height: AppSpacing.sm),
                              ResultBanner(
                                key: const Key('login-result'),
                                succeeded: _result!.succeeded,
                                message: _result!.message,
                              ),
                            ],
                            const SizedBox(height: AppSpacing.md),
                            SizedBox(
                              height: 56,
                              child: AppButton(
                                label: 'Sign in',
                                icon: Icons.login_rounded,
                                loading: _isLoading,
                                onPressed: _handleSignIn,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextButton.icon(
                              key: const Key('resend-verification'),
                              onPressed: _isLoading
                                  ? null
                                  : _handleResendVerification,
                              icon: const Icon(
                                Icons.mark_email_read_outlined,
                                size: AppSizes.iconMd,
                              ),
                              label: const Text(
                                'Send/Resend verification email',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            AppCard(
                              color: AppColors.surfaceSunken,
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm,
                              ),
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: AppSpacing.xs,
                                children: [
                                  Text(
                                    "Don't have an account?",
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  if (isWorker)
                                    TextButton(
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => SignUpScreen(
                                              session: widget.session,
                                            ),
                                          ),
                                        );
                                      },
                                      child: const Text(
                                        'Create worker account',
                                      ),
                                    )
                                  else
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: AppSpacing.sm + 6,
                                      ),
                                      child: Text(
                                        'Supervisor accounts are invite-only',
                                        style: AppTypography.label.copyWith(
                                          color: AppColors.textPrimary,
                                        ),
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
