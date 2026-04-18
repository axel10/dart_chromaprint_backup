import 'rust/api/simple.dart';

int getPcmLength({required String path, double? maxSeconds}) {
  final pcm = getAudioPcm(path: path, maxSeconds: maxSeconds);
  return pcm.length;
}
