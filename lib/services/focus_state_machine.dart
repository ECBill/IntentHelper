/// 对话关注点状态机
/// 统一管理用户在开放式长对话中的关注点追踪、漂移和预测

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:app/models/focus_models.dart';
import 'package:app/models/human_understanding_models.dart';
import 'package:app/services/focus_drift_model.dart';
import 'package:app/services/llm.dart';

/// 对话关注点状态机
/// 整合意图管理、主题追踪和因果分析，提供统一的关注点模型
class FocusStateMachine {
  // 关注点列表
  final List<FocusPoint> _activeFocuses = [];
  final List<FocusPoint> _latentFocuses = [];
  final List<FocusPoint> _allFocuses = [];
  
  // 漂移模型
  final FocusDriftModel _driftModel = FocusDriftModel();
  
  // 对话历史缓冲（用于提供上下文）
  final List<SemanticAnalysisInput> _conversationHistory = [];
  static const int _maxHistorySize = 10;
  
  // 配置参数
  static const int _maxActiveFocuses = 12;  // 活跃关注点上限
  // 活跃关注点下限：设为3个的原因：
  // 1. 确保UI始终有足够内容展示，避免空状态
  // 2. 3个关注点足以让用户了解当前对话重点
  // 3. 比之前的6个更宽松，减少因评分严格导致的空列表问题
  // 4. 结合回退机制和强制提升逻辑，可以有效防止完全空状态
  static const int _minActiveFocuses = 3;
  static const int _maxLatentFocuses = 8;   // 潜在关注点上限
  
  // 评分权重配置
  static const double _weightRecency = 0.25;
  static const double _weightRepetition = 0.20;
  static const double _weightEmotion = 0.15;
  static const double _weightCausal = 0.20;
  static const double _weightDrift = 0.20;
  
  // 时间衰减参数
  static const double _recencyTau = 300.0; // 5分钟衰减参数
  static const double _recencyBeta = 0.7;  // 慢速衰减
  
  // 相似度阈值（用于合并）
  static const double _similarityThreshold = 0.7;
  
  // LLM提取控制（用于测试环境）
  bool _useLLMExtraction = true;
  
  bool _initialized = false;

  /// 初始化状态机
  Future<void> initialize({bool useLLMExtraction = true}) async {
    if (_initialized) return;
    
    _useLLMExtraction = useLLMExtraction;
    print('[FocusStateMachine] 🚀 初始化关注点状态机 (LLM提取: $_useLLMExtraction)...');
    _initialized = true;
    print('[FocusStateMachine] ✅ 关注点状态机初始化完成');
  }

  /// 摄入新的对话片段
  /// 这是主要的输入接口，接收语义分析结果并更新关注点
  Future<void> ingestUtterance(SemanticAnalysisInput analysis) async {
    print('[FocusStateMachine] 📥 摄入新对话: ${analysis.content.substring(0, math.min(50, analysis.content.length))}...');
    
    // 添加到对话历史
    _conversationHistory.add(analysis);
    if (_conversationHistory.length > _maxHistorySize) {
      _conversationHistory.removeAt(0);
    }
    
    // 使用LLM深度提取关注点（异步）
    List<FocusPoint> extractedFocuses = [];
    if (_useLLMExtraction) {
      try {
        extractedFocuses = await _extractFocusesWithLLM(analysis);
      } catch (e) {
        print('[FocusStateMachine] ⚠️ LLM提取失败，使用基础提取: $e');
        // 降级到基础提取
        extractedFocuses = _extractFocusesFromAnalysis(analysis);
      }
    } else {
      // 直接使用基础提取（测试模式）
      extractedFocuses = _extractFocusesFromAnalysis(analysis);
    }
    
    // 处理每个提取的关注点
    if (extractedFocuses.isNotEmpty) {
      for (final newFocus in extractedFocuses) {
        _processNewFocus(newFocus, analysis);
      }
    } else {
      print('[FocusStateMachine] ℹ️ 本次提取为空，保持现有关注点状态');
    }
    
    // 更新所有关注点的分数
    await updateScores();
    
    // 重新分类关注点（活跃/潜在）
    _reclassifyFocuses();
    
    // 更新漂移轨迹
    _driftModel.updateTrajectory(_activeFocuses);
    
    print('[FocusStateMachine] ✅ 处理完成，活跃: ${_activeFocuses.length}, 潜在: ${_latentFocuses.length}');
    
    // 调试：输出当前活跃关注点列表
    if (_activeFocuses.isNotEmpty) {
      print('[FocusStateMachine] 📋 活跃关注点列表: ${_activeFocuses.map((f) => "${f.canonicalLabel}(${f.salienceScore.toStringAsFixed(2)})").join(", ")}');
    } else {
      print('[FocusStateMachine] ⚠️ 警告：活跃关注点列表为空！总关注点数: ${_allFocuses.length}');
    }
  }

  /// 使用LLM深度提取关注点（更精确、更具体）
  Future<List<FocusPoint>> _extractFocusesWithLLM(SemanticAnalysisInput analysis) async {
    // 构建对话上下文（最近5条消息）
    final contextBuffer = StringBuffer();
    final historyLength = _conversationHistory.length;
    final startIndex = math.max(0, historyLength - 5);
    final recentMessages = _conversationHistory.skip(startIndex);
    
    for (final msg in recentMessages) {
      contextBuffer.writeln(msg.content);
    }
    final contextMessages = contextBuffer.toString();
    
    final focusExtractionPrompt = '''
你是一个对话关注点提取专家。请从用户的对话中提取**具体的、细粒度的**关注点。

【核心原则】：
1. **具体性优先**：提取具体的人名、事件、项目、问题，而非抽象类别
   - ❌ 错误："工作"、"对话"、"casual_chat"
   - ✅ 正确："朋友的恋情进展"、"Flutter项目的性能优化"、"下周的产品发布会"
2. **关系和上下文**：捕捉人物关系、事件细节、时间背景
   - 例如："同事小李建议的新架构方案"、"母亲提到的体检结果"
3. **动态性**：关注点应该反映对话的实时演进
4. **多样性**：同时捕捉事件、实体、主题三种类型
5. **延续性**：结合前文上下文理解当前对话

【最近对话上下文】：
$contextMessages

【当前对话】：
${analysis.content}

【用户情感】：${analysis.emotion}
【提取的实体】：${analysis.entities.join(', ')}
【意图】：${analysis.intent}

【输出格式】（JSON数组）：
[
  {
    "type": "event|topic|entity",
    "canonicalLabel": "简洁但具体的标签（10字以内）",
    "aliases": ["其他可能的叫法"],
    "emotionalScore": 0.5,
    "metadata": {
      "source": "llm_extraction",
      "specific_context": "详细上下文（如涉及谁、什么时间、什么地方）",
      "content_snippet": "相关的对话片段",
      "entities": ["相关实体列表"],
      "temporal_info": "时间信息（如有）",
      "relational_info": "关系信息（如：朋友、同事、家人）"
    }
  }
]

【分类指导】：
- **event（事件）**：具体发生的或将要发生的事情
  - 例：朋友的恋情、产品发布、会议、旅行计划
- **topic（主题）**：讨论的话题或领域（需要具体）
  - 例：Flutter性能调优、机器学习入门、职业发展规划
- **entity（实体）**：具体的人、地点、物品、工具
  - 例：朋友张三、北京、iPhone、VS Code

【严格要求】：
- 每个标签必须具体，避免泛泛而谈
- 最多返回5个关注点
- 置信度低的不要强行提取
- 如果当前对话很简短但能从上下文推断关注点，仍应提取
- 如果实在无法提取有意义的关注点，返回空数组 []
''';

    try {
      final llm = await LLM.create('gpt-4o-mini');
      final response = await llm.createRequest(content: focusExtractionPrompt);
      
      // 解析JSON响应
      final jsonResponse = _extractJsonFromResponse(response);
      print("[FocusStateMachine] LLM响应: ${_truncateForLog(jsonResponse, 200)}");
      final focusesJson = jsonDecode(jsonResponse) as List;
      
      final focuses = <FocusPoint>[];
      for (final item in focusesJson) {
        final typeStr = item['type'] as String;
        FocusType type;
        if (typeStr == 'event') {
          type = FocusType.event;
        } else if (typeStr == 'entity') {
          type = FocusType.entity;
        } else {
          type = FocusType.topic;
        }
        
        final focus = FocusPoint(
          type: type,
          canonicalLabel: item['canonicalLabel'] as String,
          aliases: (item['aliases'] as List?)?.map((e) => e.toString()).toSet() ?? {},
          emotionalScore: (item['emotionalScore'] as num?)?.toDouble() ?? 0.5,
          metadata: Map<String, dynamic>.from(item['metadata'] ?? {}),
        );
        
        focuses.add(focus);
      }
      
      print('[FocusStateMachine] ✅ LLM提取了 ${focuses.length} 个关注点: ${focuses.map((f) => f.canonicalLabel).join(', ')}');
      return focuses;
      
    } catch (e) {
      print('[FocusStateMachine] ❌ LLM提取失败: $e');
      rethrow;
    }
  }
  
  /// 截断文本用于日志输出
  String _truncateForLog(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  /// 从LLM响应中提取JSON（处理markdown代码块等格式）
  String _extractJsonFromResponse(String response) {
    // 尝试提取markdown代码块中的JSON
    final jsonBlockPattern = RegExp(r'```json?\s*(\[[\s\S]*?\])\s*```', multiLine: true);
    final match = jsonBlockPattern.firstMatch(response);
    if (match != null) {
      return match.group(1)!;
    }
    
    // 尝试直接查找JSON数组
    final jsonArrayPattern = RegExp(r'\[[\s\S]*\]');
    final arrayMatch = jsonArrayPattern.firstMatch(response);
    if (arrayMatch != null) {
      return arrayMatch.group(0)!;
    }
    
    // 如果都找不到，返回原始响应
    return response.trim();
  }

  /// 从语义分析中提取关注点（基础版，作为降级方案）
  List<FocusPoint> _extractFocusesFromAnalysis(SemanticAnalysisInput analysis) {
    final focuses = <FocusPoint>[];
    
    // 1. 从意图提取关注点（作为事件）
    if (analysis.intent.isNotEmpty && analysis.intent != 'unknown') {
      final intentFocus = FocusPoint(
        type: FocusType.event,
        canonicalLabel: analysis.intent,
        emotionalScore: _parseEmotionScore(analysis.emotion),
        metadata: {
          'source': 'intent',
          'content_snippet': analysis.content.substring(0, math.min(100, analysis.content.length)),
        },
      );
      focuses.add(intentFocus);
    }
    
    // 2. 从实体提取关注点
    for (final entity in analysis.entities) {
      if (entity.trim().isEmpty) continue;
      
      final entityFocus = FocusPoint(
        type: FocusType.entity,
        canonicalLabel: entity,
        emotionalScore: _parseEmotionScore(analysis.emotion),
        metadata: {
          'source': 'entity',
          'content_snippet': analysis.content.substring(0, math.min(100, analysis.content.length)),
        },
      );
      focuses.add(entityFocus);
    }
    
    // 3. 从内容中提取主题关注点（关键词）
    final topicKeywords = _extractTopicKeywords(analysis.content);
    for (final keyword in topicKeywords) {
      final topicFocus = FocusPoint(
        type: FocusType.topic,
        canonicalLabel: keyword,
        emotionalScore: _parseEmotionScore(analysis.emotion),
        metadata: {
          'source': 'topic_extraction',
          'content_snippet': analysis.content.substring(0, math.min(100, analysis.content.length)),
        },
      );
      focuses.add(topicFocus);
    }
    
    return focuses;
  }

  /// 提取主题关键词（简化版）
  List<String> _extractTopicKeywords(String content) {
    final keywords = <String>[];
    
    // 常见主题关键词模式
    final patterns = {
      '工作': ['工作', '项目', '任务', '开发', '设计', '编程', '代码'],
      '学习': ['学习', '研究', '了解', '教程', '课程', '知识'],
      '生活': ['生活', '日常', '家庭', '朋友', '休息', '放松'],
      '健康': ['健康', '运动', '锻炼', '饮食', '睡眠', '身体'],
      '情感': ['感觉', '心情', '情绪', '想法', '感受', '体会'],
      '计划': ['计划', '安排', '准备', '打算', '考虑', '想要'],
      '问题': ['问题', '困难', '挑战', '障碍', '麻烦', '疑问'],
      '目标': ['目标', '理想', '愿望', '期望', '希望', '梦想'],
    };
    
    patterns.forEach((category, words) {
      for (final word in words) {
        if (content.contains(word) && !keywords.contains(category)) {
          keywords.add(category);
          break;
        }
      }
    });
    
    return keywords;
  }

  /// 解析情绪分数
  double _parseEmotionScore(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'positive':
      case 'happy':
      case 'excited':
        return 0.8;
      case 'curious':
      case 'interested':
        return 0.6;
      case 'neutral':
        return 0.5;
      case 'frustrated':
      case 'confused':
        return 0.4;
      case 'negative':
      case 'sad':
      case 'angry':
        return 0.3;
      default:
        return 0.5;
    }
  }

  /// 处理新关注点
  void _processNewFocus(FocusPoint newFocus, SemanticAnalysisInput analysis) {
    // 检查是否与现有关注点相似（合并逻辑）
    final existingFocus = _findSimilarFocus(newFocus);
    
    if (existingFocus != null) {
      // 合并到现有关注点
      existingFocus.recordMention(timestamp: analysis.timestamp);
      existingFocus.emotionalScore = (existingFocus.emotionalScore * 0.7 + newFocus.emotionalScore * 0.3);
      existingFocus.metadata.addAll(newFocus.metadata);
      print('[FocusStateMachine] 🔄 合并关注点: ${existingFocus.canonicalLabel}');
    } else {
      // 添加新关注点
      _allFocuses.add(newFocus);
      print('[FocusStateMachine] ➕ 新关注点: ${newFocus.canonicalLabel} (${newFocus.type})');
    }
  }

  /// 查找相似关注点
  FocusPoint? _findSimilarFocus(FocusPoint newFocus) {
    for (final existing in _allFocuses) {
      // 必须类型相同
      if (existing.type != newFocus.type) continue;
      
      // 精确匹配
      if (existing.canonicalLabel == newFocus.canonicalLabel) {
        return existing;
      }
      
      // 别名匹配
      if (existing.aliases.contains(newFocus.canonicalLabel)) {
        return existing;
      }
      
      // 模糊匹配（简化版，基于包含关系）
      final similarity = _computeSimilarity(existing.canonicalLabel, newFocus.canonicalLabel);
      if (similarity >= _similarityThreshold) {
        return existing;
      }
    }
    
    return null;
  }

  /// 计算两个标签的相似度
  double _computeSimilarity(String label1, String label2) {
    // 简化的相似度计算：基于Jaccard相似度
    final set1 = label1.toLowerCase().split('').toSet();
    final set2 = label2.toLowerCase().split('').toSet();
    
    final intersection = set1.intersection(set2).length;
    final union = set1.union(set2).length;
    
    if (union == 0) return 0.0;
    
    return intersection / union;
  }

  /// 更新所有关注点的分数
  Future<void> updateScores() async {
    final now = DateTime.now();
    
    for (final focus in _allFocuses) {
      // 1. 计算最近性分数（基于时间衰减）
      focus.recencyScore = _calculateRecencyScore(focus, now);
      
      // 2. 计算重复强化分数（基于提及次数）
      focus.repetitionScore = _calculateRepetitionScore(focus);
      
      // 3. 计算因果连接度分数
      focus.causalConnectivityScore = _calculateCausalConnectivity(focus);
      
      // 4. 计算漂移预测分数
      focus.driftPredictiveScore = _driftModel.calculateDriftMomentum(focus);
      
      // 5. 计算综合显著性分数
      focus.salienceScore = _calculateSalienceScore(focus);
    }
  }

  /// 计算最近性分数（非线性衰减，慢速尾部）
  double _calculateRecencyScore(FocusPoint focus, DateTime now) {
    final deltaSeconds = now.difference(focus.lastUpdated).inSeconds.toDouble();
    
    // f_recency(Δt) = 1 / (1 + (Δt / τ)^β)
    final score = 1.0 / (1.0 + math.pow(deltaSeconds / _recencyTau, _recencyBeta));
    
    return score;
  }

  /// 计算重复强化分数（对数缩放）
  double _calculateRepetitionScore(FocusPoint focus) {
    // log(1 + mention_count) / log(1 + max_mentions)
    const maxMentions = 20.0;
    final score = math.log(1 + focus.mentionCount) / math.log(1 + maxMentions);
    
    return math.min(1.0, score);
  }

  /// 计算因果连接度分数
  double _calculateCausalConnectivity(FocusPoint focus) {
    // 基于链接的其他关注点数量
    if (focus.linkedFocusIds.isEmpty) return 0.0;
    
    final totalFocuses = math.max(1, _allFocuses.length);
    final normalizedDegree = focus.linkedFocusIds.length / math.sqrt(totalFocuses);
    
    return math.min(1.0, normalizedDegree);
  }

  /// 计算综合显著性分数
  double _calculateSalienceScore(FocusPoint focus) {
    final score = _weightRecency * focus.recencyScore +
        _weightRepetition * focus.repetitionScore +
        _weightEmotion * focus.emotionalScore +
        _weightCausal * focus.causalConnectivityScore +
        _weightDrift * focus.driftPredictiveScore;
    
    return math.max(0.0, math.min(1.0, score));
  }

  /// 重新分类关注点（活跃/潜在）
  void _reclassifyFocuses() {
    print('[FocusStateMachine] 🔄 开始重新分类关注点，当前总数: ${_allFocuses.length}');
    
    // 如果没有任何关注点，尝试从历史对话中补充
    if (_allFocuses.isEmpty && _conversationHistory.isNotEmpty) {
      print('[FocusStateMachine] ⚠️ 关注点列表为空但有对话历史，尝试回退提取');
      _performFallbackExtraction();
    }
    
    // 按显著性分数排序
    _allFocuses.sort((a, b) => b.salienceScore.compareTo(a.salienceScore));
    
    // 调试：输出前几个关注点的分数
    if (_allFocuses.isNotEmpty) {
      print('[FocusStateMachine] 📊 排序后前5个关注点: ${_allFocuses.take(5).map((f) => "${f.canonicalLabel}(${f.salienceScore.toStringAsFixed(3)})").join(", ")}');
    }
    
    // 清空现有分类
    _activeFocuses.clear();
    _latentFocuses.clear();
    
    // 预测新兴关注点
    final predictions = _driftModel.predictEmerging(_allFocuses);
    
    // 应用预测分数到漂移分数
    predictions.forEach((focusId, predictScore) {
      final focus = _allFocuses.firstWhere(
        (f) => f.id == focusId,
        orElse: () => FocusPoint(type: FocusType.topic, canonicalLabel: ''),
      );
      if (focus.canonicalLabel.isNotEmpty) {
        focus.driftPredictiveScore = (focus.driftPredictiveScore * 0.5 + predictScore * 0.5);
      }
    });
    
    // 重新计算显著性（包含更新的漂移分数）
    for (final focus in _allFocuses) {
      focus.salienceScore = _calculateSalienceScore(focus);
    }
    
    // 再次排序
    _allFocuses.sort((a, b) => b.salienceScore.compareTo(a.salienceScore));
    
    // 分配到活跃和潜在列表
    // 活跃：前N个高分关注点
    final activeThreshold = _allFocuses.length > _maxActiveFocuses
        ? _allFocuses[_maxActiveFocuses - 1].salienceScore
        : 0.3;
    
    print('[FocusStateMachine] 📊 活跃阈值: ${activeThreshold.toStringAsFixed(3)}');
    
    for (final focus in _allFocuses) {
      if (_activeFocuses.length < _maxActiveFocuses && focus.salienceScore >= activeThreshold) {
        focus.updateState(FocusState.active);
        _activeFocuses.add(focus);
      } else if (_latentFocuses.length < _maxLatentFocuses && focus.salienceScore >= 0.2) {
        focus.updateState(FocusState.latent);
        _latentFocuses.add(focus);
      } else {
        focus.updateState(FocusState.fading);
      }
    }
    
    // 确保至少有最小数量的活跃关注点
    while (_activeFocuses.length < _minActiveFocuses && _latentFocuses.isNotEmpty) {
      final promoted = _latentFocuses.removeAt(0);
      promoted.updateState(FocusState.active);
      _activeFocuses.add(promoted);
      print('[FocusStateMachine] ⬆️ 提升潜在关注点到活跃: ${promoted.canonicalLabel}');
    }
    
    // 如果还是不够，从所有关注点中按分数提升
    if (_activeFocuses.length < _minActiveFocuses && _allFocuses.length > _activeFocuses.length) {
      // 使用Set提高成员检查性能
      final activeFocusIds = _activeFocuses.map((f) => f.id).toSet();
      final latentFocusIds = _latentFocuses.map((f) => f.id).toSet();
      
      // 获取未分配的关注点并按分数排序
      final unassignedFocuses = _allFocuses
          .where((f) => !activeFocusIds.contains(f.id) && !latentFocusIds.contains(f.id))
          .toList()
        ..sort((a, b) => b.salienceScore.compareTo(a.salienceScore));
      
      // 提升最高分的关注点直到满足最小数量
      final needCount = _minActiveFocuses - _activeFocuses.length;
      for (final focus in unassignedFocuses.take(needCount)) {
        focus.updateState(FocusState.active);
        _activeFocuses.add(focus);
        print('[FocusStateMachine] ⬆️ 强制提升关注点到活跃以满足最小数量: ${focus.canonicalLabel}(${focus.salienceScore.toStringAsFixed(3)})');
      }
    }
    
    // 修剪过旧的关注点
    final beforePruneCount = _allFocuses.length;
    _pruneOldFocuses();
    final afterPruneCount = _allFocuses.length;
    if (beforePruneCount != afterPruneCount) {
      print('[FocusStateMachine] ✂️ 修剪了 ${beforePruneCount - afterPruneCount} 个过旧关注点');
    }
    
    print('[FocusStateMachine] ✅ 重新分类完成: 活跃=${_activeFocuses.length}, 潜在=${_latentFocuses.length}, 总数=${_allFocuses.length}');
  }
  
  /// 回退提取：当LLM返回空但有对话历史时，使用基础方法提取
  void _performFallbackExtraction() {
    if (_conversationHistory.isEmpty) {
      print('[FocusStateMachine] ⚠️ 无法执行回退提取：对话历史为空');
      return;
    }
    
    print('[FocusStateMachine] 🔄 执行回退提取...');
    final recentAnalysis = _conversationHistory.last;
    final fallbackFocuses = _extractFocusesFromAnalysis(recentAnalysis);
    
    for (final focus in fallbackFocuses) {
      _processNewFocus(focus, recentAnalysis);
    }
    
    print('[FocusStateMachine] ✅ 回退提取完成，提取了 ${fallbackFocuses.length} 个关注点');
  }

  /// 修剪过旧的关注点
  void _pruneOldFocuses() {
    final cutoff = DateTime.now().subtract(Duration(hours: 2));
    
    _allFocuses.removeWhere((focus) {
      return focus.lastUpdated.isBefore(cutoff) && 
             focus.state == FocusState.fading &&
             focus.salienceScore < 0.1;
    });
  }

  /// 获取顶部N个关注点
  List<FocusPoint> getTop(int n) {
    final sorted = List<FocusPoint>.from(_activeFocuses)
      ..sort((a, b) => b.salienceScore.compareTo(a.salienceScore));
    return sorted.take(n).toList();
  }

  /// 计算增量更新
  FocusUpdateDelta computeDelta() {
    // 简化版：标记所有活跃关注点为更新
    return FocusUpdateDelta(
      added: [],
      updated: List.from(_activeFocuses),
      removed: [],
      transitions: _driftModel.getTransitionHistory(limit: 10),
    );
  }

  /// 获取活跃关注点
  List<FocusPoint> getActiveFocuses() => List.from(_activeFocuses);
  
  /// 获取潜在关注点
  List<FocusPoint> getLatentFocuses() => List.from(_latentFocuses);
  
  /// 获取所有关注点
  List<FocusPoint> getAllFocuses() => List.from(_allFocuses);
  
  /// 获取漂移模型统计
  Map<String, dynamic> getDriftStats() => _driftModel.getTransitionStats();
  
  /// 获取系统统计
  Map<String, dynamic> getStatistics() {
    return {
      'active_focuses_count': _activeFocuses.length,
      'latent_focuses_count': _latentFocuses.length,
      'total_focuses_count': _allFocuses.length,
      'drift_stats': _driftModel.getTransitionStats(),
      'focus_type_distribution': _getFocusTypeDistribution(),
      'avg_salience_score': _allFocuses.isNotEmpty
          ? _allFocuses.map((f) => f.salienceScore).reduce((a, b) => a + b) / _allFocuses.length
          : 0.0,
    };
  }

  /// 获取关注点类型分布
  Map<String, int> _getFocusTypeDistribution() {
    final dist = <String, int>{
      'event': 0,
      'topic': 0,
      'entity': 0,
    };
    
    for (final focus in _activeFocuses) {
      dist[focus.type.toString().split('.').last] = (dist[focus.type.toString().split('.').last] ?? 0) + 1;
    }
    
    return dist;
  }

  /// 重置状态机
  void reset() {
    _activeFocuses.clear();
    _latentFocuses.clear();
    _allFocuses.clear();
    _conversationHistory.clear();
    _driftModel.clear();
    print('[FocusStateMachine] 🔄 状态机已重置');
  }

  /// 释放资源
  void dispose() {
    reset();
    _initialized = false;
    print('[FocusStateMachine] ♻️ 状态机已释放');
  }
}
