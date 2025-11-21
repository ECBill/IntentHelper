/// 对话关注点状态机
/// 统一管理用户在开放式长对话中的关注点追踪、漂移和预测

import 'dart:async';
import 'dart:math' as math;
import 'package:app/models/focus_models.dart';
import 'package:app/models/human_understanding_models.dart';
import 'package:app/services/focus_drift_model.dart';

/// 对话关注点状态机
/// 整合意图管理、主题追踪和因果分析，提供统一的关注点模型
class FocusStateMachine {
  // 关注点列表
  final List<FocusPoint> _activeFocuses = [];
  final List<FocusPoint> _latentFocuses = [];
  final List<FocusPoint> _allFocuses = [];
  
  // 漂移模型
  final FocusDriftModel _driftModel = FocusDriftModel();
  
  // 配置参数
  static const int _maxActiveFocuses = 12;  // 活跃关注点上限
  static const int _minActiveFocuses = 6;   // 活跃关注点下限
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
  
  bool _initialized = false;

  /// 初始化状态机
  Future<void> initialize() async {
    if (_initialized) return;
    
    print('[FocusStateMachine] 🚀 初始化关注点状态机...');
    _initialized = true;
    print('[FocusStateMachine] ✅ 关注点状态机初始化完成');
  }

  /// 摄入新的对话片段
  /// 这是主要的输入接口，接收语义分析结果并更新关注点
  Future<void> ingestUtterance(SemanticAnalysisInput analysis) async {
    print('[FocusStateMachine] 📥 摄入新对话: ${analysis.content.substring(0, math.min(50, analysis.content.length))}...');
    
    // 从语义分析中提取关注点
    final extractedFocuses = _extractFocusesFromAnalysis(analysis);
    
    // 处理每个提取的关注点
    for (final newFocus in extractedFocuses) {
      _processNewFocus(newFocus, analysis);
    }
    
    // 更新所有关注点的分数
    await updateScores();
    
    // 重新分类关注点（活跃/潜在）
    _reclassifyFocuses();
    
    // 更新漂移轨迹
    _driftModel.updateTrajectory(_activeFocuses);
    
    print('[FocusStateMachine] ✅ 处理完成，活跃: ${_activeFocuses.length}, 潜在: ${_latentFocuses.length}');
  }

  /// 从语义分析中提取关注点
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
    // 按显著性分数排序
    _allFocuses.sort((a, b) => b.salienceScore.compareTo(a.salienceScore));
    
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
    }
    
    // 修剪过旧的关注点
    _pruneOldFocuses();
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
