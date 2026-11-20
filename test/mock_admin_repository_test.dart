import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/data/mock_admin_repository.dart';
import 'package:smart_safety/data/mock_repositories.dart';
import 'package:smart_safety/domain/repositories.dart';
import 'package:smart_safety/user_role.dart';

void main() {
  group('MockAdminRepository (demo admin console backend)', () {
    late MockAdminRepository repository;

    setUp(() {
      repository = MockAdminRepository(MockDataSet.currentDemo());
    });

    test('seeds the demo administrator and the full demo team', () async {
      final users = await repository.watchUsers().first;
      expect(users, hasLength(7));
      final admin = users.singleWhere(
        (user) => user.email == 'admin@example.test',
      );
      expect(admin.role, UserRole.administrator);
      expect(admin.active, isTrue);
      expect(repository.isLive, isTrue);
    });

    test('overview counts include the administrator', () async {
      final overview = await repository.watchOverview().first;
      expect(overview.totalUsers, 7);
      expect(overview.administrators, 1);
      expect(overview.supervisors, 1);
      expect(overview.workers, 5);
      expect(overview.totalHelmets, greaterThan(0));
    });

    test('createUser adds the account, returns a setup link, and audits',
        () async {
      final result = await repository.createUser(
        email: 'new.supervisor@example.test',
        name: 'New Supervisor',
        role: UserRole.supervisor,
        siteIds: const ['site-main'],
      );
      expect(result.uid, isNotEmpty);
      expect(result.passwordSetupLink, contains(result.uid));

      final users = await repository.watchUsers().first;
      expect(users, hasLength(8));

      final audit = await repository.watchAuditLog().first;
      expect(audit.first.action, 'createUser');
      expect(audit.first.targetId, result.uid);
    });

    test('createUser rejects a duplicate email', () async {
      await expectLater(
        repository.createUser(
          email: 'worker@example.test',
          name: 'Duplicate',
          role: UserRole.worker,
        ),
        throwsA(
          isA<RepositoryAccessException>().having(
            (error) => error.code,
            'code',
            'ALREADY_EXISTS',
          ),
        ),
      );
    });

    test('an administrator cannot change their own role', () async {
      await expectLater(
        repository.setUserRole(uid: 'admin-demo', role: UserRole.supervisor),
        throwsA(
          isA<RepositoryAccessException>().having(
            (error) => error.code,
            'code',
            'PERMISSION_DENIED',
          ),
        ),
      );
    });

    test('registerHelmet returns a one-time secret and lists the helmet',
        () async {
      final result = await repository.registerHelmet(
        helmetId: 'H-99',
        siteId: 'site-main',
      );
      expect(result.secret.keyVersion, 'v1');
      expect(result.secret.secretBase64, isNotEmpty);
      expect(result.helmet.provisioningStatus, 'provisioned');

      final helmets = await repository.watchHelmetsMeta().first;
      expect(helmets.map((helmet) => helmet.helmetId), contains('H-99'));

      final rotated = await repository.rotateHelmetSecret(helmetId: 'H-99');
      expect(rotated.keyVersion, 'v2');
      expect(rotated.secretBase64, isNot(result.secret.secretBase64));

      final audit = await repository.watchAuditLog().first;
      expect(
        audit.map((entry) => entry.action),
        containsAll(['registerHelmet', 'rotateHelmetSecret']),
      );
      // Secrets never reach the audit log.
      expect(
        audit.map((entry) => entry.summary).join(' '),
        isNot(contains(result.secret.secretBase64)),
      );
    });

    test('assignHelmet syncs the worker authorized helmets both ways',
        () async {
      await repository.registerHelmet(helmetId: 'H-98', siteId: 'site-main');
      await repository.assignHelmet(helmetId: 'H-98', workerUid: 'worker-ali');

      var assignments = await repository.getUserAssignments('worker-ali');
      expect(assignments.authorizedHelmetIds, contains('H-98'));

      await repository.assignHelmet(helmetId: 'H-98', workerUid: null);
      assignments = await repository.getUserAssignments('worker-ali');
      expect(assignments.authorizedHelmetIds, isNot(contains('H-98')));
    });
  });
}
