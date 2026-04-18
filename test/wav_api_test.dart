import 'dart:io';
import 'dart:typed_data';

import 'package:dart_chromaprint/dart_chromaprint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('wav reader parses fixture metadata', () async {
    const wavPath = 'test/test.wav';
    final wav = await const ChromaprintWavReader().readFile(wavPath);

    expect(wav.sampleRate, 44100);
    expect(wav.channels, 2);
    expect(wav.samples, isNotEmpty);
    expect(wav.samples.length.isEven, isTrue);
  });

  test('wav API output matches parsed PCM pipeline output', () async {
    const wavPath = 'test/test.wav';

    final reader = const ChromaprintWavReader();
    final wavBytes = await File(wavPath).readAsBytes();
    final wav = await reader.readFile(wavPath);
    final fromBytes = fingerprintStringFromWavBytes(
      Uint8List.fromList(wavBytes),
    );
    final fromFile = await fingerprintStringFromWavFile(wavPath);
    final fromParsedPcm = fingerprintStringFromInt16Pcm(
      samples: wav.samples,
      sampleRate: wav.sampleRate,
      channels: wav.channels,
    );

    expect(fromBytes, fromParsedPcm);
    expect(fromFile, fromParsedPcm);
  });
}
