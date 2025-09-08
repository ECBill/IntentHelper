/// 主题历史记录服务
/// 专门用于存储和查询FoA识别的历史数据

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:app/models/log_evaluation_models.dart';

class TopicHistoryService {
  static final TopicHistoryService _instance = TopicHistoryService._internal();
  factory TopicHistoryService() => _instance;
  TopicHistoryService._internal();

  static const String _historyFileName = 'topic_history.json';
  List<TopicHistoryEntry> _history = [];

  /// 记录主题识别结果
  Future<void> recordTopicDetection({
    required String conversationId,
    required String content,
    required List<dynamic> detectedTopics,
    required DateTime timestamp,
  }) async {
    final entry = TopicHistoryEntry(
      id: '${conversationId}_${timestamp.millisecondsSinceEpoch}',
      conversationId: conversationId,
      content: content,
      detectedTopics: detectedTopics.map((t) => TopicSnapshot.fromTopic(t)).toList(),
      timestamp: timestamp,
    );

    _history.add(entry);

    // 保持最近1000条记录，避免文件过大
    if (_history.length > 1000) {
      _history = _history.skip(_history.length - 1000).toList();
    }

    await _saveHistory();
  }

  /// 获取指定时间范围的主题历史
  List<TopicHistoryEntry> getTopicHistory({
    DateTimeRange? dateRange,
    String? conversationId,
  }) {
    var filtered = _history.where((entry) {
      if (dateRange != null) {
        return entry.timestamp.isAfter(dateRange.start) &&
               entry.timestamp.isBefore(dateRange.end.add(Duration(days: 1)));
      }
      return true;
    });

    if (conversationId != null) {
      filtered = filtered.where((entry) => entry.conversationId == conversationId);
    }

    return filtered.toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
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
        final List<dynamic> jsonList = jsonDecode(content);
        _history = jsonList.map((json) => TopicHistoryEntry.fromJson(json)).toList();
      }
    } catch (e) {
      print('加载主题历史失败: $e');
      _history = [];
    }
  }

  Future<void> _saveHistory() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_historyFileName');
      final jsonList = _history.map((entry) => entry.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      print('保存主题历史失败: $e');
    }
  }

  /// 清理旧记录
  Future<void> cleanOldRecords({int daysToKeep = 30}) async {
    final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
    _history.removeWhere((entry) => entry.timestamp.isBefore(cutoffDate));
    await _saveHistory();
  }

  /// 获取统计信息
  Map<String, dynamic> getStatistics({DateTimeRange? dateRange}) {
    final entries = getTopicHistory(dateRange: dateRange);

    final topicCounts = <String, int>{};
    final categoryCounts = <String, int>{};

    for (final entry in entries) {
      for (final topic in entry.detectedTopics) {
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
