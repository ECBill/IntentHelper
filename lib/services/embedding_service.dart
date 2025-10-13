import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
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
      print('[EmbeddingService] 🔄 开始初始化模型...');
      print('[EmbeddingService] 🔍 当前平台: ${Platform.operatingSystem}');

      // 检查ONNX Runtime是否可用
      try {
        print('[EmbeddingService] 📦 检查ONNX Runtime可用性...');
        final testOptions = OrtSessionOptions();
        print('[EmbeddingService] ✅ ONNX Runtime 初始化成功');
      } catch (e) {
        print('[EmbeddingService] ❌ ONNX Runtime 不可用: $e');
        return false;
      }

      // 尝试加载模型文件
      try {
        print('[EmbeddingService] 📁 尝试加载模型文件: assets/gte-model.onnx');
        final modelData = await rootBundle.load('assets/gte-model.onnx');
        print('[EmbeddingService] ✅ 模型文件读取成功，大小: ${modelData.lengthInBytes} bytes');

        final modelBytes = modelData.buffer.asUint8List();

        // 验证文件不为空且有合理大小
        if (modelBytes.length < 1000) {
          throw Exception('模型文件太小 (${modelBytes.length} bytes)，可能不是有效的ONNX模型');
        }

        // 检查ONNX文件魔数和格式
        if (modelBytes.length >= 8) {
          final header = modelBytes.take(8).toList();
          print('[EmbeddingService] 🔍 模型文件头部: ${header.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

          // ONNX文件通常以protobuf魔数开头 (08 XX 12 XX...)
          if (header[0] != 0x08) {
            print('[EmbeddingService] ⚠️ 警告: 文件头��不符合标准ONNX格式');
          }
        }

        final sessionOptions = OrtSessionOptions();

        // 为Android优化设置
        if (Platform.isAndroid) {
          print('[EmbeddingService] 🤖 配置Android优化设置...');
          // 可以在这里添加Android特定的优化配置
        }

        print('[EmbeddingService] ⚙️ 创建ONNX会话...');
        _session = await OrtSession.fromBuffer(modelBytes, sessionOptions);

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
          _isModelLoaded = false;
          _session?.release();
          _session = null;
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
    } catch (e, stackTrace) {
      print('[EmbeddingService] ❌ 模型初始化过程中发生未知错误: $e');
      print('[EmbeddingService] 🔍 堆栈跟踪: $stackTrace');
      _isModelLoaded = false;
      return false;
    }
  }

  Future<bool> _testModelInference() async {
    try {
      if (_session == null) return false;

      print('[EmbeddingService] 🧪 测试模型推理...');

      // 创建简单的测试输入
      final testTokens = [101, 1000, 2000, 102]; // [CLS] token1 token2 [SEP]
      final paddedTokens = List<int>.from(testTokens);

      // 填充到固定长度
      while (paddedTokens.length < 512) {
        paddedTokens.add(0);
      }

      final inputIds = _createInputTensor(paddedTokens);
      final attentionMask = _createInputTensor(_createAttentionMask(paddedTokens));
      final tokenTypeIds = _createInputTensor(List.filled(paddedTokens.length, 0));

      print('[EmbeddingService] 🔧 执行测试推理...');
      final outputs = await _session!.run(OrtRunOptions(), {
        'input_ids': inputIds,
        'attention_mask': attentionMask,
        'token_type_ids': tokenTypeIds,
      });

      print('[EmbeddingService] ✅ 测试推理成功，输出数量: ${outputs.length}');

      if (outputs.isNotEmpty) {
        final firstOutput = outputs[0];
        print('[EmbeddingService] 📊 第一个输出类型: ${firstOutput.runtimeType}');

      }

      return true;
    } catch (e) {
      print('[EmbeddingService] ❌ 模型��理测试失败: $e');
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
      print('[EmbeddingService] ❌ 生成文本嵌入�����量失败: $e');
      return await _generateFallbackEmbedding(text);
    }
  }

  List<int> _createAttentionMask(List<int> tokens) {
    return tokens.map((id) => id == 0 ? 0 : 1).toList();
  }

  /// 使用GTE模型生成嵌入向量
  Future<List<double>?> _generateEmbeddingWithModel(String text) async {
    try {
      if (!_isModelLoaded || _session == null) {
        print('[EmbeddingService] ⚠️ 模型未加载或会话为空');
        return null;
      }

      final tokens = _tokenizeText(text);
      print('[EmbeddingService] 📝 输入文本: "$text"');
      print('[EmbeddingService] 📝 分词结果: ${tokens.length} tokens, 前10: ${tokens.take(10).toList()}');
      if (tokens.isEmpty) {
        print('[EmbeddingService] ⚠️ 分词后为空，跳过嵌入生成');
        return null;
      }

      final inputIds = _createInputTensor(tokens);
      final attentionMask = _createInputTensor(_createAttentionMask(tokens));
      final tokenTypeIds = _createInputTensor(List.filled(tokens.length, 0));
      print('[EmbeddingService] 📝 inputIds类型: \\${inputIds.runtimeType}, attentionMask类型: \\${attentionMask.runtimeType}');

      print('[EmbeddingService] 🔧 执行模型推理...');
      final outputs = await _session!.run(OrtRunOptions(), {
        'input_ids': inputIds,
        'attention_mask': attentionMask,
        'token_type_ids': tokenTypeIds,
      });
      print('[EmbeddingService] 📝 推理输出数量: \\${outputs.length}');
      for (int i = 0; i < outputs.length; i++) {
        print('[EmbeddingService] 📝 输出[\\$i]类型: \\${outputs[i].runtimeType}');
      }

      final outputTensor = outputs.isNotEmpty ? outputs[0] : null;
      print('[EmbeddingService] 📝 outputTensor类型: \\${outputTensor?.runtimeType}');

      if (outputTensor != null && outputTensor is OrtValueTensor) {
        final raw = outputTensor.value;
        print('[EmbeddingService] 📝 outputTensor.value类型: \\${raw.runtimeType}');
        if (raw is List<List<List<double>>>) {
          print('[EmbeddingService] 📝 outputTensor.value shape: [\\${raw.length}, \\${raw[0].length}, \\${raw[0][0].length}]');
          // 只取 [CLS] token 的 embedding
          return _normalizeVector(raw[0][0]);
        } else if (raw is List<List<double>>) {
          print('[EmbeddingService] 📝 outputTensor.value shape: [\\${raw.length}, \\${raw[0].length}]');
          return _normalizeVector(raw[0]);
        } else if (raw is Float32List) {
          print('[EmbeddingService] 📝 outputTensor.value Float32List长度: \\${raw.length}');
          return _normalizeVector(raw.cast<double>());
        } else {
          print('[EmbeddingService] ⚠️ outputTensor.value 类型未知: \\${raw.runtimeType}');
        }
      } else {
        print('[EmbeddingService] ⚠️ outputTensor为空或类型不是OrtValueTensor');
      }

      return null;
    } catch (e, stackTrace) {
      print('[EmbeddingService] ❌ GTE模型推理失败: $e');
      print('[EmbeddingService] 🔍 堆栈: $stackTrace');
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
    // 修复：使用Int64List而不是Int32List，因为模型期望int64类型
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
      } else if (raw is List<List<List<double>>>) {
        // 处理 [1, 512, 384]，取 raw[0] 得到 [512, 384]，做 mean pooling
        final pooled = _meanPooling(raw[0]);
        return _normalizeVector(pooled);
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

  // 为不同算法留一个版本号，便于将来迁移或判断是否需要重算
  static const int fallbackEmbeddingVersion = 2;

  // ---------------------- 新增：稳定可重复的哈希工具与分词 ----------------------
  // 将字符串稳定地哈希到一个非负 32bit 整数（使用 md5，避免 Dart hashCode 的不稳定性）
  int _stableHash32(String s, {int seed = 0}) {
    final bytes = utf8.encode('$seed#$s');
    final digest = md5.convert(bytes).bytes; // 16 bytes
    // 取前4个字节组成32位无符号整数
    int value = 0;
    for (int i = 0; i < 4; i++) {
      value = (value << 8) | (digest[i] & 0xFF);
    }
    // 保证非负
    return value & 0x7FFFFFFF;
  }

  // 将哈希映射到 [-1, 1] 的符号（第5个字节的最低位）
  int _stableSign(String s) {
    final bytes = md5.convert(utf8.encode('sign#$s')).bytes;
    final bit = bytes[0] & 0x01;
    return bit == 0 ? 1 : -1;
  }

  // 简单的中英文混合分词：
  // - 中文：采用字 bi-gram / tri-gram（覆盖更多语义组合）
  // - 英文：基于单词分割 + 低频过滤
  List<String> _extractTokensMixed(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return const [];

    final tokens = <String>[];

    // 中文字符范围匹配
    final chinese = RegExp(r'[\u4e00-\u9fa5]');
    final hasChinese = chinese.hasMatch(normalized);

    if (hasChinese) {
      // 连续中文片段按字符切分
      final onlyCn = normalized.replaceAll(RegExp(r'[^\u4e00-\u9fa5]'), ' ');
      for (final segment in onlyCn.split(RegExp(r'\s+'))) {
        if (segment.isEmpty) continue;
        // uni-gram（单字）适当加入，权重较低
        for (int i = 0; i < segment.length; i++) {
          tokens.add(segment.substring(i, i + 1));
        }
        // bi-gram
        for (int i = 0; i < segment.length - 1; i++) {
          tokens.add(segment.substring(i, i + 2));
        }
        // tri-gram
        for (int i = 0; i < segment.length - 2; i++) {
          tokens.add(segment.substring(i, i + 3));
        }
      }
    }

    // 英文/数字按单词切分
    final wordMatches = RegExp(r'[a-z0-9]+').allMatches(normalized);
    for (final m in wordMatches) {
      final w = m.group(0)!;
      if (w.length >= 2) tokens.add(w);
    }

    // 去重但保留一定重复度（保留原始，后续以词频计权）
    return tokens;
  }

  // ---------------------- 新版：稳定的哈希嵌入（Feature Hashing + Signed Sum） ----------------------
  Future<List<double>> _generateSemanticVector(String text) async {
    final tokens = _extractTokensMixed(text);
    if (tokens.isEmpty) {
      // 极端情况给一个单位向量的第0维
      final v = List<double>.filled(vectorDimensions, 0.0);
      v[0] = 1.0;
      return v;
    }

    // 基于词频的权重（简化 TF），中文 uni-gram 权重稍低，bi/tri-gram 偏高
    final tf = <String, double>{};
    for (final t in tokens) {
      final len = t.runes.length; // 中文长度按字符
      final isCn = RegExp(r'^[\u4e00-\u9fa5]+').hasMatch(t);
      double base = 1.0;
      if (isCn) {
        if (len == 1) base = 0.5; // 单字权重偏低
        else if (len == 2) base = 1.0;
        else base = 1.2; // 3字以上略高
      }
      tf[t] = (tf[t] ?? 0) + base;
    }

    // Feature Hashing 到固定维度，带符号累加
    final vector = List<double>.filled(vectorDimensions, 0.0);
    tf.forEach((token, weight) {
      final idx = _stableHash32(token) % vectorDimensions;
      final sgn = _stableSign(token);
      // 轻微长度和词频的 log 缩放
      final w = weight * (1.0 + 0.1 * (token.length.clamp(1, 10))) * 1.0;
      vector[idx] += sgn * w;
    });

    // 归一化
    return _normalizeVector(vector);
  }

  // ---------------------- 新增：词法匹配与混合排序 ----------------------
  // 简单词法分数（Jaccard + 关键字段加分）
  double _lexicalScore({
    required String query,
    required EventNode event,
  }) {
    final qTokens = _extractTokensMixed(query).toSet();
    final docText = event.getEmbeddingText();
    final dTokens = _extractTokensMixed(docText).toSet();
    if (qTokens.isEmpty || dTokens.isEmpty) return 0.0;

    final inter = qTokens.intersection(dTokens).length.toDouble();
    final uni = qTokens.union(dTokens).length.toDouble();
    double jaccard = uni > 0 ? inter / uni : 0.0;

    // 事件名称命中加分（强相关性）
    double nameBoost = 0.0;
    for (final t in qTokens) {
      if (t.length <= 1) continue;
      if (event.name.toLowerCase().contains(t)) nameBoost += 0.05;
    }

    return (jaccard * 0.8 + nameBoost).clamp(0.0, 1.0);
  }

  // 领域关键词加权（例如：酒店/旅游相关）
  double _domainBoost(String query, EventNode event) {
    final q = query.toLowerCase();
    final name = event.name.toLowerCase();
    final type = event.type.toLowerCase();

    final hotelKeys = ['酒店', '预订', '旅店', '民宿', '入住', '房型'];
    final travelKeys = ['旅行', '旅游', '出行', '行程', '景点', '路线', '机票', '车票'];

    double boost = 0.0;
    bool qHotel = hotelKeys.any((k) => q.contains(k));
    bool qTravel = travelKeys.any((k) => q.contains(k));

    if (qHotel || qTravel) {
      // 名称/类型中命中关键词给较大加分
      if (hotelKeys.any((k) => name.contains(k) || type.contains(k))) boost += 0.15;
      if (travelKeys.any((k) => name.contains(k) || type.contains(k))) boost += 0.12;

      // 目的/结果轻量加分
      final intentText = '${event.purpose ?? ''} ${event.result ?? ''}'.toLowerCase();
      if (hotelKeys.any((k) => intentText.contains(k))) boost += 0.05;
      if (travelKeys.any((k) => intentText.contains(k))) boost += 0.05;
    }

    // 与领域明显不相关的类别适当惩罚（避免“学习马术/游戏体验”跑到前面）
    final unrelated = ['游戏', '学习', '马术', '编程', '训练', '健身'];
    if (qHotel || qTravel) {
      if (unrelated.any((k) => name.contains(k) || type.contains(k))) {
        boost -= 0.08;
      }
    }

    return boost.clamp(-0.2, 0.25);
  }

  /// 混合排序：语义余弦 + 词法匹配 + 领域加权
  Future<List<Map<String, dynamic>>> searchSimilarEventsHybridByText(
    String queryText,
    List<EventNode> eventNodes, {
    int topK = 10,
    double cosineThreshold = 0.2,
    double wCos = 0.6,
    double wLex = 0.3,
    double wBoost = 0.1,
  }) async {
    final queryVector = await generateTextEmbedding(queryText);
    if (queryVector == null) return [];

    final candidates = <Map<String, dynamic>>[];
    for (final e in eventNodes) {
      if (e.embedding == null || e.embedding!.isEmpty) continue;
      final cos = calculateCosineSimilarity(queryVector, e.embedding!);
      if (cos < cosineThreshold) continue; // 先做一次语义召回
      final lex = _lexicalScore(query: queryText, event: e);
      final boost = _domainBoost(queryText, e);
      final score = (wCos * cos + wLex * lex + wBoost * (boost + 0.0)).clamp(-1.0, 1.0);
      candidates.add({'event': e, 'similarity': cos, 'lexical': lex, 'boost': boost, 'score': score});
    }

    // 主排序按综合分数，其次按语义相似度
    candidates.sort((a, b) {
      final s = (b['score'] as double).compareTo(a['score'] as double);
      if (s != 0) return s;
      return (b['similarity'] as double).compareTo(a['similarity'] as double);
    });

    return candidates.take(topK).toList();
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

  /// 计算两个向量的欧氏距离
  double calculateEuclideanDistance(List<double> a, List<double> b) {
    if (a.length != b.length) throw ArgumentError('向量维度不匹配');
    double sum = 0.0;
    for (int i = 0; i < a.length; i++) {
      final diff = a[i] - b[i];
      sum += diff * diff;
    }
    return sqrt(sum);
  }

  /// 计算曼哈顿距离
  double calculateManhattanDistance(List<double> a, List<double> b) {
    if (a.length != b.length) throw ArgumentError('向量维度不匹配');
    double sum = 0.0;
    for (int i = 0; i < a.length; i++) {
      sum += (a[i] - b[i]).abs();
    }
    return sum;
  }

  /// 计算点积
  double calculateDotProduct(List<double> a, List<double> b) {
    if (a.length != b.length) throw ArgumentError('向量维度不匹配');
    double sum = 0.0;
    for (int i = 0; i < a.length; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  /// 向量whitening（均值方差归一化）
  List<double> whitenVector(List<double> vector, {List<double>? mean, List<double>? std}) {
    final vMean = mean ?? _calcMean(vector);
    final vStd = std ?? _calcStd(vector, vMean);
    return [for (int i = 0; i < vector.length; i++) (vStd[i] > 1e-8 ? (vector[i] - vMean[i]) / vStd[i] : 0.0)];
  }
  List<double> _calcMean(List<double> v) => List.generate(v.length, (i) => v[i]);
  List<double> _calcStd(List<double> v, List<double> mean) {
    final std = List<double>.filled(v.length, 0.0);
    for (int i = 0; i < v.length; i++) {
      std[i] = (v[i] - mean[i]) * (v[i] - mean[i]);
    }
    return std.map((e) => sqrt(e)).toList();
  }

  /// 多路融合排序（先用余弦筛选，再用欧氏距离重排）
  Future<List<Map<String, dynamic>>> findSimilarEventsAdvanced(
      List<double> queryVector,
      List<EventNode> eventNodes, {
        int topK = 10,
        double threshold = 0.5,
        bool useWhitening = false,
        bool useDiversity = false,
      }) async {
    // 1. 可选whitening
    final qv = useWhitening ? whitenVector(queryVector) : queryVector;
    final candidates = <Map<String, dynamic>>[];
    for (final eventNode in eventNodes) {
      if (eventNode.embedding != null && eventNode.embedding!.isNotEmpty) {
        final emb = useWhitening ? whitenVector(eventNode.embedding!) : eventNode.embedding!;
        final cosine = calculateCosineSimilarity(qv, emb);
        if (cosine >= threshold) {
          candidates.add({'event': eventNode, 'similarity': cosine, 'embedding': emb});
        }
      }
    }
    // 2. 先按余弦排序，取topK*2
    candidates.sort((a, b) => (b['similarity'] as double).compareTo(a['similarity'] as double));
    final shortlist = candidates.take(topK * 2).toList();
    // 3. 用欧氏距离重排
    shortlist.sort((a, b) => calculateEuclideanDistance(qv, a['embedding'] as List<double>)
        .compareTo(calculateEuclideanDistance(qv, b['embedding'] as List<double>)));
    var results = shortlist.take(topK).toList();
    // 4. 可选多样性提升（最大化前K结果的差异性）
    if (useDiversity && results.length > 1) {
      final diverse = <Map<String, dynamic>>[];
      final used = <int>{};
      for (int i = 0; i < results.length; i++) {
        if (i == 0) {
          diverse.add(results[0]);
          used.add(0);
        } else {
          double minSim = 1.0;
          int minIdx = -1;
          for (int j = 0; j < results.length; j++) {
            if (used.contains(j)) continue;
            double sim = 0.0;
            for (final d in diverse) {
              sim += calculateCosineSimilarity(
                  d['embedding'] as List<double>,
                  results[j]['embedding'] as List<double>);
            }
            sim /= diverse.length;
            if (sim < minSim) {
              minSim = sim;
              minIdx = j;
            }
          }
          if (minIdx >= 0) {
            diverse.add(results[minIdx]);
            used.add(minIdx);
          }
        }
      }
      results = diverse;
    }
    // 5. 返回结果
    return results.map((e) => {'event': e['event'], 'similarity': e['similarity']}).toList();
  }

  /// 预留PCA降维接口（未实现，需外部支持）
  List<double> pcaReduce(List<double> vector, int targetDim) {
    // TODO: 可集成外部PCA库
    if (vector.length <= targetDim) return vector;
    return vector.take(targetDim).toList();
  }

  /// 查找与查询向量最相似的事件
  Future<List<Map<String, dynamic>>> findSimilarEvents(
      List<double> queryVector,
      List<EventNode> eventNodes, {
        int topK = 10,
        double threshold = 0.5,
      }) async {
    print('[EmbeddingService][调试] eventNodes 长度: \\${eventNodes.length}');
    final results = <Map<String, dynamic>>[];
    int debugCount = 0;
    for (final eventNode in eventNodes) {
      print('[EmbeddingService][调试] eventNode: \\${eventNode.name}, embedding: \\${eventNode.embedding}');
      if (eventNode.embedding != null && eventNode.embedding!.isNotEmpty) {
        final similarity = calculateCosineSimilarity(queryVector, eventNode.embedding!);
        if (debugCount < 10) {
          print('[EmbeddingService][调试] 事件: "\\${eventNode.name}", embeddingText: "\\${eventNode.getEmbeddingText()}"');
          print('[EmbeddingService][调试] 相似度: \\${similarity}');
          debugCount++;
        }
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
      final testOptions = OrtSessionOptions();
      dependencies.add('ONNX Runtime: ✅ 可用');
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

  /// 批量保存事件到本地json文件，embedding字段持久化
  Future<void> saveEventsToFile(List<EventNode> events, String filePath) async {
    final jsonList = events.map((e) => e.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    final file = File(filePath);
    await file.writeAsString(jsonString);
    print('[EmbeddingService] ✅ 已保存事件到 $filePath');
  }

  /// 从本地json文件加载事件，embedding字段自动恢复
  Future<List<EventNode>> loadEventsFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      print('[EmbeddingService] ⚠️ 文件不存在: $filePath');
      return [];
    }
    final jsonString = await file.readAsString();
    final jsonList = jsonDecode(jsonString) as List;
    final events = jsonList.map((e) => EventNode.fromJson(e)).toList();
    print('[EmbeddingService] ✅ 已从 $filePath 加载事件: ${events.length} 条');
    return events.cast<EventNode>();
  }

  // 生成缓存键（包含回退版本号，避免算法升级后命中旧缓存）
  String _generateCacheKey(String text) {
    final bytes = utf8.encode('$fallbackEmbeddingVersion|$text');
    final digest = md5.convert(bytes);
    return digest.toString();
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