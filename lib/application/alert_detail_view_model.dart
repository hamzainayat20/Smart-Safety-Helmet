import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';
import '../user_role.dart';
import 'app_dependencies.dart';

final class AlertDetailViewModel extends ChangeNotifier {
  AlertDetailViewModel({
    required this.profile,
    required this.alertId,
    required this.dependencies,
  });

  final UserProfile profile;
  final String alertId;
  final AppDependencies dependencies;

  StreamSubscription<SafetyAlert?>? _subscription;
  StreamSubscription<Map<String, WorkerLocation>>? _locationSubscription;
  SafetyAlert? _alert;
  Map<String, WorkerLocation> _locations = const {};
  RepositoryAccessException? _error;
  bool _loading = true;
  bool _markingViewed = false;
  bool _acknowledging = false;
  bool _resolving = false;
  bool _retryingDelivery = false;

  SafetyAlert? get alert => _alert;
  WorkerLocation? get latestPhoneLocation =>
      _alert == null ? null : _locations[_alert!.helmetId];
  bool get isLoading => _loading;
  String? get errorMessage => _error?.message;
  bool get permissionDenied => _error?.code == 'PERMISSION_DENIED';
  bool get isAcknowledging => _acknowledging;
  bool get isResolving => _resolving;
  bool get isRetryingDelivery => _retryingDelivery;
  bool get canAcknowledge =>
      (profile.role == UserRole.supervisor ||
          profile.role == UserRole.administrator) &&
      _alert != null &&
      _alert!.status != AlertStatus.acknowledged &&
      _alert!.status != AlertStatus.resolved;

  void start() {
    if (_subscription != null) return;
    dependencies.sensitiveData.register(clearSensitiveState);
    _subscription = dependencies.alerts
        .watchAuthorizedAlert(profile, alertId)
        .listen(
          (alert) {
            _alert = alert;
            _loading = false;
            _error = null;
            notifyListeners();
            if (alert != null &&
                (alert.status == AlertStatus.created ||
                    alert.status == AlertStatus.delivered)) {
              unawaited(_markViewedAfterBackendConfirmation());
            }
          },
          onError: (Object error) {
            _loading = false;
            _error = error is RepositoryAccessException
                ? error
                : const RepositoryAccessException(
                    'BACKEND_ERROR',
                    'The alert detail could not be loaded.',
                  );
            notifyListeners();
          },
        );
    if (profile.role == UserRole.supervisor ||
        profile.role == UserRole.administrator) {
      _locationSubscription = dependencies.workerLocations
          .watchLatestLocations(profile)
          .listen((locations) {
            _locations = locations;
            notifyListeners();
          });
    }
  }

  Future<void> _markViewedAfterBackendConfirmation() async {
    if (_markingViewed) return;
    _markingViewed = true;
    try {
      final canonical = await dependencies.alerts.markViewed(
        actor: profile,
        alertId: alertId,
      );
      _alert = canonical;
    } on Object {
      // Viewing remains visible locally; lifecycle state changes only after a
      // canonical backend response and can be retried on the next stream event.
    } finally {
      _markingViewed = false;
      notifyListeners();
    }
  }

  Future<void> acknowledge() async {
    if (_acknowledging || !canAcknowledge) return;
    _acknowledging = true;
    notifyListeners();
    try {
      _alert = await dependencies.alerts.acknowledge(
        actor: profile,
        alertId: alertId,
      );
      _error = null;
    } on Object catch (error) {
      _error = error is RepositoryAccessException
          ? error
          : const RepositoryAccessException(
              'BACKEND_ERROR',
              'Acknowledgement failed. The alert remains unacknowledged.',
            );
      rethrow;
    } finally {
      _acknowledging = false;
      notifyListeners();
    }
  }

  Future<void> resolve(String note) async {
    if (_resolving || _alert?.status != AlertStatus.acknowledged) return;
    _resolving = true;
    notifyListeners();
    try {
      _alert = await dependencies.alerts.resolve(
        actor: profile,
        alertId: alertId,
        resolutionNote: note,
      );
      _error = null;
    } on Object catch (error) {
      _error = error is RepositoryAccessException
          ? error
          : const RepositoryAccessException(
              'BACKEND_ERROR',
              'Resolution was not confirmed by the backend.',
            );
      rethrow;
    } finally {
      _resolving = false;
      notifyListeners();
    }
  }

  Future<void> retryDelivery() async {
    if (_retryingDelivery) return;
    _retryingDelivery = true;
    notifyListeners();
    try {
      _alert = await dependencies.alerts.retryDelivery(
        actor: profile,
        alertId: alertId,
      );
      _error = null;
    } on Object catch (error) {
      _error = error is RepositoryAccessException
          ? error
          : const RepositoryAccessException(
              'BACKEND_ERROR',
              'Notification delivery retry failed.',
            );
      rethrow;
    } finally {
      _retryingDelivery = false;
      notifyListeners();
    }
  }

  Future<void> clearSensitiveState() async {
    await _subscription?.cancel();
    await _locationSubscription?.cancel();
    _subscription = null;
    _locationSubscription = null;
    _alert = null;
    _locations = const {};
    _loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    dependencies.sensitiveData.unregister(clearSensitiveState);
    _subscription?.cancel();
    _locationSubscription?.cancel();
    super.dispose();
  }
}
