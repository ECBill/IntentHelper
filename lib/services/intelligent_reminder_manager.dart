/// 智能提醒管理器
/// 基于用户对话中的关键词、意图和行为模式，主动发送个性化提醒

import 'dart:async';
import 'package:app/models/human_understanding_models.dart';
import 'package:app/services/llm.dart';
import 'package:app/controllers/chat_controller.dart';
import 'package:app/services/natural_language_reminder_service.dart'; // 🔥 新增
import 'package:app/views/reminder_management_screen.dart'; // 🔥 新增：导入 ReminderItem

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

  // 提醒计数器（防止过度提醒）
  final Map<int, int> _hourlyReminderCount = {};

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

    // 检查每小时提醒限制
    final currentHour = DateTime.now().hour;
    final hourlyCount = _hourlyReminderCount[currentHour] ?? 0;
    if (hourlyCount >= _maxRemindersPerHour) {
      print('[IntelligentReminderManager] ⚠️ 达到每小时提醒限制');
      return;
    }

    // 生成个性化提醒内容
    final reminderContent = await _generateReminderContent(rule, analysis);

    final reminder = PendingReminder(
      id: reminderId,
      rule: rule,
      content: reminderContent,
      scheduledTime: DateTime.now().add(Duration(seconds: rule.delaySeconds)),
      context: analysis,
    );

    _pendingReminders.add(reminder);
    print('[IntelligentReminderManager] 📅 安排提醒: ${rule.description} (${rule.delaySeconds}秒后)');
  }

  /// 生成个性化提醒内容
  Future<String> _generateReminderContent(ReminderRule rule, SemanticAnalysisInput analysis) async {
    try {
      final contentPrompt = '''
你是一个贴心的智能助手。请根据用户的对话历史和当前上下文，生成一个自然、有用的提醒消息。

【提醒类型】：${rule.type.toString()}
【提醒目标】：${rule.targetKeyword ?? rule.targetIntent}
【提醒描述】：${rule.description}

【用户近期对话】：
"${analysis.content}"

【用户情绪】：${analysis.emotion}
【相关实体】：${analysis.entities.join(', ')}

【生成要求】：
1. 语调自然友好，就像一个贴心的朋友
2. 提醒要有实际价值，不要空洞
3. 长度控制在30-50字
4. 可以结合用户的情绪状态调整语调
5. 避免过于正式或机械化的表达

【示例风格】：
- "我注意到你最近经常提到学习Flutter，要不要我帮你整理一个学习计划？"
- "看起来你对那个项目挺关注的，需要我提醒你明天跟进一下吗？"
- "你刚才提到的优化方案很有意思，要不要记录下来避免忘记？"

请生成一个合适的提醒消息：
''';

      final llm = await LLM.create('gpt-4o-mini', systemPrompt: contentPrompt);
      final response = await llm.createRequest(content: analysis.content);

      // 清理响应，移除引号和多余符号
      String cleanResponse = response.trim();
      if (cleanResponse.startsWith('"') && cleanResponse.endsWith('"')) {
        cleanResponse = cleanResponse.substring(1, cleanResponse.length - 1);
      }

      return cleanResponse.isNotEmpty ? cleanResponse : rule.defaultMessage;

    } catch (e) {
      print('[IntelligentReminderManager] ❌ 生成提醒内容失败: $e');
      return rule.defaultMessage;
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

  /// 🔥 新增：手动创建提醒的便捷方法
  Future<void> createManualReminder({
    required String title,
    String? description,
    required DateTime reminderTime,
    String type = 'task', // 改为 String 类型，添加 task 选项
  }) async {
    await _nlReminderService.createManualReminder(
      title: title,
      description: description,
      reminderTime: reminderTime,
      type: type,
    );
  }

  /// 🔥 新增：添加提醒方法
  Future<void> addReminder(ReminderItem reminder) async {
    await _nlReminderService.addReminder(reminder);
  }

  /// 🔥 新增：更新提醒方法
  Future<void> updateReminder(ReminderItem updatedReminder) async {
    await _nlReminderService.updateReminder(updatedReminder);
  }

  /// 🔥 新增：删除提醒方法
  Future<void> deleteReminder(String reminderId) async {
    await _nlReminderService.deleteReminder(reminderId);
  }

  /// 清理资源
  void dispose() {
    _reminderCheckTimer?.cancel();
    _analysisTimer?.cancel();
    _nlReminderService.dispose();
    print('[IntelligentReminderManager] 🧹 智能提醒管理器已清理');
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
