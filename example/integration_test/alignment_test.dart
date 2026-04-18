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

  test('subfingerprints match Rust baseline on decoded PCM fixture', () {
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
    final fingerprint = ChromaprintFingerprintCalculator().transformFlattened(
      normalized,
    );

    final rustFingerprint = getFingerprintWordsBaseline(
      path: path,
      sampleRate: sampleRate,
      channels: channels,
    );

    expect(fingerprint, rustFingerprint);
  });

  test('pure Dart preprocessing + fingerprint matches Rust baseline', () {
    const path = '../test/test_decoded.pcm';
    final bytes = File(path).readAsBytesSync();
    final samples = ChromaprintPreprocessor.decodeLittleEndianPcm(
      Uint8List.fromList(bytes),
    );

    final fingerprint = fingerprintWordsFromInt16Pcm(
      samples: samples,
      sampleRate: 44100,
      channels: 2,
    );

    final rustFingerprint = getFingerprintWordsBaseline(
      path: path,
      sampleRate: 44100,
      channels: 2,
    );

    expect(fingerprint, rustFingerprint);
  });

  test('compressed fingerprint string matches Rust baseline', () async {
    const path = '../test/test_decoded.pcm';
    final bytes = File(path).readAsBytesSync();
    final samples = ChromaprintPreprocessor.decodeLittleEndianPcm(
      Uint8List.fromList(bytes),
    );

    final fingerprint = fingerprintStringFromInt16Pcm(
      samples: samples,
      sampleRate: 44100,
      channels: 2,
    );

    final rustFingerprint = await getFingerprintRaw(
      path: path,
      sampleRate: 44100,
      channels: 2,
    );

    expect(fingerprint, rustFingerprint);
  });

  test('WAV bytes and file APIs match Rust compressed fingerprint', () async {
    const pcmPath = '../test/test_decoded.pcm';
    final pcmBytes = File(pcmPath).readAsBytesSync();
    final wavBytes = _buildPcm16Wav(
      pcmBytes: pcmBytes,
      sampleRate: 44100,
      channels: 2,
      bitsPerSample: 16,
    );

    final fromBytes = fingerprintStringFromWavBytes(wavBytes);

    final tempDir = await Directory.systemTemp.createTemp('chromaprint_wav_');
    final wavPath = '${tempDir.path}${Platform.pathSeparator}fixture.wav';
    await File(wavPath).writeAsBytes(wavBytes);
    try {
      final fromFile = await fingerprintStringFromWavFile(wavPath);
      final rustFingerprint = await getFingerprintRaw(
        path: pcmPath,
        sampleRate: 44100,
        channels: 2,
      );

      expect(fromBytes, rustFingerprint);
      expect(fromFile, rustFingerprint);
    } finally {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
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

Uint8List _buildPcm16Wav({
  required List<int> pcmBytes,
  required int sampleRate,
  required int channels,
  required int bitsPerSample,
}) {
  final dataSize = pcmBytes.length;
  final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
  final blockAlign = channels * (bitsPerSample ~/ 8);
  final fileSize = 36 + dataSize;

  final bytes = BytesBuilder(copy: false)
    ..add('RIFF'.codeUnits)
    ..add(_uint32le(fileSize))
    ..add('WAVE'.codeUnits)
    ..add('fmt '.codeUnits)
    ..add(_uint32le(16))
    ..add(_uint16le(1))
    ..add(_uint16le(channels))
    ..add(_uint32le(sampleRate))
    ..add(_uint32le(byteRate))
    ..add(_uint16le(blockAlign))
    ..add(_uint16le(bitsPerSample))
    ..add('data'.codeUnits)
    ..add(_uint32le(dataSize))
    ..add(pcmBytes);

  return bytes.takeBytes();
}

Uint8List _uint16le(int value) {
  final data = ByteData(2)..setUint16(0, value, Endian.little);
  return data.buffer.asUint8List();
}

Uint8List _uint32le(int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.little);
  return data.buffer.asUint8List();
}
