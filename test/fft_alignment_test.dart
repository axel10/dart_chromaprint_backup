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

  test('fftea frontend matches Rust baseline on decoded PCM fixture', () {
    const path = 'test/test_decoded.pcm';
    const sampleRate = 44100;
    const channels = 2;

    final processed = getProcessedPcm(
      path: path,
      sampleRate: sampleRate,
      channels: channels,
    );
    final rustSpectrum = getFftSpectrumBaseline(
      path: path,
      sampleRate: sampleRate,
      channels: channels,
    );

    final fft = ChromaprintFft();
    final dartSpectrum = fft.transformFlattened(processed);

    expect(dartSpectrum.length, rustSpectrum.length);

    var maxAbsDiff = 0.0;
    var meanAbsDiff = 0.0;
    for (var i = 0; i < rustSpectrum.length; i++) {
      final diff = (dartSpectrum[i] - rustSpectrum[i]).abs();
      if (diff > maxAbsDiff) {
        maxAbsDiff = diff;
      }
      meanAbsDiff += diff;
    }
    meanAbsDiff /= rustSpectrum.length;

    expect(maxAbsDiff, lessThan(1e-6));
    expect(meanAbsDiff, lessThan(1e-8));
  });
}
