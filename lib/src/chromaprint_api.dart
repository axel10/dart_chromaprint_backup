import 'dart:io';
import 'dart:typed_data';

import 'chromaprint_encoding.dart';
import 'chromaprint_features.dart';
import 'chromaprint_fft.dart';
import 'chromaprint_fingerprint.dart';
import 'chromaprint_preprocessing.dart';
import 'chromaprint_wav.dart';

Uint32List fingerprintWordsFromProcessedPcm(
  List<double> monoSamples, {
  ChromaprintFft? fft,
  ChromaprintChroma? chroma,
  ChromaprintChromaFilter? chromaFilter,
  ChromaprintChromaNormalizer? normalizer,
  ChromaprintFingerprintCalculator? fingerprintCalculator,
}) {
  final fftStage = fft ?? ChromaprintFft();
  final chromaStage = chroma ?? ChromaprintChroma();
  final filterStage = chromaFilter ?? ChromaprintChromaFilter();
  final normalizerStage = normalizer ?? const ChromaprintChromaNormalizer();
  final fingerprintStage =
      fingerprintCalculator ?? ChromaprintFingerprintCalculator();

  final spectrum = fftStage.transformFlattened(monoSamples);
  final chromaValues = chromaStage.transformFlattened(spectrum);
  final filtered = filterStage.transformFlattened(chromaValues);
  final normalized = normalizerStage.transformFlattened(filtered);
  return fingerprintStage.transformFlattened(normalized);
}

Uint32List fingerprintWordsFromInt16Pcm({
  required Int16List samples,
  required int sampleRate,
  required int channels,
  ChromaprintPreprocessor preprocessor = const ChromaprintPreprocessor(),
  ChromaprintFft? fft,
  ChromaprintChroma? chroma,
  ChromaprintChromaFilter? chromaFilter,
  ChromaprintChromaNormalizer? normalizer,
  ChromaprintFingerprintCalculator? fingerprintCalculator,
}) {
  final processed = preprocessor.processInt16Pcm(
    samples: samples,
    sampleRate: sampleRate,
    channels: channels,
  );

  return fingerprintWordsFromProcessedPcm(
    processed,
    fft: fft,
    chroma: chroma,
    chromaFilter: chromaFilter,
    normalizer: normalizer,
    fingerprintCalculator: fingerprintCalculator,
  );
}

String fingerprintStringFromProcessedPcm(
  List<double> monoSamples, {
  ChromaprintFft? fft,
  ChromaprintChroma? chroma,
  ChromaprintChromaFilter? chromaFilter,
  ChromaprintChromaNormalizer? normalizer,
  ChromaprintFingerprintCalculator? fingerprintCalculator,
  int algorithmId = chromaprintAlgorithmIdTest2,
}) {
  final words = fingerprintWordsFromProcessedPcm(
    monoSamples,
    fft: fft,
    chroma: chroma,
    chromaFilter: chromaFilter,
    normalizer: normalizer,
    fingerprintCalculator: fingerprintCalculator,
  );
  return encodeFingerprintWords(words, algorithmId: algorithmId);
}

String fingerprintStringFromInt16Pcm({
  required Int16List samples,
  required int sampleRate,
  required int channels,
  ChromaprintPreprocessor preprocessor = const ChromaprintPreprocessor(),
  ChromaprintFft? fft,
  ChromaprintChroma? chroma,
  ChromaprintChromaFilter? chromaFilter,
  ChromaprintChromaNormalizer? normalizer,
  ChromaprintFingerprintCalculator? fingerprintCalculator,
  int algorithmId = chromaprintAlgorithmIdTest2,
}) {
  final words = fingerprintWordsFromInt16Pcm(
    samples: samples,
    sampleRate: sampleRate,
    channels: channels,
    preprocessor: preprocessor,
    fft: fft,
    chroma: chroma,
    chromaFilter: chromaFilter,
    normalizer: normalizer,
    fingerprintCalculator: fingerprintCalculator,
  );
  return encodeFingerprintWords(words, algorithmId: algorithmId);
}

Uint32List fingerprintWordsFromWavBytes(
  Uint8List bytes, {
  ChromaprintWavReader wavReader = const ChromaprintWavReader(),
  ChromaprintPreprocessor preprocessor = const ChromaprintPreprocessor(),
  ChromaprintFft? fft,
  ChromaprintChroma? chroma,
  ChromaprintChromaFilter? chromaFilter,
  ChromaprintChromaNormalizer? normalizer,
  ChromaprintFingerprintCalculator? fingerprintCalculator,
}) {
  final wav = wavReader.parseBytes(bytes);
  return fingerprintWordsFromInt16Pcm(
    samples: wav.samples,
    sampleRate: wav.sampleRate,
    channels: wav.channels,
    preprocessor: preprocessor,
    fft: fft,
    chroma: chroma,
    chromaFilter: chromaFilter,
    normalizer: normalizer,
    fingerprintCalculator: fingerprintCalculator,
  );
}

Future<Uint32List> fingerprintWordsFromWavFile(
  String path, {
  ChromaprintWavReader wavReader = const ChromaprintWavReader(),
  ChromaprintPreprocessor preprocessor = const ChromaprintPreprocessor(),
  ChromaprintFft? fft,
  ChromaprintChroma? chroma,
  ChromaprintChromaFilter? chromaFilter,
  ChromaprintChromaNormalizer? normalizer,
  ChromaprintFingerprintCalculator? fingerprintCalculator,
}) async {
  final bytes = await File(path).readAsBytes();
  return fingerprintWordsFromWavBytes(
    bytes,
    wavReader: wavReader,
    preprocessor: preprocessor,
    fft: fft,
    chroma: chroma,
    chromaFilter: chromaFilter,
    normalizer: normalizer,
    fingerprintCalculator: fingerprintCalculator,
  );
}

String fingerprintStringFromWavBytes(
  Uint8List bytes, {
  ChromaprintWavReader wavReader = const ChromaprintWavReader(),
  ChromaprintPreprocessor preprocessor = const ChromaprintPreprocessor(),
  ChromaprintFft? fft,
  ChromaprintChroma? chroma,
  ChromaprintChromaFilter? chromaFilter,
  ChromaprintChromaNormalizer? normalizer,
  ChromaprintFingerprintCalculator? fingerprintCalculator,
  int algorithmId = chromaprintAlgorithmIdTest2,
}) {
  final words = fingerprintWordsFromWavBytes(
    bytes,
    wavReader: wavReader,
    preprocessor: preprocessor,
    fft: fft,
    chroma: chroma,
    chromaFilter: chromaFilter,
    normalizer: normalizer,
    fingerprintCalculator: fingerprintCalculator,
  );
  return encodeFingerprintWords(words, algorithmId: algorithmId);
}

Future<String> fingerprintStringFromWavFile(
  String path, {
  ChromaprintWavReader wavReader = const ChromaprintWavReader(),
  ChromaprintPreprocessor preprocessor = const ChromaprintPreprocessor(),
  ChromaprintFft? fft,
  ChromaprintChroma? chroma,
  ChromaprintChromaFilter? chromaFilter,
  ChromaprintChromaNormalizer? normalizer,
  ChromaprintFingerprintCalculator? fingerprintCalculator,
  int algorithmId = chromaprintAlgorithmIdTest2,
}) async {
  final bytes = await File(path).readAsBytes();
  return fingerprintStringFromWavBytes(
    bytes,
    wavReader: wavReader,
    preprocessor: preprocessor,
    fft: fft,
    chroma: chroma,
    chromaFilter: chromaFilter,
    normalizer: normalizer,
    fingerprintCalculator: fingerprintCalculator,
    algorithmId: algorithmId,
  );
}
