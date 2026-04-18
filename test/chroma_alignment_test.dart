import 'dart:io';

import 'package:dart_chromaprint/dart_chromaprint.dart';
import 'package:dart_chromaprint/src/rust/frb_generated.dart';
import 'package:dart_chromaprint/src/rust/frb_generated.io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';
import 'package:flutter_rust_bridge/src/generalized_frb_rust_binding/generalized_frb_rust_binding.dart';
import 'package:flutter_rust_bridge/src/main_components/port_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final libraryPath = Directory.current.uri
        .resolve('rust/target/release/dart_chromaprint.dll')
        .toFilePath();
    if (RustLib.instance.initialized) {
      return;
    }

    final externalLibrary = ExternalLibrary.open(libraryPath);
    final handler = BaseHandler();
    final binding = GeneralizedFrbRustBinding(externalLibrary);
    final portManager = PortManager(binding, handler);
    final api = RustLibApiImpl(
      handler: handler,
      wire: RustLibWire.fromExternalLibrary(externalLibrary),
      generalizedFrbRustBinding: binding,
      portManager: portManager,
    );

    RustLib.initMock(api: api);
    await api.crateApiSimpleInitApp();
  });

  test('chroma pipeline matches Rust baselines on decoded PCM fixture', () {
    const path = 'test/test_decoded.pcm';
    const sampleRate = 44100;
    const channels = 2;

    final processed = getProcessedPcm(
      path: path,
      sampleRate: sampleRate,
      channels: channels,
    );

    final spectrum = ChromaprintFft().transformFlattened(processed);
    final chroma = ChromaprintChroma().transformFlattened(spectrum);
    final filtered = ChromaprintChromaFilter().transformFlattened(chroma);
    final normalized = const ChromaprintChromaNormalizer().transformFlattened(
      filtered,
    );

    final rustChroma = getChromaBaseline(
      path: path,
      sampleRate: sampleRate,
      channels: channels,
    );
    final rustFiltered = getFilteredChromaBaseline(
      path: path,
      sampleRate: sampleRate,
      channels: channels,
    );
    final rustNormalized = getNormalizedChromaBaseline(
      path: path,
      sampleRate: sampleRate,
      channels: channels,
    );

    _expectClose(chroma, rustChroma, maxAbsDiff: 1e-6, meanAbsDiff: 1e-8);
    _expectClose(filtered, rustFiltered, maxAbsDiff: 1e-6, meanAbsDiff: 1e-8);
    _expectClose(
      normalized,
      rustNormalized,
      maxAbsDiff: 1e-6,
      meanAbsDiff: 1e-8,
    );
  });
}

void _expectClose(
  List<double> actual,
  List<double> expected, {
  required double maxAbsDiff,
  required double meanAbsDiff,
}) {
  expect(actual.length, expected.length);

  var actualMax = 0.0;
  var actualMean = 0.0;
  for (var i = 0; i < actual.length; i++) {
    final diff = (actual[i] - expected[i]).abs();
    if (diff > actualMax) {
      actualMax = diff;
    }
    actualMean += diff;
  }
  actualMean /= actual.length;

  expect(actualMax, lessThan(maxAbsDiff));
  expect(actualMean, lessThan(meanAbsDiff));
}
