import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:app/models/graph_models.dart';

/// 嵌入服务 - 专门为EventNode提供向量嵌入功能
class EmbeddingService {
  static final EmbeddingService _instance = EmbeddingService._internal();
  factory EmbeddingService() => _instance;
  EmbeddingService._internal();

  // 向量维度，与EventNode中的@HnswIndex(dimensions: 384)保持一致
  static const int vectorDimensions = 384;

  // 缓存已计算的向量，避免重复计算
  final Map<String, List<double>> _embeddingCache = {};

  // ONNX 会话和相关组件
  OrtSession? _session;
  bool _isModelLoaded = false;
  List<String>? _inputNames;
  List<String>? _outputNames;

  /// 初始化服务
  Future<bool> initialize() async {
    if (_isModelLoaded) return true;
    return await _initializeModel();
  }

  /// 初始化GTE模型
  Future<bool> _initializeModel() async {
    if (_isModelLoaded) return true;

    try {
      print('[EmbeddingService] 🔄 正在加载GTE模型...');

      final modelData = await rootBundle.load('assets/gte-model.onnx');
      final modelBytes = modelData.buffer.asUint8List();

      final sessionOptions = OrtSessionOptions();

      _session = await OrtSession.fromBuffer(modelBytes, sessionOptions);

      // GTE-small 默认输入输出名
      _inputNames = ['input_ids'];      // 可根据模型实际检查
      _outputNames = ['last_hidden_state']; // 或 'sentence_embedding' 视模型而定

      _isModelLoaded = true;
      print('[EmbeddingService] ✅ GTE模型加载成功');
      print('[EmbeddingService] 📊 输入: $_inputNames');
      print('[EmbeddingService] 📊 输出: $_outputNames');

      return true;
    } catch (e) {
      print('[EmbeddingService] ❌ GTE模型加载失败: $e');
      _isModelLoaded = false;
      return false;
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
      print('[EmbeddingService] ❌ 生成文本嵌入向量失败: $e');
      return await _generateFallbackEmbedding(text);
    }
  }

  /// 使用GTE模型生成嵌入向量
  Future<List<double>?> _generateEmbeddingWithModel(String text) async {
    try {
      if (!_isModelLoaded || _session == null || _inputNames == null || _outputNames == null) {
        return null;
      }

      final tokens = _tokenizeText(text);
      if (tokens.isEmpty) return null;

      final inputTensor = _createInputTensor(tokens);
      final inputMap = {_inputNames![0]: inputTensor};

      // 注意：Dart 的 onnxruntime.run() 返回的是 List<OrtValue>
      final inputName = 'gte-model.onnx'; // 请根据你的模型实际输入名替换
      final runOptions = OrtRunOptions();

      final outputs = _session!.run(runOptions, {
        inputName: _createInputTensor(tokens),
      });

      final outputTensor = outputs.isNotEmpty ? outputs[0] : null;
      if (outputTensor != null) {
        final embedding = _extractEmbedding(outputTensor);
        if (embedding.length == vectorDimensions) return embedding;
        return _resizeEmbedding(embedding, vectorDimensions);
      }

      return null;
    } catch (e) {
      print('[EmbeddingService] ❌ GTE模型推理失败: $e');
      return null;
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

  /// 创建输入张量
  OrtValueTensor _createInputTensor(List<int> tokens) {
    final shape = [1, tokens.length];
    final data = Int64List.fromList(tokens);

    return OrtValueTensor.createTensorWithDataList(data, shape);
  }


  /// 从输出张量提取嵌入向量
  List<double> _extractEmbedding(OrtValue outputTensor) {
    if (outputTensor is OrtValueTensor) {
      final raw = outputTensor.value;

      if (raw is Float32List) {
        return _normalizeVector(raw.cast<double>());
      } else if (raw is List<double>) {
        return _normalizeVector(raw);
      } else if (raw is List<List<double>>) {
        return _normalizeVector(raw[0]);
      }
    }

    return _generateFallbackVector();
  }


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

  /// 释放模型资源
  void dispose() {
    try {
      _session?.release();
      _session = null;
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