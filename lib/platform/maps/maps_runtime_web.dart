import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'maps_runtime_contract.dart';

const String _webMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_WEB_API_KEY');

MapsRuntime createMapsRuntime({required Duration timeout}) =>
    _WebMapsRuntime(apiKey: _webMapsApiKey, timeout: timeout);

final class _WebMapsRuntime implements MapsRuntime {
  _WebMapsRuntime({required this.apiKey, required this.timeout});

  final String apiKey;
  final Duration timeout;
  Future<MapsRuntimeResult>? _initialization;

  @override
  Future<MapsRuntimeResult> initialize() =>
      _initialization ??= _initializeOnce();

  Future<MapsRuntimeResult> _initializeOnce() async {
    if (_mapsJavascriptApiIsReady()) {
      return const MapsRuntimeResult.ready();
    }
    final normalizedKey = apiKey.trim();
    if (normalizedKey.isEmpty) {
      return const MapsRuntimeResult(
        MapsRuntimeStatus.missingKey,
        message: 'No Web Maps API key is configured.',
      );
    }
    if (_looksLikePlaceholder(normalizedKey)) {
      return const MapsRuntimeResult(
        MapsRuntimeStatus.invalidConfiguration,
        message: 'The Web Maps API key configuration is a placeholder.',
      );
    }

    final existing = web.document.querySelector(
      'script[data-smart-safety-google-maps]',
    );
    final script = existing == null
        ? _appendMapsScript(normalizedKey)
        : existing as web.HTMLScriptElement;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_mapsJavascriptApiIsReady()) {
        // Give the SDK's authentication callback a chance to reject an
        // invalid or incorrectly restricted key before any map is rendered.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (script.dataset['loadState'] == 'failed') {
          return const MapsRuntimeResult(
            MapsRuntimeStatus.invalidConfiguration,
            message: 'The Web Maps API key was rejected.',
          );
        }
        return const MapsRuntimeResult.ready();
      }
      if (script.dataset['loadState'] == 'failed') {
        return const MapsRuntimeResult(
          MapsRuntimeStatus.loadFailed,
          message: 'The Google Maps JavaScript API failed to load.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return const MapsRuntimeResult(
      MapsRuntimeStatus.timedOut,
      message: 'The Google Maps JavaScript API did not become ready in time.',
    );
  }

  web.HTMLScriptElement _appendMapsScript(String key) {
    final script = web.HTMLScriptElement()
      ..async = true
      ..defer = true
      ..dataset['smartSafetyGoogleMaps'] = 'true'
      ..src = Uri.https('maps.googleapis.com', '/maps/api/js', {
        'key': key,
        'loading': 'async',
      }).toString();
    globalContext.setProperty(
      'gm_authFailure'.toJS,
      (() {
        script.dataset['loadState'] = 'failed';
      }).toJS,
    );
    script.addEventListener(
      'error',
      ((web.Event _) {
        script.dataset['loadState'] = 'failed';
      }).toJS,
    );
    web.document.head?.append(script);
    return script;
  }

  bool _mapsJavascriptApiIsReady() {
    try {
      final google = globalContext.getProperty<JSAny?>('google'.toJS);
      if (google == null) return false;
      final maps = (google as JSObject).getProperty<JSAny?>('maps'.toJS);
      return maps != null;
    } on Object {
      return false;
    }
  }

  bool _looksLikePlaceholder(String key) {
    final normalized = key.toLowerCase();
    return normalized.contains('replace') ||
        normalized.contains('placeholder') ||
        normalized.contains('<') ||
        normalized.contains('>');
  }
}
