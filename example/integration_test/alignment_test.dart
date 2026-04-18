import 'package:dart_chromaprint/dart_chromaprint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
  });

  test('FFT frontend matches Rust baseline on decoded PCM fixture', () {
    const path = '../test/test_decoded.pcm';
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

    final spectrum = ChromaprintFft().transformFlattened(processed);
    _expectClose(spectrum, rustSpectrum, maxAbsDiff: 1e-6, meanAbsDiff: 1e-8);
  });

  test('chroma stages match Rust baselines on decoded PCM fixture', () {
    const path = '../test/test_decoded.pcm';
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
