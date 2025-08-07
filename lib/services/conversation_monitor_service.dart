/// 对话监听服务
/// 实时监听数据库中的新对话记录，并触发人类理解系统处理
/// 参考ASR服务的模式，基于数据库写入事件触发处理

import 'dart:async';
import 'package:app/services/objectbox_service.dart';
import 'package:app/services/human_understanding_system.dart';

class ConversationMonitorService {
  static final ConversationMonitorService _instance = ConversationMonitorService._internal();
  factory ConversationMonitorService() => _instance;
  ConversationMonitorService._internal();

  final HumanUnderstandingSystem _understandingSystem = HumanUnderstandingSystem();

  Timer? _pollingTimer;
  bool _isMonitoring = false;
  int _lastProcessedTimestamp = 0;
  final Set<int> _processedRecordIds = {};

  // 配置参数
  static const int _pollingInterval = 10; // 10秒轮询一次
  static const int _batchSize = 8; // 每次处理8条对话
  static const int _maxRetainedIds = 500; // 最多保留500个已处理ID

  /// 启动对话监听
  Future<void> startMonitoring() async {
    if (_isMonitoring) {
      print('[ConversationMonitor] ⚠️ 监听已在运行中');
      return;
    }

    print('[ConversationMonitor] 🚀 启动对话监听服务...');

    try {
      // 确保人类理解系统已初始化
      await _understandingSystem.initialize();

      // 设置初始时间戳
      _lastProcessedTimestamp = DateTime.now().millisecondsSinceEpoch;

      // 启动轮询
      _startPolling();

      _isMonitoring = true;
      print('[ConversationMonitor] ✅ 对话监听服务启动成功');

    } catch (e) {
      print('[ConversationMonitor] ❌ 启动监听服务失败: $e');
      rethrow;
    }
  }

  /// 停止对话监听
  void stopMonitoring() {
    print('[ConversationMonitor] 🛑 停止对话监听服务...');

    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isMonitoring = false;

    print('[ConversationMonitor] ✅ 对话监听服务已停止');
  }

  /// 启动轮询机制
  void _startPolling() {
    _pollingTimer = Timer.periodic(Duration(seconds: _pollingInterval), (timer) {
      _checkForNewConversations();
    });

    print('[ConversationMonitor] 👂 轮询机制已启动，间隔: ${_pollingInterval}秒');
  }

  /// 检查新对话
  Future<void> _checkForNewConversations() async {
    if (!_isMonitoring) return;

    try {
      // 获取自上次处理以来的新记录
      final newRecords = ObjectBoxService().getRecordsSince(_lastProcessedTimestamp);

      if (newRecords.isEmpty) {
        return; // 没有新记录，静默返回
      }

      print('[ConversationMonitor] 📊 发现 ${newRecords.length} 条新对话记录');

      // 过滤未处理的记录
      final unprocessedRecords = newRecords.where((record) {
        return record.id != null && !_processedRecordIds.contains(record.id);
      }).toList();

      if (unprocessedRecords.isEmpty) {
        print('[ConversationMonitor] ℹ️ 所有记录已处理过');
        return;
      }

      print('[ConversationMonitor] 🔄 开始处理 ${unprocessedRecords.length} 条新记录');

      // 按时间排序并限制数量
      unprocessedRecords.sort((a, b) => (a.createdAt ?? 0).compareTo(b.createdAt ?? 0));
      final recordsToProcess = unprocessedRecords.take(_batchSize).toList();

      // 检查是否有实质性内容
      final meaningfulRecords = _filterMeaningfulRecords(recordsToProcess);

      if (meaningfulRecords.isEmpty) {
        print('[ConversationMonitor] ℹ️ 没有实质性对话内容');
        _markRecordsAsProcessed(recordsToProcess);
        return;
      }

      // 构建对话上下文并处理
      await _processConversationBatch(meaningfulRecords);

      // 标记为已处理
      _markRecordsAsProcessed(recordsToProcess);

      // 更新时间戳
      _updateProcessedTimestamp();

    } catch (e) {
      print('[ConversationMonitor] ❌ 检查新对话失败: $e');
    }
  }

  /// 过滤有意义的记录
  List<dynamic> _filterMeaningfulRecords(List<dynamic> records) {
    return records.where((record) {
      final content = record.content?.toString() ?? '';

      // 过滤条件
      if (content.trim().isEmpty) return false;
      if (content.length < 3) return false; // 太短的内容
      if (_isSystemMessage(content)) return false; // 系统消息

      return true;
    }).toList();
  }

  /// 判断是否为系统消息
  bool _isSystemMessage(String content) {
    final systemPatterns = [
      '录音开始',
      '录音结束',
      '系统启动',
      '连接成功',
      '断开连接',
    ];

    return systemPatterns.any((pattern) => content.contains(pattern));
  }

  /// 处理对话批次
  Future<void> _processConversationBatch(List<dynamic> records) async {
    try {
      print('[ConversationMonitor] 📦 处理 ${records.length} 条有意义的对话记录');

      // 构建完整的对话上下文
      final contextBuilder = StringBuffer();
      String lastRole = '';

      for (final record in records) {
        final role = record.role ?? 'unknown';
        final content = record.content ?? '';
        final createdAt = record.createdAt; // 修复：使用createdAt而不是timestamp

        if (content.trim().isNotEmpty) {
          // 格式化时间
          String timeStr = '';
          if (createdAt != null) {
            final time = DateTime.fromMillisecondsSinceEpoch(createdAt);
            timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
          }

          // 如果角色发生变化，添加换行
          if (role != lastRole && contextBuilder.isNotEmpty) {
            contextBuilder.writeln();
          }

          contextBuilder.writeln('[$timeStr] $role: $content');
          lastRole = role;
        }
      }

      final conversationContext = contextBuilder.toString().trim();

      if (conversationContext.isEmpty) {
        print('[ConversationMonitor] ⚠️ 对话上下文为空');
        return;
      }

      // 提取综合内容
      final allContent = records
          .map((r) => r.content?.toString() ?? '')
          .where((content) => content.trim().isNotEmpty)
          .join(' ');

      // 创建语义分析输入
      final semanticInput = _createSemanticAnalysisInput(
        allContent,
        conversationContext,
        records
      );

      // 提交给人类理解系统处理
      await _understandingSystem.processSemanticInput(semanticInput);

      print('[ConversationMonitor] ✅ 对话批次处理完成');

    } catch (e) {
      print('[ConversationMonitor] ❌ 处理对话批次失败: $e');
    }
  }

  /// 创建语义分析输入
  dynamic _createSemanticAnalysisInput(String content, String context, List<dynamic> records) {
    // 基础实体提取
    final entities = _extractEntities(content);

    // 基础意图推断
    final intent = _inferIntent(content);

    // 基础情绪推断
    final emotion = _inferEmotion(content);

    // 获取最新时间戳
    final latestTimestamp = records
        .map((r) => r.createdAt as int? ?? 0) // 修复：使用createdAt而不是timestamp
        .fold<int>(0, (max, ts) => ts > max ? ts : max);

    return SemanticAnalysisInput(
      entities: entities,
      intent: intent,
      emotion: emotion,
      content: content,
      timestamp: latestTimestamp > 0
          ? DateTime.fromMillisecondsSinceEpoch(latestTimestamp)
          : DateTime.now(),
      additionalContext: {
        'source': 'conversation_monitor',
        'conversation_context': context,
        'record_count': records.length,
        'processing_timestamp': DateTime.now().toIso8601String(),
        'batch_processing': true,
      },
    );
  }

  /// 基础实体提取
  List<String> _extractEntities(String content) {
    final entities = <String>[];
    final lowerContent = content.toLowerCase();

    // 技术相关实体
    if (lowerContent.contains('flutter')) entities.add('Flutter');
    if (lowerContent.contains('ai') || lowerContent.contains('人工智能')) entities.add('AI');
    if (lowerContent.contains('机器学习')) entities.add('机器学习');
    if (lowerContent.contains('数据库')) entities.add('数据库');
    if (lowerContent.contains('性能') || lowerContent.contains('优化')) entities.add('性能优化');
    if (lowerContent.contains('bug') || lowerContent.contains('错误')) entities.add('Bug修复');

    // 工作相关实体
    if (lowerContent.contains('项目') || lowerContent.contains('工作')) entities.add('工作项目');
    if (lowerContent.contains('会议') || lowerContent.contains('讨论')) entities.add('会议');
    if (lowerContent.contains('团队') || lowerContent.contains('协作')) entities.add('团队协作');
    if (lowerContent.contains('功能') || lowerContent.contains('模块')) entities.add('功能开发');

    // 学���相关实体
    if (lowerContent.contains('学习') || lowerContent.contains('教程')) entities.add('学习');
    if (lowerContent.contains('了解') || lowerContent.contains('研究')) entities.add('研究');

    return entities.isEmpty ? ['对话'] : entities;
  }

  /// 基础意图推断
  String _inferIntent(String content) {
    final lowerContent = content.toLowerCase();

    if (lowerContent.contains('学习') || lowerContent.contains('教程') || lowerContent.contains('了解')) {
      return 'learning';
    }
    if (lowerContent.contains('规划') || lowerContent.contains('计划') || lowerContent.contains('准备')) {
      return 'planning';
    }
    if (lowerContent.contains('问题') || lowerContent.contains('bug') || lowerContent.contains('优化')) {
      return 'problem_solving';
    }
    if (lowerContent.contains('完成') || lowerContent.contains('进展') || lowerContent.contains('做了')) {
      return 'sharing_experience';
    }
    if (lowerContent.contains('推荐') || lowerContent.contains('什么') || lowerContent.contains('如何')) {
      return 'information_seeking';
    }

    return 'casual_chat';
  }

  /// 基础情绪推断
  String _inferEmotion(String content) {
    final lowerContent = content.toLowerCase();

    if (lowerContent.contains('不错') || lowerContent.contains('完成') || lowerContent.contains('好')) {
      return 'positive';
    }
    if (lowerContent.contains('困难') || lowerContent.contains('问题') || lowerContent.contains('棘手')) {
      return 'frustrated';
    }
    if (lowerContent.contains('感兴趣') || lowerContent.contains('想') || lowerContent.contains('希望')) {
      return 'curious';
    }
    if (lowerContent.contains('需要') || lowerContent.contains('应该') || lowerContent.contains('考虑')) {
      return 'focused';
    }

    return 'neutral';
  }

  /// 标记记录为已处理
  void _markRecordsAsProcessed(List<dynamic> records) {
    for (final record in records) {
      if (record.id != null) {
        _processedRecordIds.add(record.id!);
      }
    }

    // 清理过多的已处理ID
    if (_processedRecordIds.length > _maxRetainedIds) {
      final sortedIds = _processedRecordIds.toList()..sort();
      _processedRecordIds.clear();
      _processedRecordIds.addAll(sortedIds.skip(_maxRetainedIds ~/ 2));
    }
  }

  /// 更新处理时间戳
  void _updateProcessedTimestamp() {
    _lastProcessedTimestamp = DateTime.now().millisecondsSinceEpoch;
  }

  /// 手动触发处理（用于测试或手动同步）
  Future<void> triggerProcessing() async {
    print('[ConversationMonitor] 🔄 手动触发对话处理...');
    await _checkForNewConversations();
  }

  /// 获取监听状态
  Map<String, dynamic> getMonitoringStatus() {
    return {
      'is_monitoring': _isMonitoring,
      'last_processed_timestamp': _lastProcessedTimestamp,
      'processed_record_count': _processedRecordIds.length,
      'polling_interval_seconds': _pollingInterval,
      'batch_size': _batchSize,
      'last_check_time': DateTime.now().toIso8601String(),
    };
  }

  /// 重置监听状态
  void resetMonitoringState() {
    print('[ConversationMonitor] 🔄 重置监听状态...');

    _processedRecordIds.clear();
    _lastProcessedTimestamp = DateTime.now().millisecondsSinceEpoch;

    print('[ConversationMonitor] ✅ 监听状态已重置');
  }

  /// 释放资源
  void dispose() {
    stopMonitoring();
    _processedRecordIds.clear();
    print('[ConversationMonitor] 🔌 对话监听服务已释放');
  }
}

/// 语义分析输入模型（临时定义，应该使用实际的模型）
class SemanticAnalysisInput {
  final List<String> entities;
  final String intent;
  final String emotion;
  final String content;
  final DateTime timestamp;
  final Map<String, dynamic> additionalContext;

  SemanticAnalysisInput({
    required this.entities,
    required this.intent,
    required this.emotion,
    required this.content,
    required this.timestamp,
    required this.additionalContext,
  });
}
