import 'dart:typed_data';

import 'chromaprint_features.dart';
import 'chromaprint_fft.dart';
import 'chromaprint_fingerprint.dart';
import 'chromaprint_preprocessing.dart';

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
