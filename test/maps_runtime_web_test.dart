// Browser-only: run with  flutter test --platform chrome test/maps_runtime_web_test.dart
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/platform/maps/maps_runtime_contract.dart';
import 'package:smart_safety/platform/maps/maps_runtime_web.dart';
import 'package:web/web.dart' as web;

/// Inserts the marker script the runtime looks for, without any src, so no
/// network request is made. [loadState] mimics gm_authFailure / onerror.
web.HTMLScriptElement _existingScript({String? loadState}) {
  final script = web.HTMLScriptElement()
    ..setAttribute('data-smart-safety-google-maps', 'true');
  if (loadState != null) script.setAttribute('data-load-state', loadState);
  web.document.head!.append(script);
  return script;
}

void _setGoogleMapsReady() {
  final google = JSObject()..setProperty('maps'.toJS, JSObject());
  globalContext.setProperty('google'.toJS, google);
}

void main() {
  tearDown(() {
    final scripts = web.document.querySelectorAll(
      'script[data-smart-safety-google-maps]',
    );
    for (var index = 0; index < scripts.length; index++) {
      (scripts.item(index)! as web.Element).remove();
    }
    globalContext.delete('google'.toJS);
  });

  MapsRuntime runtime(String key, {int timeoutMs = 400}) =>
      createWebMapsRuntimeForTesting(
        apiKey: key,
        timeout: Duration(milliseconds: timeoutMs),
      );

  test('a missing key reports missingKey', () async {
    final result = await runtime('  ').initialize();
    expect(result.status, MapsRuntimeStatus.missingKey);
  });

  test('a placeholder key is treated as invalid configuration', () async {
    final result = await runtime('REPLACE_WITH_KEY').initialize();
    expect(result.status, MapsRuntimeStatus.invalidConfiguration);
  });

  test('a script without load-state attribute is read safely (no TypeError)', () async {
    _existingScript();
    final result = await runtime('test-key', timeoutMs: 300).initialize();
    expect(result.status, MapsRuntimeStatus.timedOut);
  });

  test('a failed script load reports loadFailed', () async {
    _existingScript(loadState: 'failed');
    final result = await runtime('test-key').initialize();
    expect(result.status, MapsRuntimeStatus.loadFailed);
  });

  test('a key rejected by the Maps SDK reports invalid configuration', () async {
    final script = _existingScript();
    final pending = runtime('test-key', timeoutMs: 3000).initialize();
    // The SDK finishes loading, then its auth callback rejects the key inside
    // the runtime's post-load check window (gm_authFailure).
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _setGoogleMapsReady();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    script.setAttribute('data-load-state', 'failed');
    final result = await pending;
    expect(result.status, MapsRuntimeStatus.invalidConfiguration);
    expect(result.message, 'The Web Maps API key was rejected.');
  });

  test('an SDK that loads with an accepted key is ready', () async {
    _existingScript();
    final pending = runtime('test-key', timeoutMs: 3000).initialize();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _setGoogleMapsReady();
    final result = await pending;
    expect(result.status, MapsRuntimeStatus.ready);
  });

  test('an already loaded SDK is reused without a key check', () async {
    _setGoogleMapsReady();
    final result = await runtime('test-key').initialize();
    expect(result.status, MapsRuntimeStatus.ready);
  });
}
