/// 认知负载估算器
/// 负责评估用户当前的认知压力和负载水平

import 'dart:async';
import 'dart:math' as math;
import 'package:app/models/human_understanding_models.dart';

class CognitiveLoadEstimator {
  static final CognitiveLoadEstimator _instance = CognitiveLoadEstimator._internal();
  factory CognitiveLoadEstimator() => _instance;
  CognitiveLoadEstimator._internal();

  final List<CognitiveLoadAssessment> _assessmentHistory = [];
  final StreamController<CognitiveLoadAssessment> _loadUpdatesController = StreamController.broadcast();

  Timer? _monitoringTimer;
  bool _initialized = false;

  // 负载权重配置
  static const Map<String, double> _loadWeights = {
    'intent_count': 0.25,      // 意图数量权重
    'topic_count': 0.20,       // 主题数量权重
    'emotional_intensity': 0.20, // 情绪强度权重
    'topic_switch_rate': 0.15,  // 话题切换频率权重
    'complexity_score': 0.10,   // 语言复杂度权重
    'temporal_pressure': 0.10,  // 时间压力权重
  };

  /// 认知负载更新流
  Stream<CognitiveLoadAssessment> get loadUpdates => _loadUpdatesController.stream;

  /// 初始化估算器
  Future<void> initialize() async {
    if (_initialized) return;

    print('[CognitiveLoadEstimator] 🚀 初始化认知负载估算器...');

    // 启动持续监控
    _startContinuousMonitoring();

    _initialized = true;
    print('[CognitiveLoadEstimator] ✅ 认知负载估算器初始化完成');
  }

  /// 评估当前认知负载
  Future<CognitiveLoadAssessment> assessCognitiveLoad({
    required List<Intent> activeIntents,
    required List<ConversationTopic> activeTopics,
    required List<ConversationTopic> backgroundTopics,
    required String currentEmotion,
    required double topicSwitchRate,
    required String lastConversationContent,
    Map<String, dynamic> additionalContext = const {},
  }) async {
    if (!_initialized) await initialize();

    print('[CognitiveLoadEstimator] 🧠 评估认知负载...');

    try {
      // 1. 计算各项负载因子
      final factors = await _calculateLoadFactors(
        activeIntents: activeIntents,
        activeTopics: activeTopics,
        backgroundTopics: backgroundTopics,
        currentEmotion: currentEmotion,
        topicSwitchRate: topicSwitchRate,
        lastConversationContent: lastConversationContent,
        additionalContext: additionalContext,
      );

      // 2. 计算综合负载分数
      final overallScore = _calculateOverallScore(factors);

      // 3. 确定负载级别
      final level = _determineLoadLevel(overallScore);

      // 4. 生成建议
      final recommendation = _generateRecommendation(level, factors);

      // 5. 创建评估结果
      final assessment = CognitiveLoadAssessment(
        level: level,
        score: overallScore,
        factors: factors,
        activeIntentCount: activeIntents.length,
        activeTopicCount: activeTopics.length,
        emotionalIntensity: factors['emotional_intensity'] ?? 0.0,
        topicSwitchRate: topicSwitchRate,
        complexityScore: factors['complexity_score'] ?? 0.0,
        recommendation: recommendation,
      );

      // 6. 存储历史记录
      _assessmentHistory.add(assessment);
      if (_assessmentHistory.length > 100) {
        _assessmentHistory.removeAt(0); // 保持最近100次评估
      }

      _loadUpdatesController.add(assessment);

      print('[CognitiveLoadEstimator] ✅ 认知负载评估完成: ${level.toString().split('.').last} (${overallScore.toStringAsFixed(2)})');

      return assessment;

    } catch (e) {
      print('[CognitiveLoadEstimator] ❌ 评估认知负载失败: $e');

      // 返回默认评估
      return CognitiveLoadAssessment(
        level: CognitiveLoadLevel.moderate,
        score: 0.5,
        factors: {},
        activeIntentCount: activeIntents.length,
        activeTopicCount: activeTopics.length,
        emotionalIntensity: 0.5,
        topicSwitchRate: topicSwitchRate,
        complexityScore: 0.5,
        recommendation: '无法评估当前认知负载',
      );
    }
  }

  /// 计算负载因子
  Future<Map<String, double>> _calculateLoadFactors({
    required List<Intent> activeIntents,
    required List<ConversationTopic> activeTopics,
    required List<ConversationTopic> backgroundTopics,
    required String currentEmotion,
    required double topicSwitchRate,
    required String lastConversationContent,
    Map<String, dynamic> additionalContext = const {},
  }) async {
    final factors = <String, double>{};

    // 1. 意图数量负载 (0-1)
    factors['intent_count'] = _calculateIntentLoad(activeIntents);

    // 2. 主题数量负载 (0-1)
    factors['topic_count'] = _calculateTopicLoad(activeTopics, backgroundTopics);

    // 3. 情绪强度负载 (0-1)
    factors['emotional_intensity'] = _calculateEmotionalLoad(currentEmotion);

    // 4. 话题切换频率负载 (0-1)
    factors['topic_switch_rate'] = _calculateSwitchRateLoad(topicSwitchRate);

    // 5. 语言复杂度负载 (0-1)
    factors['complexity_score'] = await _calculateComplexityLoad(lastConversationContent);

    // 6. 时间压力负载 (0-1)
    factors['temporal_pressure'] = _calculateTemporalPressure(activeIntents, additionalContext);

    return factors;
  }

  /// 计算意图数量负载
  double _calculateIntentLoad(List<Intent> activeIntents) {
    final count = activeIntents.length;

    // 考虑意图状态和紧急性
    double weightedCount = 0.0;
    for (final intent in activeIntents) {
      double weight = 1.0;

      // 执行中的意图权重更高
      if (intent.state == IntentLifecycleState.executing) {
        weight = 1.5;
      } else if (intent.state == IntentLifecycleState.clarifying) {
        weight = 1.2;
      }

      // 紧急意图权重更高
      final urgency = intent.context['urgency']?.toString() ?? 'medium';
      if (urgency == 'high') {
        weight *= 1.3;
      }

      weightedCount += weight;
    }

    // 标准化到0-1范围
    return math.min(weightedCount / 5.0, 1.0); // 5个意图为满负载
  }

  /// 计算主题数量负载
  double _calculateTopicLoad(List<ConversationTopic> activeTopics, List<ConversationTopic> backgroundTopics) {
    // 活跃主题权重1.0，背景主题权重0.3
    final weightedCount = activeTopics.length * 1.0 + backgroundTopics.length * 0.3;

    // 标准化到0-1范围
    return math.min(weightedCount / 8.0, 1.0); // 8个主题为满负载
  }

  /// 计算情绪强度负载
  double _calculateEmotionalLoad(String emotion) {
    // 情绪强度映射
    const emotionIntensity = {
      'excited': 0.9,
      'frustrated': 0.9,
      'angry': 1.0,
      'anxious': 0.8,
      'confused': 0.7,
      'overwhelmed': 1.0,
      'stressed': 0.9,
      'worried': 0.7,
      'positive': 0.3,
      'happy': 0.2,
      'satisfied': 0.2,
      'calm': 0.1,
      'relaxed': 0.1,
      'neutral': 0.3,
      'negative': 0.6,
    };

    return emotionIntensity[emotion.toLowerCase()] ?? 0.5;
  }

  /// 计算话题切换频率负载
  double _calculateSwitchRateLoad(double switchRate) {
    // 频繁的话题切换增加认知负载
    if (switchRate > 0.5) return 1.0;      // 非常频繁
    if (switchRate > 0.3) return 0.8;      // 频繁
    if (switchRate > 0.15) return 0.5;     // 适中
    if (switchRate > 0.05) return 0.3;     // 较低
    return 0.1;                            // 很低
  }

  /// 计算语言复杂度负载
  Future<double> _calculateComplexityLoad(String content) async {
    if (content.isEmpty) return 0.0;

    double complexity = 0.0;

    // 1. 句子长度复杂度
    final sentences = content.split(RegExp(r'[.!?。！？]'));
    final avgSentenceLength = sentences.isEmpty ? 0 :
        sentences.map((s) => s.length).reduce((a, b) => a + b) / sentences.length;
    complexity += math.min(avgSentenceLength / 50.0, 1.0) * 0.3;

    // 2. 词汇复杂度（长词、专业词汇）
    final words = content.split(RegExp(r'\s+'));
    final longWords = words.where((w) => w.length > 6).length;
    complexity += math.min(longWords / words.length, 1.0) * 0.3;

    // 3. 嵌套结构复杂度（括号、从句）
    final nestedStructures = RegExp(r'[()（）]').allMatches(content).length;
    complexity += math.min(nestedStructures / 10.0, 1.0) * 0.2;

    // 4. 多语言混用复杂度
    final hasEnglish = RegExp(r'[a-zA-Z]').hasMatch(content);
    final hasChinese = RegExp(r'[\u4e00-\u9fa5]').hasMatch(content);
    if (hasEnglish && hasChinese) {
      complexity += 0.2;
    }

    return math.min(complexity, 1.0);
  }

  /// 计算时间压力负载
  double _calculateTemporalPressure(List<Intent> activeIntents, Map<String, dynamic> context) {
    double pressure = 0.0;
    final now = DateTime.now();

    // 1. 基于意图的时间压力
    for (final intent in activeIntents) {
      final timeframe = intent.context['timeframe']?.toString() ?? 'medium';
      final urgency = intent.context['urgency']?.toString() ?? 'medium';

      if (timeframe == 'short' && urgency == 'high') {
        pressure += 0.4;
      } else if (timeframe == 'short' || urgency == 'high') {
        pressure += 0.2;
      }
    }

    // 2. 基于对话频率的时间压力
    final conversationRate = context['conversation_rate'] as double? ?? 0.0;
    if (conversationRate > 10) {  // 每分钟超过10次对话
      pressure += 0.3;
    } else if (conversationRate > 5) {
      pressure += 0.15;
    }

    // 3. 基于时间点的压力（工作时间 vs 休息时间）
    final hour = now.hour;
    if (hour >= 9 && hour <= 18) {  // 工作时间
      pressure += 0.1;
    }

    return math.min(pressure, 1.0);
  }

  /// 计算综合负载分数
  double _calculateOverallScore(Map<String, double> factors) {
    double totalScore = 0.0;

    for (final entry in factors.entries) {
      final weight = _loadWeights[entry.key] ?? 0.0;
      totalScore += entry.value * weight;
    }

    return math.min(totalScore, 1.0);
  }

  /// 确定负载级别
  CognitiveLoadLevel _determineLoadLevel(double score) {
    if (score >= 0.8) return CognitiveLoadLevel.overload;
    if (score >= 0.6) return CognitiveLoadLevel.high;
    if (score >= 0.3) return CognitiveLoadLevel.moderate;
    return CognitiveLoadLevel.low;
  }

  /// 生成建议
  String _generateRecommendation(CognitiveLoadLevel level, Map<String, double> factors) {
    final recommendations = <String>[];

    switch (level) {
      case CognitiveLoadLevel.overload:
        recommendations.add('⚠️ 认知负载过重，建议暂停部分任务');
        break;
      case CognitiveLoadLevel.high:
        recommendations.add('🔸 认知负载较高，建议优先处理重要事项');
        break;
      case CognitiveLoadLevel.moderate:
        recommendations.add('✅ 认知负载适中，可以正常进行');
        break;
      case CognitiveLoadLevel.low:
        recommendations.add('😊 认知负载较低，适合学习新知识');
        break;
    }

    // 基于具体因子的建议
    if ((factors['intent_count'] ?? 0) > 0.7) {
      recommendations.add('🎯 活跃意图过多，建议完成或暂停部分意图');
    }

    if ((factors['emotional_intensity'] ?? 0) > 0.7) {
      recommendations.add('💭 情绪强度较高，建议先调节情绪状态');
    }

    if ((factors['topic_switch_rate'] ?? 0) > 0.7) {
      recommendations.add('🔄 话题切换频繁，建议专注于单一主题');
    }

    if ((factors['complexity_score'] ?? 0) > 0.7) {
      recommendations.add('📝 语言复杂度高，建议简化表达方式');
    }

    if ((factors['temporal_pressure'] ?? 0) > 0.7) {
      recommendations.add('⏰ 时间压力较大，建议合理安排优先级');
    }

    return recommendations.join('\n');
  }

  /// 启动持续监控
  void _startContinuousMonitoring() {
    _monitoringTimer = Timer.periodic(Duration(minutes: 5), (timer) {
      _analyzeTrends();
    });
  }

  /// 分析负载趋势
  void _analyzeTrends() {
    if (_assessmentHistory.length < 3) return;

    final recent = _assessmentHistory.takeLast(3);
    final scores = recent.map((a) => a.score).toList();

    // 检测上升趋势
    bool isIncreasing = true;
    for (int i = 1; i < scores.length; i++) {
      if (scores[i] <= scores[i - 1]) {
        isIncreasing = false;
        break;
      }
    }

    // 检测下降趋势
    bool isDecreasing = true;
    for (int i = 1; i < scores.length; i++) {
      if (scores[i] >= scores[i - 1]) {
        isDecreasing = false;
        break;
      }
    }

    if (isIncreasing && recent.last.score > 0.7) {
      print('[CognitiveLoadEstimator] ⚠️ 检测到认知负载持续上升，当前: ${recent.last.score.toStringAsFixed(2)}');
    } else if (isDecreasing && recent.first.score > 0.6) {
      print('[CognitiveLoadEstimator] 📉 认知负载正在下降，情况好转');
    }
  }

  /// 获取负载历史
  List<CognitiveLoadAssessment> getLoadHistory({int limit = 20}) {
    final sortedHistory = List<CognitiveLoadAssessment>.from(_assessmentHistory);
    sortedHistory.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sortedHistory.take(limit).toList();
  }

  /// 获取当前负载状态
  CognitiveLoadAssessment? getCurrentLoad() {
    return _assessmentHistory.isEmpty ? null : _assessmentHistory.last;
  }

  /// 计算平均负载
  double calculateAverageLoad({Duration? period}) {
    if (_assessmentHistory.isEmpty) return 0.0;

    var relevantAssessments = _assessmentHistory;

    if (period != null) {
      final cutoffTime = DateTime.now().subtract(period);
      relevantAssessments = _assessmentHistory
          .where((assessment) => assessment.timestamp.isAfter(cutoffTime))
          .toList();
    }

    if (relevantAssessments.isEmpty) return 0.0;

    final totalScore = relevantAssessments
        .map((assessment) => assessment.score)
        .reduce((a, b) => a + b);

    return totalScore / relevantAssessments.length;
  }

  /// 检测负载峰值
  List<CognitiveLoadAssessment> detectLoadPeaks({double threshold = 0.8}) {
    return _assessmentHistory
        .where((assessment) => assessment.score >= threshold)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
  }

  /// 分析负载模式
  Map<String, dynamic> analyzeLoadPatterns() {
    if (_assessmentHistory.length < 10) {
      return {'error': '数据不足，无法分析模式'};
    }

    // 按时间段分析
    final hourlyLoads = <int, List<double>>{};
    for (final assessment in _assessmentHistory) {
      final hour = assessment.timestamp.hour;
      hourlyLoads.putIfAbsent(hour, () => []).add(assessment.score);
    }

    final hourlyAverages = <int, double>{};
    for (final entry in hourlyLoads.entries) {
      hourlyAverages[entry.key] = entry.value.reduce((a, b) => a + b) / entry.value.length;
    }

    // 找出负载最高和最低的时间段
    final sortedHours = hourlyAverages.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final levelDistribution = <String, int>{};
    for (final assessment in _assessmentHistory) {
      final level = assessment.level.toString().split('.').last;
      levelDistribution[level] = (levelDistribution[level] ?? 0) + 1;
    }

    return {
      'total_assessments': _assessmentHistory.length,
      'average_load': calculateAverageLoad(),
      'peak_hours': sortedHours.take(3).map((e) => {'hour': e.key, 'load': e.value}).toList(),
      'low_hours': sortedHours.reversed.take(3).map((e) => {'hour': e.key, 'load': e.value}).toList(),
      'level_distribution': levelDistribution,
      'current_trend': _getCurrentTrend(),
      'last_peak': detectLoadPeaks().isNotEmpty ? detectLoadPeaks().first.timestamp.toIso8601String() : null,
    };
  }

  /// 获取当前趋势
  String _getCurrentTrend() {
    if (_assessmentHistory.length < 5) return 'insufficient_data';

    final recent = _assessmentHistory.takeLast(5);
    final scores = recent.map((a) => a.score).toList();

    final firstHalf = scores.take(2).reduce((a, b) => a + b) / 2;
    final secondHalf = scores.skip(3).reduce((a, b) => a + b) / 2;

    final diff = secondHalf - firstHalf;

    if (diff > 0.1) return 'increasing';
    if (diff < -0.1) return 'decreasing';
    return 'stable';
  }

  /// 获取负载统计信息
  Map<String, dynamic> getLoadStatistics() {
    return analyzeLoadPatterns();
  }

  /// 释放资源
  void dispose() {
    _monitoringTimer?.cancel();
    _loadUpdatesController.close();
    _assessmentHistory.clear();
    _initialized = false;
    print('[CognitiveLoadEstimator] 🔌 认知负载估算器已释放');
  }
}

// 扩展方法
extension ListExtension<T> on List<T> {
  List<T> takeLast(int count) {
    if (count >= length) return this;
    return skip(length - count).toList();
  }
}
