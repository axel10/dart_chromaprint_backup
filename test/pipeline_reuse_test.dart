import 'dart:io';
import 'dart:typed_data';

import 'package:dart_chromaprint/dart_chromaprint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reusing the same pipeline produces stable fingerprints', () {
    const sampleRate = 44100;
    const channels = 2;

    final bytes = File('test/test_decoded.pcm').readAsBytesSync();
    final samples = ChromaprintPreprocessor.decodeLittleEndianPcm(
      Uint8List.sublistView(bytes),
    );
    final pipeline = ChromaprintPipeline();

    final first = pipeline.fingerprintWordsFromInt16Pcm(
      samples: samples,
      sampleRate: sampleRate,
      channels: channels,
    );
    final second = pipeline.fingerprintWordsFromInt16Pcm(
      samples: samples,
      sampleRate: sampleRate,
      channels: channels,
    );
    final baseline = fingerprintWordsFromInt16Pcm(
      samples: samples,
      sampleRate: sampleRate,
      channels: channels,
    );

    expect(first, baseline);
    expect(second, baseline);
  });
}
