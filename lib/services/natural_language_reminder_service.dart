/// 自然语言提醒服务
/// 解析自然语言中的时间表达，自动创建和管理提醒

import 'dart:async';
import 'dart:convert';
import 'package:app/models/human_understanding_models.dart';
import 'package:app/services/llm.dart';
import 'package:app/controllers/chat_controller.dart';
// 🔥 修改：导入TodoEntity和ObjectBoxService，移除ReminderItem
import 'package:app/models/todo_entity.dart';
import 'package:app/services/objectbox_service.dart';

class NaturalLanguageReminderService {
  static final NaturalLanguageReminderService _instance = NaturalLanguageReminderService._internal();
  factory NaturalLanguageReminderService() => _instance;
  NaturalLanguageReminderService._internal();

  // 🔥 修改：提醒存储改为使用TodoEntity
  final StreamController<List<TodoEntity>> _remindersController = StreamController.broadcast();

  // 🔥 新增：重复检测机制
  final Set<String> _recentContentHashes = {};
  final Map<String, DateTime> _lastReminderByType = {};
  final List<String> _processedTexts = [];

  // 系统状态
  Timer? _reminderCheckTimer;
  Timer? _cleanupTimer;
  bool _initialized = false;
  ChatController? _chatController;

  // 配置参数
  static const int _checkInterval = 30; // 30秒检查一次
  static const int _cleanupInterval = 300; // 5分钟清理一次过期数据
  static const int _minIntervalBetweenSimilarReminders = 3600; // 同类型提醒最小间隔1小时
  static const double _minConfidenceThreshold = 0.8; // 🔥 提高置信度阈值到0.8
  static const int _maxProcessedTextsHistory = 100; // 最多保留100条处理历史

  /// 提醒列表更新流
  Stream<List<TodoEntity>> get remindersStream => _remindersController.stream;

  /// 获取所有智能提醒任务
  List<TodoEntity> get allReminders {
    try {
      // 🔥 修改：从数据库获取所有智能提醒任务
      final allTodos = ObjectBoxService().getAllTodos() ?? [];
      return allTodos.where((todo) =>
        todo.isIntelligentReminder &&
        todo.reminderType == 'natural_language'
      ).toList();
    } catch (e) {
      print('[NLReminderService] ❌ 获取提醒失败: $e');
      return [];
    }
  }

  /// 初始化服务
  Future<void> initialize({ChatController? chatController}) async {
    if (_initialized) return;

    print('[NLReminderService] 🚀 初始化自然语言提醒服务...');

    _chatController = chatController;

    // 启动定时检查
    _startReminderTimer();
    _startCleanupTimer();

    _initialized = true;
    print('[NLReminderService] ✅ 自然语言提醒服务初始化完成');
  }

  /// 处理语义分析输入，查找潜在的提醒需求
  Future<void> processSemanticAnalysis(SemanticAnalysisInput analysis) async {
    if (!_initialized) return;

    try {
      // 🔥 新增：预过滤，排除明显不需要提醒的内容
      if (!_shouldProcessForReminder(analysis.content)) {
        return;
      }

      // 🔥 新增：检查是否与最近处理的内容过于相似
      if (_isDuplicateContent(analysis.content)) {
        print('[NLReminderService] ⚠️ 检测到重复内容，跳过处理');
        return;
      }

      // 使用LLM分析是否包含时间相关的提醒信息
      final reminderInfo = await _extractReminderFromText(analysis.content);

      if (reminderInfo != null) {
        // 🔥 新增：严格验证提醒信息的有效性
        if (!_isValidReminderInfo(reminderInfo)) {
          print('[NLReminderService] ⚠️ 提醒信息验证失败，跳过创建');
          return;
        }

        final todo = await _createTodoFromInfo(reminderInfo, analysis);
        if (todo != null) {
          // 向用户确认提醒创建
          await _sendConfirmationMessage(todo);

          // 通知更新
          _notifyRemindersChanged();
        }
      }

      // 记录已处理的内容
      _recordProcessedContent(analysis.content);

    } catch (e) {
      print('[NLReminderService] ❌ 处理语义分析失败: $e');
    }
  }

  /// 使用LLM提取提醒信息
  Future<Map<String, dynamic>?> _extractReminderFromText(String content) async {
    try {
      final extractionPrompt = '''
你是一个时间提醒解析专家。请分析用户的话语，判断是否包含需要设置提醒的信息。

【重要提醒】：
请非常严格地判断，只有当用户明确表达了"需要在特定时间点做某件具体事情"时才创建提醒。

【必须满足的条件】：
1. 有明确的时间表达（如：明天8点、一小时后、下周三等）
2. 有具体的事件或任务（不能是模糊的"提醒"或"检查"）
3. 用户有明确的提醒意图（主动要求设置提醒）

【不应创建提醒的情况】：
- 用户只是在描述时间概念，没有具体任务
- 模糊的时间表达如"每小时"、"定时"等周期性描述
- 用户在询问时间相关问题，而非要求设置提醒
- 用户在讨论过去的事件
- 用户在做假设性陈述
- 包含"可能"、"也许"、"随便"等不确定词汇

【时间解析规则】：
- "明天上午9点"、"后天下午3点"等具体时间
- "一小时后"、"十分钟后"等相对时间（但必须有具体任务）
- 绝对不接受"每小时"、"定时"等周期性时间

【事件识别】：
- 必须是具体的约会、会议、面试、任务等
- 不能是模糊的"提醒"、"检查"等

【置信度要求】：
- 只有当你非常确定用户需要提醒时，才设置confidence > 0.8
- 任何不确定的情况都应该返回 {"has_reminder": false}

输出格式为JSON：
{
  "has_reminder": true/false,
  "event_description": "具体事件描述",
  "time_expression": "原始时间表达",
  "parsed_time": "解析后的时间(ISO 8601格式)",
  "reminder_type": "appointment|task|meeting",
  "confidence": 0.9,
  "context": "相关上下文"
}

如果没有明确的提醒需求，返回 {"has_reminder": false}

用户说的话：
"${content}"

当前时间：${DateTime.now().toIso8601String()}
''';

      final llm = await LLM.create('gpt-4o-mini', systemPrompt: extractionPrompt);
      final response = await llm.createRequest(content: content);

      print('[NLReminderService] 🤖 LLM响应: ${response.substring(0, response.length > 200 ? 200 : response.length)}...');

      // 提取JSON
      final jsonStart = response.indexOf('{');
      final jsonEnd = response.lastIndexOf('}');
      if (jsonStart == -1 || jsonEnd == -1) {
        print('[NLReminderService] ⚠️ LLM响应中未找到JSON');
        return null;
      }

      final jsonStr = response.substring(jsonStart, jsonEnd + 1);
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;

      // 🔥 提高置信度要求到0.8
      if (result['has_reminder'] == true && (result['confidence'] ?? 0) >= _minConfidenceThreshold) {
        return result;
      }

      return null;

    } catch (e) {
      print('[NLReminderService] ❌ LLM提取失败: $e');
      return null;
    }
  }

  /// 🔥 修改：从提醒信息创建TodoEntity
  Future<TodoEntity?> _createTodoFromInfo(Map<String, dynamic> info, SemanticAnalysisInput analysis) async {
    try {
      final eventDescription = info['event_description']?.toString() ?? '';
      final timeExpression = info['time_expression']?.toString() ?? '';
      final parsedTimeStr = info['parsed_time']?.toString() ?? '';
      final reminderType = info['reminder_type']?.toString() ?? 'task';
      final confidence = (info['confidence'] as num?)?.toDouble() ?? 0.5;

      if (eventDescription.isEmpty || parsedTimeStr.isEmpty) {
        print('[NLReminderService] ⚠️ 事件描述或时间为空');
        return null;
      }

      // 解析时间
      DateTime reminderTime;
      try {
        reminderTime = DateTime.parse(parsedTimeStr);
      } catch (e) {
        // 如果LLM给出的时间格式有问题，尝试自然语言时间解析
        reminderTime = await _parseNaturalLanguageTime(timeExpression);
      }

      // 确保提醒时间在未来
      if (reminderTime.isBefore(DateTime.now())) {
        print('[NLReminderService] ⚠️ 提醒时间已过期: $reminderTime');
        return null;
      }

      // 生成提醒标题
      final title = _generateReminderTitle(eventDescription, reminderType);

      final todo = TodoEntity(
        task: title,
        detail: eventDescription,
        deadline: reminderTime.millisecondsSinceEpoch,
        status: Status.pending,
        isIntelligentReminder: true,
        originalText: analysis.content,
        reminderType: 'natural_language',
        confidence: confidence,
      );

      // 保存到数据库
      ObjectBoxService().createTodos([todo]);

      print('[NLReminderService] ✅ 创建自然语言提醒任务: $title, 时间: $reminderTime');
      return todo;

    } catch (e) {
      print('[NLReminderService] ❌ 创建提醒任务失败: $e');
      return null;
    }
  }

  /// 解析自然语言时间表达
  Future<DateTime> _parseNaturalLanguageTime(String timeExpression) async {
    final now = DateTime.now();
    final lowerExpression = timeExpression.toLowerCase();

    // 相对时间解析
    if (lowerExpression.contains('分钟后')) {
      final minuteMatch = RegExp(r'(\d+)分钟后').firstMatch(lowerExpression);
      if (minuteMatch != null) {
        final minutes = int.parse(minuteMatch.group(1)!);
        return now.add(Duration(minutes: minutes));
      }
    }

    if (lowerExpression.contains('小时后')) {
      final hourMatch = RegExp(r'(\d+)小时后').firstMatch(lowerExpression);
      if (hourMatch != null) {
        final hours = int.parse(hourMatch.group(1)!);
        return now.add(Duration(hours: hours));
      }
    }

    if (lowerExpression.contains('明天')) {
      var tomorrow = now.add(Duration(days: 1));

      // 检查是否有具体时间
      if (lowerExpression.contains('晚上')) {
        final timeMatch = RegExp(r'(\d+)点').firstMatch(lowerExpression);
        if (timeMatch != null) {
          int hour = int.parse(timeMatch.group(1)!);
          if (hour < 12) hour += 12; // 晚上时间
          tomorrow = tomorrow.copyWith(hour: hour, minute: 0, second: 0);
        } else {
          tomorrow = tomorrow.copyWith(hour: 19, minute: 0, second: 0); // 默认晚上7点
        }
      } else if (lowerExpression.contains('上午')) {
        final timeMatch = RegExp(r'(\d+)点').firstMatch(lowerExpression);
        if (timeMatch != null) {
          final hour = int.parse(timeMatch.group(1)!);
          tomorrow = tomorrow.copyWith(hour: hour, minute: 0, second: 0);
        } else {
          tomorrow = tomorrow.copyWith(hour: 9, minute: 0, second: 0); // 默认上午9点
        }
      } else if (lowerExpression.contains('下午')) {
        final timeMatch = RegExp(r'(\d+)点').firstMatch(lowerExpression);
        if (timeMatch != null) {
          int hour = int.parse(timeMatch.group(1)!);
          if (hour < 12) hour += 12; // 下午时间
          tomorrow = tomorrow.copyWith(hour: hour, minute: 0, second: 0);
        } else {
          tomorrow = tomorrow.copyWith(hour: 14, minute: 0, second: 0); // 默认下午2点
        }
      }

      return tomorrow;
    }

    if (lowerExpression.contains('后天')) {
      return now.add(Duration(days: 2)).copyWith(hour: 9, minute: 0, second: 0);
    }

    // 默认返回1小时后
    return now.add(Duration(hours: 1));
  }

  /// 生成提醒标题
  String _generateReminderTitle(String description, String type) {
    switch (type) {
      case 'appointment':
        return '约会提醒';
      case 'meeting':
        return '会议提醒';
      case 'task':
        return '任务提醒';
      case 'check':
        return '检查提醒';
      default:
        return description.length > 10 ? description.substring(0, 10) + '...' : description;
    }
  }

  /// 🔥 修改：添加提醒（已经不需要，因为直接保存到数据库）
  Future<void> addReminder(TodoEntity reminder) async {
    // 这个方法保留兼容性，但实际不做任何操作
    // 因为提醒已经在创建时直接保存到数据库
    _notifyRemindersChanged();
  }

  /// 🔥 修改：更新提醒
  Future<void> updateReminder(TodoEntity updatedReminder) async {
    try {
      ObjectBoxService().updateTodo(updatedReminder);
      _notifyRemindersChanged();
    } catch (e) {
      print('[NLReminderService] ❌ 更新提醒失败: $e');
    }
  }

  /// 🔥 修改：删除提醒
  Future<void> deleteReminder(String reminderId) async {
    try {
      final id = int.tryParse(reminderId);
      if (id != null) {
        ObjectBoxService().deleteTodo(id);
        _notifyRemindersChanged();
      }
    } catch (e) {
      print('[NLReminderService] ❌ 删除提醒失败: $e');
    }
  }

  /// 🔥 修改：标记提醒为完成
  Future<void> markReminderCompleted(String reminderId) async {
    try {
      final id = int.tryParse(reminderId);
      if (id != null) {
        final allTodos = ObjectBoxService().getAllTodos() ?? [];
        final todo = allTodos.where((t) => t.id == id).firstOrNull;
        if (todo != null) {
          todo.status = Status.completed;
          ObjectBoxService().updateTodo(todo);
          _notifyRemindersChanged();
        }
      }
    } catch (e) {
      print('[NLReminderService] ❌ 标记提醒完成失败: $e');
    }
  }

  /// 通知提醒列表变化
  void _notifyRemindersChanged() {
    if (!_remindersController.isClosed) {
      _remindersController.add(allReminders);
    }
  }

  /// 启动提醒检查定时器
  void _startReminderTimer() {
    _reminderCheckTimer?.cancel();
    _reminderCheckTimer = Timer.periodic(Duration(seconds: _checkInterval), (timer) {
      _checkDueReminders();
    });
    print('[NLReminderService] ⏰ 提醒检查定时器已启动，间隔: ${_checkInterval}秒');
  }

  /// 启动清理定时器
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(Duration(seconds: _cleanupInterval), (timer) {
      _cleanupExpiredReminders();
    });
    print('[NLReminderService] 🧹 清理定时器已启动，间隔: ${_cleanupInterval}秒');
  }

  /// 检查到期的提醒
  void _checkDueReminders() async {
    final now = DateTime.now();
    final reminders = allReminders;

    final dueReminders = reminders.where((reminder) =>
        reminder.status == Status.pending &&
        reminder.deadline != null &&
        reminder.deadline! <= now.millisecondsSinceEpoch + 60000 && // 1分钟内
        reminder.deadline! > now.millisecondsSinceEpoch - 300000    // 5分钟前
    ).toList();

    for (final reminder in dueReminders) {
      await _triggerReminder(reminder);
    }
  }

  /// 清理过期的提醒
  void _cleanupExpiredReminders() {
    // 这里可以添加清理逻辑，但考虑到用户可能想查看过期的提醒，暂时保留
    print('[NLReminderService] 🧹 清理检查完成');
  }

  /// 触发提醒
  Future<void> _triggerReminder(TodoEntity reminder) async {
    try {
      print('[NLReminderService] 🔔 触发提醒: ${reminder.task}');

      // 发送提醒消息到聊天
      if (_chatController != null) {
        final message = '🔔 自然语言提醒：${reminder.task}\n📝 ${reminder.detail}';
        await _chatController!.sendSystemMessage(message);
      }

      // 这里可以添加其他提醒方式，如推送通知等

    } catch (e) {
      print('[NLReminderService] ❌ 触发提醒失败: $e');
    }
  }

  /// 🔥 修改：发送确认消息
  Future<void> _sendConfirmationMessage(TodoEntity reminder) async {
    try {
      if (_chatController != null) {
        final timeStr = _formatReminderTime(DateTime.fromMillisecondsSinceEpoch(reminder.deadline!));
        final message = '✅ 已为您创建自然语言提醒：${reminder.task}\n⏰ 提醒时间：$timeStr';
        await _chatController!.sendSystemMessage(message);
      }
    } catch (e) {
      print('[NLReminderService] ❌ 发送确认消息失败: $e');
    }
  }

  /// 格式化提醒时间
  String _formatReminderTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = dateTime.difference(now);

    if (difference.inDays > 0) {
      return '${difference.inDays}天后 ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时${difference.inMinutes % 60}分钟后';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟后';
    } else {
      return '现在';
    }
  }

  /// 获取服务状态
  Map<String, dynamic> getServiceStatus() {
    final reminders = allReminders; // 🔥 修复：使用allReminders getter
    return {
      'initialized': _initialized,
      'reminder_count': reminders.length,
      'active_reminders': reminders.where((r) => r.status == Status.pending).length,
      'completed_reminders': reminders.where((r) => r.status == Status.completed).length,
      'timer_active': _reminderCheckTimer?.isActive ?? false,
      'check_interval_seconds': _checkInterval,
    };
  }

  /// 获取统计信息
  Map<String, dynamic> getStatistics() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(Duration(days: 1));

    final reminders = allReminders;
    final todayReminders = reminders.where((r) =>
        r.deadline != null &&
        r.deadline! >= todayStart.millisecondsSinceEpoch &&
        r.deadline! < todayEnd.millisecondsSinceEpoch
    ).toList();

    return {
      'total_reminders': reminders.length,
      'active_reminders': reminders.where((r) => r.status == Status.pending).length,
      'completed_reminders': reminders.where((r) => r.status == Status.completed).length,
      'today_reminders': todayReminders.length,
      'overdue_reminders': reminders.where((r) =>
          r.status == Status.pending &&
          r.deadline != null &&
          r.deadline! < now.millisecondsSinceEpoch
      ).length,
      'upcoming_reminders': reminders.where((r) =>
          r.status == Status.pending &&
          r.deadline != null &&
          r.deadline! > now.millisecondsSinceEpoch
      ).length,
    };
  }

  /// 🔥 修改：手动创建提醒
  Future<TodoEntity?> createManualReminder({
    required String title,
    String? description,
    required DateTime reminderTime,
    String type = 'natural_language',
  }) async {
    try {
      final todo = TodoEntity(
        task: title,
        detail: description ?? '',
        deadline: reminderTime.millisecondsSinceEpoch,
        status: Status.pending,
        isIntelligentReminder: true,
        originalText: '手动创建：$title',
        reminderType: type,
      );

      ObjectBoxService().createTodos([todo]);

      // 发送确认消息
      await _sendConfirmationMessage(todo);

      // 通知更新
      _notifyRemindersChanged();

      return todo;

    } catch (e) {
      print('[NLReminderService] ❌ 创建手动提醒失败: $e');
      return null;
    }
  }

  /// 清理资源
  void dispose() {
    _reminderCheckTimer?.cancel();
    _cleanupTimer?.cancel();
    _remindersController.close();
    _initialized = false;
    print('[NLReminderService] 🧹 自然语言提醒服务已清理');
  }

  /// 计算提醒内容的哈希值
  String _hashReminderContent(TodoEntity reminder) {
    final content = '${reminder.task}|${reminder.detail}|${reminder.deadline}';
    return content.hashCode.toString();
  }

  /// 更新重复检测记录
  void _updateContentHashRecord(String contentHash, DateTime reminderTime) {
    _recentContentHashes.add(contentHash);

    // 清理过期的哈希记录
    _recentContentHashes.removeWhere((hash) =>
        _lastReminderByType[hash]?.isBefore(reminderTime.subtract(Duration(hours: 1))) ?? true
    );

    // 更新最后提醒时间
    _lastReminderByType[contentHash] = reminderTime;

    // 限制处理历史记录数量
    if (_processedTexts.length > _maxProcessedTextsHistory) {
      final oldestText = _processedTexts.removeAt(0);
      _recentContentHashes.removeWhere((hash) => hash == oldestText);
      _lastReminderByType.remove(oldestText);
    }
  }

  /// 预过滤，排除明显不需要提醒的内容
  bool _shouldProcessForReminder(String content) {
    final lowerContent = content.toLowerCase();

    // 🔥 新增：更严格的过滤条件
    // 排除包含无意义词汇的内容
    final meaninglessWords = ['随便', '没事', '算了', '不用', '无所谓', '可能', '也许', '或许'];
    if (meaninglessWords.any((word) => lowerContent.contains(word))) {
      print('[NLReminderService] ⚠️ 内容包含无意义词汇，跳过处理');
      return false;
    }

    // 排除周期性时间表达
    final periodicExpressions = ['每小时', '定时', '每天', '每周', '每月', '定期', '周期性'];
    if (periodicExpressions.any((expr) => lowerContent.contains(expr))) {
      print('[NLReminderService] ⚠️ 检测到周期性时间表达，跳过处理');
      return false;
    }

    // 排除疑问句（通常是在询问，而非设置提醒）
    if (lowerContent.contains('?') || lowerContent.contains('？') ||
        lowerContent.contains('什么时候') || lowerContent.contains('多久') ||
        lowerContent.contains('怎么') || lowerContent.contains('为什么')) {
      print('[NLReminderService] ⚠️ 检测到疑问句，跳过处理');
      return false;
    }

    // 排除过去时表达
    final pastExpressions = ['昨天', '前天', '上周', '上个月', '之前', '已经', '刚才'];
    if (pastExpressions.any((expr) => lowerContent.contains(expr))) {
      print('[NLReminderService] ⚠️ 检测到过去时表达，跳过处理');
      return false;
    }

    // 内容长度过短，可能信息不充分
    if (content.trim().length < 5) {
      print('[NLReminderService] ⚠️ 内容过短，跳过处理');
      return false;
    }

    return true;
  }

  /// 检查内容是否与最近处理的内容过于相似
  bool _isDuplicateContent(String content) {
    final contentHash = content.hashCode.toString();

    // 检查哈希值是否在最近处理记录中
    if (_recentContentHashes.contains(contentHash)) {
      return true;
    }

    return false;
  }

  /// 严格验证提醒信息的有效性
  bool _isValidReminderInfo(Map<String, dynamic> info) {
    // 检查必需字段
    if (info['event_description'] == null || info['parsed_time'] == null) {
      return false;
    }

    // 检查置信度
    final confidence = (info['confidence'] as num?)?.toDouble() ?? 0.5;
    if (confidence < _minConfidenceThreshold) {
      return false;
    }

    return true;
  }

  /// 记录已处理的内容
  void _recordProcessedContent(String content) {
    final contentHash = content.hashCode.toString();
    _processedTexts.add(content);

    // 更新重复检测记录
    _recentContentHashes.add(contentHash);

    // 限制处理历史记录数量
    if (_processedTexts.length > _maxProcessedTextsHistory) {
      final oldestText = _processedTexts.removeAt(0);
      _recentContentHashes.removeWhere((hash) => hash == oldestText);
      _lastReminderByType.remove(oldestText);
    }
  }
}
