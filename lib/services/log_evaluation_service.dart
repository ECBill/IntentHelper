import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:app/models/log_evaluation_models.dart';
import 'package:app/services/objectbox_service.dart';
import 'package:app/services/topic_history_service.dart';
import 'package:app/models/record_entity.dart';
import 'package:app/models/objectbox.g.dart';

import 'knowledge_graph_manager.dart';
import 'package:app/services/kg_history_service.dart'; // 新增

/// 日志评估服务
class LogEvaluationService {
  static const String _evaluationFileName = 'evaluations.json';

  Map<String, UserEvaluation> _evaluations = {};
  final TopicHistoryService _topicHistoryService = TopicHistoryService();

  /// 初始化服务
  Future<void> initialize() async {
    await _loadEvaluations();
    await _topicHistoryService.initialize();
  }

  /// 获取FoA主题识别数据（修改版）
  /// TODO: 需要重新实现以配合新的Focus State Machine
  Future<List<FoAEntry>> getFoAEntries({DateTimeRange? dateRange}) async {
    final entries = <FoAEntry>[];
    /* 
    // 暂时注释掉，等待重新实现以配合Focus State Machine
    try {
      // 从主题历史服务获取按窗口分组的数据
      final windows = _topicHistoryService.getTopicHistoryWindows(dateRange: dateRange);
      for (final window in windows) {
        if (window.topics.isEmpty) continue;
        final entryId = 'foa_window_${window.windowStart.millisecondsSinceEpoch}';
        final evaluation = _evaluations[entryId];
        // 计算窗口内平均置信度
        final avgConfidence = window.topics
            .map((t) => t.relevanceScore)
            .reduce((a, b) => a + b) / window.topics.length;
        entries.add(FoAEntry(
          id: entryId,
          topics: window.topics.map((t) => t.name).toList(),
          confidence: avgConfidence,
          timestamp: window.windowStart,
          relatedContent: '',  // 不保存具体内容
          evaluation: evaluation,
        ));
      }
    } catch (e) {
      print('获取FoA数据失败: $e');
    }
    */
    return entries;
  }

  /// 回退的FoA数据获取方法（原来的模拟数据）
  /// TODO: 需要重新实现以配合新的Focus State Machine
  Future<List<FoAEntry>> _getFallbackFoAEntries({DateTimeRange? dateRange}) async {
    final entries = <FoAEntry>[];
    /* 
    // 暂时注释掉，等待重新实现以配合Focus State Machine
    try {
      final startTime = dateRange?.start.millisecondsSinceEpoch ??
                       DateTime.now().subtract(Duration(days: 30)).millisecondsSinceEpoch;
      final endTime = dateRange?.end.add(Duration(days: 1)).millisecondsSinceEpoch ??
                     DateTime.now().millisecondsSinceEpoch;

      // 获取相关的对话记录
      final query = ObjectBoxService.recordBox
          .query(RecordEntity_.createdAt.between(startTime, endTime))
          .order(RecordEntity_.createdAt)
          .build();
      final records = query.find();
      query.close();

      for (final record in records) {
        if (record.content == null || record.content!.isEmpty) continue;

        // 模拟FoA主题识别结果 - 实际应该从ConversationTopicTracker获取
        List<String> topics = [];
        double confidence = 0.0;

        if (record.content!.contains('会议')) {
          topics = ['会议', '工作'];
          confidence = 0.85;
        } else if (record.content!.contains('天气')) {
          topics = ['天气', '日常'];
          confidence = 0.95;
        } else if (record.content!.contains('吃饭') || record.content!.contains('食物')) {
          topics = ['饮食', '日常'];
          confidence = 0.90;
        }

        if (topics.isNotEmpty) {
          final entryId = 'foa_${record.id}';
          final evaluation = _evaluations[entryId];

          entries.add(FoAEntry(
            id: entryId,
            topics: topics,
            confidence: confidence,
            timestamp: DateTime.fromMillisecondsSinceEpoch(record.createdAt ?? 0),
            relatedContent: record.content!,
            evaluation: evaluation,
          ));
        }
      }
    } catch (e) {
      print('获取回退FoA数据失败: $e');
    }
    */

    return entries;
  }

  /// 获取Todo提醒数据
  Future<List<TodoEntry>> getTodoEntries({DateTimeRange? dateRange}) async {
    final entries = <TodoEntry>[];

    try {
      final startTime = dateRange?.start.millisecondsSinceEpoch ??
                       DateTime.now().subtract(Duration(days: 30)).millisecondsSinceEpoch;
      final endTime = dateRange?.end.add(Duration(days: 1)).millisecondsSinceEpoch ??
                     DateTime.now().millisecondsSinceEpoch;

      final query = ObjectBoxService.todoBox
          .query(TodoEntity_.createdAt.between(startTime, endTime)
              .and(TodoEntity_.reminderType.equals('natural_language')))
          .order(TodoEntity_.createdAt)
          .build();
      final todos = query.find();
      query.close();

      for (final todo in todos) {
        if (todo.task == null || todo.task!.isEmpty) continue;

        final entryId = 'todo_${todo.id}';
        final evaluation = _evaluations[entryId];

        entries.add(TodoEntry(
          id: entryId,
          task: todo.task!,
          deadline: todo.deadline != null ? DateTime.fromMillisecondsSinceEpoch(todo.deadline!) : null,
          confidence: 0.9, // 模拟置信度
          timestamp: DateTime.fromMillisecondsSinceEpoch(todo.createdAt ?? 0),
          relatedContent: todo.detail ?? '',
          evaluation: evaluation,
        ));
      }
    } catch (e) {
      print('获取Todo数据失败: $e');
    }

    return entries;
  }

  /// 获取智能推荐数据
  Future<List<RecommendationEntry>> getRecommendationEntries({DateTimeRange? dateRange}) async {
    final entries = <RecommendationEntry>[];

    try {
      final startTime = dateRange?.start.millisecondsSinceEpoch ??
                       DateTime.now().subtract(Duration(days: 30)).millisecondsSinceEpoch;
      final endTime = dateRange?.end.add(Duration(days: 1)).millisecondsSinceEpoch ??
                     DateTime.now().millisecondsSinceEpoch;

      // 获取助手回复中包含推荐内容的记录
      final query = ObjectBoxService.recordBox
          .query(RecordEntity_.createdAt.between(startTime, endTime)
              .and(RecordEntity_.role.equals('assistant')))
          .order(RecordEntity_.createdAt)
          .build();
      final records = query.find();
      query.close();

      for (final record in records) {
        if (record.content == null || record.content!.isEmpty) continue;

        // 检查是否包含推荐内容
        if (record.content!.contains('建议') || record.content!.contains('推荐') || record.content!.contains('可以试试')) {
          final entryId = 'rec_${record.id}';
          final evaluation = _evaluations[entryId];

          entries.add(RecommendationEntry(
            id: entryId,
            content: record.content!,
            source: '智能提醒系统',
            relevance: 0.8, // 模拟相关性分��
            timestamp: DateTime.fromMillisecondsSinceEpoch(record.createdAt ?? 0),
            relatedContent: record.content!,
            evaluation: evaluation,
          ));
        }
      }
    } catch (e) {
      print('获取推荐数据失败: $e');
    }

    return entries;
  }

  /// 获取总结数据
  Future<List<SummaryEntry>> getSummaryEntries({DateTimeRange? dateRange}) async {
    final entries = <SummaryEntry>[];

    try {
      final startTime = dateRange?.start.millisecondsSinceEpoch ??
                       DateTime.now().subtract(Duration(days: 30)).millisecondsSinceEpoch;
      final endTime = dateRange?.end.add(Duration(days: 1)).millisecondsSinceEpoch ??
                     DateTime.now().millisecondsSinceEpoch;

      final query = ObjectBoxService.summaryBox
          .query(SummaryEntity_.createdAt.between(startTime, endTime))
          .order(SummaryEntity_.createdAt)
          .build();
      final summaries = query.find();
      query.close();

      for (final summary in summaries) {
        if (summary.content == null || summary.content!.isEmpty) continue;

        final entryId = 'summary_${summary.id}';
        final evaluation = _evaluations[entryId];

        entries.add(SummaryEntry(
          id: entryId,
          subject: summary.subject ?? '未命名总结',
          content: summary.content!,
          timestamp: DateTime.fromMillisecondsSinceEpoch(summary.createdAt ?? 0),
          relatedContent: summary.content!,
          evaluation: evaluation,
        ));
      }
    } catch (e) {
      print('获取总结数据失败: $e');
    }

    return entries;
  }

  /// 获取知识图谱数据
  Future<List<KGEntry>> getKGEntries({DateTimeRange? dateRange}) async {
    // 从持久化的KG历史读取统一文字版本
    final entries = <KGEntry>[];
    final kgHistory = KGHistoryService();
    await kgHistory.initialize();
    final history = kgHistory.getHistory(dateRange: dateRange);
    for (final entry in history) {
      final entryId = 'kg_${entry.windowStart.millisecondsSinceEpoch}';
      final evaluation = _evaluations[entryId];
      entries.add(KGEntry(
        id: entryId,
        nodeType: entry.windowStart.toIso8601String(),
        content: entry.summary,
        properties: {},
        timestamp: entry.windowStart,
        relatedContent: '',
        evaluation: evaluation,
      ));
    }
    return entries;
  }

  /// 获取认知负载数据
  Future<List<CognitiveLoadEntry>> getCognitiveLoadEntries({DateTimeRange? dateRange}) async {
    final entries = <CognitiveLoadEntry>[];

    try {
      final startTime = dateRange?.start.millisecondsSinceEpoch ??
                       DateTime.now().subtract(Duration(days: 30)).millisecondsSinceEpoch;
      final endTime = dateRange?.end.add(Duration(days: 1)).millisecondsSinceEpoch ??
                     DateTime.now().millisecondsSinceEpoch;

      // 获取对话记录并分析认知负载
      final query = ObjectBoxService.recordBox
          .query(RecordEntity_.createdAt.between(startTime, endTime))
          .order(RecordEntity_.createdAt)
          .build();
      final records = query.find();
      query.close();

      for (final record in records) {
        if (record.content == null || record.content!.isEmpty) continue;

        // 模拟认知负载分析 - 实际应该从CognitiveLoadEstimator获取
        final contentLength = record.content!.length;
        double loadValue = 0.0;
        String loadLevel = '';

        if (contentLength > 100) {
          loadValue = 0.8;
          loadLevel = '高';
        } else if (contentLength > 50) {
          loadValue = 0.6;
          loadLevel = '中���';
        } else {
          loadValue = 0.3;
          loadLevel = '低';
        }

        final entryId = 'load_${record.id}';
        final evaluation = _evaluations[entryId];

        entries.add(CognitiveLoadEntry(
          id: entryId,
          value: loadValue,
          level: loadLevel,
          timestamp: DateTime.fromMillisecondsSinceEpoch(record.createdAt ?? 0),
          relatedContent: record.content!,
          evaluation: evaluation,
        ));
      }
    } catch (e) {
      print('获取认知负载数据失败: $e');
    }

    return entries;
  }

  /// 获取对话日志
  Future<List<ConversationLogEntry>> getConversationLogs({
    DateTimeRange? dateRange,
  }) async {
    final logs = <ConversationLogEntry>[];

    // 获取对话记录时间范围
    final startTime = dateRange?.start.millisecondsSinceEpoch ??
                     DateTime.now().subtract(Duration(days: 30)).millisecondsSinceEpoch;
    final endTime = dateRange?.end.add(Duration(days: 1)).millisecondsSinceEpoch ??
                   DateTime.now().millisecondsSinceEpoch;

    try {
      // 从 ObjectBox 获取对话记录
      final query = ObjectBoxService.recordBox
          .query(RecordEntity_.createdAt.between(startTime, endTime))
          .order(RecordEntity_.createdAt)
          .build();
      final records = query.find();
      query.close();

      print('找到 ${records.length} 条对话记录');

      for (final record in records) {
        if (record.content == null || record.content!.isEmpty) continue;

        final timestamp = DateTime.fromMillisecondsSinceEpoch(record.createdAt ?? 0);
        final logId = record.id.toString();

        // 收集功能结果
        final functionResults = <String, dynamic>{};

        // 1. FoA识别 - 暂时注释掉，等待重新实现以配合Focus State Machine
        /* 
        final foaResults = await _getFoAResults(record, timestamp);
        if (foaResults.isNotEmpty) {
          functionResults['foa'] = foaResults;
        }
        */

        // 2. Todo生成 - 从 TodoEntity 获取
        final todoResults = await _getTodoResults(record, timestamp);
        if (todoResults.isNotEmpty) {
          functionResults['todo'] = todoResults;
        }

        // 3. 主动推荐 - 从 IntelligentReminderManager 获取
        final recommendationResults = await _getRecommendationResults(record, timestamp);
        if (recommendationResults.isNotEmpty) {
          functionResults['recommendations'] = recommendationResults;
        }

        // 4. 总结 - 从 SummaryEntity 获取
        final summaryResults = await _getSummaryResults(record, timestamp);
        if (summaryResults.isNotEmpty) {
          functionResults['summaries'] = summaryResults;
        }

        // 5. KG内容 - 从知识图谱获取
        final kgResults = await _getKGResults(record, timestamp);
        if (kgResults.isNotEmpty) {
          functionResults['kg'] = kgResults;
        }

        // 6. 认知负载 - 从 CognitiveLoadEstimator 获取
        final cognitiveLoadResults = await _getCognitiveLoadResults(record, timestamp);
        if (cognitiveLoadResults.isNotEmpty) {
          functionResults['cognitiveLoad'] = cognitiveLoadResults;
        }

        // 显示所有对话记录，不管是否有功能结果
        final evaluation = _evaluations[logId];
        logs.add(ConversationLogEntry(
          id: logId,
          role: record.role ?? 'user',
          content: record.content!,
          timestamp: timestamp,
          functionResults: functionResults,
          evaluation: evaluation,
        ));
      }
    } catch (e) {
      print('获取对话记录失败: $e');
    }

    print('生成了 ${logs.length} 条日志条目');
    return logs;
  }

  /// 获取FoA识别结果
  /// TODO: 需要重新实现以配合新的Focus State Machine
  Future<List<Map<String, dynamic>>> _getFoAResults(RecordEntity record, DateTime timestamp) async {
    /* 
    // 暂时注释掉，等待重新实现以配合Focus State Machine
    try {
      // 这里应该从 ConversationTopicTracker 获取主题分析结果
      // 目前先返回模拟数据，实际实现需要调用相应的服务
      if (record.content != null && record.content!.contains('会议')) {
        return [{'topics': ['会议', '工作'], 'confidence': 0.85}];
      } else if (record.content != null && record.content!.contains('天气')) {
        return [{'topics': ['天气', '日常'], 'confidence': 0.95}];
      }
      return [];
    } catch (e) {
      print('获取FoA结果失败: $e');
      return [];
    }
    */
    return [];
  }

  /// 获取Todo生成结果
  Future<List<Map<String, dynamic>>> _getTodoResults(RecordEntity record, DateTime timestamp) async {
    try {
      // 查找相关时间范围内的Todo记录
      final query = ObjectBoxService.todoBox
          .query(TodoEntity_.createdAt.between(
            timestamp.subtract(Duration(minutes: 5)).millisecondsSinceEpoch,
            timestamp.add(Duration(minutes: 5)).millisecondsSinceEpoch,
          ))
          .build();
      final todos = query.find();
      query.close();

      return todos.map((todo) => {
        'event': todo.task ?? '',
        'reminderTime': todo.deadline != null ? DateTime.fromMillisecondsSinceEpoch(todo.deadline!).toString() : '未指定',
        'confidence': 0.9,
      }).toList();
    } catch (e) {
      print('获取Todo结果失败: $e');
      return [];
    }
  }

  /// 获取主动推荐结果
  Future<List<Map<String, dynamic>>> _getRecommendationResults(RecordEntity record, DateTime timestamp) async {
    try {
      // 这里应该从 IntelligentReminderManager 获取智能提醒结果
      // 目前先返回模拟数据
      if (record.role == 'assistant' && record.content != null && record.content!.contains('建议')) {
        return [{'content': '智能推荐内容', 'source': '智能提醒系统'}];
      }
      return [];
    } catch (e) {
      print('获取推荐结果失败: $e');
      return [];
    }
  }

  /// 获取总结结果
  Future<List<Map<String, dynamic>>> _getSummaryResults(RecordEntity record, DateTime timestamp) async {
    try {
      // 查找相关时间范围内的Summary记录
      final query = ObjectBoxService.summaryBox
          .query(SummaryEntity_.createdAt.between(
            timestamp.subtract(Duration(minutes: 10)).millisecondsSinceEpoch,
            timestamp.add(Duration(minutes: 10)).millisecondsSinceEpoch,
          ))
          .build();
      final summaries = query.find();
      query.close();

      return summaries.map((summary) => {
        'subject': summary.subject ?? '',
        'content': summary.content ?? '',
      }).toList();
    } catch (e) {
      print('获取总结结果失败: $e');
      return [];
    }
  }

  /// 获取KG结果
  Future<List<Map<String, dynamic>>> _getKGResults(RecordEntity record, DateTime timestamp) async {
    try {
      // 暂时跳过KG查询，因为模型字段可能不匹配
      // TODO: 需要检查Node和Edge模型的实际字段结构
      return [];
    } catch (e) {
      print('获取KG结果失败: $e');
      return [];
    }
  }

  /// 获取认知负载结果
  Future<Map<String, dynamic>> _getCognitiveLoadResults(RecordEntity record, DateTime timestamp) async {
    try {
      // 这里应该从 CognitiveLoadEstimator 获取认知负载分析结果
      // 目前先返回模拟数据
      if (record.content != null) {
        final contentLength = record.content!.length;
        if (contentLength > 100) {
          return {'value': 0.8, 'level': '高'};
        } else if (contentLength > 50) {
          return {'value': 0.6, 'level': '中等'};
        } else {
          return {'value': 0.3, 'level': '低'};
        }
      }
      return {};
    } catch (e) {
      print('获取认知负载结果失败: $e');
      return {};
    }
  }

  /// 保存评估
  Future<void> saveEvaluation(String logId, UserEvaluation evaluation) async {
    _evaluations[logId] = evaluation;
    await _saveEvaluations();
  }

  /// 计算评估指标
  Future<EvaluationMetrics> calculateMetrics({
    DateTimeRange? dateRange,
    List<ConversationLogEntry>? logs,
  }) async {
    // 获取所有模块的评���数据
    final foaEntries = await getFoAEntries(dateRange: dateRange);
    final todoEntries = await getTodoEntries(dateRange: dateRange);
    final recEntries = await getRecommendationEntries(dateRange: dateRange);
    final summaryEntries = await getSummaryEntries(dateRange: dateRange);
    final kgEntries = await getKGEntries(dateRange: dateRange);
    final loadEntries = await getCognitiveLoadEntries(dateRange: dateRange);

    // 收集所有评估
    final allEvaluations = <UserEvaluation>[];

    foaEntries.where((e) => e.evaluation != null).forEach((e) => allEvaluations.add(e.evaluation!));
    todoEntries.where((e) => e.evaluation != null).forEach((e) => allEvaluations.add(e.evaluation!));
    recEntries.where((e) => e.evaluation != null).forEach((e) => allEvaluations.add(e.evaluation!));
    summaryEntries.where((e) => e.evaluation != null).forEach((e) => allEvaluations.add(e.evaluation!));
    kgEntries.where((e) => e.evaluation != null).forEach((e) => allEvaluations.add(e.evaluation!));
    loadEntries.where((e) => e.evaluation != null).forEach((e) => allEvaluations.add(e.evaluation!));

    if (allEvaluations.isEmpty) {
      return EvaluationMetrics(
        todoAccuracy: 0.0,
        averageFoaScore: 0.0,
        averageRecommendationRelevance: 0.0,
        averageCognitiveLoadReasonability: 0.0,
        averageSummaryRelevance: 0.0,
        averageKgAccuracy: 0.0,
        totalEvaluations: 0,
      );
    }

    // 计算Todo准确率 = 正确数 / 总数
    final todoEvaluations = allEvaluations.where((e) => e.todoCorrect != null);
    final todoAccuracy = todoEvaluations.isEmpty
        ? 0.0
        : todoEvaluations.where((e) => e.todoCorrect == true).length / todoEvaluations.length;

    // 计算FoA平均分 = 各次标注映射值的平均
    final foaEvaluations = allEvaluations.where((e) => e.foaScore != null);
    final averageFoaScore = foaEvaluations.isEmpty
        ? 0.0
        : foaEvaluations.map((e) => e.foaScore!).reduce((a, b) => a + b) / foaEvaluations.length;

    // 计算主动推荐平均相关性 = 平均分
    final recEvaluations = allEvaluations.where((e) => e.recommendationRelevance != null);
    final averageRecommendationRelevance = recEvaluations.isEmpty
        ? 0.0
        : recEvaluations.map((e) => e.recommendationRelevance!.toDouble()).reduce((a, b) => a + b) / recEvaluations.length;

    // 计算认知负载合理性 = 平均分
    final cogEvaluations = allEvaluations.where((e) => e.cognitiveLoadReasonability != null);
    final averageCognitiveLoadReasonability = cogEvaluations.isEmpty
        ? 0.0
        : cogEvaluations.map((e) => e.cognitiveLoadReasonability!.toDouble()).reduce((a, b) => a + b) / cogEvaluations.length;

    // 计算总结质量平均分
    final summaryEvaluations = allEvaluations.where((e) => e.summaryRelevance != null);
    final averageSummaryRelevance = summaryEvaluations.isEmpty
        ? 0.0
        : summaryEvaluations.map((e) => e.summaryRelevance!.toDouble()).reduce((a, b) => a + b) / summaryEvaluations.length;

    // 计算KG准确性平均分
    final kgEvaluations = allEvaluations.where((e) => e.kgAccuracy != null);
    final averageKgAccuracy = kgEvaluations.isEmpty
        ? 0.0
        : kgEvaluations.map((e) => e.kgAccuracy!.toDouble()).reduce((a, b) => a + b) / kgEvaluations.length;

    return EvaluationMetrics(
      todoAccuracy: todoAccuracy,
      averageFoaScore: averageFoaScore,
      averageRecommendationRelevance: averageRecommendationRelevance,
      averageCognitiveLoadReasonability: averageCognitiveLoadReasonability,
      averageSummaryRelevance: averageSummaryRelevance,
      averageKgAccuracy: averageKgAccuracy,
      totalEvaluations: allEvaluations.length,
    );
  }

  /// 导出数据
  Future<String> exportData({
    required List<ConversationLogEntry> logs,
    required EvaluationMetrics metrics,
    required String format,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    if (format == 'json') {
      final file = File('${directory.path}/log_evaluation_export_$timestamp.json');
      final data = {
        'exportTime': DateTime.now().toIso8601String(),
        'metrics': metrics.toJson(),
        'logs': logs.map((log) => log.toJson()).toList(),
      };
      await file.writeAsString(jsonEncode(data));
      return file.path;
    } else if (format == 'csv') {
      final file = File('${directory.path}/log_evaluation_export_$timestamp.csv');
      final buffer = StringBuffer();

      // CSV头部
      buffer.writeln('ID,角色,内容,时间戳,FoA评分,Todo正确,推荐相关性,认知负载合理性,评估时间');

      // 数据行
      for (final log in logs) {
        final eval = log.evaluation;
        buffer.writeln([
          log.id,
          log.role,
          '"${log.content.replaceAll('"', '""')}"',
          log.timestamp.toIso8601String(),
          eval?.foaScore ?? '',
          eval?.todoCorrect ?? '',
          eval?.recommendationRelevance ?? '',
          eval?.cognitiveLoadReasonability ?? '',
          eval?.evaluatedAt.toIso8601String() ?? '',
        ].join(','));
      }

      await file.writeAsString(buffer.toString());
      return file.path;
    }

    throw Exception('不支持的导出格式: $format');
  }

  /// 加载评估
  Future<void> _loadEvaluations() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_evaluationFileName');

      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> jsonMap = jsonDecode(content);
        _evaluations = jsonMap.map((key, value) =>
          MapEntry(key, UserEvaluation.fromJson(value)));
      }
    } catch (e) {
      print('加载评估失败: $e');
      _evaluations = {};
    }
  }

  /// 保存评估
  Future<void> _saveEvaluations() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_evaluationFileName');
      final jsonMap = _evaluations.map((key, value) =>
        MapEntry(key, value.toJson()));
      await file.writeAsString(jsonEncode(jsonMap));
    } catch (e) {
      print('保存评估失败: $e');
    }
  }
}
