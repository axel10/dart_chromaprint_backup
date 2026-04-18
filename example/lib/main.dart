import 'package:flutter/material.dart';
import 'package:dart_chromaprint/dart_chromaprint.dart';
import 'package:file_picker/file_picker.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String? _filePath;
  int? _pcmLength;
  double _maxSeconds = 10.0; // Default to 10 seconds
  bool _isLoading = false;

  Future<void> _pickAndProcessFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.audio,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _filePath = result.files.single.path;
        _isLoading = true;
        _pcmLength = null;
      });

      try {
        // Call the new pure Dart interface
        final length = getPcmLength(path: _filePath!, maxSeconds: _maxSeconds);
        setState(() {
          _pcmLength = length;
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('PCM Length Demo')),
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
                  Text('PCM Length:', style: Theme.of(context).textTheme.headlineMedium),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
