enum MapsRuntimeStatus {
  ready,
  missingKey,
  invalidConfiguration,
  loadFailed,
  timedOut,
}

final class MapsRuntimeResult {
  const MapsRuntimeResult(this.status, {this.message});

  const MapsRuntimeResult.ready() : this(MapsRuntimeStatus.ready);

  final MapsRuntimeStatus status;
  final String? message;

  bool get canRenderInteractiveMap => status == MapsRuntimeStatus.ready;
}

abstract interface class MapsRuntime {
  Future<MapsRuntimeResult> initialize();
}
