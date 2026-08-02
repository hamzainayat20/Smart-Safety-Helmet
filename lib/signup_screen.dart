import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'main.dart';
import 'user_role.dart';

class SignUpScreen extends StatefulWidget {
  final UserRole initialRole;

  const SignUpScreen({super.key, required this.initialRole});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  late UserRole _role = widget.initialRole;
  final AuthService _authService = AuthService();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _orgController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

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

    String? error = await _authService.signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
      name: _nameController.text.trim(),
      organization: _orgController.text.trim(),
      role: _role,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (error == null) {
        // Use pushAndRemoveUntil to ensure a clean navigation to Dashboard
        // This provides a smoother transition than popUntil
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => AuthWrapper()),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
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
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                      color: Colors.white.withOpacity(0.90),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Back to login',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.70),
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
                        color: Colors.white.withOpacity(0.65),
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
                      _role == UserRole.supervisor
                          ? 'Set up your supervisor profile'
                          : 'Set up your worker profile',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.70),
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
                        _FieldLabel('Select your role'),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _RoleTile(
                                title: 'Supervisor',
                                subtitle: 'Monitor &\nmanage',
                                icon: Icons.person_outline,
                                selected: _role == UserRole.supervisor,
                                onTap: () => setState(() => _role = UserRole.supervisor),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _RoleTile(
                                title: 'Worker',
                                subtitle: 'Track your\nstatus',
                                icon: Icons.badge_outlined,
                                selected: _role == UserRole.worker,
                                onTap: () => setState(() => _role = UserRole.worker),
                                iconBg: const Color(0xFFDFF3E4),
                                iconColor: const Color(0xFF1E7A34),
                              ),
                            ),
                          ],
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
                        _FieldLabel('Work email'),
                        const SizedBox(height: 8),
                        _Input(
                          controller: _emailController,
                          hintText: 'name@company.com',
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
                                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                      ),
                                      SizedBox(width: 10),
                                      Icon(Icons.arrow_forward_rounded, size: 20),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _role == UserRole.supervisor
                              ? 'Tip: Use your work email for supervisor access.'
                              : 'Tip: Use your work email for worker access.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.black.withOpacity(0.38),
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

class _RoleTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color iconBg;
  final Color iconColor;

  const _RoleTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.iconBg = const Color(0xFFE7F0FF),
    this.iconColor = const Color(0xFF2F80ED),
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFF2F80ED) : Colors.black.withOpacity(0.10),
            width: selected ? 1.4 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: const Color(0xFF16324F),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black.withOpacity(0.45),
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
                height: 1.15,
              ),
            ),
          ],
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
        color: Colors.black.withOpacity(0.70),
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

  const _Input({
    required this.controller,
    required this.hintText,
    this.obscureText = false,
    this.suffix,
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
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.black.withOpacity(0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.black.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2F80ED), width: 1.2),
        ),
      ),
    );
  }
}

