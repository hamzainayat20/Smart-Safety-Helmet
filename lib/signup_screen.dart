import 'package:flutter/material.dart';
import 'application/session_controller.dart';

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
    const bgTop = Color(0xFF0B1C3A);
    const bgBottom = Color(0xFF07152C);
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
                padding: EdgeInsets.fromLTRB(
                  (w * 0.06).clamp(16.0, 22.0),
                  (h * 0.015).clamp(6.0, 12.0),
                  (w * 0.06).clamp(16.0, 22.0),
                  10,
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                      ),
                      color: Colors.white.withValues(alpha: 0.90),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Back to login',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.70),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
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
                      'CREATE ACCOUNT',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Get started',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 26,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Set up your worker profile',
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
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF2F80ED)),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.badge_outlined,
                                color: Color(0xFF1E7A34),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Worker account\nSupervisor access requires an administrator invitation.',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _FieldLabel('Full name'),
                        const SizedBox(height: 8),
                        _Input(
                          controller: _nameController,
                          hintText: 'Enter your name',
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 14),
                        _FieldLabel('Email address'),
                        const SizedBox(height: 8),
                        _Input(
                          controller: _emailController,
                          hintText: 'name@example.com',
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 14),
                        _FieldLabel('Password'),
                        const SizedBox(height: 8),
                        _Input(
                          controller: _passwordController,
                          hintText: 'Create a password',
                          obscureText: true,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 14),
                        _FieldLabel('Site / Organization'),
                        const SizedBox(height: 8),
                        _Input(
                          controller: _orgController,
                          hintText: 'Enter site name…',
                          textInputAction: TextInputAction.done,
                        ),
                        if (_result != null) ...[
                          const SizedBox(height: 14),
                          Semantics(
                            liveRegion: true,
                            child: Container(
                              key: const Key('signup-result'),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _result!.succeeded
                                    ? const Color(0xFFE8F5E9)
                                    : const Color(0xFFFFEBEE),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    _result!.message,
                                    style: TextStyle(
                                      color: _result!.succeeded
                                          ? const Color(0xFF1E7A34)
                                          : const Color(0xFF9B1C1C),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (_result!.succeeded)
                                    TextButton(
                                      key: const Key('return-to-login'),
                                      onPressed: () =>
                                          Navigator.of(context).maybePop(),
                                      child: const Text('Return to sign in'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
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
                            onPressed: _isLoading ? null : _handleSignUp,
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Continue',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                      ),
                                      SizedBox(width: 10),
                                      Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Tip: Use your work email for worker access.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.black.withValues(alpha: 0.38),
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
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
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  const _Input({
    required this.controller,
    required this.hintText,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      decoration: InputDecoration(
        hintText: hintText,
        filled: true,
        fillColor: Colors.white,
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
