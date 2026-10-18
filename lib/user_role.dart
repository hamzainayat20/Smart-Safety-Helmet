enum UserRole { administrator, supervisor, worker }

UserRole? userRoleFromTrustedClaim(Object? value) {
  if (value is! String) return null;
  return switch (value) {
    'administrator' || 'admin' => UserRole.administrator,
    'supervisor' => UserRole.supervisor,
    'worker' => UserRole.worker,
    _ => null,
  };
}

extension UserRoleLabel on UserRole {
  String get label {
    switch (this) {
      case UserRole.administrator:
        return 'Administrator';
      case UserRole.supervisor:
        return 'Supervisor';
      case UserRole.worker:
        return 'Worker';
    }
  }

  String get accessLabel {
    switch (this) {
      case UserRole.administrator:
        return 'ADMINISTRATOR ACCESS';
      case UserRole.supervisor:
        return 'SUPERVISOR ACCESS';
      case UserRole.worker:
        return 'WORKER ACCESS';
    }
  }
}
