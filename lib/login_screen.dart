import 'package:flutter/material.dart';
import 'application/session_controller.dart';
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

  @override
  Widget build(BuildContext context) {
    const bgTop = Color(0xFF0B1C3A);
    const bgBottom = Color(0xFF07152C);
    const accent = Color(0xFF2F80ED);
    const sectionBg = Color(0xFFF4F6FA);

    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;

    final sectionRadius = (w * 0.07).clamp(18.0, 26.0);

    return Scaffold(
      backgroundColor: bgBottom,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgTop, bgBottom],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.only(
                  left: (w * 0.05).clamp(10.0, 18.0),
                  top: (h * 0.01).clamp(0.0, 10.0),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                    ),
                    color: Colors.white.withValues(alpha: 0.90),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  (w * 0.08).clamp(22.0, 36.0),
                  0,
                  (w * 0.08).clamp(22.0, 36.0),
                  18,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.role.accessLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Welcome back',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 26,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in to monitor your site',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.70),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: sectionBg,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(sectionRadius),
                      topRight: Radius.circular(sectionRadius),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      (w * 0.08).clamp(22.0, 36.0),
                      22,
                      (w * 0.08).clamp(22.0, 36.0),
                      28,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _FieldLabel('Email address'),
                        const SizedBox(height: 8),
                        _Input(
                          controller: _emailController,
                          hintText: 'name@example.com',
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                        ),
                        const SizedBox(height: 14),
                        _FieldLabel('Password'),
                        const SizedBox(height: 8),
                        _Input(
                          controller: _passwordController,
                          hintText: '••••••••',
                          obscureText: _obscure,
                          suffix: IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                        ),
                        if (_result != null) ...[
                          const SizedBox(height: 12),
                          Semantics(
                            liveRegion: true,
                            child: Container(
                              key: const Key('login-result'),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _result!.succeeded
                                    ? const Color(0xFFE8F5E9)
                                    : const Color(0xFFFFEBEE),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _result!.message,
                                style: TextStyle(
                                  color: _result!.succeeded
                                      ? const Color(0xFF1E7A34)
                                      : const Color(0xFF9B1C1C),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            key: const Key('forgot-password'),
                            onPressed: _isLoading
                                ? null
                                : _handlePasswordReset,
                            child: const Text(
                              'Forgot password?',
                              style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1F5E8C),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            onPressed: _isLoading ? null : _handleSignIn,
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Sign in',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: Colors.black.withValues(alpha: 0.12),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'or',
                              style: TextStyle(
                                color: Colors.black.withValues(alpha: 0.40),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Divider(
                                color: Colors.black.withValues(alpha: 0.12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 48,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black.withValues(
                                alpha: 0.75,
                              ),
                              side: BorderSide(
                                color: Colors.black.withValues(alpha: 0.18),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: null,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.access_time_rounded, size: 18),
                                SizedBox(width: 10),
                                Text(
                                  'SSO not configured',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                "Don't have an account? ",
                                style: TextStyle(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              InkWell(
                                onTap: widget.role == UserRole.worker
                                    ? () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => SignUpScreen(
                                              session: widget.session,
                                            ),
                                          ),
                                        );
                                      }
                                    : null,
                                child: Text(
                                  widget.role == UserRole.worker
                                      ? 'Create worker account'
                                      : 'Supervisor accounts are invite-only',
                                  style: TextStyle(
                                    color: accent,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: MediaQuery.paddingOf(context).bottom),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.black.withValues(alpha: 0.70),
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    );
  }
}

class _Input extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;

  const _Input({
    required this.controller,
    required this.hintText,
    this.obscureText = false,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      decoration: InputDecoration(
        hintText: hintText,
        filled: true,
        fillColor: Colors.white,
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2F80ED), width: 1.2),
        ),
      ),
    );
  }
}
