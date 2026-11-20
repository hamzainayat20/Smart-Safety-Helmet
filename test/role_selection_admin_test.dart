import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/application/app_dependencies.dart';
import 'package:smart_safety/application/session_controller.dart';
import 'package:smart_safety/role_selection_screen.dart';
import 'package:smart_safety/user_role.dart';

void main() {
  group('Administrator on the workspace selection screen', () {
    testWidgets(
      'shows an Administrator card and continues to an invite-only admin login',
      (tester) async {
        final dependencies = AppDependencies.allMocks();
        final session = SessionController(dependencies)..start();

        await tester.pumpWidget(
          MaterialApp(home: RoleSelectionScreen(session: session)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Supervisor'), findsOneWidget);
        expect(find.text('Worker'), findsOneWidget);
        // The third card sits below the fold of the role list.
        await tester.scrollUntilVisible(find.text('Administrator'), 80);
        await tester.pumpAndSettle();
        expect(find.text('Administrator'), findsOneWidget);

        await tester.tap(find.text('Administrator'));
        await tester.pumpAndSettle();
        expect(find.text('Continue as Administrator'), findsOneWidget);

        await tester.tap(find.text('Continue as Administrator'));
        await tester.pumpAndSettle();

        // The administrator login offers no self-service sign-up: admin
        // accounts are created by an existing admin or the bootstrap.
        expect(
          find.text('Administrator accounts are invite-only'),
          findsOneWidget,
        );
        expect(find.text('Create worker account'), findsNothing);
        session.dispose();
      },
    );
  });

  group('Administrator sign-in (demo accounts)', () {
    test(
      'demo administrator signs in through the administrator portal',
      () async {
        final session = SessionController(AppDependencies.allMocks());
        final result = await session.signIn(
          email: 'admin@example.test',
          password: 'password',
          expectedRole: UserRole.administrator,
        );
        expect(result.succeeded, isTrue);
        session.dispose();
      },
    );

    test(
      'the administrator account cannot enter through another portal',
      () async {
        final session = SessionController(AppDependencies.allMocks());
        final result = await session.signIn(
          email: 'admin@example.test',
          password: 'password',
          expectedRole: UserRole.supervisor,
        );
        expect(result.succeeded, isFalse);
        expect(result.issue, SessionIssue.roleMismatch);
        session.dispose();
      },
    );

    test(
      'a worker account cannot enter through the administrator portal',
      () async {
        final session = SessionController(AppDependencies.allMocks());
        final result = await session.signIn(
          email: 'worker@example.test',
          password: 'password',
          expectedRole: UserRole.administrator,
        );
        expect(result.succeeded, isFalse);
        expect(result.issue, SessionIssue.roleMismatch);
        session.dispose();
      },
    );
  });
}
