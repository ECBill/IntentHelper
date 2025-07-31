import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import '../utils/asr_utils.dart';
import 'text_correction_service.dart';

/// 流式ASR服务 - 使用Sherpa-ONNX paraformer-zh-online模型
/// 支持低延迟的流式中文识别，优化版本 + 智能纠错
class StreamingAsrService {
  sherpa_onnx.OnlineRecognizer? _recognizer;
  sherpa_onnx.OnlineStream? _stream;
  bool _isInitialized = false;

  // 流式识别结果回调
  StreamController<String> _resultController = StreamController<String>.broadcast();
  Stream<String> get resultStream => _resultController.stream;

  // 文本纠错服务
  final TextCorrectionService _correctionService = TextCorrectionService();
  bool _enableCorrection = true; // 是否启用纠错

  // 优化音频缓冲区管理
  List<double> _audioBuffer = [];
  static const int _optimalChunkSize = 3200; // 200ms at 16kHz，更适合中文语音
  static const int _minChunkSize = 800;  // 50ms 最小处理单位
  static const double _sampleRate = 16000.0;

  // 音频质量统计
  double _audioLevel = 0.0;
  int _silenceFrameCount = 0;
  static const double _silenceThreshold = 0.01; // 静音阈值

  // 识别状态管理
  String _lastPartialResult = '';
  String _lastFinalResult = '';
  String _lastCorrectedResult = ''; // 上次纠错后的结果
  DateTime _lastActivityTime = DateTime.now();

  // 纠错统计
  int _totalCorrections = 0;
  int _totalRecognitions = 0;

  bool get isInitialized => _isInitialized;
  double get currentAudioLevel => _audioLevel;
  bool get isCorrectionEnabled => _enableCorrection;
  double get correctionRate => _totalRecognitions > 0 ? _totalCorrections / _totalRecognitions : 0.0;

  /// 初始化流式ASR服务
  Future<void> init() async {
    try {
      print('[StreamingAsrService] 🚀 Initializing optimized streaming ASR...');

      // 初始化Sherpa-ONNX绑定
      sherpa_onnx.initBindings();

      // 创建优化的流式识别器配置
      final config = await _createOptimizedConfig();

      _recognizer = sherpa_onnx.OnlineRecognizer(config);
      print('[StreamingAsrService] ✅ Optimized recognizer created');

      _stream = _recognizer!.createStream();
      print('[StreamingAsrService] ✅ Audio stream created');

      _isInitialized = true;
      print('[StreamingAsrService] 🎉 Optimized streaming ASR initialized successfully');

    } catch (e, stackTrace) {
      print('[StreamingAsrService] ❌ Failed to initialize: $e');
      print('[StreamingAsrService] Stack trace: $stackTrace');
      _isInitialized = false;
      rethrow;
    }
  }

  /// 创建优化的流式识别器配置
  Future<sherpa_onnx.OnlineRecognizerConfig> _createOptimizedConfig() async {
    print('[StreamingAsrService] 📝 Creating optimized streaming config...');

    // 获取模型文件路径
    final encoderPath = await copyAssetFile('assets/sherpa-onnx-streaming-paraformer-bilingual-zh-en/encoder.onnx');
    final decoderPath = await copyAssetFile('assets/sherpa-onnx-streaming-paraformer-bilingual-zh-en/decoder.onnx');
    final tokensPath = await copyAssetFile('assets/sherpa-onnx-streaming-paraformer-bilingual-zh-en/tokens.txt');

    print('[StreamingAsrService] 📂 Model files loaded');

    // 创建paraformer模型配置
    final paraformerConfig = sherpa_onnx.OnlineParaformerModelConfig(
      encoder: encoderPath,
      decoder: decoderPath,
    );

    // 优化模型配置 - 增加线程数和优化参数
    final modelConfig = sherpa_onnx.OnlineModelConfig(
      paraformer: paraformerConfig,
      tokens: tokensPath,
      numThreads: 4, // 增加到4个线程提高实时性能
      provider: "cpu",
      debug: false, // 关闭debug以提高性能
    );

    // 优化特征提取配置
    final featConfig = sherpa_onnx.FeatureConfig(
      sampleRate: 16000,
      featureDim: 80,
    );

    // 优化端点检测参数以适应中文语音特点
    final config = sherpa_onnx.OnlineRecognizerConfig(
      model: modelConfig,
      feat: featConfig,
      enableEndpoint: true,
      // 调整端点检测参数以适应中文语音节奏
      rule1MinTrailingSilence: 1.0,  // 减少静音检测时间
      rule2MinTrailingSilence: 0.8,  // 更快响应短句
      rule3MinUtteranceLength: 10.0, // 减少最小话语长度
      hotwordsFile: '',
      hotwordsScore: 2.0, // 提高热词权重
      maxActivePaths: 8,   // 增加搜索路径数量
    );

    print('[StreamingAsrService] ✅ Optimized config created');
    return config;
  }

  /// 音频预处理 - 添加音频增强
  Float32List _preprocessAudio(Float32List audioData) {
    if (audioData.isEmpty) return audioData;

    // 计算音频能量
    double energy = 0.0;
    for (double sample in audioData) {
      energy += sample * sample;
    }
    _audioLevel = math.sqrt(energy / audioData.length);

    // 检测静音
    if (_audioLevel < _silenceThreshold) {
      _silenceFrameCount++;
    } else {
      _silenceFrameCount = 0;
      _lastActivityTime = DateTime.now();
    }

    // 音频归一化 - 但保持动态范围
    if (_audioLevel > 0.1) {
      final normalizedData = Float32List(audioData.length);
      final scaleFactor = 0.8 / _audioLevel; // 适度归一化
      for (int i = 0; i < audioData.length; i++) {
        normalizedData[i] = audioData[i] * scaleFactor;
        // 软限幅
        if (normalizedData[i] > 0.95) normalizedData[i] = 0.95;
        if (normalizedData[i] < -0.95) normalizedData[i] = -0.95;
      }
      return normalizedData;
    }

    return audioData;
  }

  /// 对识别结果进行智能纠错
  String _correctRecognitionResult(String originalText) {
    if (!_enableCorrection || originalText.isEmpty) {
      return originalText;
    }

    _totalRecognitions++;

    // 应用文本纠错
    String correctedText = _correctionService.correctText(originalText);

    // 如果发生了纠错，记录统计信息
    if (correctedText != originalText) {
      _totalCorrections++;
      print('[StreamingAsrService] 🔧 纠错应用: "$originalText" → "$correctedText"');
    }

    return correctedText;
  }

  /// 优化的音频处理方法（带纠错）
  Future<String> processAudio(Float32List audioData) async {
    if (!_isInitialized || _stream == null) {
      print('[StreamingAsrService] ⚠️ Service not initialized');
      return '';
    }

    try {
      // 预处理音频
      final processedAudio = _preprocessAudio(audioData);

      // 将音频数据添加到缓冲区
      _audioBuffer.addAll(processedAudio);

      String result = '';

      // 使用更智能的缓冲区处理
      while (_audioBuffer.length >= _minChunkSize) {
        // 确定处理块大小
        int chunkSize = math.min(_audioBuffer.length, _optimalChunkSize);

        // 如果接近最优大小，使用最优大小
        if (_audioBuffer.length >= _optimalChunkSize) {
          chunkSize = _optimalChunkSize;
        }

        final chunk = Float32List.fromList(_audioBuffer.take(chunkSize).toList());
        _audioBuffer.removeRange(0, chunkSize);

        // 输入音频到流式识别器
        _stream!.acceptWaveform(samples: chunk, sampleRate: _sampleRate.toInt());

        // 处理识别
        await _processRecognition();

        // 获取当前结果并应用纠错
        final currentResult = _recognizer!.getResult(_stream!);
        if (currentResult.text.isNotEmpty && currentResult.text != _lastPartialResult) {
          // 对部分结果应用轻量级纠错（只纠正明显错误）
          String correctedResult = _correctRecognitionResult(currentResult.text);
          result = correctedResult;
          _lastPartialResult = currentResult.text; // 记录原始结果
          _lastCorrectedResult = correctedResult;  // 记录纠错结果

          print('[StreamingAsrService] 🎙️ Partial: $correctedResult (level: ${_audioLevel.toStringAsFixed(3)})');
          _resultController.add(correctedResult);
        }

        // 检查端点
        if (_recognizer!.isEndpoint(_stream!)) {
          final finalResult = _recognizer!.getResult(_stream!);
          if (finalResult.text.isNotEmpty && finalResult.text != _lastFinalResult) {
            // 对最终结果应用完整纠错
            String correctedFinalResult = _correctRecognitionResult(finalResult.text);
            result = correctedFinalResult;
            _lastFinalResult = finalResult.text;     // 记录原始结果
            _lastCorrectedResult = correctedFinalResult; // 记录纠错结果

            print('[StreamingAsrService] 🏁 Final: $correctedFinalResult');
            _resultController.add(correctedFinalResult);
          }

          // 重置流
          _recognizer!.reset(_stream!);
          _lastPartialResult = '';
        }
      }

      return result;

    } catch (e, stackTrace) {
      print('[StreamingAsrService] ❌ Error processing audio: $e');
      print('[StreamingAsrService] Stack trace: $stackTrace');
      return '';
    }
  }

  /// 异步处理识别逻辑
  Future<void> _processRecognition() async {
    try {
      // 批量处理可用的音频数据
      int processedFrames = 0;
      while (_recognizer!.isReady(_stream!) && processedFrames < 10) {
        _recognizer!.decode(_stream!);
        processedFrames++;
      }
    } catch (e) {
      print('[StreamingAsrService] ❌ Error in recognition: $e');
    }
  }

  /// 优化的连续音频输入方法（带纠错）
  void feedAudio(Float32List audioData) {
    if (!_isInitialized || _stream == null) return;

    try {
      final processedAudio = _preprocessAudio(audioData);
      _stream!.acceptWaveform(samples: processedAudio, sampleRate: _sampleRate.toInt());

      // 非阻塞处理
      _processRecognitionAsync();

    } catch (e) {
      print('[StreamingAsrService] ❌ Error feeding audio: $e');
    }
  }

  /// 异步处理识别（非阻塞，带纠错）
  void _processRecognitionAsync() {
    Future.microtask(() async {
      try {
        await _processRecognition();

        final result = _recognizer!.getResult(_stream!);
        if (result.text.isNotEmpty && result.text != _lastPartialResult) {
          // 应用纠错
          String correctedResult = _correctRecognitionResult(result.text);
          _lastPartialResult = result.text;
          _lastCorrectedResult = correctedResult;
          _resultController.add(correctedResult);
        }
      } catch (e) {
        print('[StreamingAsrService] ❌ Async recognition error: $e');
      }
    });
  }

  /// 获取当前识别结果（纠错后）
  String getCurrentResult() {
    if (!_isInitialized || _stream == null) return '';

    try {
      final result = _recognizer!.getResult(_stream!);
      return _correctRecognitionResult(result.text);
    } catch (e) {
      print('[StreamingAsrService] ❌ Error getting result: $e');
      return '';
    }
  }

  /// 智能刷新 - 根据音频状态决定是否强制结束（带纠错）
  String flushAndGetResult() {
    if (!_isInitialized || _stream == null) return '';

    try {
      // 检查是否有待处理的音频
      if (_audioBuffer.isNotEmpty) {
        // 处理剩余的音频缓冲区
        final remaining = Float32List.fromList(_audioBuffer);
        _audioBuffer.clear();
        _stream!.acceptWaveform(samples: remaining, sampleRate: _sampleRate.toInt());
      }

      // 添加适量静音来触发端点
      final silenceDuration = _silenceFrameCount > 10 ? 800 : 1600; // 根据静音情况调整
      final silence = Float32List(silenceDuration);
      _stream!.acceptWaveform(samples: silence, sampleRate: _sampleRate.toInt());

      // 处理剩余识别
      while (_recognizer!.isReady(_stream!)) {
        _recognizer!.decode(_stream!);
      }

      final result = _recognizer!.getResult(_stream!);
      if (result.text.isNotEmpty) {
        // 应用纠错
        String correctedResult = _correctRecognitionResult(result.text);
        _resultController.add(correctedResult);
        _recognizer!.reset(_stream!);
        _lastPartialResult = '';
        _lastFinalResult = result.text;
        _lastCorrectedResult = correctedResult;
        print('[StreamingAsrService] 🔄 Flushed result: $correctedResult');
        return correctedResult;
      }

      return '';

    } catch (e) {
      print('[StreamingAsrService] ❌ Error flushing: $e');
      return '';
    }
  }

  /// 启用/禁用文本纠错
  void setTextCorrectionEnabled(bool enabled) {
    _enableCorrection = enabled;
    print('[StreamingAsrService] ${enabled ? '✅' : '❌'} 文本纠错${enabled ? '已启用' : '已禁用'}');
  }

  /// 获取纠错统计信息
  Map<String, dynamic> getCorrectionStats() {
    return {
      'totalRecognitions': _totalRecognitions,
      'totalCorrections': _totalCorrections,
      'correctionRate': correctionRate,
      'isEnabled': _enableCorrection,
      'lastOriginal': _lastFinalResult,
      'lastCorrected': _lastCorrectedResult,
      ..._correctionService.getCorrectionStats(),
    };
  }

  /// 获取识别状态信息（包含纠错信息）
  Map<String, dynamic> getStatus() {
    return {
      'isInitialized': _isInitialized,
      'audioLevel': _audioLevel,
      'silenceFrames': _silenceFrameCount,
      'bufferSize': _audioBuffer.length,
      'lastActivity': _lastActivityTime.millisecondsSinceEpoch,
      'lastPartial': _lastPartialResult,
      'lastFinal': _lastFinalResult,
      'lastCorrected': _lastCorrectedResult,
      'correctionEnabled': _enableCorrection,
      'correctionRate': correctionRate,
    };
  }

  /// 重置识别器状态（包含纠错统计）
  void reset() {
    if (!_isInitialized || _stream == null) return;

    try {
      _recognizer!.reset(_stream!);
      _audioBuffer.clear();
      _lastPartialResult = '';
      _lastFinalResult = '';
      _lastCorrectedResult = '';
      _silenceFrameCount = 0;
      _audioLevel = 0.0;
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
