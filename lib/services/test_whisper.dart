import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import '../utils/asr_utils.dart';
import 'dart:io';

void main() async {
  try {
    print('Testing Whisper model loading...');

    const modelDir = 'assets/sherpa-onnx-whisper-tiny.en';
    final encoderPath = await copyAssetFile('$modelDir/tiny.en-encoder.int8.onnx');
    final decoderPath = await copyAssetFile('$modelDir/tiny.en-decoder.int8.onnx');
    final tokensPath = await copyAssetFile('$modelDir/tiny.en-tokens.txt');

    print('Encoder: $encoderPath');
    print('Decoder: $decoderPath');
    print('Tokens: $tokensPath');

    // 检查文件是否存在且可读
    final encoderFile = File(encoderPath);
    final decoderFile = File(decoderPath);
    final tokensFile = File(tokensPath);

    if (!await encoderFile.exists()) {
      print('ERROR: Encoder file does not exist!');
      exit(1);
    }
    if (!await decoderFile.exists()) {
      print('ERROR: Decoder file does not exist!');
      exit(1);
    }
    if (!await tokensFile.exists()) {
      print('ERROR: Tokens file does not exist!');
      exit(1);
    }

    print('All files exist, creating model config...');

    final modelConfig = sherpa_onnx.OfflineModelConfig(
      tokens: tokensPath,
      whisper: sherpa_onnx.OfflineWhisperModelConfig(
        encoder: encoderPath,
        decoder: decoderPath,
      ),
      modelType: "whisper",
    );

    print('Model config created, creating recognizer config...');

    final config = sherpa_onnx.OfflineRecognizerConfig(
      model: modelConfig,
    );

    print('Recognizer config created, creating recognizer...');

    final recognizer = sherpa_onnx.OfflineRecognizer(config);

    print('SUCCESS: Whisper OfflineRecognizer created successfully!');
    recognizer.free();
  } catch (e, st) {
    print('ERROR: Whisper model loading failed: $e');
    print('Stack trace: $st');
    exit(1);
  }
}
