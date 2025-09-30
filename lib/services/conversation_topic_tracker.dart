/// 对话主题追踪器
/// 负责识别、跟踪和管理对话中的主题演进

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:app/models/human_understanding_models.dart';
import 'package:app/services/human_understanding_system.dart';
import 'package:app/services/llm.dart';
import 'package:app/services/topic_history_service.dart';

class ConversationTopicTracker {
  static final ConversationTopicTracker _instance = ConversationTopicTracker._internal();
  factory ConversationTopicTracker() => _instance;
  ConversationTopicTracker._internal();

  final Map<String, ConversationTopic> _topics = {};
  final List<String> _conversationHistory = [];
  final StreamController<ConversationTopic> _topicUpdatesController = StreamController.broadcast();
  final TopicHistoryService _historyService = TopicHistoryService();

  Timer? _relevanceDecayTimer;
  bool _initialized = false;

  // 新规则：每分钟衰减5%，并基于阈值决定活跃/背景/删除
  static const double _relevanceDecayRate = 0.95; // 每分钟衰减5%
  static const double _deletionThreshold = 0.3;   // 小于等于即删除
  static const double _activeThreshold = 0.6;     // 大于等于为活跃

  /// 主题更新流
  Stream<ConversationTopic> get topicUpdates => _topicUpdatesController.stream;

  /// 初始化追踪器
  Future<void> initialize() async {
    if (_initialized) return;

    print('[ConversationTopicTracker] 🚀 初始化对话主题追踪器...');

    // 初始化历史服务
    await _historyService.initialize();

    // 启动相关性衰减定时器
    _startRelevanceDecayTimer();

    _initialized = true;
    print('[ConversationTopicTracker] ✅ 对话主题追踪器初始化完成');
  }

  /// 处理新的对话内容
  Future<List<ConversationTopic>> processConversation(SemanticAnalysisInput analysis) async {
    if (!_initialized) await initialize();

    print('[ConversationTopicTracker] 🎯 分析对话主题: "${analysis.content.substring(0, analysis.content.length > 50 ? 50 : analysis.content.length)}..."');

    try {
      // 1. 记录对话历史
      _conversationHistory.add(analysis.content);
      if (_conversationHistory.length > 20) {
        _conversationHistory.removeAt(0);
      }

      // 2. 识别主题
      final detectedTopics = await _detectTopics(analysis);

      // 3. 写入历史
      await _historyService.recordTopicDetection(
        conversationId: 'conversation_${DateTime.now().millisecondsSinceEpoch}',
        content: analysis.content,
        detectedTopics: detectedTopics,
        timestamp: DateTime.now(),
      );

      // 4. 衰减未提及主题
      await _updateTopicRelevance(analysis, detectedTopics);

      // 5. 主题切换检测（无需保存返回值）


      // 6. 返回受影响主题（当前检测到的）
      final affectedTopics = <ConversationTopic>[]..addAll(detectedTopics);

      print('[ConversationTopicTracker] ✅ 主题分析完成，当前活跃主题 ${getActiveTopics().length} 个');
      return affectedTopics;

    } catch (e) {
      print('[ConversationTopicTracker] ❌ 处理对话主题失败: $e');
      return [];
    }
  }

  /// 检测对话中的主题
  Future<List<ConversationTopic>> _detectTopics(SemanticAnalysisInput analysis) async {
    // 获取当前活跃主题和知识图谱信息
    List<String> activeTopics = [];
    String knowledgeGraphInfo = '';
    try {
      activeTopics = HumanUnderstandingSystem().topicTracker.getActiveTopics().map((t) => t.name).toList();
    } catch (e) {}
    try {
      final kgData = HumanUnderstandingSystem().knowledgeGraphManager.getLastResult();
      if (kgData != null && kgData.isNotEmpty) {
        knowledgeGraphInfo = kgData.toString();
      }
    } catch (e) {}

    final topicDetectionPrompt = '''
你是一个对话主题识别专家。请从用户的对话中识别主要的讨论主题。

【当前活跃主题】:
${activeTopics.isNotEmpty ? activeTopics.join(', ') : '无'}
【相关知识图谱信息】:
${knowledgeGraphInfo.isNotEmpty ? knowledgeGraphInfo : '无'}

【主题识别原则】：
1. 识别具体的、有意义的主题，避免过于泛化
2. 一个主题应该是用户会持续关注或讨论的内容
3. 区分主要主题和次要主题
4. 考虑主题的时效性和重要性

【主题分类】：
- work: 工作相关（项目、任务、同事等）
- life: 生活日常（家庭、朋友、日常活动等）
- health: 健康相关（身体、心理、运动等）
- learning: 学习成长（技能、知识、课程等）
- entertainment: 娱乐休闲（电影、游戏、旅行等）
- finance: 财务理财（投资、消费、理财等）
- relationship: 人际关系（友情、恋爱、社交等）
- technology: 科技产品（软件、硬件、数字生活等）
- food: 美食餐饮
- shopping: 购物消费
- other: 其他

输出格式为JSON数组：
[
  {
    "name": "主题名称（具体描述）",
    "category": "主题分类",
    "relevance_score": 0.8,
    "keywords": ["关键词1", "关键词2"],
    "entities": ["相关实体"],
    "context": {
      "importance": "high|medium|low",
      "time_sensitivity": "urgent|normal|low",
      "emotional_tone": "情绪色彩"
    }
  }
]

如果没有明确的主题，返回空数组 []。

当前对话：
"${analysis.content}"

检测到的实体：${analysis.entities}
检测到的情绪：${analysis.emotion}

最近的对话上下文：
${_conversationHistory.take(5).join('\n')}
''';

    try {
      final llm = await LLM.create('gpt-4o-mini', systemPrompt: topicDetectionPrompt);
      final response = await llm.createRequest(content: analysis.content);

      final jsonStart = response.indexOf('[');
      final jsonEnd = response.lastIndexOf(']');
      if (jsonStart == -1 || jsonEnd == -1) return [];

      final jsonStr = response.substring(jsonStart, jsonEnd + 1);
      final List<dynamic> topicsData = jsonDecode(jsonStr);

      final detectedTopics = <ConversationTopic>[];
      for (final topicData in topicsData) {
        if (topicData is Map) {
          final topicName = topicData['name']?.toString() ?? '';
          final category = topicData['category']?.toString() ?? 'other';
          final relevanceScore = (topicData['relevance_score'] as num?)?.toDouble() ?? 0.5;
          final keywords = (topicData['keywords'] as List?)?.map((e) => e.toString()).toList() ?? [];
          final entities = (topicData['entities'] as List?)?.map((e) => e.toString()).toList() ?? [];
          final context = (topicData['context'] as Map?) ?? {};

          if (topicName.isNotEmpty) {
            final existingTopic = _findSimilarTopic(topicName, category);
            if (existingTopic != null) {
              existingTopic.updateRelevance(relevanceScore, '对话中重新提及');
              existingTopic.keywords = [...existingTopic.keywords, ...keywords].toSet().toList();
              existingTopic.entities = [...existingTopic.entities, ...entities].toSet().toList();
              existingTopic.context.addAll(Map<String, dynamic>.from(context));
              // 根据分数更新状态
              existingTopic.state = relevanceScore >= _activeThreshold ? TopicState.active : TopicState.background;
              detectedTopics.add(existingTopic);
              _topicUpdatesController.add(existingTopic);
            } else {
              final newTopic = ConversationTopic(
                name: topicName,
                category: category,
                relevanceScore: relevanceScore,
                keywords: keywords,
                entities: entities,
                context: Map<String, dynamic>.from(context),
              );
              // 新建时按阈值设置状态
              newTopic.state = relevanceScore >= _activeThreshold ? TopicState.active : TopicState.background;

              _topics[newTopic.id] = newTopic;
              detectedTopics.add(newTopic);
              _topicUpdatesController.add(newTopic);
              print('[ConversationTopicTracker] 🆕 新主题: $topicName ($category)');
            }
          }
        }
      }

      return detectedTopics;

    } catch (e) {
      print('[ConversationTopicTracker] ❌ 检测主题失败: $e');
      return [];
    }
  }

  /// 查找相似主题
  ConversationTopic? _findSimilarTopic(String name, String category) {
    return _topics.values.where((topic) {
      final nameSimilarity = _calculateSimilarity(topic.name, name);
      final categorySame = topic.category == category;
      return nameSimilarity > 0.7 && categorySame;
    }).firstOrNull;
  }

  double _calculateSimilarity(String str1, String str2) {
    if (str1 == str2) return 1.0;
    if (str1.isEmpty || str2.isEmpty) return 0.0;
    final words1 = str1.toLowerCase().split(' ').toSet();
    final words2 = str2.toLowerCase().split(' ').toSet();
    final intersection = words1.intersection(words2);
    final union = words1.union(words2);
    return intersection.length / union.length;
  }

  /// 更新未提及主题的相关性（按分钟衰减，<=0.3删除）
  Future<void> _updateTopicRelevance(SemanticAnalysisInput analysis, List<ConversationTopic> detectedTopics) async {
    final detectedTopicIds = detectedTopics.map((t) => t.id).toSet();

    final toRemove = <String>[];
    for (final topic in _topics.values) {
      if (!detectedTopicIds.contains(topic.id)) {
        final minutesSince = DateTime.now().difference(topic.lastMentioned).inMinutes;
        if (minutesSince > 0) {
          final decayFactor = math.pow(_relevanceDecayRate, minutesSince.toDouble());
          final newRelevance = (topic.relevanceScore * decayFactor).clamp(0.0, 1.0);

          if (newRelevance <= _deletionThreshold) {
            toRemove.add(topic.id);
            continue;
          }

          if ((newRelevance - topic.relevanceScore).abs() > 0.0001) {
            topic.updateRelevance(newRelevance, '时间衰减');
            topic.state = newRelevance >= _activeThreshold ? TopicState.active : TopicState.background;
            _topicUpdatesController.add(topic);
          }
        }
      }
    }

    for (final id in toRemove) {
      final removed = _topics.remove(id);
      if (removed != null) {
        print('[ConversationTopicTracker] 🗑️ 已删除低权重主题: ${removed.name} (${removed.relevanceScore.toStringAsFixed(2)})');
      }
    }
  }

  /// 检测主题切换
  Future<List<String>> _detectTopicSwitches(SemanticAnalysisInput analysis) async {
    if (_conversationHistory.length < 2) return [];

    final switchDetectionPrompt = '''
你是一个对话主题切换检测专家。请分析用户的对话，判断是否发生了主题切换。

【切换类型】：
- abrupt_switch: 突然切换到完全不同的主题
- gradual_transition: 逐渐过渡到相关主题
- return_to_previous: 回到之前讨论过的主题
- topic_expansion: 在当前主题基础上扩展
- no_switch: 没有明显的主题切换

输出格式为JSON：
{
  "switch_detected": true/false,
  "switch_type": "切换类型",
  "from_topic": "之前的主题（如果有）",
  "to_topic": "新的主题",
  "confidence": 0.8,
  "reason": "切换原因描述"
}

当前对话：
"${analysis.content}"

最近的对话上下文：
${_conversationHistory.takeLast(5).join('\n')}

当前活跃主题：
${getActiveTopics().map((t) => '${t.name} (${t.relevanceScore.toStringAsFixed(2)})').join(', ')}
''';

    try {
      final llm = await LLM.create('gpt-4o-mini', systemPrompt: switchDetectionPrompt);
      final response = await llm.createRequest(content: analysis.content);

      final jsonStart = response.indexOf('{');
      final jsonEnd = response.lastIndexOf('}');
      if (jsonStart == -1 || jsonEnd == -1) return [];

      final jsonStr = response.substring(jsonStart, jsonEnd + 1);
      final Map<String, dynamic> switchData = jsonDecode(jsonStr);

      final switchDetected = switchData['switch_detected'] as bool? ?? false;
      if (switchDetected) {
        final switchType = switchData['switch_type']?.toString() ?? 'unknown';
        final fromTopic = switchData['from_topic']?.toString();
        final toTopic = switchData['to_topic']?.toString();
        final reason = switchData['reason']?.toString() ?? '主题切换';

        print('[ConversationTopicTracker] 🔄 检测到主题切换: $switchType ($fromTopic -> $toTopic), 原因: $reason');
        return [switchType];
      }

      return [];

    } catch (e) {
      print('[ConversationTopicTracker] ❌ 检测主题切换失败: $e');
      return [];
    }
  }

  /// 启动相关性衰减定时器（每分钟）
  void _startRelevanceDecayTimer() {
    _relevanceDecayTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _performRelevanceDecay();
    });
  }

  /// 执行相关性衰减（按分钟），并删除<=0.3的主题
  void _performRelevanceDecay() {
    final now = DateTime.now();
    final topicsToUpdate = <ConversationTopic>[];
    final toRemove = <String>[];

    for (final topic in _topics.values) {
      final minutesSince = now.difference(topic.lastMentioned).inMinutes;
      if (minutesSince > 0) {
        final decayFactor = math.pow(_relevanceDecayRate, minutesSince.toDouble());
        final newRelevance = (topic.relevanceScore * decayFactor).clamp(0.0, 1.0);

        if (newRelevance <= _deletionThreshold) {
          toRemove.add(topic.id);
          continue;
        }

        if ((topic.relevanceScore - newRelevance).abs() > 0.01) {
          topic.updateRelevance(newRelevance, '定期衰减');
          topic.state = newRelevance >= _activeThreshold ? TopicState.active : TopicState.background;
          topicsToUpdate.add(topic);
        }
      }
    }

    for (final id in toRemove) {
      final removed = _topics.remove(id);
      if (removed != null) {
        print('[ConversationTopicTracker] 🗑️ 定期衰减删除主题: ${removed.name} (${removed.relevanceScore.toStringAsFixed(2)})');
      }
    }

    for (final topic in topicsToUpdate) {
      _topicUpdatesController.add(topic);
    }

    if (topicsToUpdate.isNotEmpty || toRemove.isNotEmpty) {
      print('[ConversationTopicTracker] 🔄 衰减更新: ${topicsToUpdate.length} 个主题更新, ${toRemove.length} 个主题删除');
    }
  }

  /// 获取活跃主题（>=0.6 且状态为active）
  List<ConversationTopic> getActiveTopics() {
    return _topics.values
        .where((topic) => topic.relevanceScore >= _activeThreshold && topic.state == TopicState.active)
        .toList()
      ..sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
  }

  /// 获取背景主题（0.3 - 0.6 之间）
  List<ConversationTopic> getBackgroundTopics() {
    return _topics.values
        .where((topic) => topic.relevanceScore > _deletionThreshold && topic.relevanceScore < _activeThreshold)
        .toList()
      ..sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
  }

  /// 获取所有主题
  List<ConversationTopic> getAllTopics() {
    return _topics.values.toList()..sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
  }

  /// 按类别获取主题
  List<ConversationTopic> getTopicsByCategory(String category) {
    return _topics.values
        .where((topic) => topic.category == category)
        .toList()
      ..sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
  }

  /// 搜索主题
  List<ConversationTopic> searchTopics(String query) {
    final q = query.toLowerCase();
    return _topics.values
        .where((topic) => topic.name.toLowerCase().contains(q) || topic.keywords.any((k) => k.toLowerCase().contains(q)))
        .toList()
      ..sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
  }

  /// 主题切换频率估算
  double calculateTopicSwitchRate() {
    final activeTopics = getActiveTopics();
    final conversationLength = _conversationHistory.length;
    if (conversationLength == 0) return 0.0;
    return activeTopics.length / conversationLength.toDouble();
  }

  /// 主题统计
  Map<String, dynamic> getTopicStatistics() {
    final categoryDistribution = <String, int>{};
    final stateDistribution = <String, int>{};

    for (final topic in _topics.values) {
      categoryDistribution[topic.category] = (categoryDistribution[topic.category] ?? 0) + 1;
      final state = topic.state.toString().split('.').last;
      stateDistribution[state] = (stateDistribution[state] ?? 0) + 1;
    }

    return {
      'total_topics': _topics.length,
      'active_topics': getActiveTopics().length,
      'background_topics': getBackgroundTopics().length,
      'category_distribution': categoryDistribution,
      'state_distribution': stateDistribution,
      'switch_rate': calculateTopicSwitchRate(),
      'conversation_length': _conversationHistory.length,
      'last_update': DateTime.now().toIso8601String(),
    };
  }

  /// 手动更新主题状态
  bool updateTopicState(String topicId, TopicState newState) {
    final topic = _topics[topicId];
    if (topic == null) return false;
    topic.state = newState;
    _topicUpdatesController.add(topic);
    return true;
  }

  /// 手动设置主题相关性（<=0.3直接删除）
  bool setTopicRelevance(String topicId, double relevance, String reason) {
    final topic = _topics[topicId];
    if (topic == null) return false;

    final newScore = relevance.clamp(0.0, 1.0);
    if (newScore <= _deletionThreshold) {
      final removed = _topics.remove(topicId);
      if (removed != null) {
        print('[ConversationTopicTracker] 🗑️ 手动设置触发删除主题: ${removed.name} (${newScore.toStringAsFixed(2)})');
      }
      return true;
    }

    topic.updateRelevance(newScore, reason);
    topic.state = newScore >= _activeThreshold ? TopicState.active : TopicState.background;
    _topicUpdatesController.add(topic);
    return true;
  }

  /// 释放资源
  void dispose() {
    _relevanceDecayTimer?.cancel();
    _topicUpdatesController.close();
    _topics.clear();
    _conversationHistory.clear();
    _initialized = false;
    print('[ConversationTopicTracker] 🔌 对话主题追踪器已释放');
  }
}

extension ListExtension<T> on List<T> {
  List<T> takeLast(int count) {
    if (count >= length) return this;
    return skip(length - count).toList();
  }

  T? get firstOrNull => isEmpty ? null : first;
}
