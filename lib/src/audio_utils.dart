import 'dart:typed_data';
import 'rust/api/simple.dart';

int getPcmLength({required String path, double? maxSeconds}) {
  final pcm = getAudioPcm(path: path, maxSeconds: maxSeconds);
  return pcm.length;
}

Float32List getAudioPcmData({required String path, double? maxSeconds}) {
  return getAudioPcm(path: path, maxSeconds: maxSeconds);
}
