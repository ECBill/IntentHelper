/// 对话主题追踪器
/// 负责识别、跟踪和管理对话中的主题演进

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:app/models/human_understanding_models.dart';
import 'package:app/services/llm.dart';

class ConversationTopicTracker {
  static final ConversationTopicTracker _instance = ConversationTopicTracker._internal();
  factory ConversationTopicTracker() => _instance;
  ConversationTopicTracker._internal();

  final Map<String, ConversationTopic> _topics = {};
  final List<String> _conversationHistory = [];
  final StreamController<ConversationTopic> _topicUpdatesController = StreamController.broadcast();

  Timer? _relevanceDecayTimer;
  bool _initialized = false;

  // 主题相关性衰减参数
  static const double _relevanceDecayRate = 0.95; // 每小时衰减5%
  static const double _minimumRelevance = 0.1;

  /// 主题更新流
  Stream<ConversationTopic> get topicUpdates => _topicUpdatesController.stream;

  /// 初始化追踪器
  Future<void> initialize() async {
    if (_initialized) return;

    print('[ConversationTopicTracker] 🚀 初始化对话主题追踪器...');

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
      // 1. 添加到对话历史
      _conversationHistory.add(analysis.content);
      if (_conversationHistory.length > 20) {
        _conversationHistory.removeAt(0); // 保持最近20条对话
      }

      // 2. 识别当前对话中的主题
      final detectedTopics = await _detectTopics(analysis);

      // 3. 更新现有主题���相关性
      await _updateTopicRelevance(analysis, detectedTopics);

      // 4. 检测主题切换
      final topicSwitches = await _detectTopicSwitches(analysis);

      // 5. 返回受影响的主题
      final affectedTopics = <ConversationTopic>[];
      affectedTopics.addAll(detectedTopics);

      print('[ConversationTopicTracker] ✅ 主题分析完成，当前活跃主题 ${getActiveTopics().length} 个');

      return affectedTopics;

    } catch (e) {
      print('[ConversationTopicTracker] ❌ 处理对话主题失败: $e');
      return [];
    }
  }

  /// 检测对话中的主题
  Future<List<ConversationTopic>> _detectTopics(SemanticAnalysisInput analysis) async {
    final topicDetectionPrompt = '''
你是一个对话主题识别专家。请从用户的对话中识别主要的讨论主题。

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
      if (jsonStart == -1 || jsonEnd == -1) {
        return [];
      }

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
            // 检查是否已存���相似主题
            final existingTopic = _findSimilarTopic(topicName, category);

            if (existingTopic != null) {
              // 更新现有主题
              existingTopic.updateRelevance(relevanceScore, '对话中重新提及');
              existingTopic.keywords = [...existingTopic.keywords, ...keywords].toSet().toList();
              existingTopic.entities = [...existingTopic.entities, ...entities].toSet().toList();
              existingTopic.context.addAll(Map<String, dynamic>.from(context));
              detectedTopics.add(existingTopic);
              _topicUpdatesController.add(existingTopic);
            } else {
              // 创建新主题
              final newTopic = ConversationTopic(
                name: topicName,
                category: category,
                relevanceScore: relevanceScore,
                keywords: keywords,
                entities: entities,
                context: Map<String, dynamic>.from(context),
              );

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

  /// 查���相似主题
  ConversationTopic? _findSimilarTopic(String name, String category) {
    return _topics.values.where((topic) {
      final nameSimilarity = _calculateSimilarity(topic.name, name);
      final categorySame = topic.category == category;
      return nameSimilarity > 0.7 && categorySame;
    }).firstOrNull;
  }

  /// 简单的字符串相似性计算
  double _calculateSimilarity(String str1, String str2) {
    if (str1 == str2) return 1.0;
    if (str1.isEmpty || str2.isEmpty) return 0.0;

    final words1 = str1.toLowerCase().split(' ').toSet();
    final words2 = str2.toLowerCase().split(' ').toSet();

    final intersection = words1.intersection(words2);
    final union = words1.union(words2);

    return intersection.length / union.length;
  }

  /// 更新主题相关性
  Future<void> _updateTopicRelevance(SemanticAnalysisInput analysis, List<ConversationTopic> detectedTopics) async {
    final detectedTopicIds = detectedTopics.map((t) => t.id).toSet();

    // 降低未提及主题的相关性
    for (final topic in _topics.values) {
      if (!detectedTopicIds.contains(topic.id)) {
        final timeSinceLastMention = DateTime.now().difference(topic.lastMentioned).inHours;

        if (timeSinceLastMention > 0) {
          final decayFactor = math.pow(_relevanceDecayRate, timeSinceLastMention.toDouble());
          final newRelevance = math.max(topic.relevanceScore * decayFactor, _minimumRelevance);

          if (newRelevance != topic.relevanceScore) {
            topic.updateRelevance(newRelevance, '时间衰减');

            // 更新主题状态
            if (newRelevance < 0.3 && topic.state == TopicState.active) {
              topic.state = TopicState.background;
            } else if (newRelevance < 0.1 && topic.state == TopicState.background) {
              topic.state = TopicState.dormant;
            }

            _topicUpdatesController.add(topic);
          }
        }
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

        print('[ConversationTopicTracker] 🔄 检测到主题切换: $switchType ($fromTopic -> $toTopic)');

        return [switchType];
      }

      return [];

    } catch (e) {
      print('[ConversationTopicTracker] ❌ 检测主题切换失败: $e');
      return [];
    }
  }

  /// 启动相关性衰减定时器
  void _startRelevanceDecayTimer() {
    _relevanceDecayTimer = Timer.periodic(Duration(hours: 1), (timer) {
      _performRelevanceDecay();
    });
  }

  /// 执行相关性衰减
  void _performRelevanceDecay() {
    final now = DateTime.now();
    final topicsToUpdate = <ConversationTopic>[];

    for (final topic in _topics.values) {
      final hoursSinceLastMention = now.difference(topic.lastMentioned).inHours;

      if (hoursSinceLastMention > 0) {
        final decayFactor = math.pow(_relevanceDecayRate, hoursSinceLastMention.toDouble());
        final newRelevance = math.max(topic.relevanceScore * decayFactor, _minimumRelevance);

        if ((topic.relevanceScore - newRelevance).abs() > 0.01) {
          topic.updateRelevance(newRelevance, '定期衰减');
          topicsToUpdate.add(topic);

          // 更新状态
          if (newRelevance < 0.3 && topic.state == TopicState.active) {
            topic.state = TopicState.background;
          } else if (newRelevance < 0.1 && topic.state == TopicState.background) {
            topic.state = TopicState.dormant;
          }
        }
      }
    }

    // 通知更新
    for (final topic in topicsToUpdate) {
      _topicUpdatesController.add(topic);
    }

    if (topicsToUpdate.isNotEmpty) {
      print('[ConversationTopicTracker] 🔄 相关性衰减更新了 ${topicsToUpdate.length} 个主题');
    }
  }

  /// 获取活跃主题（相关性 > 0.3）
  List<ConversationTopic> getActiveTopics() {
    return _topics.values
        .where((topic) => topic.relevanceScore > 0.3 && topic.state == TopicState.active)
        .toList()
      ..sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
  }

  /// 获取背景主题（相关性 0.1-0.3）
  List<ConversationTopic> getBackgroundTopics() {
    return _topics.values
        .where((topic) => topic.relevanceScore >= 0.1 && topic.relevanceScore <= 0.3)
        .toList()
      ..sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
  }

  /// 获取所有主题
  List<ConversationTopic> getAllTopics() {
    return _topics.values.toList()
      ..sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
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
    final queryLower = query.toLowerCase();
    return _topics.values
        .where((topic) =>
            topic.name.toLowerCase().contains(queryLower) ||
            topic.keywords.any((keyword) => keyword.toLowerCase().contains(queryLower)))
        .toList()
      ..sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
  }

  /// 计算主题切换频率
  double calculateTopicSwitchRate() {
    // 基于最近的对话历史计算切换频率
    // 这里简化为基于活跃主题数量的估算
    final activeTopics = getActiveTopics();
    final conversationLength = _conversationHistory.length;

    if (conversationLength == 0) return 0.0;

    return activeTopics.length / conversationLength.toDouble();
  }

  /// 获取主题统计信息
  Map<String, dynamic> getTopicStatistics() {
    final categoryDistribution = <String, int>{};
    final stateDistribution = <String, int>{};

    for (final topic in _topics.values) {
      final category = topic.category;
      final state = topic.state.toString().split('.').last;

      categoryDistribution[category] = (categoryDistribution[category] ?? 0) + 1;
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

  /// 手动设置主题相关性
  bool setTopicRelevance(String topicId, double relevance, String reason) {
    final topic = _topics[topicId];
    if (topic == null) return false;

    topic.updateRelevance(relevance, reason);
    _topicUpdatesController.add(topic);
    return true;
  }

  /// 添加主题（新增方法）
  Future<void> addTopic(String topicName, {double importance = 0.5}) async {
    if (!_initialized) await initialize();

    try {
      // 检查是否已存在
      if (_topics.containsKey(topicName)) {
        final existingTopic = _topics[topicName]!;
        existingTopic.updateRelevance(importance, '手动添加');
        _topicUpdatesController.add(existingTopic);
        print('[ConversationTopicTracker] 🔄 更新已存在主题: $topicName');
        return;
      }

      // 创建新主题
      final topic = ConversationTopic(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: topicName,
        category: 'general',
        keywords: [topicName],
        relevanceScore: importance,
        confidence: 0.8,
        lastMentioned: DateTime.now(),
        firstMentioned: DateTime.now(),
        mentionCount: 1,
        state: TopicState.active,
        context: {'source': 'manual_add'},
      );

      _topics[topicName] = topic;
      _topicUpdatesController.add(topic);
      print('[ConversationTopicTracker] ➕ 添加新主题: $topicName');
    } catch (e) {
      print('[ConversationTopicTracker] ❌ 添加主题失败: $e');
    }
  }

  /// 清除所有主题（新增方法）
  Future<void> clearAllTopics() async {
    try {
      _topics.clear();
      _conversationHistory.clear();
      print('[ConversationTopicTracker] 🧹 已清除所有主题');
    } catch (e) {
      print('[ConversationTopicTracker] ❌ 清除主题失败: $e');
    }
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

// 扩展方法
extension ListExtension<T> on List<T> {
  List<T> takeLast(int count) {
    if (count >= length) return this;
    return skip(length - count).toList();
  }

  T? get firstOrNull {
    return isEmpty ? null : first;
  }
}
