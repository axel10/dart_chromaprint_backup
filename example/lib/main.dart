import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:dart_chromaprint/dart_chromaprint.dart';
import 'package:file_picker/file_picker.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
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
  String? _filePath;
  int? _pcmLength;
  double _maxSeconds = 10.0; // Default to 10 seconds
  bool _isLoading = false;
  Float32List? _pcmData;

  Future<void> _pickAndProcessFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.audio,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _filePath = result.files.single.path;
        _isLoading = true;
        _pcmLength = null;
        _pcmData = null;
      });

      try {
        final data = getAudioPcmData(path: _filePath!, maxSeconds: _maxSeconds);
        setState(() {
          _pcmData = data;
          _pcmLength = data.length;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _savePcm() async {
    if (_pcmData == null) return;

    String fileName = 'decoded.pcm';
    if (_filePath != null) {
      final baseName = _filePath!.split(Platform.pathSeparator).last;
      fileName = '${baseName.split('.').first}_decoded.pcm';
    }

    // According to user's successful attempt
    final savePath = await FilePicker.saveFile(
      dialogTitle: 'Save Decoded PCM Data',
      fileName: fileName,
      type: FileType.any,
    );

    if (savePath != null) {
      setState(() => _isLoading = true);
      try {
        final file = File(savePath);
        // Convert Float32 to Int16 for standard PCM file
        final int16Data = Int16List(_pcmData!.length);
        for (var i = 0; i < _pcmData!.length; i++) {
          int16Data[i] = (_pcmData![i] * 32767).clamp(-32768, 32767).toInt();
        }
        await file.writeAsBytes(int16Data.buffer.asUint8List());

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved to $savePath'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving file: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PCM Decoder Demo')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_filePath != null) ...[
                Text('Selected File:', style: Theme.of(context).textTheme.titleMedium),
                Text(_filePath!, textAlign: TextAlign.center),
                const SizedBox(height: 20),
              ],
              if (_isLoading)
                const CircularProgressIndicator()
              else if (_pcmLength != null) ...[
                Text('PCM Samples:', style: Theme.of(context).textTheme.headlineMedium),
                Text('$_pcmLength samples',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        )),
              ] else
                const Text('Select an audio file to see its PCM length'),
              const SizedBox(height: 30),
              Text('Max Seconds: ${_maxSeconds.toInt()}s'),
              Slider(
                value: _maxSeconds,
                min: 1,
                max: 120,
                divisions: 119,
                label: '${_maxSeconds.toInt()}s',
                onChanged: _isLoading
                    ? null
                    : (value) {
                        setState(() {
                          _maxSeconds = value;
                        });
                      },
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _pickAndProcessFile,
                icon: const Icon(Icons.audio_file),
                label: const Text('Pick Audio File'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              if (_pcmData != null) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _savePcm,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save Decoded PCM'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    backgroundColor: Colors.blue.shade50,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
