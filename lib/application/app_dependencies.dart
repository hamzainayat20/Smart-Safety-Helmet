import '../data/mock_repositories.dart';
import '../domain/repositories.dart';
import 'simulated_gps.dart';

typedef SensitiveDataClearer = Future<void> Function();

enum DataSourceKind { liveFirebase, deterministicMock }

final class SensitiveDataRegistry {
  final Set<SensitiveDataClearer> _clearers = {};

  void register(SensitiveDataClearer clearer) => _clearers.add(clearer);

  void unregister(SensitiveDataClearer clearer) => _clearers.remove(clearer);

  Future<void> clearAll() async {
    final clearers = List<SensitiveDataClearer>.of(_clearers);
    for (final clearer in clearers) {
      await clearer();
    }
  }
}

final class AppDependencies {
  AppDependencies({
    required this.authentication,
    required this.users,
    required this.sites,
    required this.helmets,
    required this.readings,
    this.workerLocations = const NoopWorkerLocationRepository(),
    this.workerLocationTracker = const NoopWorkerLocationTracker(),
    this.assessments = const NoopAssessmentRepository(),
    required this.alerts,
    required this.configuration,
    required this.dataSourceKind,
    this.notifications = const NoopNotificationRepository(),
    this.assistant = const NoopAssistantRepository(),
    SensitiveDataRegistry? sensitiveData,
    SimulatedLocationProvider? simulatedLocations,
  }) : sensitiveData = sensitiveData ?? SensitiveDataRegistry(),
       simulatedLocations =
           simulatedLocations ?? simulatedLocationProviderFromEnvironment();

  final AuthenticationRepository authentication;
  final UserRepository users;
  final SiteRepository sites;
  final HelmetRepository helmets;
  final ReadingRepository readings;
  final WorkerLocationRepository workerLocations;
  final WorkerLocationTracker workerLocationTracker;
  final AssessmentRepository assessments;
  final AlertRepository alerts;
  final ConfigurationRepository configuration;
  final NotificationRepository notifications;
  final AssistantRepository assistant;
  final DataSourceKind dataSourceKind;
  final SensitiveDataRegistry sensitiveData;

  /// Map-only demo locations. Disabled unless this build was compiled with
  /// SMART_SAFETY_ENABLE_SIMULATED_GPS=true and a valid test coordinate.
  final SimulatedLocationProvider simulatedLocations;

  factory AppDependencies.allMocks({
    String? initialUid,
    DateTime? referenceTimeUtc,
    Set<String> unverifiedUids = const {},
    Set<String> disabledUids = const {},
    Set<String> unclaimedUids = const {},
    bool backendConnected = true,
  }) {
    final data = MockDataSet.currentDemo(referenceTimeUtc: referenceTimeUtc);
    return AppDependencies(
      authentication: MockAuthenticationRepository(
        data,
        initialUid: initialUid,
        unverifiedUids: unverifiedUids,
        disabledUids: disabledUids,
        unclaimedUids: unclaimedUids,
      ),
      users: MockUserRepository(data),
      sites: MockSiteRepository(data),
      helmets: MockHelmetRepository(data),
      readings: MockReadingRepository(data, backendConnected: backendConnected),
      assessments: MockAssessmentRepository(data),
      assistant: MockAssistantRepository(),
      alerts: MockAlertRepository(data),
      configuration: MockConfigurationRepository(data),
      dataSourceKind: DataSourceKind.deterministicMock,
    );
  }
}
