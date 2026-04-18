import 'rust/api/simple.dart';

int getPcmLength({required String path}) {
  final pcm = getAudioPcm(path: path);
  return pcm.length;
}
