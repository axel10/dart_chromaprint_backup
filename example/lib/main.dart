import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_chromaprint/dart_chromaprint.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const int _sampleRate = 44100;
  static const int _channels = 2;
  static const int _benchmarkIterations = 100;

  bool _isLoading = false;
  bool _isBenchmarking = false;
  String? _fingerprint;
  String? _errorMessage;
  String? _fixturePath;
  Int16List? _fixtureSamples;
  BenchmarkSummary? _benchmarkSummary;

  @override
  void initState() {
    super.initState();
    _loadFixtureAndFingerprint();
  }

  Future<void> _loadFixtureAndFingerprint() async {
    final fixturePath = _resolveFixturePath();
    if (fixturePath == null) {
      setState(() {
        _errorMessage = 'Fixture not found: test/test_decoded.pcm';
        _fingerprint = null;
        _fixturePath = null;
        _fixtureSamples = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _fingerprint = null;
      _errorMessage = null;
      _benchmarkSummary = null;
    });

    try {
      final bytes = await File(fixturePath).readAsBytes();
      final samples = ChromaprintPreprocessor.decodeLittleEndianPcm(
        Uint8List.fromList(bytes),
      );
      final fingerprint = fingerprintStringFromInt16Pcm(
        samples: samples,
        sampleRate: _sampleRate,
        channels: _channels,
      );

      setState(() {
        _fixturePath = fixturePath;
        _fixtureSamples = samples;
        _fingerprint = fingerprint;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '$e';
        _fingerprint = null;
        _fixturePath = null;
        _fixtureSamples = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _runBenchmark() async {
    final samples = _fixtureSamples;
    if (samples == null) {
      setState(() {
        _errorMessage = 'Benchmark fixture is not ready yet.';
      });
      return;
    }

    setState(() {
      _isBenchmarking = true;
      _errorMessage = null;
      _benchmarkSummary = null;
    });

    try {
      final dartResult = await _benchmark<String>(
        iterations: _benchmarkIterations,
        body: () {
          return fingerprintStringFromInt16Pcm(
            samples: samples,
            sampleRate: _sampleRate,
            channels: _channels,
          );
        },
      );

      final rustResult = await _benchmark<String>(
        iterations: _benchmarkIterations,
        body: () {
          return getFingerprintRawFromPcm(
            samples: samples,
            sampleRate: _sampleRate,
            channels: _channels,
          );
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _benchmarkSummary = BenchmarkSummary(
          iterations: _benchmarkIterations,
          dartTotal: dartResult.total,
          dartAverageMicros: dartResult.averageMicros,
          rustTotal: rustResult.total,
          rustAverageMicros: rustResult.averageMicros,
          rustOverDart:
              rustResult.totalMicroseconds / dartResult.totalMicroseconds,
          outputsMatch: dartResult.lastValue == rustResult.lastValue,
        );
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBenchmarking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Dart Chromaprint Demo')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Using the pure Dart pipeline to fingerprint `test/test_decoded.pcm`.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Input: 44.1 kHz stereo PCM, output: AcoustID-compatible Chromaprint string',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Benchmark mode: PCM is decoded once into memory, then Dart and Rust each run 100 fingerprint calculations without file IO in the timed loop.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 24),
                      if (_isLoading)
                        const Center(child: CircularProgressIndicator())
                      else if (_errorMessage != null) ...[
                        _SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Error',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(_errorMessage!),
                            ],
                          ),
                        ),
                      ] else ...[
                        _SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Fingerprint Ready',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Fixture: ${_fixturePath ?? "unknown"}',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                constraints: const BoxConstraints(
                                  minHeight: 180,
                                ),
                                child: SingleChildScrollView(
                                  child: SelectableText(
                                    _fingerprint ??
                                        'No fingerprint available yet.',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _isBenchmarking ? null : _runBenchmark,
                              icon: _isBenchmarking
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.speed),
                              label: Text(
                                _isBenchmarking
                                    ? 'Benchmarking...'
                                    : 'Run 100x In-Memory Benchmark',
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _isLoading
                                  ? null
                                  : _loadFixtureAndFingerprint,
                              icon: const Icon(Icons.fingerprint),
                              label: const Text('Recalculate fingerprint'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_benchmarkSummary != null) ...[
                          _SectionCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Benchmark Result',
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
                                _MetricRow(
                                  label: 'Iterations',
                                  value: '${_benchmarkSummary!.iterations}',
                                ),
                                _MetricRow(
                                  label: 'Dart total',
                                  value: _formatDuration(
                                    _benchmarkSummary!.dartTotal,
                                  ),
                                ),
                                _MetricRow(
                                  label: 'Dart avg',
                                  value: _formatMicros(
                                    _benchmarkSummary!.dartAverageMicros,
                                  ),
                                ),
                                const Divider(height: 24),
                                _MetricRow(
                                  label: 'Rust total',
                                  value: _formatDuration(
                                    _benchmarkSummary!.rustTotal,
                                  ),
                                ),
                                _MetricRow(
                                  label: 'Rust avg',
                                  value: _formatMicros(
                                    _benchmarkSummary!.rustAverageMicros,
                                  ),
                                ),
                                const Divider(height: 24),
                                _MetricRow(
                                  label: 'Rust / Dart',
                                  value:
                                      '${_benchmarkSummary!.rustOverDart.toStringAsFixed(2)}x',
                                ),
                                _MetricRow(
                                  label: 'Outputs match',
                                  value: _benchmarkSummary!.outputsMatch
                                      ? 'Yes'
                                      : 'No',
                                ),
                              ],
                            ),
                          ),
                        ] else
                          Text(
                            'Tap the benchmark button to run 100 fingerprint calculations from the same in-memory PCM buffer and compare Dart with Rust.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String? _resolveFixturePath() {
    final candidates = <String>[
      Directory.current.uri.resolve('../test/test_decoded.pcm').toFilePath(),
      Directory.current.uri.resolve('test/test_decoded.pcm').toFilePath(),
      Directory.current.uri.resolve('../../test/test_decoded.pcm').toFilePath(),
    ];

    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }

    return null;
  }
}

class BenchmarkSummary {
  const BenchmarkSummary({
    required this.iterations,
    required this.dartTotal,
    required this.dartAverageMicros,
    required this.rustTotal,
    required this.rustAverageMicros,
    required this.rustOverDart,
    required this.outputsMatch,
  });

  final int iterations;
  final Duration dartTotal;
  final double dartAverageMicros;
  final Duration rustTotal;
  final double rustAverageMicros;
  final double rustOverDart;
  final bool outputsMatch;
}

class _TimedResult<T> {
  const _TimedResult({
    required this.total,
    required this.averageMicros,
    required this.lastValue,
  });

  final Duration total;
  final double averageMicros;
  final T lastValue;
  double get totalMicroseconds => total.inMicroseconds.toDouble();
}

Future<_TimedResult<T>> _benchmark<T>({
  required int iterations,
  required FutureOr<T> Function() body,
}) async {
  T lastValue = await body();
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    lastValue = await body();
  }
  stopwatch.stop();

  final total = stopwatch.elapsed;
  return _TimedResult(
    total: total,
    averageMicros: total.inMicroseconds / iterations,
    lastValue: lastValue,
  );
}

String _formatDuration(Duration duration) {
  return '${duration.inMilliseconds} ms';
}

String _formatMicros(double micros) {
  if (micros >= 1000.0) {
    return '${(micros / 1000.0).toStringAsFixed(2)} ms';
  }
  return '${micros.toStringAsFixed(1)} us';
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
