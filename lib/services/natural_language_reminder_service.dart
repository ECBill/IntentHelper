/// 自然语言提醒服务
/// 解析自然语言中的时间表达，自动创建和管理提醒

import 'dart:async';
import 'dart:convert';
import 'package:app/models/human_understanding_models.dart';
import 'package:app/services/llm.dart';
import 'package:app/controllers/chat_controller.dart';
import 'package:app/views/reminder_management_screen.dart';

class NaturalLanguageReminderService {
  static final NaturalLanguageReminderService _instance = NaturalLanguageReminderService._internal();
  factory NaturalLanguageReminderService() => _instance;
  NaturalLanguageReminderService._internal();

  // 提醒存储
  final List<ReminderItem> _reminders = [];
  final StreamController<List<ReminderItem>> _remindersController = StreamController.broadcast();

  // 系统状态
  Timer? _reminderCheckTimer;
  bool _initialized = false;
  ChatController? _chatController;

  // 配置参数
  static const int _checkInterval = 30; // 30秒检查一次

  /// 提醒列表更新流
  Stream<List<ReminderItem>> get remindersStream => _remindersController.stream;

  /// 获取所有提醒
  List<ReminderItem> get allReminders => List.unmodifiable(_reminders);

  /// 初始化服务
  Future<void> initialize({ChatController? chatController}) async {
    if (_initialized) return;

    print('[NLReminderService] 🚀 初始化自然语言提醒服务...');

    _chatController = chatController;

    // 启动定时检查
    _startReminderTimer();

    _initialized = true;
    print('[NLReminderService] ✅ 自然语言提醒服务初始化完成');
  }

  /// 处理语义分析输入，查找潜在的提醒需求
  Future<void> processSemanticAnalysis(SemanticAnalysisInput analysis) async {
    if (!_initialized) return;

    try {
      // 使用LLM分析是否包含时间相关的提醒信息
      final reminderInfo = await _extractReminderFromText(analysis.content);

      if (reminderInfo != null) {
        final reminder = await _createReminderFromInfo(reminderInfo, analysis);
        if (reminder != null) {
          await addReminder(reminder);

          // 向用户确认提醒创建
          await _sendConfirmationMessage(reminder);
        }
      }

    } catch (e) {
      print('[NLReminderService] ❌ 处理语义分析失败: $e');
    }
  }

  /// 使用LLM提取提醒信息
  Future<Map<String, dynamic>?> _extractReminderFromText(String content) async {
    try {
      final extractionPrompt = '''
你是一个时间提醒解析专家。请分析用户的话语，判断是否包含需要设置提醒的信息。

【分析要点】：
1. 寻找明确的时间表达（如：明天8点、一小时后、下周三等）
2. 识别需要提醒的事件或任务
3. 判断是否有明确的提醒意图

【时间解析规则】：
- "明天"、"后天"等相对日期
- "一小时后"、"十分钟后"等相对时间
- "晚上八点"、"下午三点"等具体时间
- "下周三"、"本周五"等相对星期

【事件识别】：
- 约会、会议、面试等
- 任务、工作、事情等
- 提醒、检查、确认等

输出格式为JSON：
{
  "has_reminder": true/false,
  "event_description": "事件描述",
  "time_expression": "原始时间表达",
  "parsed_time": "解析后的时间(ISO 8601格式)",
  "reminder_type": "appointment|task|check|reminder",
  "confidence": 0.8,
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

      if (result['has_reminder'] == true && (result['confidence'] ?? 0) > 0.6) {
        return result;
      }

      return null;

    } catch (e) {
      print('[NLReminderService] ❌ LLM提取失败: $e');
      return null;
    }
  }

  /// 从提醒信息创建提醒对象
  Future<ReminderItem?> _createReminderFromInfo(Map<String, dynamic> info, SemanticAnalysisInput analysis) async {
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

      final reminder = ReminderItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        description: eventDescription,
        reminderTime: reminderTime,
        originalText: analysis.content,
        createdAt: DateTime.now(),
      );

      print('[NLReminderService] ✅ 创建提醒: $title, 时间: $reminderTime');
      return reminder;

    } catch (e) {
      print('[NLReminderService] ❌ 创建提醒失败: $e');
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

  /// 添加提醒
  Future<void> addReminder(ReminderItem reminder) async {
    _reminders.add(reminder);
    _reminders.sort((a, b) => a.reminderTime.compareTo(b.reminderTime));
    _notifyRemindersChanged();
  }

  /// 更新提醒
  Future<void> updateReminder(ReminderItem updatedReminder) async {
    final index = _reminders.indexWhere((r) => r.id == updatedReminder.id);
    if (index != -1) {
      _reminders[index] = updatedReminder;
      _reminders.sort((a, b) => a.reminderTime.compareTo(b.reminderTime));
      _notifyRemindersChanged();
    }
  }

  /// 删除提醒
  Future<void> deleteReminder(String reminderId) async {
    _reminders.removeWhere((r) => r.id == reminderId);
    _notifyRemindersChanged();
  }

  /// 标记提醒为完成
  Future<void> markReminderCompleted(String reminderId) async {
    final index = _reminders.indexWhere((r) => r.id == reminderId);
    if (index != -1) {
      _reminders[index] = _reminders[index].copyWith(isCompleted: true);
      _notifyRemindersChanged();
    }
  }

  /// 通知提醒列表变化
  void _notifyRemindersChanged() {
    if (!_remindersController.isClosed) {
      _remindersController.add(List.unmodifiable(_reminders));
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

  /// 检查到期的提醒
  void _checkDueReminders() async {
    final now = DateTime.now();
    final dueReminders = _reminders.where((reminder) =>
        !reminder.isCompleted &&
        reminder.reminderTime.isBefore(now.add(Duration(minutes: 1))) &&
        reminder.reminderTime.isAfter(now.subtract(Duration(minutes: 5)))
    ).toList();

    for (final reminder in dueReminders) {
      await _triggerReminder(reminder);
    }
  }

  /// 触发提醒
  Future<void> _triggerReminder(ReminderItem reminder) async {
    try {
      print('[NLReminderService] 🔔 触发提醒: ${reminder.title}');

      // 发送提醒消息到聊天
      if (_chatController != null) {
        final message = '🔔 提醒：${reminder.title}\n${reminder.description}';
        await _chatController!.sendSystemMessage(message);
      }

      // 这里可以添加其他提醒方式，如推送通知等

    } catch (e) {
      print('[NLReminderService] ❌ 触发提醒失败: $e');
    }
  }

  /// 发送确认消息
  Future<void> _sendConfirmationMessage(ReminderItem reminder) async {
    try {
      if (_chatController != null) {
        final timeStr = _formatReminderTime(reminder.reminderTime);
        final message = '✅ 已为您创建提醒：${reminder.title}\n⏰ 提醒时间：$timeStr';
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
    return {
      'initialized': _initialized,
      'reminder_count': _reminders.length,
      'active_reminders': _reminders.where((r) => !r.isCompleted).length,
      'completed_reminders': _reminders.where((r) => r.isCompleted).length,
      'timer_active': _reminderCheckTimer?.isActive ?? false,
      'check_interval_seconds': _checkInterval,
    };
  }

  /// 获取统计信息
  Map<String, dynamic> getStatistics() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(Duration(days: 1));

    final todayReminders = _reminders.where((r) =>
        r.reminderTime.isAfter(todayStart) && r.reminderTime.isBefore(todayEnd)
    ).toList();

    return {
      'total_reminders': _reminders.length,
      'active_reminders': _reminders.where((r) => !r.isCompleted).length,
      'completed_reminders': _reminders.where((r) => r.isCompleted).length,
      'today_reminders': todayReminders.length,
      'overdue_reminders': _reminders.where((r) =>
          !r.isCompleted && r.reminderTime.isBefore(now)
      ).length,
      'upcoming_reminders': _reminders.where((r) =>
          !r.isCompleted && r.reminderTime.isAfter(now)
      ).length,
    };
  }

  /// 手动创建提醒
  Future<void> createManualReminder({
    required String title,
    String? description,
    required DateTime reminderTime,
    String type = 'task', // 改为 String 类型
  }) async {
    final reminder = ReminderItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      description: description ?? '',
      reminderTime: reminderTime,
      originalText: '手动创建：$title',
      createdAt: DateTime.now(),
      isCompleted: false,
    );

    await addReminder(reminder);

    // 发送确认消息
    await _sendConfirmationMessage(reminder);
  }

  /// 清理资源
  void dispose() {
    _reminderCheckTimer?.cancel();
    _remindersController.close();
    _initialized = false;
    print('[NLReminderService] 🧹 自然语言提醒服务已清理');
  }
}
