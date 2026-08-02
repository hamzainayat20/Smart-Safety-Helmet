enum UserRole { supervisor, worker }

extension UserRoleLabel on UserRole {
  String get label {
    switch (this) {
      case UserRole.supervisor:
        return 'Supervisor';
      case UserRole.worker:
        return 'Worker';
    }
  }

  String get accessLabel {
    switch (this) {
      case UserRole.supervisor:
        return 'SUPERVISOR ACCESS';
      case UserRole.worker:
        return 'WORKER ACCESS';
    }
  }
}

