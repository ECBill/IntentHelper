/// 关注点漂移模型
/// 建模用户关注点在对话中的转移轨迹，预测新兴关注点

import 'dart:math' as math;
import 'package:app/models/focus_models.dart';

/// 关注点漂移模型
/// 跟踪关注点之间的转移模式，预测用户可能即将关注的内容
class FocusDriftModel {
  // 转移矩阵：从一个关注点到另一个关注点的历史转移概率
  final Map<String, Map<String, double>> _transitionMatrix = {};
  
  // 转移历史记录
  final List<FocusTransition> _transitionHistory = [];
  
  // 动量向量：记录最近的转移趋势
  final List<String> _recentFocusSequence = [];
  
  // 最大历史记录数
  static const int _maxHistorySize = 200;
  static const int _maxSequenceSize = 20;
  
  /// 记录关注点转移
  void recordTransition(FocusTransition transition) {
    _transitionHistory.add(transition);
    
    // 限制历史大小
    if (_transitionHistory.length > _maxHistorySize) {
      _transitionHistory.removeAt(0);
    }
    
    // 更新序列
    _recentFocusSequence.add(transition.toFocusId);
    if (_recentFocusSequence.length > _maxSequenceSize) {
      _recentFocusSequence.removeAt(0);
    }
    
    // 更新转移矩阵
    if (transition.fromFocusId != null) {
      final from = transition.fromFocusId!;
      final to = transition.toFocusId;
      
      _transitionMatrix.putIfAbsent(from, () => {});
      _transitionMatrix[from]![to] = (_transitionMatrix[from]![to] ?? 0.0) + transition.transitionStrength;
    }
  }

  /// 更新轨迹（基于当前活跃关注点）
  void updateTrajectory(List<FocusPoint> activeFocuses) {
    if (activeFocuses.isEmpty) return;
    
    // 按显著性排序
    final sorted = List<FocusPoint>.from(activeFocuses)
      ..sort((a, b) => b.salienceScore.compareTo(a.salienceScore));
    
    // 记录主要关注点的转移
    if (_recentFocusSequence.isNotEmpty && sorted.isNotEmpty) {
      final lastFocus = _recentFocusSequence.last;
      final currentFocus = sorted.first.id;
      
      if (lastFocus != currentFocus) {
        final transition = FocusTransition(
          timestamp: DateTime.now(),
          fromFocusId: lastFocus,
          toFocusId: currentFocus,
          transitionStrength: sorted.first.salienceScore,
          reason: 'trajectory_update',
        );
        recordTransition(transition);
      }
    }
  }

  /// 预测新兴关注点
  /// 基于转移矩阵和最近序列，计算每个潜在关注点的预测分数
  Map<String, double> predictEmerging(List<FocusPoint> allFocuses) {
    final predictions = <String, double>{};
    
    if (_recentFocusSequence.isEmpty) {
      return predictions;
    }
    
    // 基于转移矩阵预测
    final recentFocusIds = _recentFocusSequence.take(5).toList();
    for (final focusId in recentFocusIds) {
      final transitions = _transitionMatrix[focusId];
      if (transitions != null) {
        // 加权：越近期的转移权重越高
        final weight = 1.0 / (1.0 + _recentFocusSequence.length - _recentFocusSequence.lastIndexOf(focusId));
        
        transitions.forEach((toId, strength) {
          predictions[toId] = (predictions[toId] ?? 0.0) + strength * weight;
        });
      }
    }
    
    // 归一化预测分数
    if (predictions.isNotEmpty) {
      final maxScore = predictions.values.reduce(math.max);
      if (maxScore > 0) {
        predictions.updateAll((key, value) => value / maxScore);
      }
    }
    
    return predictions;
  }

  /// 计算关注点的漂移动量
  /// 基于最近提及频率和转移模式
  double calculateDriftMomentum(FocusPoint focus) {
    // 最近提及次数（过去5分钟）
    final recentCutoff = DateTime.now().subtract(Duration(minutes: 5));
    final recentMentions = focus.mentionTimestamps
        .where((t) => t.isAfter(recentCutoff))
        .length;
    
    // 提及频率分数 (0-1)
    final mentionScore = math.min(1.0, recentMentions / 5.0);
    
    // 转移入度（有多少其他关注点转向它）
    int inDegree = 0;
    _transitionMatrix.forEach((from, transitions) {
      if (transitions.containsKey(focus.id)) {
        inDegree++;
      }
    });
    
    // 转移入度分数 (0-1)
    final inDegreeScore = math.min(1.0, inDegree / 3.0);
    
    // 序列位置分数（在最近序列中的位置）
    double sequenceScore = 0.0;
    if (_recentFocusSequence.contains(focus.id)) {
      final lastIndex = _recentFocusSequence.lastIndexOf(focus.id);
      sequenceScore = lastIndex / _recentFocusSequence.length;
    }
    
    // 综合动量分数
    return 0.4 * mentionScore + 0.3 * inDegreeScore + 0.3 * sequenceScore;
  }

  /// 获取转移统计信息
  Map<String, dynamic> getTransitionStats() {
    return {
      'total_transitions': _transitionHistory.length,
      'unique_focuses': _transitionMatrix.keys.length,
      'recent_sequence_length': _recentFocusSequence.length,
      'avg_transition_strength': _transitionHistory.isNotEmpty
          ? _transitionHistory.map((t) => t.transitionStrength).reduce((a, b) => a + b) / _transitionHistory.length
          : 0.0,
    };
  }

  /// 清空历史（用于重置）
  void clear() {
    _transitionMatrix.clear();
    _transitionHistory.clear();
    _recentFocusSequence.clear();
  }

  /// 获取最近的转移序列
  List<String> getRecentSequence() => List.from(_recentFocusSequence);
  
  /// 获取转移历史
  List<FocusTransition> getTransitionHistory({int limit = 50}) {
    return _transitionHistory.reversed.take(limit).toList();
  }
}
