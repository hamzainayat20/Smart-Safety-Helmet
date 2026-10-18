import '../data/mock_repositories.dart';
import '../domain/repositories.dart';

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
    required this.alerts,
    required this.configuration,
    required this.dataSourceKind,
    this.notifications = const NoopNotificationRepository(),
    SensitiveDataRegistry? sensitiveData,
  }) : sensitiveData = sensitiveData ?? SensitiveDataRegistry();

  final AuthenticationRepository authentication;
  final UserRepository users;
  final SiteRepository sites;
  final HelmetRepository helmets;
  final ReadingRepository readings;
  final AlertRepository alerts;
  final ConfigurationRepository configuration;
  final NotificationRepository notifications;
  final DataSourceKind dataSourceKind;
  final SensitiveDataRegistry sensitiveData;

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
      alerts: MockAlertRepository(data),
      configuration: MockConfigurationRepository(data),
      dataSourceKind: DataSourceKind.deterministicMock,
    );
  }
}
