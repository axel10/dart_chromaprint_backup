import 'package:dart_chromaprint/dart_chromaprint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
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
    final dartSpectrum = fft.transformFlattened(_toDoubleList(processed));

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

List<double> _toDoubleList(List<double> samples) =>
    samples.toList(growable: false);
