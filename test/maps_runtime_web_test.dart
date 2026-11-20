// Browser-only: run with  flutter test --platform chrome test/maps_runtime_web_test.dart
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/platform/maps/maps_runtime_contract.dart';
import 'package:smart_safety/platform/maps/maps_runtime_web.dart';

void main() {
  test('web maps runtime is ready without any API key', () async {
    final runtime = createMapsRuntime(timeout: const Duration(seconds: 1));
    final result = await runtime.initialize();
    expect(result.status, MapsRuntimeStatus.ready);
    expect(result.canRenderInteractiveMap, isTrue);
  });
}
