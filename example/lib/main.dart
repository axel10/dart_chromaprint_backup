import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:dart_chromaprint/dart_chromaprint.dart';

void main() => runApp(const MyApp());

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
  bool _isLoading = false;
  String? _fingerprint;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _calculateFingerprint();
  }

  Future<void> _calculateFingerprint() async {
    final pcmPath = Directory.current.uri
        .resolve('../test/test_decoded.pcm')
        .toFilePath();

    if (!File(pcmPath).existsSync()) {
      setState(() {
        _errorMessage = 'Fixture not found: $pcmPath';
        _fingerprint = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _fingerprint = null;
      _errorMessage = null;
    });

    try {
      final bytes = await File(pcmPath).readAsBytes();
      final samples = ChromaprintPreprocessor.decodeLittleEndianPcm(
        Uint8List.fromList(bytes),
      );
      final fp = fingerprintStringFromInt16Pcm(
        samples: samples,
        sampleRate: 44100,
        channels: 2,
      );

      setState(() {
        _fingerprint = fp;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '$e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dart Chromaprint Demo')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Using the pure Dart pipeline to fingerprint `test/test_decoded.pcm`.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'Input: 44.1 kHz stereo PCM, output: AcoustID-compatible Chromaprint string',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              if (_isLoading)
                const CircularProgressIndicator()
              else if (_errorMessage != null) ...[
                Text(
                  'Error',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(color: Colors.red),
                ),
                const SizedBox(height: 8),
                Text(_errorMessage!, textAlign: TextAlign.center),
              ] else if (_fingerprint != null) ...[
                Text(
                  'Fingerprint Ready',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  height: 180,
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _fingerprint!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ] else
                const Text('No fingerprint available yet.'),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _calculateFingerprint,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Recalculate'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
