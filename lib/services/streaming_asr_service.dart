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

  // 优化音频缓冲区管理 - 使用更高效的缓冲区
  Float32List _audioBuffer = Float32List(0);
  int _bufferLength = 0;
  static const int _optimalChunkSize = 800; // 🔧 FIX: 降低到50ms，加快初始响应
  static const int _minChunkSize = 400;  // 🔧 FIX: 25ms 最小处理单位，更快启动
  static const double _sampleRate = 16000.0;
  static const int _maxBufferSize = 16000; // 1秒最大缓冲

  // 🔧 FIX: 添加即时处理模式
  bool _enableInstantProcessing = true; // 启用即时处理，不等缓冲区填满
  int _processedSamples = 0; // 跟踪已处理的样本数
  int _totalAudioReceived = 0; // 🔧 NEW: 跟踪总接收的音频数据量
  DateTime _startTime = DateTime.now(); // 🔧 NEW: 记录启动时间

  // 音频质量统计 - 简化计算
  double _audioLevel = 0.0;
  int _silenceFrameCount = 0;
  static const double _silenceThreshold = 0.01;
  int _frameCounter = 0; // 用于跳帧优化

  // 识别状态管理
  String _lastPartialResult = '';
  String _lastFinalResult = '';
  String _lastCorrectedResult = '';
  DateTime _lastActivityTime = DateTime.now();

  // 性能优化开关
  bool _enableAudioEnhancement = false; // 默认关闭音频增强以提升速度
  bool _enablePartialCorrection = false; // 只对最终结果纠错

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

      // 预分配缓冲区
      _audioBuffer = Float32List(_maxBufferSize);
      _bufferLength = 0;

      // 🔧 FIX: 重置即时处理模式状态
      _enableInstantProcessing = true;
      _processedSamples = 0;
      _totalAudioReceived = 0;
      _startTime = DateTime.now();
      
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

    // 优先使用int8量化模型以提升速度
    String encoderPath;
    String decoderPath;

    try {
      encoderPath = await copyAssetFile('assets/sherpa-onnx-streaming-paraformer-bilingual-zh-en/encoder.int8.onnx');
      decoderPath = await copyAssetFile('assets/sherpa-onnx-streaming-paraformer-bilingual-zh-en/decoder.int8.onnx');
      print('[StreamingAsrService] ✅ Using int8 quantized models for better speed');
    } catch (e) {
      // 降级到fp32模型
      encoderPath = await copyAssetFile('assets/sherpa-onnx-streaming-paraformer-bilingual-zh-en/encoder.onnx');
      decoderPath = await copyAssetFile('assets/sherpa-onnx-streaming-paraformer-bilingual-zh-en/decoder.onnx');
      print('[StreamingAsrService] ⚠️ Using fp32 models, int8 not available');
    }

    final tokensPath = await copyAssetFile('assets/sherpa-onnx-streaming-paraformer-bilingual-zh-en/tokens.txt');

    print('[StreamingAsrService] 📂 Model files loaded');

    // 创建paraformer模型配置
    final paraformerConfig = sherpa_onnx.OnlineParaformerModelConfig(
      encoder: encoderPath,
      decoder: decoderPath,
    );

    // 平衡性能配置 - 适度增加线程但避免过度
    final modelConfig = sherpa_onnx.OnlineModelConfig(
      paraformer: paraformerConfig,
      tokens: tokensPath,
      numThreads: 3, // 降低到3个线程，避免上下文切换开销
      provider: "cpu",
      debug: false,
    );

    // 优化特征提取配置
    final featConfig = sherpa_onnx.FeatureConfig(
      sampleRate: 16000,
      featureDim: 80,
    );

    // 优化端点检测参数以平衡速度和准确性
    final config = sherpa_onnx.OnlineRecognizerConfig(
      model: modelConfig,
      feat: featConfig,
      enableEndpoint: true,
      // 调整端点检测参数以获得更好的速度-准确性平衡
      rule1MinTrailingSilence: 1.2,  // 稍微增加以确保完整性
      rule2MinTrailingSilence: 0.6,  // 降低以提升响应速度
      rule3MinUtteranceLength: 8.0,  // 降低最小话语长度
      hotwordsFile: '',
      hotwordsScore: 2.0,
      maxActivePaths: 6,   // 减少到6个路径，平衡准确性和速度
    );

    print('[StreamingAsrService] ✅ Optimized config created');
    return config;
  }

  /// 轻量级音频预处理 - 只在必要时增强
  Float32List _preprocessAudioLight(Float32List audioData) {
    if (audioData.isEmpty) return audioData;

    // 跳帧优化 - 每5帧才计算一次音频质量
    _frameCounter++;
    if (_frameCounter % 5 == 0) {
      // 快速计算音频能量（简化版）
      double energy = 0.0;
      final step = math.max(1, audioData.length ~/ 100); // 采样计算
      for (int i = 0; i < audioData.length; i += step) {
        energy += audioData[i] * audioData[i];
      }
      _audioLevel = math.sqrt(energy / (audioData.length / step));

      // 检测静音
      if (_audioLevel < _silenceThreshold) {
        _silenceFrameCount++;
      } else {
        _silenceFrameCount = 0;
        _lastActivityTime = DateTime.now();
      }
    }

    // 只在启用音频增强且音频质量差时处理
    if (_enableAudioEnhancement && _audioLevel > 0.15) {
      return _enhanceAudio(audioData);
    }

    return audioData;
  }

  /// 音频增强（仅在需要时调用）
  Float32List _enhanceAudio(Float32List audioData) {
    final normalizedData = Float32List(audioData.length);
    final scaleFactor = 0.7 / _audioLevel; // 保守的归一化

    for (int i = 0; i < audioData.length; i++) {
      normalizedData[i] = (audioData[i] * scaleFactor).clamp(-0.9, 0.9);
    }

    return normalizedData;
  }

  /// 智能纠错 - 只对最终结果进行完整纠错
  String _correctRecognitionResult(String originalText, {bool isFinal = false}) {
    if (!_enableCorrection || originalText.isEmpty) {
      return originalText;
    }

    _totalRecognitions++;

    // 对于部分结果，只做快速纠错（如果启用）
    if (!isFinal && !_enablePartialCorrection) {
      return originalText;
    }

    // 应用文本纠错
    String correctedText = _correctionService.correctText(originalText);

    // 如果发生了纠错，记录统计信息
    if (correctedText != originalText) {
      _totalCorrections++;
      if (isFinal) {
        print('[StreamingAsrService] �� 最���纠错: "$originalText" → "$correctedText"');
      }
    }

    return correctedText;
  }

  /// 高效的缓冲区管理
  void _addToBuffer(Float32List audioData) {
    final dataLength = audioData.length;

    // 检查缓冲区空间
    if (_bufferLength + dataLength > _audioBuffer.length) {
      // 如果超出最大缓冲区，移除旧数据
      if (_bufferLength > _maxBufferSize ~/ 2) {
        final keepLength = _maxBufferSize ~/ 2;
        _audioBuffer.setRange(0, keepLength, _audioBuffer, _bufferLength - keepLength);
        _bufferLength = keepLength;
      } else {
        // 扩展缓冲区
        final newBuffer = Float32List(_audioBuffer.length * 2);
        newBuffer.setRange(0, _bufferLength, _audioBuffer);
        _audioBuffer = newBuffer;
      }
    }

    // 添加新数据
    _audioBuffer.setRange(_bufferLength, _bufferLength + dataLength, audioData);
    _bufferLength += dataLength;
  }

  /// 优化的音频处理方法（非阻塞版本）
  Future<String> processAudio(Float32List audioData) async {
    if (!_isInitialized || _stream == null) {
      return '';
    }

    try {
      // 轻量级预处理
      final processedAudio = _preprocessAudioLight(audioData);

      // 🔧 FIX: 跟踪总接收的音频数据
      _totalAudioReceived += processedAudio.length;

      // 高效添加到缓冲区
      _addToBuffer(processedAudio);

      String result = '';

      // 🔧 FIX: 改进的即时处理模式切换逻辑
      int targetChunkSize = _optimalChunkSize;
      bool shouldSwitchToNormal = false;
      
      if (_enableInstantProcessing) {
        // 多条件判断是否应该��换到正常模式：
        // 1. 已接收足够的音频数据 (1秒)
        // 2. 或者运行时间超过3秒
        // 3. 或者已经有识别结果输出
        final elapsedMs = DateTime.now().difference(_startTime).inMilliseconds;
        
        if (_totalAudioReceived >= 16000 || // 1秒的音频数据
            elapsedMs >= 3000 || // 3秒运行时间
            _lastPartialResult.isNotEmpty) { // 已有识别结果
          shouldSwitchToNormal = true;
        } else {
          targetChunkSize = _minChunkSize; // 继续使用小块
        }
      }

      // 处理完整的音频块
      while (_bufferLength >= targetChunkSize) {
        // 提取音频块（避免额外的内存分配）
        final chunk = _audioBuffer.sublist(0, targetChunkSize);

        // 移动剩余数据（高效的内存操作）
        final remaining = _bufferLength - targetChunkSize;
        if (remaining > 0) {
          _audioBuffer.setRange(0, remaining, _audioBuffer, targetChunkSize);
        }
        _bufferLength = remaining;

        // 🔧 FIX: 即时输入音频到识别器，无需等待
        _stream!.acceptWaveform(samples: chunk, sampleRate: _sampleRate.toInt());
        _processedSamples += targetChunkSize;

        // 异步处理识别（不等待）
        _processRecognitionNonBlocking();

        // 快速检查结果
        final currentResult = _recognizer!.getResult(_stream!);
        if (currentResult.text.isNotEmpty && currentResult.text != _lastPartialResult) {
          // 对部分结果只做轻量纠错
          String correctedResult = _correctRecognitionResult(currentResult.text, isFinal: false);
          result = correctedResult;
          _lastPartialResult = currentResult.text;
          _lastCorrectedResult = correctedResult;

          _resultController.add(correctedResult);
          
          // 🔧 FIX: 一旦有识别结果，立即切换到正常模式
          if (_enableInstantProcessing) {
            shouldSwitchToNormal = true;
          }
        }

        // 检查端点
        if (_recognizer!.isEndpoint(_stream!)) {
          final finalResult = _recognizer!.getResult(_stream!);
          if (finalResult.text.isNotEmpty && finalResult.text != _lastFinalResult) {
            // 对最终结果进行完整纠错
            String correctedFinalResult = _correctRecognitionResult(finalResult.text, isFinal: true);
            result = correctedFinalResult;
            _lastFinalResult = finalResult.text;
            _lastCorrectedResult = correctedFinalResult;

            print('[StreamingAsrService] 🏁 Final: $correctedFinalResult');
            _resultController.add(correctedFinalResult);
          }

          // 重置流
          _recognizer!.reset(_stream!);
          _lastPartialResult = '';
        }

        // 🔧 FIX: 执行模式切换
        if (shouldSwitchToNormal && _enableInstantProcessing) {
          _enableInstantProcessing = false;
          targetChunkSize = _optimalChunkSize; // 立即切换到正常块大小
          print('[StreamingAsrService] 🚀 切换到正常处理模式 (音频:${_totalAudioReceived}, 时间:${DateTime.now().difference(_startTime).inMilliseconds}ms, 结果:${_lastPartialResult.isNotEmpty})');
        }
      }

      return result;

    } catch (e) {
      print('[StreamingAsrService] ❌ Error processing audio: $e');
      return '';
    }
  }

  /// 非阻塞识别处理
  void _processRecognitionNonBlocking() {
    try {
      // 限制处理帧数以避免阻塞
      int processedFrames = 0;
      while (_recognizer!.isReady(_stream!) && processedFrames < 5) {
        _recognizer!.decode(_stream!);
        processedFrames++;
      }
    } catch (e) {
      print('[StreamingAsrService] ❌ Error in non-blocking recognition: $e');
    }
  }

  /// 优化的连续音频输入方法
  void feedAudio(Float32List audioData) {
    if (!_isInitialized || _stream == null) return;

    try {
      final processedAudio = _preprocessAudioLight(audioData);
      _stream!.acceptWaveform(samples: processedAudio, sampleRate: _sampleRate.toInt());

      // 完全非阻塞处理
      Future.microtask(() => _processRecognitionNonBlocking());

    } catch (e) {
      print('[StreamingAsrService] ❌ Error feeding audio: $e');
    }
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

      // 添加适量静��来触发端点
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

  /// 性能优化设置
  void setPerformanceMode({
    bool enableAudioEnhancement = false,
    bool enablePartialCorrection = false,
    bool enableTextCorrection = true,
  }) {
    _enableAudioEnhancement = enableAudioEnhancement;
    _enablePartialCorrection = enablePartialCorrection;
    _enableCorrection = enableTextCorrection;

    print('[StreamingAsrService] 🎛️ 性能模式设置:');
    print('  音频增强: ${enableAudioEnhancement ? "启用" : "禁用"}');
    print('  部分结果纠错: ${enablePartialCorrection ? "启用" : "禁用"}');
    print('  文本纠错: ${enableTextCorrection ? "启用" : "禁用"}');
  }
}
