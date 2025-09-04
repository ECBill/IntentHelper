/// 智能提醒管理器
/// 基于用户对话中的关键词、意图和行为模式，主动发送个性化提醒

import 'dart:async';
import 'package:app/models/human_understanding_models.dart';
import 'package:app/services/llm.dart';
import 'package:app/controllers/chat_controller.dart';
import 'package:app/services/natural_language_reminder_service.dart'; // 🔥 新增：导入TodoEntity和ObjectBoxService
import 'package:app/models/todo_entity.dart';
import 'package:app/services/objectbox_service.dart';

class IntelligentReminderManager {
  static final IntelligentReminderManager _instance = IntelligentReminderManager._internal();
  factory IntelligentReminderManager() => _instance;
  IntelligentReminderManager._internal();

  // 关键词和意图追踪
  final Map<String, KeywordTracker> _keywordTrackers = {};
  final Map<String, IntentTracker> _intentTrackers = {};
  final List<ReminderRule> _activeRules = [];
  final List<PendingReminder> _pendingReminders = [];
  final Set<String> _sentReminderIds = {};

  // 🔥 新增：自然语言提醒服务
  final NaturalLanguageReminderService _nlReminderService = NaturalLanguageReminderService();

  // 系统状态
  Timer? _reminderCheckTimer;
  Timer? _analysisTimer;
  bool _initialized = false;
  ChatController? _chatController;

  // 配置参数
  static const int _checkInterval = 30; // 30秒检查一次
  static const int _analysisInterval = 300; // 5分钟分析一次
  static const int _maxRemindersPerHour = 3; // 每小时最多3个提醒

  // 🔥 新增：智能提醒调度参数
  static const int _minIntervalBetweenReminders = 900; // 15分钟内最多发送1个提醒
  static const int _maxRemindersPerDay = 8; // 每天最多8个提醒

  // 🔥 修改：提醒计数器改为更精细的时间跟踪
  final List<DateTime> _recentReminderTimes = [];
  final Map<int, int> _hourlyReminderCount = {}; // 🔥 新增：每小时提醒计数

  /// 初始化提醒管理器
  Future<void> initialize({ChatController? chatController}) async {
    if (_initialized) return;

    print('[IntelligentReminderManager] 🚀 初始化智能提醒管理器...');

    _chatController = chatController;

    // 🔥 新增：初始化自然语言提醒服务
    await _nlReminderService.initialize(chatController: chatController);

    // 加载预定义的提醒规则
    await _loadDefaultReminderRules();

    // 启动定时器
    _startReminderTimer();
    _startAnalysisTimer();

    _initialized = true;
    print('[IntelligentReminderManager] ✅ 智能提醒管理器初始化完成');
  }

  /// 处理新的语义分析输入
  Future<void> processSemanticAnalysis(SemanticAnalysisInput analysis) async {
    if (!_initialized) return;

    try {
      // 1. 🔥 新增：首先处理自然语言提醒
      await _nlReminderService.processSemanticAnalysis(analysis);

      // 2. 更新关键词追踪器
      await _updateKeywordTrackers(analysis);

      // 3. 更新意图追踪器
      await _updateIntentTrackers(analysis);

      // 4. 检查是否触发新的提醒规则
      await _checkTriggeredReminders(analysis);

    } catch (e) {
      print('[IntelligentReminderManager] ❌ 处理语义分析失败: $e');
    }
  }

  /// 更新关键词追踪器
  Future<void> _updateKeywordTrackers(SemanticAnalysisInput analysis) async {
    final keywords = _extractKeywords(analysis.content);

    for (final keyword in keywords) {
      _keywordTrackers.putIfAbsent(keyword, () => KeywordTracker(keyword));
      _keywordTrackers[keyword]!.addOccurrence(analysis.timestamp);
    }

    // 清理过期的关键词追踪器
    _cleanupExpiredTrackers();
  }

  /// 更新意图追踪器
  Future<void> _updateIntentTrackers(SemanticAnalysisInput analysis) async {
    final intent = analysis.intent;
    if (intent.isNotEmpty) {
      _intentTrackers.putIfAbsent(intent, () => IntentTracker(intent));
      _intentTrackers[intent]!.addOccurrence(analysis.timestamp, analysis.entities);
    }
  }

  /// 检查触发的提醒
  Future<void> _checkTriggeredReminders(SemanticAnalysisInput analysis) async {
    for (final rule in _activeRules) {
      if (await _evaluateReminderRule(rule, analysis)) {
        await _scheduleReminder(rule, analysis);
      }
    }
  }

  /// 评估提醒规则是否满足条件
  Future<bool> _evaluateReminderRule(ReminderRule rule, SemanticAnalysisInput analysis) async {
    switch (rule.type) {
      case ReminderType.keywordFrequency:
        return _evaluateKeywordFrequencyRule(rule);

      case ReminderType.intentPattern:
        return _evaluateIntentPatternRule(rule);

      case ReminderType.timeBasedFollow:
        return _evaluateTimeBasedRule(rule, analysis);

      case ReminderType.contextualSuggestion:
        return await _evaluateContextualRule(rule, analysis);
    }
  }

  /// 评估关键词频率规则
  bool _evaluateKeywordFrequencyRule(ReminderRule rule) {
    final tracker = _keywordTrackers[rule.targetKeyword];
    if (tracker == null) return false;

    final frequency = tracker.getFrequencyInWindow(Duration(hours: rule.timeWindowHours));
    return frequency >= rule.threshold && !_hasRecentReminder(rule.id);
  }

  /// 评估意图模式规则
  bool _evaluateIntentPatternRule(ReminderRule rule) {
    final tracker = _intentTrackers[rule.targetIntent];
    if (tracker == null) return false;

    final occurrences = tracker.getOccurrencesInWindow(Duration(hours: rule.timeWindowHours));
    return occurrences >= rule.threshold && !_hasRecentReminder(rule.id);
  }

  /// 评估时间基础规则
  bool _evaluateTimeBasedRule(ReminderRule rule, SemanticAnalysisInput analysis) {
    // 检查是否有相关的未完成意图或任务
    final relatedKeywords = rule.relatedKeywords ?? [];
    final hasRelatedActivity = relatedKeywords.any((keyword) =>
    _keywordTrackers[keyword]?.hasRecentActivity(Duration(hours: rule.timeWindowHours)) ?? false);

    return hasRelatedActivity && !_hasRecentReminder(rule.id);
  }

  /// 评估上下文建议规则
  Future<bool> _evaluateContextualRule(ReminderRule rule, SemanticAnalysisInput analysis) async {
    // 使用LLM进行上下文分析
    return await _analyzeContextForReminder(rule, analysis);
  }

  /// 使用LLM分析上下文是否适合提醒
  Future<bool> _analyzeContextForReminder(ReminderRule rule, SemanticAnalysisInput analysis) async {
    try {
      final contextPrompt = '''
你是一个智能提醒助手。请分析当前对话上下文，判断是否适合发送特定类型的提醒。

【提醒规则】：
- 类型: ${rule.type.toString()}
- 目标关键词: ${rule.targetKeyword}
- 目标意图: ${rule.targetIntent}
- 描述: ${rule.description}

【当前对话内容】：
"${analysis.content}"

【用户当前情绪】：${analysis.emotion}
【检测到的实体】：${analysis.entities.join(', ')}
【检测到的意图】：${analysis.intent}

【判断标准】：
1. 提醒是否与当前话题相关
2. 用户当前状态是否适合接收提醒
3. 提醒是否有实际价值
4. 时机是否合适（不要在用户专注其他事情时打断）

请回答 "YES" 或 "NO"，并简单说明原因。
''';

      final llm = await LLM.create('gpt-4o-mini', systemPrompt: contextPrompt);
      final response = await llm.createRequest(content: analysis.content);

      return response.toUpperCase().contains('YES');

    } catch (e) {
      print('[IntelligentReminderManager] ❌ LLM上下文分析失败: $e');
      return false;
    }
  }

  /// 安排提醒
  Future<void> _scheduleReminder(ReminderRule rule, SemanticAnalysisInput analysis) async {
    final reminderId = '${rule.id}_${DateTime.now().millisecondsSinceEpoch}';

    if (_sentReminderIds.contains(reminderId)) return;

    // 🔥 新增：检查是否太频繁发送提醒
    if (!_canSendReminderNow()) {
      print('[IntelligentReminderManager] ⚠️ 提醒发送过于频繁，延迟处理');
      return;
    }

    // 🔥 修改：使用智能调度，避免集中发送
    final scheduledTime = _calculateOptimalReminderTime(rule);

    // 生成个性化提醒内容
    final reminderContent = await _generateReminderContent(rule, analysis);

    // 🔥 新增：直接创建TodoEntity而不是PendingReminder
    await _createReminderTodo(rule, analysis, reminderContent, scheduledTime, reminderId);
  }

  /// 🔥 新增：创建提醒任务
  Future<void> _createReminderTodo(
      ReminderRule rule,
      SemanticAnalysisInput analysis,
      String content,
      DateTime scheduledTime,
      String reminderId
      ) async {
    try {
      final todo = TodoEntity(
        task: _generateReminderTitle(rule, content),
        detail: content,
        deadline: scheduledTime.millisecondsSinceEpoch,
        status: Status.intelligent_suggestion, // 🔥 修改：智能建议使用专门的状态
        isIntelligentReminder: true,
        originalText: analysis.content,
        reminderType: 'intelligent',
        ruleId: rule.id,
        confidence: null,
      );

      // 保存到数据库
      ObjectBoxService().createTodos([todo]);

      // 标记为已处理
      _sentReminderIds.add(reminderId);
      _recentReminderTimes.add(DateTime.now());

      // 发送通知到聊天
      await _sendReminderNotification(todo, rule);

      print('[IntelligentReminderManager] ✅ 创建智能提醒任务: ${todo.task}');

    } catch (e) {
      print('[IntelligentReminderManager] ❌ 创建提醒任务失败: $e');
    }
  }

  /// 🔥 新增：生成提醒标题
  String _generateReminderTitle(ReminderRule rule, String content) {
    switch (rule.type) {
      case ReminderType.keywordFrequency:
        return '💡 ${rule.targetKeyword}相关提醒';
      case ReminderType.intentPattern:
        return '📋 ${rule.targetIntent}跟进提醒';
      case ReminderType.timeBasedFollow:
        return '⏰ 定时跟进提醒';
      case ReminderType.contextualSuggestion:
        return '🎯 智能建议提醒';
      default:
        return '🔔 智能提醒';
    }
  }

  /// 🔥 新增：发送提醒通知到聊天
  Future<void> _sendReminderNotification(TodoEntity todo, ReminderRule rule) async {
    try {
      if (_chatController == null) return;


      final message = '${todo.task}\n📝 ${todo.detail}\n';

      final reminderMessage = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'text': message,
        'isUser': 'assistant',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'type': 'intelligent_reminder_created',
        'todo_id': todo.id.toString(),
      };

      _chatController!.addSystemMessage(reminderMessage);

    } catch (e) {
      print('[IntelligentReminderManager] ❌ 发送提醒通知失败: $e');
    }
  }

  /// 启动提醒检查定时器
  void _startReminderTimer() {
    _reminderCheckTimer = Timer.periodic(Duration(seconds: _checkInterval), (timer) {
      _processScheduledReminders();
    });
  }

  /// 启动分析定时器
  void _startAnalysisTimer() {
    _analysisTimer = Timer.periodic(Duration(seconds: _analysisInterval), (timer) {
      _performPeriodicAnalysis();
    });
  }

  /// 处理预定的提醒
  void _processScheduledReminders() async {
    final now = DateTime.now();
    final readyReminders = _pendingReminders.where((r) => r.scheduledTime.isBefore(now)).toList();

    for (final reminder in readyReminders) {
      await _sendReminder(reminder);
      _pendingReminders.remove(reminder);
    }
  }

  /// 发送提醒消息
  Future<void> _sendReminder(PendingReminder reminder) async {
    try {
      if (_chatController == null) {
        print('[IntelligentReminderManager] ⚠️ ChatController未设置，无法发送提醒');
        return;
      }

      // 创建assistant角色的消息
      final reminderMessage = {
        'id': reminder.id,
        'text': reminder.content,
        'isUser': 'assistant', // 使用字符串形式的角色标识
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'type': 'intelligent_reminder',
        'rule_type': reminder.rule.type.toString(),
      };

      // 注入到聊天系统
      _chatController!.addSystemMessage(reminderMessage);

      // 标记为已发送
      _sentReminderIds.add(reminder.id);

      // 更新每小时计数
      final currentHour = DateTime.now().hour;
      _hourlyReminderCount[currentHour] = (_hourlyReminderCount[currentHour] ?? 0) + 1;

      // 🔥 新增：记录最近发送的提醒时间
      _recentReminderTimes.add(DateTime.now());

      print('[IntelligentReminderManager] 💬 发送智能提醒: ${reminder.content}');

    } catch (e) {
      print('[IntelligentReminderManager] ❌ 发送提醒失败: $e');
    }
  }

  /// 执行定期分析
  void _performPeriodicAnalysis() {
    try {
      // 清理过期数据
      _cleanupExpiredData();

      // 分析新的模式
      _analyzeEmergingPatterns();

      // 动态调整规则
      _adjustReminderRules();

    } catch (e) {
      print('[IntelligentReminderManager] ❌ 定期分析失败: $e');
    }
  }

  /// 提取关键词
  List<String> _extractKeywords(String content) {
    final keywords = <String>[];
    final words = content.toLowerCase().split(RegExp(r'\s+'));

    // 技术关键词
    final techKeywords = ['flutter', 'ai', '人工智能', '机器学习', '数据库', '优化', 'bug', '性能'];

    // 工作关键词
    final workKeywords = ['项目', '工作', '会议', '任务', '计划', '规划', 'deadline', '进度'];

    // 学习关键词
    final learnKeywords = ['学习', '教程', '了解', '研究', '掌握', '理解'];

    // 生活关键词
    final lifeKeywords = ['健康', '运动', '休息', '睡觉', '吃饭', '放松'];

    final allKeywords = [...techKeywords, ...workKeywords, ...learnKeywords, ...lifeKeywords];

    for (final word in words) {
      if (allKeywords.contains(word)) {
        keywords.add(word);
      }
    }

    return keywords.toSet().toList();
  }

  /// 加载默认提醒规则
  Future<void> _loadDefaultReminderRules() async {
    _activeRules.addAll([
      // 学习提醒规则
      ReminderRule(
        id: 'learning_follow_up',
        type: ReminderType.keywordFrequency,
        targetKeyword: '学习',
        threshold: 3,
        timeWindowHours: 24,
        delaySeconds: 1800, // 30分钟后提醒
        description: '学习跟进提醒',
        defaultMessage: '我注意到你最近经常提到学习，要不要我帮你制定一个学习计划？',
      ),

      // 项目进度提醒
      ReminderRule(
        id: 'project_progress',
        type: ReminderType.intentPattern,
        targetIntent: 'planning',
        threshold: 2,
        timeWindowHours: 12,
        delaySeconds: 3600, // 1小时后提醒
        description: '项目进度跟进',
        defaultMessage: '你之前提到的项目计划，现在进展如何？需要我帮你回顾一下要点吗？',
      ),

      // 问题解决提醒
      ReminderRule(
        id: 'problem_solving_follow',
        type: ReminderType.keywordFrequency,
        targetKeyword: 'bug',
        threshold: 2,
        timeWindowHours: 6,
        delaySeconds: 2700, // 45分钟后提醒
        description: '问题解决跟进',
        defaultMessage: '刚才讨论的那个bug解决了吗？如果还有困难，我可以帮你分析一下。',
      ),

      // 健康提醒
      ReminderRule(
        id: 'health_reminder',
        type: ReminderType.timeBasedFollow,
        targetKeyword: '工作',
        threshold: 1,
        timeWindowHours: 3,
        delaySeconds: 5400, // 1.5小时后提醒
        description: '健康休息提醒',
        defaultMessage: '你已经专注工作一段时间了，要不要起来活动一下，休息休息眼睛？',
        relatedKeywords: ['项目', '开发', '编程'],
      ),

      // 上下文建议提醒
      ReminderRule(
        id: 'contextual_suggestion',
        type: ReminderType.contextualSuggestion,
        targetIntent: 'information_seeking',
        threshold: 1,
        timeWindowHours: 2,
        delaySeconds: 1200, // 20分钟后提醒
        description: '上下文智能建议',
        defaultMessage: '根据你刚才的问题，我想到了一些相关的建议，要听听吗？',
      ),
    ]);

    print('[IntelligentReminderManager] ✅ 加载了 ${_activeRules.length} 个默认提醒规则');
  }

  /// 检查是否有最近的提醒
  bool _hasRecentReminder(String ruleId) {
    return _sentReminderIds.any((id) => id.startsWith(ruleId));
  }

  /// 清理过期的追踪器
  void _cleanupExpiredTrackers() {
    final cutoffTime = DateTime.now().subtract(Duration(days: 7));

    _keywordTrackers.removeWhere((key, tracker) => tracker.lastActivity.isBefore(cutoffTime));
    _intentTrackers.removeWhere((key, tracker) => tracker.lastActivity.isBefore(cutoffTime));
  }

  /// 清理过期数据
  void _cleanupExpiredData() {
    final now = DateTime.now();

    // 清理过期的提醒ID
    _sentReminderIds.removeWhere((id) {
      final parts = id.split('_');
      if (parts.length < 2) return true;

      try {
        final timestamp = int.parse(parts.last);
        final reminderTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        return now.difference(reminderTime).inDays > 7;
      } catch (e) {
        return true;
      }
    });

    // 清理过期的每小时计数
    _hourlyReminderCount.removeWhere((hour, count) => hour < now.hour - 24);
  }

  /// 分析新兴模式
  void _analyzeEmergingPatterns() {
    // 这里可以实现更复杂的模式分析逻辑
    print('[IntelligentReminderManager] 🔍 分析用户行为模式...');
  }

  /// 动态调整提醒规则
  void _adjustReminderRules() {
    // 这里可以实现基于用户反馈的规则调整逻辑
    print('[IntelligentReminderManager] ⚙️ 动态调整提醒规则...');
  }

  /// 获取统计信息
  Map<String, dynamic> getStatistics() {
    // 🔥 新增：合并自然语言提醒统计
    final nlStats = _nlReminderService.getStatistics();

    return {
      'keyword_trackers': _keywordTrackers.length,
      'intent_trackers': _intentTrackers.length,
      'active_rules': _activeRules.length,
      'pending_reminders': _pendingReminders.length,
      'sent_reminders_today': _sentReminderIds.where((id) {
        final parts = id.split('_');
        if (parts.length < 2) return false;
        try {
          final timestamp = int.parse(parts.last);
          final reminderTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
          return DateTime.now().difference(reminderTime).inDays == 0;
        } catch (e) {
          return false;
        }
      }).length,
      'hourly_reminder_count': _hourlyReminderCount,
      // 🔥 新增：自然语言提醒统计
      'natural_language_reminders': nlStats,
    };
  }

  /// 🔥 新增：获取自然语言提醒服务引用
  NaturalLanguageReminderService get naturalLanguageReminderService => _nlReminderService;

  /// 🔥 新增：手动创建提醒任务
  Future<TodoEntity?> createManualReminderTodo({
    required String title,
    String? description,
    required DateTime reminderTime,
    String type = 'manual',
  }) async {
    try {
      final todo = TodoEntity(
        task: title,
        detail: description ?? '',
        deadline: reminderTime.millisecondsSinceEpoch,
        status: Status.pending,
        isIntelligentReminder: type != 'manual',
        originalText: type == 'manual' ? null : description,
        reminderType: type,
        confidence: null,
      );

      ObjectBoxService().createTodos([todo]);
      return todo;

    } catch (e) {
      print('[IntelligentReminderManager] ❌ 创建手动提醒失败: $e');
      return null;
    }
  }

  /// 清理资源
  void dispose() {
    _reminderCheckTimer?.cancel();
    _analysisTimer?.cancel();
    _nlReminderService.dispose();
    print('[IntelligentReminderManager] 🧹 智能提醒管理器已清理');
  }

  /// 🔥 新增：检查是否可以发送提醒
  bool _canSendReminderNow() {
    final now = DateTime.now();

    // 清理过期的提醒时间记录
    _recentReminderTimes.removeWhere((time) =>
    now.difference(time).inMinutes > _minIntervalBetweenReminders ~/ 60);

    // 检查最近是否发送过提醒
    if (_recentReminderTimes.isNotEmpty) {
      final lastReminderTime = _recentReminderTimes.last;
      if (now.difference(lastReminderTime).inSeconds < _minIntervalBetweenReminders) {
        return false;
      }
    }

    // 检查今天是否已达到最大提醒数
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayReminders = _recentReminderTimes.where((time) =>
        time.isAfter(todayStart)).length;

    return todayReminders < _maxRemindersPerDay;
  }

  /// 🔥 新增：计算最优提醒时间
  DateTime _calculateOptimalReminderTime(ReminderRule rule) {
    final now = DateTime.now();
    var scheduledTime = now.add(Duration(seconds: rule.delaySeconds));

    // 避开用户可能忙碌的时间（深夜或早晨）
    if (scheduledTime.hour < 8) {
      scheduledTime = scheduledTime.copyWith(hour: 8, minute: 0);
    } else if (scheduledTime.hour > 22) {
      scheduledTime = scheduledTime.add(Duration(days: 1)).copyWith(hour: 9, minute: 0);
    }

    return scheduledTime;
  }

  /// 🔥 新增：生成个性化提醒内容
  Future<String> _generateReminderContent(ReminderRule rule, SemanticAnalysisInput analysis) async {
    try {
      final contentPrompt = '''
根据用户的对话内容和提醒规则，生成一个个性化的提醒内容。

【提醒规则】：
- 类型: ${rule.type.toString()}
- 目标关键词: ${rule.targetKeyword}
- 目标意图: ${rule.targetIntent}
- 默认消息: ${rule.defaultMessage}

【用户对话内容】：
"${analysis.content}"

【用户情绪】：${analysis.emotion}

请生成一个简洁、友好、有用的提醒内容，不超过100字。
''';

      final llm = await LLM.create('gpt-4o-mini', systemPrompt: contentPrompt);
      final response = await llm.createRequest(content: analysis.content);

      return response.trim().isNotEmpty ? response.trim() : rule.defaultMessage;
    } catch (e) {
      print('[IntelligentReminderManager] ❌ 生成提醒内容失败: $e');
      return rule.defaultMessage;
    }
  }

  /// 🔥 新增：格式化时间差
  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}天';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}小时';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}分钟';
    } else {
      return '现在';
    }
  }
}

/// 数据模型
class KeywordTracker {
  final String keyword;
  final List<DateTime> occurrences = [];
  DateTime lastActivity = DateTime.now();

  KeywordTracker(this.keyword);

  void addOccurrence(DateTime time) {
    occurrences.add(time);
    lastActivity = time;

    // 保留最近7天的数据
    final cutoff = time.subtract(Duration(days: 7));
    occurrences.removeWhere((t) => t.isBefore(cutoff));
  }

  double getFrequencyInWindow(Duration window) {
    final cutoff = DateTime.now().subtract(window);
    final recentOccurrences = occurrences.where((t) => t.isAfter(cutoff)).length;
    return recentOccurrences / window.inHours.toDouble();
  }

  bool hasRecentActivity(Duration window) {
    final cutoff = DateTime.now().subtract(window);
    return occurrences.any((t) => t.isAfter(cutoff));
  }
}

class IntentTracker {
  final String intent;
  final List<IntentOccurrence> occurrences = [];
  DateTime lastActivity = DateTime.now();

  IntentTracker(this.intent);

  void addOccurrence(DateTime time, List<String> entities) {
    occurrences.add(IntentOccurrence(time, entities));
    lastActivity = time;

    // 保留最近7天的数据
    final cutoff = time.subtract(Duration(days: 7));
    occurrences.removeWhere((o) => o.timestamp.isBefore(cutoff));
  }

  int getOccurrencesInWindow(Duration window) {
    final cutoff = DateTime.now().subtract(window);
    return occurrences.where((o) => o.timestamp.isAfter(cutoff)).length;
  }
}

class IntentOccurrence {
  final DateTime timestamp;
  final List<String> entities;

  IntentOccurrence(this.timestamp, this.entities);
}

enum ReminderType {
  keywordFrequency,    // 基于关键词频率
  intentPattern,       // 基于意图模式
  timeBasedFollow,     // 基于时间的跟进
  contextualSuggestion, // 上下文建议
}

class ReminderRule {
  final String id;
  final ReminderType type;
  final String? targetKeyword;
  final String? targetIntent;
  final double threshold;
  final int timeWindowHours;
  final int delaySeconds;
  final String description;
  final String defaultMessage;
  final List<String>? relatedKeywords;

  ReminderRule({
    required this.id,
    required this.type,
    this.targetKeyword,
    this.targetIntent,
    required this.threshold,
    required this.timeWindowHours,
    required this.delaySeconds,
    required this.description,
    required this.defaultMessage,
    this.relatedKeywords,
  });
}

class PendingReminder {
  final String id;
  final ReminderRule rule;
  final String content;
  final DateTime scheduledTime;
  final SemanticAnalysisInput context;

  PendingReminder({
    required this.id,
    required this.rule,
    required this.content,
    required this.scheduledTime,
    required this.context,
  });
}
