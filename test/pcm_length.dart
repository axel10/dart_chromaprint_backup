import 'dart:io';
import 'package:dart_chromaprint/dart_chromaprint.dart';

/// 获取pcm长度的接口在dart层实现，仅供测试
int getPcmLength(String path) {
  // 调用 Rust 实现的 getAudioPcm 获取数据
  final pcm = getAudioPcm(path: path);
  // 返回数组长度即为 PCM 采样总数（如果是多声道则是交错后的总采样数）
  return pcm.length;
}

void main() async {
  // 初始化 Rust 库
  await RustLib.init();

  const path = 'test/test.mp3';
  final file = File(path);

  if (!file.existsSync()) {
    print('错误：找不到音频文件 $path');
    return;
  }

  print('开始解析音频文件: ${file.absolute.path}');

  try {
    final length = getPcmLength(path);
    print('-------------------------');
    print('PCM 样本长度: $length');
    print('-------------------------');
  } catch (e) {
    print('获取 PCM 长度时出错: $e');
  }
}
