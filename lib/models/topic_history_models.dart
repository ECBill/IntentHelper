// filepath: lib/models/topic_history_models.dart
import 'package:app/models/log_evaluation_models.dart';

/// 窗口化的FoA主题历史记录条目
class TopicHistoryWindowEntry {
  /// 窗口起始时间戳
  final DateTime windowStart;
  /// 当窗口中检测到的主题快照列表
  final List<TopicSnapshot> topics;

  TopicHistoryWindowEntry({
    required this.windowStart,
    required this.topics,
  });

  factory TopicHistoryWindowEntry.fromJson(Map<String, dynamic> json) {
    return TopicHistoryWindowEntry(
      windowStart: DateTime.parse(json['windowStart'] as String),
      topics: (json['topics'] as List<dynamic>)
          .map((e) => TopicSnapshot.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'windowStart': windowStart.toIso8601String(),
      'topics': topics.map((t) => t.toJson()).toList(),
    };
  }
}
