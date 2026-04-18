import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_chromaprint/dart_chromaprint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
  });

  test('Dart and Rust fingerprint performance comparison', () async {
    const path = '../test/test_decoded.pcm';
    const sampleRate = 44100;
    const channels = 2;
    const warmupRuns = 2;
    const measuredRuns = 5;

    final file = File(path);
    expect(file.existsSync(), isTrue, reason: 'Missing fixture: $path');
    final bytes = file.readAsBytesSync();
    final samples = ChromaprintPreprocessor.decodeLittleEndianPcm(
      Uint8List.fromList(bytes),
    );
    final pipeline = ChromaprintPipeline();

    final dartWordResult = await _benchmark<Uint32List>(
      label: 'dart_words',
      warmupRuns: warmupRuns,
      measuredRuns: measuredRuns,
      body: () {
        return pipeline.fingerprintWordsFromInt16Pcm(
          samples: samples,
          sampleRate: sampleRate,
          channels: channels,
        );
      },
    );

    final rustWordResult = await _benchmark<Uint32List>(
      label: 'rust_words',
      warmupRuns: warmupRuns,
      measuredRuns: measuredRuns,
      body: () {
        return getFingerprintWordsFromPcm(
          samples: samples,
          sampleRate: sampleRate,
          channels: channels,
        );
      },
    );

    expect(dartWordResult.lastValue, rustWordResult.lastValue);

    final dartStringResult = await _benchmark<String>(
      label: 'dart_string',
      warmupRuns: warmupRuns,
      measuredRuns: measuredRuns,
      body: () {
        return pipeline.fingerprintStringFromInt16Pcm(
          samples: samples,
          sampleRate: sampleRate,
          channels: channels,
        );
      },
    );

    final rustStringResult = await _benchmark<String>(
      label: 'rust_string',
      warmupRuns: warmupRuns,
      measuredRuns: measuredRuns,
      body: () {
        return getFingerprintRawFromPcm(
          samples: samples,
          sampleRate: sampleRate,
          channels: channels,
        );
      },
    );

    expect(dartStringResult.lastValue, rustStringResult.lastValue);

    final wordRatio =
        rustWordResult.averageMicros / dartWordResult.averageMicros;
    final stringRatio =
        rustStringResult.averageMicros / dartStringResult.averageMicros;

    // ignore: avoid_print
    print(
      [
        'In-memory fingerprint benchmark on $path',
        'Words  : Dart ${dartWordResult.averageMicros.toStringAsFixed(1)} us, '
            'Rust ${rustWordResult.averageMicros.toStringAsFixed(1)} us, '
            'Rust/Dart ${wordRatio.toStringAsFixed(2)}x',
        'String : Dart ${dartStringResult.averageMicros.toStringAsFixed(1)} us, '
            'Rust ${rustStringResult.averageMicros.toStringAsFixed(1)} us, '
            'Rust/Dart ${stringRatio.toStringAsFixed(2)}x',
      ].join('\n'),
    );
  });
}

class _BenchmarkResult<T> {
  const _BenchmarkResult({
    required this.averageMicros,
    required this.lastValue,
  });

  final double averageMicros;
  final T lastValue;
}

Future<_BenchmarkResult<T>> _benchmark<T>({
  required String label,
  required int warmupRuns,
  required int measuredRuns,
  required FutureOr<T> Function() body,
}) async {
  T lastValue = await body();

  for (var i = 0; i < warmupRuns; i++) {
    lastValue = await body();
  }

  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < measuredRuns; i++) {
    lastValue = await body();
  }
  stopwatch.stop();

  final averageMicros = stopwatch.elapsedMicroseconds / measuredRuns;
  // ignore: avoid_print
  print('$label: ${averageMicros.toStringAsFixed(1)} us average');
  return _BenchmarkResult(averageMicros: averageMicros, lastValue: lastValue);
}
