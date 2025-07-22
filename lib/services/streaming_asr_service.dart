import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import '../utils/asr_utils.dart';

/// 流式ASR服务 - 使用Sherpa-ONNX paraformer-zh-online模型
/// 支持低延迟的流式中文识别
class StreamingAsrService {
  sherpa_onnx.OnlineRecognizer? _recognizer;
  sherpa_onnx.OnlineStream? _stream;
  bool _isInitialized = false;

  // 流式识别结果回调
  StreamController<String> _resultController = StreamController<String>.broadcast();
  Stream<String> get resultStream => _resultController.stream;

  // 用于累积音频数据的缓冲区
  List<double> _audioBuffer = [];
  static const int _bufferSize = 1600; // 100ms at 16kHz

  bool get isInitialized => _isInitialized;

  /// 初始化流式ASR服务
  Future<void> init() async {
    try {
      print('[StreamingAsrService] 🚀 Initializing streaming ASR with paraformer...');

      // 初始化Sherpa-ONNX绑定
      sherpa_onnx.initBindings();

      // 创建流式识别器配置
      final config = await _createStreamingConfig();

      // 修复API调用：使用正确的构造函数语法
      _recognizer = sherpa_onnx.OnlineRecognizer(config);
      print('[StreamingAsrService] ✅ Online recognizer created');

      // 创建流式音频流
      _stream = _recognizer!.createStream();
      print('[StreamingAsrService] ✅ Audio stream created');

      _isInitialized = true;
      print('[StreamingAsrService] 🎉 Streaming ASR initialized successfully');

    } catch (e, stackTrace) {
      print('[StreamingAsrService] ❌ Failed to initialize: $e');
      print('[StreamingAsrService] Stack trace: $stackTrace');
      _isInitialized = false;
      rethrow;
    }
  }

  /// 创建流式识别器配置
  Future<sherpa_onnx.OnlineRecognizerConfig> _createStreamingConfig() async {
    print('[StreamingAsrService] 📝 Creating streaming config...');

    // 获取模型文件路径
    final encoderPath = await copyAssetFile('assets/sherpa-onnx-streaming-paraformer-bilingual-zh-en/encoder.onnx');
    final decoderPath = await copyAssetFile('assets/sherpa-onnx-streaming-paraformer-bilingual-zh-en/decoder.onnx');
    final tokensPath = await copyAssetFile('assets/sherpa-onnx-streaming-paraformer-bilingual-zh-en/tokens.txt');

    print('[StreamingAsrService] 📂 Model files copied:');
    print('[StreamingAsrService]   Encoder: $encoderPath');
    print('[StreamingAsrService]   Decoder: $decoderPath');
    print('[StreamingAsrService]   Tokens: $tokensPath');

    // 创建paraformer模型配置
    final paraformerConfig = sherpa_onnx.OnlineParaformerModelConfig(
      encoder: encoderPath,
      decoder: decoderPath,
    );

    // 创建模型配置
    final modelConfig = sherpa_onnx.OnlineModelConfig(
      paraformer: paraformerConfig,
      tokens: tokensPath,
      numThreads: 2, // 使用2个线程以平衡性能和延迟
      provider: "cpu",
      debug: true,
    );

    // 创建特征提取配置
    final featConfig = sherpa_onnx.FeatureConfig(
      sampleRate: 16000,
      featureDim: 80,
    );

    // 创建识别器配置 - 移除不存在的参数
    final config = sherpa_onnx.OnlineRecognizerConfig(
      model: modelConfig,
      feat: featConfig,
      enableEndpoint: true,
      rule1MinTrailingSilence: 2.4,
      rule2MinTrailingSilence: 1.2,
      rule3MinUtteranceLength: 20.0,
      hotwordsFile: '',
      hotwordsScore: 1.5,
      maxActivePaths: 4,
    );

    print('[StreamingAsrService] ✅ Streaming config created');
    return config;
  }

  /// 处理音频数据 - 支持流式识别
  Future<String> processAudio(Float32List audioData) async {
    if (!_isInitialized || _stream == null) {
      print('[StreamingAsrService] ⚠️ Service not initialized');
      return '';
    }

    try {
      // 将音频数据添加到缓冲区
      _audioBuffer.addAll(audioData);

      String result = '';

      // 当缓冲区有足够数据时进行处理
      while (_audioBuffer.length >= _bufferSize) {
        // 取出一个缓冲区大小的数据
        final chunk = Float32List.fromList(_audioBuffer.take(_bufferSize).toList());
        _audioBuffer.removeRange(0, _bufferSize);

        // 输入音频到流式识别器
        _stream!.acceptWaveform(samples: chunk, sampleRate: 16000);

        // 检查是否有新的识别结果
        while (_recognizer!.isReady(_stream!)) {
          _recognizer!.decode(_stream!);
        }

        // 获取部分识别结果（不等待句子结束）
        final partialResult = _recognizer!.getResult(_stream!);
        if (partialResult.text.isNotEmpty) {
          result = partialResult.text;
          print('[StreamingAsrService] 🎙️ Partial result: $result');

          // 发送流式结果
          _resultController.add(result);
        }

        // 检查是否检测到端点（句子结束）
        if (_recognizer!.isEndpoint(_stream!)) {
          final finalResult = _recognizer!.getResult(_stream!);
          if (finalResult.text.isNotEmpty) {
            result = finalResult.text;
            print('[StreamingAsrService] 🏁 Final result: $result');

            // 发送最终结果
            _resultController.add(result);
          }

          // 重置流以准备下一个话语
          _recognizer!.reset(_stream!);
        }
      }

      return result;

    } catch (e, stackTrace) {
      print('[StreamingAsrService] ❌ Error processing audio: $e');
      print('[StreamingAsrService] Stack trace: $stackTrace');
      return '';
    }
  }

  /// 输入音频数据但不立即获取结果（用于连续流式识别）
  void feedAudio(Float32List audioData) {
    if (!_isInitialized || _stream == null) return;

    try {
      _stream!.acceptWaveform(samples: audioData, sampleRate: 16000);

      // 解码可用的音频
      while (_recognizer!.isReady(_stream!)) {
        _recognizer!.decode(_stream!);
      }

      // 获取当前识别结果
      final result = _recognizer!.getResult(_stream!);
      if (result.text.isNotEmpty) {
        _resultController.add(result.text);
      }

    } catch (e) {
      print('[StreamingAsrService] ❌ Error feeding audio: $e');
    }
  }

  /// 获取当前识别结果
  String getCurrentResult() {
    if (!_isInitialized || _stream == null) return '';

    try {
      final result = _recognizer!.getResult(_stream!);
      return result.text;
    } catch (e) {
      print('[StreamingAsrService] ❌ Error getting result: $e');
      return '';
    }
  }

  /// 强制结束当前话语并获取最终结果
  String flushAndGetResult() {
    if (!_isInitialized || _stream == null) return '';

    try {
      // 输入一小段静音来触发端点检测
      final silence = Float32List(1600); // 100ms silence
      _stream!.acceptWaveform(samples: silence, sampleRate: 16000);

      // 处理剩余音频
      while (_recognizer!.isReady(_stream!)) {
        _recognizer!.decode(_stream!);
      }

      final result = _recognizer!.getResult(_stream!);
      if (result.text.isNotEmpty) {
        _resultController.add(result.text);
        _recognizer!.reset(_stream!);
      }

      return result.text;

    } catch (e) {
      print('[StreamingAsrService] ❌ Error flushing: $e');
      return '';
    }
  }

  /// 重置识别器��态
  void reset() {
    if (!_isInitialized || _stream == null) return;

    try {
      _recognizer!.reset(_stream!);
      _audioBuffer.clear();
      print('[StreamingAsrService] 🔄 Recognizer reset');
    } catch (e) {
      print('[StreamingAsrService] ❌ Error resetting: $e');
    }
  }

  /// 释放资源
  void dispose() {
    try {
      print('[StreamingAsrService] 🧹 Disposing resources...');

      _stream?.free();
      _stream = null;

      _recognizer?.free();
      _recognizer = null;

      _audioBuffer.clear();
      _resultController.close();

      _isInitialized = false;
      print('[StreamingAsrService] ✅ Resources disposed');

    } catch (e) {
      print('[StreamingAsrService] ❌ Error disposing: $e');
    }
  }
}
