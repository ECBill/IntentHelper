import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'dart:io';

void main() async {
  final vadModelPath = '/data/user/0/inc.bud.app/app_flutter/silero_vad.onnx';

  try {
    final config = sherpa_onnx.VadModelConfig(
      sileroVad: sherpa_onnx.SileroVadModelConfig(
        model: vadModelPath,
        threshold: 0.5,
        minSilenceDuration: 0.25,
        minSpeechDuration: 0.5,
        maxSpeechDuration: 5,
        windowSize: 512,
      ),
      sampleRate: 16000,
      numThreads: 1,
      provider: 'cpu',
      debug: true,
    );

    final vad = sherpa_onnx.VoiceActivityDetector(
      config: config,
      bufferSizeInSeconds: 30,
    );
    print('VAD模型加载成功！');
    vad.free();
  } catch (e, st) {
    print('VAD模型加载失败: $e');
    print(st);
    exit(1);
  }
}

