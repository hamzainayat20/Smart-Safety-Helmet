import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'application/session_controller.dart';
import 'login_screen.dart';
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
    const bgTop = Color(0xFF0B1C3A);
    const bgBottom = Color(0xFF07152C);
    const subtitleColor = Color(0xFF77A6D7);
    const cardBg = Color(0xFF0C2346);
    const cardBorder = Color(0xFF1D5FA5);
    const chipBg = Color(0xFF12335F);
    const chipText = Color(0xFF8DB7E6);
    const buttonBg = Color(0xFF2F80ED);

    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    final titleSize = (w * 0.075).clamp(22.0, 30.0);
    final subtitleSize = (w * 0.038).clamp(12.0, 15.0);

    return Scaffold(
      backgroundColor: bgBottom,
      body: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.enter): _continueToLogin,
          const SingleActivator(LogicalKeyboardKey.numpadEnter):
              _continueToLogin,
        },
        child: Focus(
          autofocus: true,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [bgTop, bgBottom],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: (w * 0.08).clamp(22.0, 36.0),
                ),
                child: ListView(
                  children: [
                    SizedBox(height: (h * 0.04).clamp(10.0, 22.0)),
                    _AppMark(size: (w * 0.18).clamp(64.0, 86.0)),
                    SizedBox(height: (h * 0.02).clamp(10.0, 18.0)),
                    Text(
                      'Who are you?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Choose a portal. Your trusted account\nassignment controls access.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: subtitleSize,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: subtitleColor,
                      ),
                    ),
                    SizedBox(height: (h * 0.03).clamp(14.0, 22.0)),
                    _RoleCard(
                      title: 'Supervisor',
                      description:
                          'Monitor workers, receive\nalerts, manage helmets',
                      leading: Icons.supervisor_account,
                      chips: const ['Live dashboard', 'GPS map', 'Alerts'],
                      selected: _role == UserRole.supervisor,
                      onTap: () => setState(() => _role = UserRole.supervisor),
                      cardBg: cardBg,
                      chipBg: chipBg,
                      chipText: chipText,
                      borderColor: cardBorder,
                    ),
                    SizedBox(height: (h * 0.02).clamp(12.0, 16.0)),
                    _DividerOr(color: Colors.white.withValues(alpha: 0.18)),
                    SizedBox(height: (h * 0.02).clamp(12.0, 16.0)),
                    _RoleCard(
                      title: 'Worker',
                      description: 'View your own\nhelmet status and\nalerts',
                      leading: Icons.badge_outlined,
                      chips: const ['Status view', 'My alerts'],
                      selected: _role == UserRole.worker,
                      onTap: () => setState(() => _role = UserRole.worker),
                      cardBg: cardBg,
                      chipBg: chipBg,
                      chipText: chipText,
                      borderColor: cardBorder,
                    ),
                    SizedBox(height: (h * 0.03).clamp(16.0, 28.0)),
                    _SelectedRolePill(role: _role),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: (h * 0.065).clamp(48.0, 56.0),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: buttonBg,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _continueToLogin,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _role == UserRole.supervisor
                                  ? 'Continue as Supervisor'
                                  : 'Continue as Worker',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Icon(Icons.arrow_forward_rounded, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
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

class _AppMark extends StatelessWidget {
  final double size;

  const _AppMark({required this.size});

  @override
  Widget build(BuildContext context) {
    const iconBg = Color(0xFF2E73B3);
    final radius = (size * 0.30).clamp(18.0, 26.0);
    final iconSize = (size * 0.46).clamp(28.0, 44.0);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: iconBg,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            color: iconBg.withValues(alpha: 0.25),
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Icon(Icons.shield, color: Colors.white, size: iconSize),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData leading;
  final List<String> chips;
  final bool selected;
  final VoidCallback onTap;
  final Color cardBg;
  final Color chipBg;
  final Color chipText;
  final Color borderColor;

  const _RoleCard({
    required this.title,
    required this.description,
    required this.leading,
    required this.chips,
    required this.selected,
    required this.onTap,
    required this.cardBg,
    required this.chipBg,
    required this.chipText,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final radius = (w * 0.06).clamp(16.0, 20.0);
    final borderW = selected ? 1.4 : 1.0;

    return InkWell(
      borderRadius: BorderRadius.circular(radius),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg.withValues(alpha: selected ? 0.96 : 0.82),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: selected
                ? borderColor
                : Colors.white.withValues(alpha: 0.12),
            width: borderW,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: chipBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(leading, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: selected ? 1 : 0,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2F80ED),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.check,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: chips
                        .map(
                          (t) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: chipBg,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              t,
                              style: TextStyle(
                                color: chipText,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DividerOr extends StatelessWidget {
  final Color color;

  const _DividerOr({required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: color, thickness: 1)),
        const SizedBox(width: 12),
        Text(
          'or',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.38),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: color, thickness: 1)),
      ],
    );
  }
}

class _SelectedRolePill extends StatelessWidget {
  final UserRole role;

  const _SelectedRolePill({required this.role});

  @override
  Widget build(BuildContext context) {
    final label = role.label;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 8, color: Color(0xFF2F80ED)),
          const SizedBox(width: 10),
          Text(
            'Portal preference: ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF77A6D7),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
