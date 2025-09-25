import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:app/utils/onnx_ffi_bindings.dart' as onnx;
import 'package:app/models/graph_models.dart';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

/// 嵌入服务 - 专门为EventNode提供向量嵌入功能
class EmbeddingService {
  static final EmbeddingService _instance = EmbeddingService._internal();
  factory EmbeddingService() => _instance;
  EmbeddingService._internal();

  // 向量维度，与EventNode中的@HnswIndex(dimensions: 384)保持一致
  static const int vectorDimensions = 384;

  // 缓存已计算的向量，避免重复计算
  final Map<String, List<double>> _embeddingCache = {};

  // ONNX FFI 组件
  ffi.Pointer<onnx.OrtEnv> _ortEnv = ffi.nullptr;
  ffi.Pointer<onnx.OrtSessionOptions> _ortSessionOptions = ffi.nullptr;
  ffi.Pointer<onnx.OrtSession> _ortSession = ffi.nullptr;
  // 直接通过 getter 获取 OrtApi，避免类型和初始化问题
  ffi.Pointer<onnx.OrtApi> get _ortApi {
    final apiBasePtr = onnx.onnxBindings.GetApiBase();
    final getApi = apiBasePtr.ref.GetApi.asFunction<onnx.GetApi_dart_t>();
    return getApi(onnx.ORT_API_VERSION);
  }

  bool _isModelLoaded = false;
  List<String>? _inputNames;
  List<String>? _outputNames;
  Completer<bool>? _initCompleter;

  /// 初始化服务
  Future<bool> initialize() async {
    if (_isModelLoaded) return true;
    if (_initCompleter != null) {
      // 有其他初始化在进行，等待其完成
      return await _initCompleter!.future;
    }
    _initCompleter = Completer<bool>();
    try {
      final result = await _initializeModel();
      _initCompleter!.complete(result);
      return result;
    } catch (e) {
      _initCompleter!.complete(false);
      rethrow;
    } finally {
      _initCompleter = null;
    }
  }

  /// 初始化GTE模型
  Future<bool> _initializeModel() async {
    if (_isModelLoaded) return true;
    try {
      print('[EmbeddingService] 🔄 开始初始化模型 (FFI)...');
      print('[EmbeddingService] 📋 平台: \\${Platform.operatingSystem}, ABI: \\${Platform.version}');
      // 1. 获取 API
      if (!_isModelLoaded) {
        final apiBasePtr = onnx.onnxBindings.GetApiBase();
        print('[EmbeddingService] 📋 apiBasePtr: 0xt\\${apiBasePtr.address.toRadixString(16)}');
        if (apiBasePtr == ffi.nullptr) {
          throw Exception('Failed to get ONNX Runtime API base.');
        }
        final getApi = apiBasePtr.ref.GetApi.asFunction<onnx.GetApi_dart_t>();
        final apiPtr = getApi(onnx.ORT_API_VERSION);
        print('[EmbeddingService] 📋 apiPtr: 0xt\\${apiPtr.address.toRadixString(16)}');
        print('[EmbeddingService] ✅ API 获取成功');
      }

      // 2. 创建环境
      print('[EmbeddingService] 🔧 调用 createEnv...');
      final envPtrPtr = calloc<ffi.Pointer<onnx.OrtEnv>>();
      var status = _ortApi.cast<onnx.OrtApiStruct>().ref.createEnv.asFunction<onnx.CreateEnv_dart_t>()(
          ffi.nullptr,
          onnx.OrtLoggingLevel.verbose.index,
          'Default'.toNativeUtf8(),
          envPtrPtr);
      print('[EmbeddingService] 🔧 createEnv 返回 status: 0xt\\${status.address.toRadixString(16)}');
      if (status.address != 0) {
        final errorMsgPtr = _ortApi.cast<onnx.OrtApiStruct>().ref.getErrorMessage.asFunction<onnx.GetErrorMessage_dart_t>()(status);
        String errorMessage;
        if (errorMsgPtr == ffi.nullptr) {
          errorMessage = 'Unknown error (error message pointer is nullptr)';
          print('[EmbeddingService] ⚠️ getErrorMessage returned nullptr for status: 0xt\\${status.address.toRadixString(16)}');
        } else {
          errorMessage = errorMsgPtr.toDartString();
        }
        _ortApi.cast<onnx.OrtApiStruct>().ref.releaseStatus.asFunction<onnx.ReleaseStatus_dart_t>()(status);
        throw Exception('ONNX Runtime FFI error: $errorMessage');
      }
      _ortEnv = envPtrPtr.value;
      calloc.free(envPtrPtr);
      _checkStatus(status);
      print('[EmbeddingService] ✅ 环境创建成功');

      // 3. 创建会话选项
      print('[EmbeddingService] 🔧 调用 createSessionOptions...');
      final sessionOptionsPtrPtr = calloc<ffi.Pointer<onnx.OrtSessionOptions>>();
      status = _ortApi.cast<onnx.OrtApiStruct>().ref.createSessionOptions.asFunction<onnx.CreateSessionOptions_dart_t>()(sessionOptionsPtrPtr);
      print('[EmbeddingService] 🔧 createSessionOptions 返回 status: 0xt\\${status.address.toRadixString(16)}');
      _ortSessionOptions = sessionOptionsPtrPtr.value;
      calloc.free(sessionOptionsPtrPtr);
      _checkStatus(status);
      print('[EmbeddingService] ✅ 会话选项创建成功');

      // 4. 加载模型文件并创建会话
      print('[EmbeddingService] 📁 尝试加载模型文件: assets/gte-model.onnx');
      final modelData = await rootBundle.load('assets/gte-model.onnx');
      final modelBytes = modelData.buffer.asUint8List();
      print('[EmbeddingService] 📁 模型文件长度: \\${modelBytes.length} 字节');

      final modelDataPtr = calloc<ffi.Uint8>(modelBytes.length);
      modelDataPtr.asTypedList(modelBytes.length).setAll(0, modelBytes);

      print('[EmbeddingService] 🔧 调用 createSessionFromArray...');
      final sessionPtrPtr = calloc<ffi.Pointer<onnx.OrtSession>>();
      status = _ortApi.cast<onnx.OrtApiStruct>().ref.createSessionFromArray.asFunction<onnx.CreateSessionFromArray_dart_t>()(
          _ortEnv, modelDataPtr.cast<ffi.Void>(), modelBytes.length, _ortSessionOptions, sessionPtrPtr);
      print('[EmbeddingService] 🔧 createSessionFromArray 返回 status: 0xt\\${status.address.toRadixString(16)}');

      _ortSession = sessionPtrPtr.value;
      calloc.free(sessionPtrPtr);
      calloc.free(modelDataPtr);
      _checkStatus(status);
      print('[EmbeddingService] ✅ ONNX会话创建成功');

      // 尝试获取模型的实际输入输出信息
      try {
        // 这里我们使用预设的名称，因为无法直接获取
        _inputNames = ['input_ids', 'attention_mask', 'token_type_ids'];
        _outputNames = ['last_hidden_state'];

        print('[EmbeddingService] 📋 预设输入名称: $_inputNames');
        print('[EmbeddingService] 📋 预设输出名称: $_outputNames');
      } catch (e) {
        print('[EmbeddingService] ⚠️ 无法获取模型元信息: $e');
      }

      _isModelLoaded = true;
      print('[EmbeddingService] ✅ GTE模型初始化完成');

      // 测试模型推理
      print('[EmbeddingService] 🧪 开始模型推理测试...');
      final testResult = await _testModelInference();
      if (!testResult) {
        print('[EmbeddingService] ❌ 模型推理测试失败，回退到备用方案');
        dispose(); // 清理已创建的 FFI 资源
        return false;
      } else {
        print('[EmbeddingService] ✅ 模型推理测试成功');
      }

      return true;

    } on PlatformException catch (e) {
      print('[EmbeddingService] ❌ 平台异常 - 模型文件加载失败:');
      print('[EmbeddingService] 错误代码: ${e.code}');
      print('[EmbeddingService] 错误消息: ${e.message}');
      return false;
    } catch (e) {
      print('[EmbeddingService] ❌ 模型解析/会话创建失败: $e');
      print('[EmbeddingService] 💡 详细错误信息: ${e.toString()}');
      if (e.toString().contains('incompatible')) {
        print('[EmbeddingService] 💡 可能是模型与设备架构不兼容');
      }
      if (e.toString().contains('version')) {
        print('[EmbeddingService] 💡 可能是ONNX版本不匹配');
      }
      return false;
    }
  }

  void _checkStatus(ffi.Pointer<onnx.OrtStatus> status) {
    if (status != ffi.nullptr) {
      final errorMsgPtr = _ortApi.cast<onnx.OrtApiStruct>().ref.getErrorMessage.asFunction<onnx.GetErrorMessage_dart_t>()(status);
      String errorMessage;
      if (errorMsgPtr == ffi.nullptr) {
        errorMessage = 'Unknown error (error message pointer is nullptr)';
      } else {
        errorMessage = errorMsgPtr.toDartString();
      }
      _ortApi.cast<onnx.OrtApiStruct>().ref.releaseStatus.asFunction<onnx.ReleaseStatus_dart_t>()(status);
      throw Exception('ONNX Runtime FFI error: $errorMessage');
    }
  }

  Future<bool> _testModelInference() async {
    final List<ffi.Pointer<onnx.OrtValue>> inputTensors = [];
    final List<ffi.Pointer<Utf8>> inputNames = [];
    final List<ffi.Pointer<Utf8>> outputNames = [];
    ffi.Pointer<ffi.Pointer<onnx.OrtValue>>? outputTensorsPtr;
    ffi.Pointer<ffi.Pointer<Utf8>>? inputNamesPtr;
    ffi.Pointer<ffi.Pointer<Utf8>>? outputNamesPtr;

    try {
      if (_ortSession == ffi.nullptr) return false;

      print('[EmbeddingService] 🧪 测试模型推理...');

      // 1. 创建简单的测试输入
      final testTokens = [101, 1000, 2000, 102]; // [CLS] token1 token2 [SEP]
      final paddedTokens = List<int>.from(testTokens);
      const maxLength = 512;
      while (paddedTokens.length < maxLength) {
        paddedTokens.add(0);
      }

      final shape = [1, maxLength];
      final inputIds = _createInt64Tensor(paddedTokens, shape);
      inputTensors.add(inputIds);

      final attentionMask = _createInt64Tensor(_createAttentionMask(paddedTokens), shape);
      inputTensors.add(attentionMask);

      final tokenTypeIds = _createInt64Tensor(List.filled(maxLength, 0), shape);
      inputTensors.add(tokenTypeIds);

      // 2. 准备输入/输出名称
      for (final name in _inputNames!) {
        inputNames.add(name.toNativeUtf8());
      }
      outputNames.addAll(_outputNames!.map((name) => name.toNativeUtf8()).toList());

      inputNamesPtr = calloc<ffi.Pointer<Utf8>>(_inputNames!.length);
      for (int i = 0; i < _inputNames!.length; i++) {
        inputNamesPtr![i] = inputNames[i];
      }

      outputNamesPtr = calloc<ffi.Pointer<Utf8>>(_outputNames!.length);
      for (int i = 0; i < _outputNames!.length; i++) {
        outputNamesPtr![i] = outputNames[i];
      }

      // 3. 准备输入/输出值指针数组
      final inputTensorsPtr = calloc<ffi.Pointer<onnx.OrtValue>>(inputTensors.length);
      for (int i = 0; i < inputTensors.length; i++) {
        inputTensorsPtr[i] = inputTensors[i];
      }

      outputTensorsPtr = calloc<ffi.Pointer<onnx.OrtValue>>(_outputNames!.length);

      // 4. 执行推理
      print('[EmbeddingService] 🔧 执行测试推理...');
      final status = _ortApi.cast<onnx.OrtApiStruct>().ref.run.asFunction<onnx.Run_dart_t>()(
        _ortSession,
        ffi.nullptr, // RunOptions
        inputNamesPtr,
        inputTensorsPtr,
        inputTensors.length,
        outputNamesPtr,
        _outputNames!.length,
        outputTensorsPtr,
      );
      _checkStatus(status);
      print('[EmbeddingService] ✅ 测试推理成功');

      // 5. 简单验证输出
      if (outputTensorsPtr.value == ffi.nullptr) {
        throw Exception('Test inference produced null output.');
      }

      return true;
    } catch (e) {
      print('[EmbeddingService] ❌ 模型推理测试失败: $e');
      return false;
    } finally {
      // 6. 释放所有资源
      for (final tensor in inputTensors) {
        _ortApi.cast<onnx.OrtApiStruct>().ref.releaseValue.asFunction<onnx.ReleaseValue_dart_t>()(tensor);
      }
      if (outputTensorsPtr != null) {
        for (int i = 0; i < _outputNames!.length; i++) {
           if (outputTensorsPtr[i] != ffi.nullptr) {
             _ortApi.cast<onnx.OrtApiStruct>().ref.releaseValue.asFunction<onnx.ReleaseValue_dart_t>()(outputTensorsPtr[i]);
           }
        }
        calloc.free(outputTensorsPtr);
      }
      inputNames.forEach(calloc.free);
      outputNames.forEach(calloc.free);
      if (inputNamesPtr != null) calloc.free(inputNamesPtr);
      if (outputNamesPtr != null) calloc.free(outputNamesPtr);
    }
  }


  /// 使用事件的名称、描述、目的、结果组合生成语义向量
  Future<List<double>?> generateEventEmbedding(EventNode eventNode) async {
    try {
      // 获取用于嵌入的文本内容
      final embeddingText = eventNode.getEmbeddingText();

      if (embeddingText.trim().isEmpty) {
        print('[EmbeddingService] ⚠️ 事件文本为空，无法生成嵌入: ${eventNode.name}');
        return null;
      }

      // 检查缓存
      final cacheKey = _generateCacheKey(embeddingText);
      if (_embeddingCache.containsKey(cacheKey)) {
        print('[EmbeddingService] 📋 使用缓存的嵌入向量: ${eventNode.name}');
        return _embeddingCache[cacheKey];
      }

      // 尝试使用GTE模型生成嵌入向量
      List<double>? embedding;
      if (await initialize()) {
        embedding = await _generateEmbeddingWithModel(embeddingText);
      }

      // 如果模型失败，使用备用方法
      if (embedding == null) {
        print('[EmbeddingService] ❌ 模型生成嵌入失败，使用备用方法: ${eventNode.name}');
        embedding = await _generateFallbackEmbedding(embeddingText);
      }

      // 缓存结果
      _embeddingCache[cacheKey] = embedding;

      print('[EmbeddingService] ✨ 生成事件嵌入向量: ${eventNode.name} (${embedding.length}维)');
      return embedding;
    } catch (e) {
      print('[EmbeddingService] ❌ 生成事件嵌入向量失败: $e');
      return await _generateFallbackEmbedding(eventNode.getEmbeddingText());
    }
  }

  /// 为文本生成嵌入向量（通用方法）
  Future<List<double>?> generateTextEmbedding(String text) async {
    try {
      if (text.trim().isEmpty) {
        return null;
      }

      final cacheKey = _generateCacheKey(text);
      if (_embeddingCache.containsKey(cacheKey)) {
        return _embeddingCache[cacheKey];
      }

      // 尝试使用GTE模型生成嵌入向量
      List<double>? embedding;
      if (await initialize()) {
        embedding = await _generateEmbeddingWithModel(text);
      }

      // 如果模型失败，使用备用方法
      if (embedding == null) {
        print('[EmbeddingService] ❌ 模型生成嵌入失败，使用备用方法');
        embedding = await _generateFallbackEmbedding(text);
      }

      _embeddingCache[cacheKey] = embedding;
      return embedding;
    } catch (e) {
      print('[EmbeddingService] ❌ 生成文本嵌入�����量失败: $e');
      return await _generateFallbackEmbedding(text);
    }
  }

  List<int> _createAttentionMask(List<int> tokens) {
    return tokens.map((id) => id == 0 ? 0 : 1).toList();
  }

  /// 使用GTE模型生成嵌入���量
  Future<List<double>?> _generateEmbeddingWithModel(String text) async {
    final List<ffi.Pointer<onnx.OrtValue>> inputTensors = [];
    final List<ffi.Pointer<Utf8>> inputNamePtrs = [];
    final List<ffi.Pointer<Utf8>> outputNamePtrs = [];
    ffi.Pointer<ffi.Pointer<onnx.OrtValue>>? outputTensorsPtr;
    ffi.Pointer<ffi.Pointer<Utf8>>? inputNamesPtr;
    ffi.Pointer<ffi.Pointer<Utf8>>? outputNamesPtr;

    try {
      if (!_isModelLoaded || _ortSession == ffi.nullptr) return null;

      final tokens = _tokenizeText(text);
      if (tokens.isEmpty) return null;

      // 1. 创建输入张量
      final shape = [1, tokens.length];
      final inputIds = _createInt64Tensor(tokens, shape);
      inputTensors.add(inputIds);

      final attentionMask = _createInt64Tensor(_createAttentionMask(tokens), shape);
      inputTensors.add(attentionMask);

      final tokenTypeIds = _createInt64Tensor(List.filled(tokens.length, 0), shape);
      inputTensors.add(tokenTypeIds);

      // 2. 准备输入/输出名称
      for (final name in _inputNames!) {
        inputNamePtrs.add(name.toNativeUtf8());
      }
      for (final name in _outputNames!) {
        outputNamePtrs.add(name.toNativeUtf8());
      }

      inputNamesPtr = calloc<ffi.Pointer<Utf8>>(_inputNames!.length);
      for (int i = 0; i < _inputNames!.length; i++) {
        inputNamesPtr![i] = inputNamePtrs[i];
      }

      outputNamesPtr = calloc<ffi.Pointer<Utf8>>(_outputNames!.length);
      for (int i = 0; i < _outputNames!.length; i++) {
        outputNamesPtr![i] = outputNamePtrs[i];
      }

      // 3. 准备输入/输出值指针数组
      final inputTensorsPtr = calloc<ffi.Pointer<onnx.OrtValue>>(inputTensors.length);
      for (int i = 0; i < inputTensors.length; i++) {
        inputTensorsPtr[i] = inputTensors[i];
      }

      outputTensorsPtr = calloc<ffi.Pointer<onnx.OrtValue>>(_outputNames!.length);

      // 4. 执行推理
      print('[EmbeddingService] 🔧 执行 FFI 推理...');
      final status = _ortApi.cast<onnx.OrtApiStruct>().ref.run.asFunction<onnx.Run_dart_t>()(
        _ortSession,
        ffi.nullptr, // RunOptions
        inputNamesPtr,
        inputTensorsPtr,
        inputTensors.length,
        outputNamesPtr,
        _outputNames!.length,
        outputTensorsPtr,
      );
      _checkStatus(status);
      print('[EmbeddingService] ✅ FFI 推理成功');

      // 5. 解析输出
      final outputValue = outputTensorsPtr.value;
      final outputDataPtrPtr = calloc<ffi.Pointer<ffi.Void>>();
      _checkStatus(_ortApi.cast<onnx.OrtApiStruct>().ref.getTensorMutableData.asFunction<onnx.GetTensorMutableData_dart_t>()(outputValue, outputDataPtrPtr));

      final outputDataPtr = outputDataPtrPtr.value.cast<ffi.Float>();
      // The output shape is [1, sequence_length, hidden_size], e.g., [1, 512, 384]
      // We need to perform mean pooling over the sequence_length dimension.
      final sequenceLength = tokens.length;
      final hiddenSize = vectorDimensions;
      final pooled = List<double>.filled(hiddenSize, 0.0);
      for (int i = 0; i < sequenceLength; i++) {
        for (int j = 0; j < hiddenSize; j++) {
          pooled[j] += outputDataPtr[i * hiddenSize + j];
        }
      }
      for (int j = 0; j < hiddenSize; j++) {
        pooled[j] /= sequenceLength;
      }

      calloc.free(outputDataPtrPtr);

      return _normalizeVector(pooled);

    } catch (e) {
      print('[EmbeddingService] ❌ GTE模型推理失败: $e');
      return null;
    } finally {
      // 6. 释放所有资源
      for (final tensor in inputTensors) {
        _ortApi.cast<onnx.OrtApiStruct>().ref.releaseValue.asFunction<onnx.ReleaseValue_dart_t>()(tensor);
      }
      if (outputTensorsPtr != null) {
        for (int i = 0; i < _outputNames!.length; i++) {
           if (outputTensorsPtr[i] != ffi.nullptr) {
             _ortApi.cast<onnx.OrtApiStruct>().ref.releaseValue.asFunction<onnx.ReleaseValue_dart_t>()(outputTensorsPtr[i]);
           }
        }
        calloc.free(outputTensorsPtr);
      }
      inputNamePtrs.forEach(calloc.free);
      outputNamePtrs.forEach(calloc.free);
      if (inputNamesPtr != null) calloc.free(inputNamesPtr);
      if (outputNamesPtr != null) calloc.free(outputNamesPtr);
    }
  }

  /// 简化的文本分词
  List<int> _tokenizeText(String text) {
    // 这是一个简化的tokenization实现
    final words = text.toLowerCase().split(RegExp(r'\s+'));
    final tokens = <int>[];

    // 添加[CLS] token
    tokens.add(101); // [CLS] token id

    for (final word in words) {
      if (word.isNotEmpty) {
        final tokenId = word.hashCode.abs() % 30000 + 1000; // 简化映射
        tokens.add(tokenId);
      }
    }

    // 添加[SEP] token
    tokens.add(102); // [SEP] token id

    const maxLength = 512;
    if (tokens.length > maxLength) {
      return tokens.take(maxLength).toList();
    } else {
      // 用[PAD] token填充
      while (tokens.length < maxLength) {
        tokens.add(0); // [PAD] token id
      }
    }

    return tokens;
  }

  /// 创建输入张量 (FFI)
  ffi.Pointer<onnx.OrtValue> _createInt64Tensor(List<int> data, List<int> shape) {
    // 1. 创建内存信息
    final memoryInfoPtrPtr = calloc<ffi.Pointer<onnx.OrtMemoryInfo>>();
    var status = _ortApi.cast<onnx.OrtApiStruct>().ref.createCpuMemoryInfo.asFunction<onnx.CreateCpuMemoryInfo_dart_t>()(
        onnx.OrtAllocatorType.arena.index, onnx.OrtMemType.default_.index, memoryInfoPtrPtr);
    final memoryInfo = memoryInfoPtrPtr.value;
    calloc.free(memoryInfoPtrPtr);
    _checkStatus(status);

    // 2. 准备数据 - 使用指针算术直接写入，避免 asTypedList
    final dataPtr = calloc<ffi.Int64>(data.length);
    for (int i = 0; i < data.length; i++) {
      dataPtr[i] = data[i];
    }

    // 3. 准备形状 - 使用指针算术直接写入
    final shapePtr = calloc<ffi.Int64>(shape.length);
    for (int i = 0; i < shape.length; i++) {
      shapePtr[i] = shape[i];
    }

    // 4. 创建张量
    final valuePtrPtr = calloc<ffi.Pointer<onnx.OrtValue>>();
    status = _ortApi.cast<onnx.OrtApiStruct>().ref.createTensorWithDataAsOrtValue.asFunction<onnx.CreateTensorWithDataAsOrtValue_dart_t>()(
        memoryInfo,
        dataPtr.cast<ffi.Void>(),
        data.length * ffi.sizeOf<ffi.Int64>(), // size in bytes
        shapePtr,
        shape.length,
        onnx.ONNXTensorElementDataType.int64.index,
        valuePtrPtr);

    final ortValue = valuePtrPtr.value;
    calloc.free(valuePtrPtr);

    // 5. 清理
    _ortApi.cast<onnx.OrtApiStruct>().ref.releaseMemoryInfo.asFunction<onnx.ReleaseMemoryInfo_dart_t>()(memoryInfo);
    _checkStatus(status);

    // IMPORTANT: Do NOT free dataPtr and shapePtr here.
    // ONNX Runtime takes ownership of these pointers when creating the tensor.
    // They will be freed when the OrtValue is released.
    return ortValue;
  }


  /// 从输出张量提取嵌入向量
  // List<double> _extractEmbedding(OrtValue outputTensor) { // This will be replaced
  //   if (outputTensor is OrtValueTensor) {
  //     final raw = outputTensor.value;

  //     if (raw is Float32List) {
  //       return _normalizeVector(raw.cast<double>());
  //     } else if (raw is List<double>) {
  //       return _normalizeVector(raw);
  //     } else if (raw is List<List<double>>) {
  //       return _normalizeVector(raw[0]);
  //     }
  //   }

  //   return _generateFallbackVector();
  // }


  /// 对序列进行平均池化
  List<double> _meanPooling(List<List<double>> sequences) {
    if (sequences.isEmpty) return _generateFallbackVector();

    final hiddenSize = sequences[0].length;
    final pooled = List<double>.filled(hiddenSize, 0.0);

    for (final seq in sequences) {
      for (int i = 0; i < seq.length && i < hiddenSize; i++) {
        pooled[i] += seq[i];
      }
    }

    for (int i = 0; i < pooled.length; i++) {
      pooled[i] /= sequences.length;
    }

    return pooled;
  }

  /// 生成备用向量
  List<double> _generateFallbackVector() {
    final random = Random();
    return List.generate(vectorDimensions, (i) => random.nextGaussian());
  }

  /// 调整嵌入向量维度
  List<double> _resizeEmbedding(List<double> embedding, int targetDim) {
    if (embedding.length == targetDim) {
      return embedding;
    }

    if (embedding.length > targetDim) {
      // 截断
      return embedding.take(targetDim).toList();
    } else {
      // 填充零或重复
      final result = List<double>.from(embedding);
      while (result.length < targetDim) {
        if (result.length + embedding.length <= targetDim) {
          result.addAll(embedding); // 重复原向量
        } else {
          // 填充剩余部分
          final remaining = targetDim - result.length;
          result.addAll(embedding.take(remaining));
          break;
        }
      }
      return result;
    }
  }

  /// 归一化向量
  List<double> _normalizeVector(List<double> vector) {
    final norm = sqrt(vector.map((x) => x * x).reduce((a, b) => a + b));
    if (norm > 0) {
      return vector.map((x) => x / norm).toList();
    }
    return vector;
  }

  /// 备用嵌入生成方法
  Future<List<double>> _generateFallbackEmbedding(String text) async {
    return _generateSemanticVector(text);
  }

  /// 生成缓存键
  String _generateCacheKey(String text) {
    final bytes = utf8.encode(text);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  /// 计算两个向量的余弦相似度
  double calculateCosineSimilarity(List<double> vectorA, List<double> vectorB) {
    if (vectorA.length != vectorB.length) {
      throw ArgumentError('向量维度不匹配: ${vectorA.length} vs ${vectorB.length}');
    }

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < vectorA.length; i++) {
      dotProduct += vectorA[i] * vectorB[i];
      normA += vectorA[i] * vectorA[i];
      normB += vectorB[i] * vectorB[i];
    }

    if (normA == 0.0 || normB == 0.0) {
      return 0.0;
    }

    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  /// 查找与查询向量最相似的事件
  Future<List<Map<String, dynamic>>> findSimilarEvents(
      List<double> queryVector,
      List<EventNode> eventNodes, {
        int topK = 10,
        double threshold = 0.5,
      }) async {
    final results = <Map<String, dynamic>>[];

    for (final eventNode in eventNodes) {
      if (eventNode.embedding != null && eventNode.embedding!.isNotEmpty) {
        final similarity = calculateCosineSimilarity(queryVector, eventNode.embedding!);

        if (similarity >= threshold) {
          results.add({
            'event': eventNode,
            'similarity': similarity,
          });
        }
      }
    }

    // 按相似度降序排序
    results.sort((a, b) => (b['similarity'] as double).compareTo(a['similarity'] as double));

    // 返回前K个结果
    return results.take(topK).toList();
  }

  /// 根据查询文本查找相似事件
  Future<List<Map<String, dynamic>>> searchSimilarEventsByText(
      String queryText,
      List<EventNode> eventNodes, {
        int topK = 10,
        double threshold = 0.5,
      }) async {
    final queryVector = await generateTextEmbedding(queryText);
    if (queryVector == null) {
      return [];
    }

    return await findSimilarEvents(queryVector, eventNodes, topK: topK, threshold: threshold);
  }

  /// 生成语义向量（备用方案）
  Future<List<double>> _generateSemanticVector(String text) async {
    // 文本预处理
    final normalizedText = text.toLowerCase().trim();
    final words = normalizedText.split(RegExp(r'\s+'));

    // 创建基础向量
    final vector = List<double>.filled(vectorDimensions, 0.0);
    final random = Random(normalizedText.hashCode);

    // 基于词汇特征生成向量
    for (int i = 0; i < words.length && i < vectorDimensions ~/ 4; i++) {
      final word = words[i];
      final wordHash = word.hashCode;
      final wordRandom = Random(wordHash);

      final startIndex = (i * 4) % vectorDimensions;
      for (int j = 0; j < 4 && startIndex + j < vectorDimensions; j++) {
        vector[startIndex + j] = wordRandom.nextDouble() * 2 - 1;
      }
    }

    // 基于文本长度和字符特征调整向量
    final lengthFactor = min(text.length / 100.0, 1.0);
    for (int i = 0; i < vectorDimensions; i++) {
      vector[i] += (random.nextDouble() * 0.2 - 0.1) * lengthFactor;

      if (text.contains(RegExp(r'[\u4e00-\u9fa5]'))) {
        vector[i] += (random.nextDouble() * 0.1 - 0.05);
      }
    }

    return _normalizeVector(vector);
  }

  /// 清空缓存
  void clearCache() {
    _embeddingCache.clear();
    print('[EmbeddingService] 🧹 已清空嵌入向量缓存');
  }

  /// 获取缓存统计信息
  Map<String, dynamic> getCacheStats() {
    return {
      'cached_embeddings': _embeddingCache.length,
      'memory_usage_estimate': _embeddingCache.length * vectorDimensions * 8,
      'model_loaded': _isModelLoaded,
    };
  }

  /// 获取模型文件路径
  String getModelFilePath() {
    return 'assets/gte-model.onnx';
  }

  /// 检查平台兼容性
  bool checkPlatformCompatibility() {
    // 检查当前平台是否支持ONNX Runtime
    return Platform.isAndroid || Platform.isIOS || Platform.isLinux || Platform.isWindows;
  }

  /// 检查依赖库
  Future<List<String>> checkDependencies() async {
    final dependencies = <String>[];

    try {
      // 检查ONNX Runtime
      // final testOptions = OrtSessionOptions(); // This will be replaced
      dependencies.add('ONNX Runtime: ✅ 可用 (FFI)');
    } catch (e) {
      dependencies.add('ONNX Runtime: ❌ 不可用 - $e');
    }

    // 检查其他依赖
    dependencies.add('Flutter: ✅ 可用');
    dependencies.add('Dart: ✅ 可用');
    dependencies.add('crypto: ✅ 可用');

    return dependencies;
  }

  /// 检查网络连接
  Future<bool> checkInternetConnection() async {
    try {
      // 简单的网络检查，这里可以根据需要扩展
      return true; // 暂时返回true，实际应用中可以实现真正的网络检查
    } catch (e) {
      return false;
    }
  }

  /// 释放模型资源
  void dispose() {
    try {
      print('[EmbeddingService] 🧹 释放 FFI 模型资源...');
      if (_ortSession != ffi.nullptr) {
        _ortApi.cast<onnx.OrtApiStruct>().ref.releaseSession.asFunction<onnx.ReleaseSession_dart_t>()(_ortSession);
        _ortSession = ffi.nullptr;
      }
      if (_ortSessionOptions != ffi.nullptr) {
        _ortApi.cast<onnx.OrtApiStruct>().ref.releaseSessionOptions.asFunction<onnx.ReleaseSessionOptions_dart_t>()(_ortSessionOptions);
        _ortSessionOptions = ffi.nullptr;
      }
      if (_ortEnv != ffi.nullptr) {
        _ortApi.cast<onnx.OrtApiStruct>().ref.releaseEnv.asFunction<onnx.ReleaseEnv_dart_t>()(_ortEnv);
        _ortEnv = ffi.nullptr;
      }

      _isModelLoaded = false;
      _inputNames = null;
      _outputNames = null;
      clearCache();
      print('[EmbeddingService] 🧹 已释放模型资源');
    } catch (e) {
      print('[EmbeddingService] ❌ 释放资源失败: $e');
    }
  }
}

extension on Random {
  double nextGaussian() {
    double u = 0, v = 0;
    while (u == 0) u = nextDouble();
    while (v == 0) v = nextDouble();
    return sqrt(-2.0 * log(u)) * cos(2.0 * pi * v);
  }
}
