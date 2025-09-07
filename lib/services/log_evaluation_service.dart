import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:app/models/log_evaluation_models.dart';

/// 日志评估服务
class LogEvaluationService {
  static const String _logFileName = 'conversation_logs.json';
  static const String _evaluationFileName = 'evaluations.json';

  List<ConversationLogEntry> _logs = [];
  Map<String, UserEvaluation> _evaluations = {};

  /// 初始化服务
  Future<void> initialize() async {
    await _loadLogs();
    await _loadEvaluations();
  }

  /// 获取对话日志
  Future<List<ConversationLogEntry>> getConversationLogs({
    DateTimeRange? dateRange,
  }) async {
    var filteredLogs = _logs;

    if (dateRange != null) {
      filteredLogs = _logs.where((log) {
        return log.timestamp.isAfter(dateRange.start) &&
               log.timestamp.isBefore(dateRange.end.add(Duration(days: 1)));
      }).toList();
    }

    // 合并评估数据
    return filteredLogs.map((log) {
      final evaluation = _evaluations[log.id];
      return ConversationLogEntry(
        id: log.id,
        role: log.role,
        content: log.content,
        timestamp: log.timestamp,
        functionResults: log.functionResults,
        evaluation: evaluation,
      );
    }).toList();
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
    final evaluatedLogs = logs ?? await getConversationLogs(dateRange: dateRange);
    final evaluations = evaluatedLogs
        .where((log) => log.evaluation != null)
        .map((log) => log.evaluation!)
        .toList();

    if (evaluations.isEmpty) {
      return EvaluationMetrics(
        todoAccuracy: 0.0,
        averageFoaScore: 0.0,
        averageRecommendationRelevance: 0.0,
        averageCognitiveLoadReasonability: 0.0,
        totalEvaluations: 0,
      );
    }

    // 计算Todo准确率
    final todoEvaluations = evaluations.where((e) => e.todoCorrect != null);
    final todoAccuracy = todoEvaluations.isEmpty
        ? 0.0
        : todoEvaluations.where((e) => e.todoCorrect == true).length / todoEvaluations.length;

    // 计算FoA平均分
    final foaEvaluations = evaluations.where((e) => e.foaScore != null);
    final averageFoaScore = foaEvaluations.isEmpty
        ? 0.0
        : foaEvaluations.map((e) => e.foaScore!).reduce((a, b) => a + b) / foaEvaluations.length;

    // 计算推荐相关性平均分
    final recEvaluations = evaluations.where((e) => e.recommendationRelevance != null);
    final averageRecommendationRelevance = recEvaluations.isEmpty
        ? 0.0
        : recEvaluations.map((e) => e.recommendationRelevance!).reduce((a, b) => a + b) / recEvaluations.length;

    // 计算认知负载合理性平均分
    final cogEvaluations = evaluations.where((e) => e.cognitiveLoadReasonability != null);
    final averageCognitiveLoadReasonability = cogEvaluations.isEmpty
        ? 0.0
        : cogEvaluations.map((e) => e.cognitiveLoadReasonability!).reduce((a, b) => a + b) / cogEvaluations.length;

    return EvaluationMetrics(
      todoAccuracy: todoAccuracy,
      averageFoaScore: averageFoaScore,
      averageRecommendationRelevance: averageRecommendationRelevance,
      averageCognitiveLoadReasonability: averageCognitiveLoadReasonability,
      totalEvaluations: evaluations.length,
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

  /// 加载日志
  Future<void> _loadLogs() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_logFileName');

      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        _logs = jsonList.map((json) => ConversationLogEntry.fromJson(json)).toList();
      } else {
        // 如果文件不存在，创建示例数据
        _logs = _generateSampleLogs();
        await _saveLogs();
      }
    } catch (e) {
      print('加载日志失败: $e');
      _logs = _generateSampleLogs();
    }
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

  /// 保存日志
  Future<void> _saveLogs() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_logFileName');
      final jsonList = _logs.map((log) => log.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      print('保存日志失败: $e');
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

  /// 生成示例日志数据
  List<ConversationLogEntry> _generateSampleLogs() {
    final now = DateTime.now();
    return [
      ConversationLogEntry(
        id: '1',
        role: 'user',
        content: '我明天有个重要会议需要准备',
        timestamp: now.subtract(Duration(hours: 2)),
        functionResults: {
          'foa': [{'topics': ['会议', '准备'], 'confidence': 0.85}],
          'todo': [{'event': '准备明天的重要会议', 'reminderTime': null, 'confidence': 0.9}],
          'cognitiveLoad': {'value': 0.6, 'level': '中等'},
        },
      ),
      ConversationLogEntry(
        id: '2',
        role: 'assistant',
        content: '我已经为您创建了一个待办事项：准备明天的重要会议。需要我提供一些会议准备的建议吗？',
        timestamp: now.subtract(Duration(hours: 2, minutes: 1)),
        functionResults: {
          'recommendations': [{'content': '会议准备清单建议', 'source': '知识库'}],
          'summaries': [{'subject': '会议准备', 'content': '用户需要准备明天的重要会议'}],
        },
      ),
      ConversationLogEntry(
        id: '3',
        role: 'user',
        content: '今天天气怎么样？',
        timestamp: now.subtract(Duration(hours: 1)),
        functionResults: {
          'foa': [{'topics': ['天气'], 'confidence': 0.95}],
          'cognitiveLoad': {'value': 0.2, 'level': '低'},
        },
      ),
    ];
  }
}
