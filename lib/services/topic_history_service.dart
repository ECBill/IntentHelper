/// 主题历史记录服务
/// 专门用于存储和查询FoA识别的历史数据

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:app/models/log_evaluation_models.dart';
import 'package:app/models/topic_history_models.dart';

class TopicHistoryService {
  static final TopicHistoryService _instance = TopicHistoryService._internal();
  factory TopicHistoryService() => _instance;
  TopicHistoryService._internal();

  static const String _historyFileName = 'topic_history.json';
  static const Duration _windowSize = Duration(minutes: 2);
  final Map<DateTime, List<TopicSnapshot>> _windowedHistory = {};

  /// 记录主题识别结果
  Future<void> recordTopicDetection({
    required String conversationId,
    required String content,
    required List<dynamic> detectedTopics,
    required DateTime timestamp,
  }) async {
    // group snapshots into fixed time windows
    final windowMs = _windowSize.inMilliseconds;
    final startMs = timestamp.millisecondsSinceEpoch ~/ windowMs * windowMs;
    final windowStart = DateTime.fromMillisecondsSinceEpoch(startMs);
    final snapshots = detectedTopics.map((t) => TopicSnapshot.fromTopic(t)).toList();
    final existing = _windowedHistory[windowStart] ?? [];
    _windowedHistory[windowStart] = [...existing, ...snapshots];

    await _saveHistory();
  }

  /// 获取按窗口分组的主题快照历史
  List<TopicHistoryWindowEntry> getTopicHistoryWindows({DateTimeRange? dateRange}) {
    final entries = _windowedHistory.entries
        .where((e) {
          final t = e.key;
          if (dateRange != null) {
            return !t.isBefore(dateRange.start) && t.isBefore(dateRange.end.add(Duration(days:1)));
          }
          return true;
        })
        .map((e) => TopicHistoryWindowEntry(windowStart: e.key, topics: e.value))
        .toList()
      ..sort((a, b) => b.windowStart.compareTo(a.windowStart));
    return entries;
  }

  /// 初始化服务
  Future<void> initialize() async {
    await _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_historyFileName');

      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> list = jsonDecode(content);
        list.map((e) => TopicHistoryWindowEntry.fromJson(e)).forEach((entry) {
          _windowedHistory[entry.windowStart] = entry.topics;
        });
      }
    } catch (e) {
      print('加载主题历史失败: $e');
      _windowedHistory.clear();
    }
  }

  Future<void> _saveHistory() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_historyFileName');
      final jsonList = _windowedHistory.entries
          .map((e) => TopicHistoryWindowEntry(windowStart: e.key, topics: e.value).toJson())
          .toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      print('保存主题历史失败: $e');
    }
  }

  /// 清理旧窗口数据
  Future<void> cleanOldRecords({int daysToKeep = 30}) async {
    final cutoff = DateTime.now().subtract(Duration(days: daysToKeep));
    _windowedHistory.removeWhere((k, _) => k.isBefore(cutoff));
    await _saveHistory();
  }

  /// 获取统计信息（按窗口分组）
  Map<String, dynamic> getStatistics({DateTimeRange? dateRange}) {
    final entries = getTopicHistoryWindows(dateRange: dateRange);

    final topicCounts = <String, int>{};
    final categoryCounts = <String, int>{};

    for (final entry in entries) {
      for (final topic in entry.topics) {
        topicCounts[topic.name] = (topicCounts[topic.name] ?? 0) + 1;
        categoryCounts[topic.category] = (categoryCounts[topic.category] ?? 0) + 1;
      }
    }

    return {
      'totalEntries': entries.length,
      'topTopics': topicCounts.entries
          .map((e) => {'name': e.key, 'count': e.value})
          .toList()
        ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int)),
      'categoryDistribution': categoryCounts,
      'dateRange': dateRange != null ? {
        'start': dateRange.start.toIso8601String(),
        'end': dateRange.end.toIso8601String(),
      } : null,
    };
  }
}
