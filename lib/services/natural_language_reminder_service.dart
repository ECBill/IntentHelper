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
  final Set<String> _processingTexts = {}; // 🔥 新增：正在处理的文本，防止重复处理

  // 系统状态
  Timer? _reminderCheckTimer;
  Timer? _cleanupTimer;
  bool _initialized = false;
  ChatController? _chatController;

  // 配置参数
  static const int _checkInterval = 10; // 🔥 修复：缩短检查间隔到10秒，确保不错过提醒
  static const int _cleanupInterval = 300; // 5分钟清理一次过期数据
  static const double _minConfidenceThreshold = 0.7; // 🔥 降低置信度阈值到0.7，避免过于严格
  static const int _maxProcessedTextsHistory = 100; // 最多保留100条处理历史
  static const int _duplicateDetectionTimeWindow = 1800; // 🔥 新增：重复检测时间窗口30分钟

  /// 提醒列表更新流
  Stream<List<TodoEntity>> get remindersStream => _remindersController.stream;

  /// 获取所有智能提醒任务
  List<TodoEntity> get allReminders {
    try {
      // 🔥 修改：从数据库获取所有智能提醒任务
      final allTodos = ObjectBoxService().getAllTodos() ?? [];

      // 🔥 修复：正确的过滤条件，使用Status枚举而不是字符串比较
      final filtered = allTodos.where((todo) {
        final isIntelligent = todo.isIntelligentReminder;
        final isNaturalLanguage = todo.reminderType == 'natural_language';
        final isPendingReminder = todo.status == Status.pending_reminder;

        // 🔥 调试输出：帮助诊断问题
        // for (var i = 0; i < allTodos.length; i++) {
        //   final todo = allTodos[i];
        //   print('[NLReminderService] 📝 Todo #$i | id: ${todo.id}, title: ${todo.task}, deadline: ${todo.deadline}, '
        //       'isIntelligentReminder: ${todo.isIntelligentReminder}, reminderType: ${todo.reminderType}, '
        //       'status: ${todo.status}');
        // }
        // if (isIntelligent || isNaturalLanguage) {
        //   print('[NLReminderService] 📝 Todo #${todo.id} | '
        //       'title: ${todo.task}, '
        //       'deadline: ${todo.deadline}, '
        //       'isIntelligentReminder: ${todo.isIntelligentReminder}, '
        //       'reminderType: ${todo.reminderType}, '
        //       'status: ${todo.status}');
        // }

        return isNaturalLanguage && isPendingReminder;
      }).toList();

      print('[NLReminderService] 📊 过滤结果: ${filtered.length}/${allTodos.length} 条智能提醒');
      return filtered;
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
      // 🔥 新增：防止重复处理同一内容
      final contentKey = '${analysis.content}_${analysis.timestamp}';
      if (_processingTexts.contains(contentKey)) {
        print('[NLReminderService] ⚠️ 正在处理相同内容，跳过');
        return;
      }
      _processingTexts.add(contentKey);

      // 🔥 修复：简单重复检测 - 避免app启动时重复处理历史内容
      if (_processedTexts.contains(analysis.content)) {
        print('[NLReminderService] ⚠️ 内容已处理过，跳过: "${analysis.content.length > 30 ? analysis.content.substring(0, 30) + '...' : analysis.content}"');
        _processingTexts.remove(contentKey);
        return;
      }

      // 🔥 新增：预过滤，排除明显不需���提醒的内容
      if (!_shouldProcessForReminder(analysis.content)) {
        _processingTexts.remove(contentKey);
        return;
      }

      // 🔥 修改：使用数据库查询进行更准确的重复检测
      if (await _isDuplicateReminderInDatabase(analysis.content)) {
        print('[NLReminderService] ⚠️ 在数据库中检测到重复提醒，跳过处理');
        _processingTexts.remove(contentKey);
        return;
      }

      // 🔥 修复：提前记录已处理内容，防止重复
      _recordProcessedContent(analysis.content);

      // 使用LLM分析是否包含时间相关的提醒信息
      final reminderInfo = await _extractReminderFromText(analysis.content);

      if (reminderInfo != null) {
        // 🔥 新增：严格验证提醒信息的有效性
        if (!_isValidReminderInfo(reminderInfo)) {
          print('[NLReminderService] ⚠️ 提醒信息验证失败，跳过创建');
          _processingTexts.remove(contentKey);
          return;
        }

        // 🔥 新增：检查是否为无意义的提醒类型描述
        if (_isGenericReminderDescription(reminderInfo)) {
          print('[NLReminderService] ⚠️ 检测到无意义的提醒描述，跳过创建');
          _processingTexts.remove(contentKey);
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

      // 🔥 移除：删除重复的记录操作
      _processingTexts.remove(contentKey);

    } catch (e) {
      print('[NLReminderService] ❌ 处理语义分析失败: $e');
      // 清理处理标记
      final contentKey = '${analysis.content}_${analysis.timestamp}';
      _processingTexts.remove(contentKey);
    }
  }

  /// 使用LLM提取提醒信息
  Future<Map<String, dynamic>?> _extractReminderFromText(String content) async {
    try {
      final extractionPrompt = '''
你是一个时间提醒解析专家。请分析用户的话语，判断是否包含需要设置提醒的信息。

【目标】：
从用户的表达中提取一个明确的提醒事件，并返回唯一的绝对时间（ISO格式，精确到分钟）。

【重要规则】：
1. 只在用户明确表达了“需要在某个时间点做某件具体事情”时才创建提醒。
2. 无论用户使用的是“相对时间”还是“绝对时间”，你必须将其统一解析为**绝对时间**（ISO 8601格式）。
3. 输出的 time_expression 也只保留最终用于提醒的时间表达（不要列出多个时间）。

【必须满足的条件】：
✅ 明确时间（如：明天8点、一小时后、下周三等）
✅ 明确任务（如：开会、面试、买东西）
✅ 明确意图（表达出想要提醒的意图）

【��应创建提醒的情况】：
- 没有具体任务
- 时间模糊（如“每小时”、“定时”、“以后”）
- 在回顾过去或假设性表述
- 任务不明确（如“提醒我”、“看一下”）

【时间处理说明】：
- 你必须将所有时间解析为绝对时间（ISO 8601 格式）
- 即使用户说的是“59分钟后”，也要根据当前时间算出目标时��，并格式化为 `2025-08-27T12:00:00Z` 这种格式
- **输出的 parsed_time 必须统一为精确到分钟的绝对时间，秒和毫秒一律设为00**

【事件识别】：
- 必须是具体的动作（如：打电话、开会、去接孩子）
- 不接受抽象任务或模糊提醒（如“提醒我一下”、“看看”）

【置信度要求】：
- 只有在非常确信用户需要提醒的情况下，才设置 confidence > 0.8
- 任何不确定的情况都返回 {"has_reminder": false}

【输出格式】：
返回格式为 JSON：
{
  "has_reminder": true/false,
  "event_description": "具体事件描述",
  "time_expression": "用户原始时间表达（只保留一个）",
  "parsed_time": "解析后的绝对时间（ISO 8601格式）",
  "reminder_type": "appointment|task|meeting",
  "confidence": 0.9,
  "context": "相关上下文"
}

如果没有明确提醒需求，返回：
{"has_reminder": false}

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
        print('[NLReminderService] ⚠️ 事件描述或���间为空');
        return null;
      }

      // 🔥 新增：防止创建无意义的提醒描述
      if (_isInvalidDescription(eventDescription)) {
        print('[NLReminderService] ⚠️ 检测到无效的事件描述: $eventDescription');
        return null;
      }

      // 🔥 修复问题1：正确处理UTC时间转换
      DateTime reminderTime;
      try {
        // 解析LLM返回的时间字符串（假设是UTC格式）
        final parsedUtcTime = DateTime.parse(parsedTimeStr);
        // 🔥 修复：检查LLM给出的时间是否合理
        final now = DateTime.now();
        final nowUtc = now.toUtc();

        // 如果LLM给出的UTC时间与当前UTC时间差距过大，说明LLM理解错误，使用自然语言解析
        final timeDiffHours = parsedUtcTime.difference(nowUtc).inHours.abs();
        if (timeDiffHours > 2400) {
          print('[NLReminderService] ⚠️ LLM时间差距过大(${timeDiffHours}小时)，使用自然语言解析');
          reminderTime = await _parseNaturalLanguageTime(timeExpression);
        } else {
          // LLM给出的是UTC时间，但我们需要的是本地时间存储
          // 🔥 修复：LLM实际上是按照本地时间理解的，但标记为UTC
          // 所以我们需要将其视为本地时间
          reminderTime = DateTime(
            parsedUtcTime.year,
            parsedUtcTime.month,
            parsedUtcTime.day,
            parsedUtcTime.hour,
            parsedUtcTime.minute,
          );
        }
      } catch (e) {
        print('[NLReminderService] ⚠️ 解析LLM时间失败，尝试自然语言解析: $e');
        // 如果LLM给出的时间格式有问题，尝试自然语言时间解析
        reminderTime = await _parseNaturalLanguageTime(timeExpression);
      }

      // 🔥 修改：确保提醒时间在未来，并且时间精确到分钟（避免秒级差异导致的重复）
      reminderTime = DateTime(
          reminderTime.year,
          reminderTime.month,
          reminderTime.day,
          reminderTime.hour,
          reminderTime.minute,
          0, // 秒设为0
          0  // 毫秒设为0
      );

      // 🔥 修��：如果时间已过且是今天，自动调整到明天同一时间
      final now = DateTime.now();
      if (reminderTime.isBefore(now)) {
        if (reminderTime.day == now.day && reminderTime.month == now.month && reminderTime.year == now.year) {
          // 同一天但时间已过，调整到明天
          reminderTime = reminderTime.add(Duration(days: 1));
          print('[NLReminderService] 📅 时间已过，自动调整到明天: $reminderTime');
        } else {
          print('[NLReminderService] ⚠️ 提醒时间已过期: $reminderTime');
          return null;
        }
      }

      // 🔥 修改：生成更具体的提醒标题和描述
      final title = _generateSpecificReminderTitle(eventDescription, reminderType, analysis.content);
      final detail = _generateSpecificReminderDetail(eventDescription, reminderType, timeExpression);

      // 🔥 修复问题3：正确设置createdAt字段
      final createdAt = DateTime.now();
      final todo = TodoEntity(
        task: title,
        detail: detail,
        deadline: reminderTime.millisecondsSinceEpoch,
        status: Status.pending_reminder, // 🔥 修复问题4：统一使用Status.pending_reminder
        isIntelligentReminder: true,
        originalText: analysis.content,
        reminderType: 'natural_language',
        confidence: confidence,
        createdAt: createdAt.millisecondsSinceEpoch, // 🔥 修复：明确设置createdAt
      );

      // 🔥 修复问题2：在保存到数据库前进行重复检查
      if (await _isExactDuplicateInDatabase(todo)) {
        print('[NLReminderService] ⚠️ 检测到完全相同的提醒已存在，跳过创建');
        return null;
      }

      // 保存到数据库（只有在通过重复检查后才保存）
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

    // 🔥 修复：处理当天时间表达，包括"点半"
    if (lowerExpression.contains('点钟') || lowerExpression.contains('点')) {
      final timeMatch = RegExp(r'(\d+)点(半)?').firstMatch(lowerExpression);
      if (timeMatch != null) {
        int hour = int.parse(timeMatch.group(1)!);
        int minute = timeMatch.group(2) != null ? 30 : 0; // 🔥 修复：正确处理"半"字

        // 判断是上午还是��午
        if (lowerExpression.contains('晚上') || lowerExpression.contains('晚')) {
          if (hour < 12) hour += 12; // 晚上时间
        } else if (lowerExpression.contains('下午')) {
          if (hour < 12) hour += 12; // 下午时间
        } else if (lowerExpression.contains('上午')) {
          // 上午时间保持不变
        } else {
          // 🔥 修复：没有明确时段时的智能判断
          if (hour >= 1 && hour <= 6 && now.hour > hour) {
            // 如果是1-6点且当前时间已过，认为是明天
            return now.add(Duration(days: 1)).copyWith(hour: hour, minute: minute, second: 0);
          } else if (hour >= 7 && hour <= 12) {
            // 7-12点，如果当前时间未到，认为是今天上午
            final targetTime = now.copyWith(hour: hour, minute: minute, second: 0);
            if (targetTime.isAfter(now)) {
              return targetTime;
            } else {
              // 如果已过，认为是明天
              return now.add(Duration(days: 1)).copyWith(hour: hour, minute: minute, second: 0);
            }
          } else if (hour >= 13 && hour <= 23) {
            // 13-23点，认为是今天下午/晚上
            final targetTime = now.copyWith(hour: hour, minute: minute, second: 0);
            if (targetTime.isAfter(now)) {
              return targetTime;
            } else {
              // 如果已过，认为是明天
              return now.add(Duration(days: 1)).copyWith(hour: hour, minute: minute, second: 0);
            }
          } else {
            // 🔥 修复：对于模糊时间，智能判断是今天还是明天
            final targetTime = now.copyWith(hour: hour, minute: minute, second: 0);
            if (targetTime.isAfter(now)) {
              return targetTime;
            } else {
              return now.add(Duration(days: 1)).copyWith(hour: hour, minute: minute, second: 0);
            }
          }
        }

        // 如果指定了今天/明天等，按具体日期处理
        if (lowerExpression.contains('明天')) {
          return now.add(Duration(days: 1)).copyWith(hour: hour, minute: minute, second: 0);
        } else if (lowerExpression.contains('后天')) {
          return now.add(Duration(days: 2)).copyWith(hour: hour, minute: minute, second: 0);
        } else {
          // 🔥 修复：默认情况下，如果时间未过认为是今天，否则是明天
          final targetTime = now.copyWith(hour: hour, minute: minute, second: 0);
          if (targetTime.isAfter(now)) {
            return targetTime;
          } else {
            return now.add(Duration(days: 1)).copyWith(hour: hour, minute: minute, second: 0);
          }
        }
      }
    }

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

    print('[NLReminderService] ⏰ 开始检查提醒: 当前时间 = $now, 总提醒数 = ${reminders.length}');

    final dueReminders = reminders.where((reminder) {
      if (reminder.status != Status.pending_reminder || reminder.deadline == null) return false;

      final deadline = DateTime.fromMillisecondsSinceEpoch(reminder.deadline!).toLocal();

      // 🧠 修改为宽容判断：只要时间已到并且没过太久就触发
      return deadline.isBefore(now.add(Duration(seconds: _checkInterval))) &&
          deadline.isAfter(now.subtract(Duration(minutes: 10)));
    }).toList();

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

      // 🔥 修改：更新提醒状态为已提醒
      reminder.status = Status.reminded;
      ObjectBoxService().updateTodo(reminder);

      // 发送提醒消息到聊天
      if (_chatController != null) {
        final message = '🔔 事件提醒：${reminder.detail ?? reminder.task}';
        await _chatController!.sendSystemMessage(message);
      }

      // 通知更新
      _notifyRemindersChanged();

    } catch (e) {
      print('[NLReminderService] ❌ 触发提醒失败: $e');
    }
  }

  /// 🔥 修改：发送确认消息
  Future<void> _sendConfirmationMessage(TodoEntity reminder) async {
    try {
      if (_chatController != null) {
        final timeStr = _formatAbsoluteReminderTime(DateTime.fromMillisecondsSinceEpoch(reminder.deadline!));
        final message = '✅ 已为您创建事件提醒：${reminder.task}\n⏰ 提醒时间：$timeStr';
        await _chatController!.sendSystemMessage(message);
      }
    } catch (e) {
      print('[NLReminderService] ❌ 发送确认消息失败: $e');
    }
  }


  /// 🔥 新增：格式化绝对时间显示
  String _formatAbsoluteReminderTime(DateTime dateTime) {
    final now = DateTime.now();
    final month = dateTime.month;
    final day = dateTime.day;
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');

    // 判断是今天、明天还是其他日期
    if (dateTime.year == now.year && dateTime.month == now.month && dateTime.day == now.day) {
      return '今天 $hour:$minute';
    } else if (dateTime.difference(now).inDays == 1 ||
        (dateTime.day == now.day + 1 && dateTime.month == now.month && dateTime.year == now.year)) {
      return '明天 $hour:$minute';
    } else if (dateTime.year == now.year) {
      // 同一年，显示月日
      return '${month}月${day}日 $hour:$minute';
    } else {
      // 不同年，显示年月日
      return '${dateTime.year}年${month}月${day}日 $hour:$minute';
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
      'active_reminders': reminders.where((r) => r.status == Status.pending_reminder).length,
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
      'active_reminders': reminders.where((r) => r.status == Status.pending_reminder).length,
      'completed_reminders': reminders.where((r) => r.status == Status.completed).length,
      'today_reminders': todayReminders.length,
      'overdue_reminders': reminders.where((r) =>
      r.status == Status.pending_reminder &&
          r.deadline != null &&
          r.deadline! < now.millisecondsSinceEpoch
      ).length,
      'upcoming_reminders': reminders.where((r) =>
      r.status == Status.pending_reminder &&
          r.deadline != null &&
          r.deadline! > now.millisecondsSinceEpoch
      ).length,
    };
  }

  /// �� 修改：手动创建提醒
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
        status: Status.pending_reminder, // 🔥 修复：统一使用Status.pending_reminder
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

    // 🔥 修复：更严格的系统消息过滤
    if (lowerContent.contains('✅') ||
        lowerContent.contains('🔔') ||
        lowerContent.contains('⏰') ||
        lowerContent.contains('已为您创建') ||
        lowerContent.contains('事件提醒') ||
        lowerContent.contains('提醒时间') ||
        lowerContent.contains('小时') && lowerContent.contains('分钟后') ||
        lowerContent.contains('天后') ||
        lowerContent.contains('智能提醒已创建') ||
        content.trim().startsWith('✅') ||
        content.trim().startsWith('🔔')) {
      print('[NLReminderService] ⚠️ 检测到系统消息，跳过处理: "${content.substring(0, content.length > 30 ? 30 : content.length)}..."');
      return false;
    }

    // 🔥 新增：排除包含确认标识的内容
    if (content.contains('已为您创建事件提醒') ||
        content.contains('智能提醒已创建') ||
        content.contains('提醒创建成功')) {
      print('[NLReminderService] ⚠️ 检测到确认消息，跳过处理');
      return false;
    }

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
      print('[NLReminderService] ⚠️ 检测到周期性时间表��，跳过处理');
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
    final pastExpressions = ['昨天', '前天', '上���', '上个月', '之前', '已经', '刚才'];
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

    // 🔥 新增：智能相似度检测
    return _isSimilarContent(content);
  }

  /// 🔥 新增：智能相似度检测
  bool _isSimilarContent(String content) {
    final lowerContent = content.toLowerCase().trim();

    // 提取时间和事件信息
    final timePattern = RegExp(r'(\d+)点半?|(\d+):(\d+)');
    final currentTimeMatch = timePattern.firstMatch(lowerContent);

    // 如果没有时间信息，跳过相似度检测
    if (currentTimeMatch == null) return false;

    // 检查最近处理的文本中是否有相似的时间和事件
    for (final processedText in _processedTexts.reversed.take(10)) {
      if (_areEventsSimilar(lowerContent, processedText.toLowerCase())) {
        print('[NLReminderService] ⚠️ 检测到相似事件，跳过处理: "$content" 与 "$processedText"');
        return true;
      }
    }

    return false;
  }

  /// 🔥 新增：判断两个事件是否相似
  bool _areEventsSimilar(String content1, String content2) {
    // 提取时间信息
    final timePattern = RegExp(r'(\d+)点半?|(\d+):(\d+)');
    final time1 = timePattern.firstMatch(content1);
    final time2 = timePattern.firstMatch(content2);

    if (time1 == null || time2 == null) return false;

    // 比较时间是否相同
    String extractedTime1 = '';
    String extractedTime2 = '';

    if (time1.group(1) != null) {
      extractedTime1 = time1.group(1)!;
      if (content1.contains('半')) extractedTime1 += ':30';
      else extractedTime1 += ':00';
    } else if (time1.group(2) != null && time1.group(3) != null) {
      extractedTime1 = '${time1.group(2)}:${time1.group(3)}';
    }

    if (time2.group(1) != null) {
      extractedTime2 = time2.group(1)!;
      if (content2.contains('半')) extractedTime2 += ':30';
      else extractedTime2 += ':00';
    } else if (time2.group(2) != null && time2.group(3) != null) {
      extractedTime2 = '${time2.group(2)}:${time2.group(3)}';
    }

    // 时间不同则不相似
    if (extractedTime1 != extractedTime2) return false;

    // 提取事件关键词
    final event1Keywords = _extractEventKeywords(content1);
    final event2Keywords = _extractEventKeywords(content2);

    // 计算关键词相似度
    if (event1Keywords.isEmpty || event2Keywords.isEmpty) return false;

    final commonKeywords = event1Keywords.intersection(event2Keywords);
    final similarity = commonKeywords.length / (event1Keywords.length + event2Keywords.length - commonKeywords.length);

    // 相似度超过0.6认为是相似事件
    return similarity >= 0.6;
  }

  /// 🔥 新增：提取事件关键词
  Set<String> _extractEventKeywords(String content) {
    // 移除时间相关词汇
    String cleanContent = content
        .replaceAll(RegExp(r'\d+点半?'), '')
        .replaceAll(RegExp(r'\d+:\d+'), '')
        .replaceAll(RegExp(r'等一下|一下|明天|后天|上午|下午|晚上'), '');

    // 提取关键动词和名词
    final keywords = <String>{};
    final words = cleanContent.split(RegExp(r'\s+'));

    for (final word in words) {
      if (word.length >= 2 && !_isStopWord(word)) {
        keywords.add(word.trim());
      }
    }

    return keywords;
  }

  /// 🔥 新增：停用词检测
  bool _isStopWord(String word) {
    final stopWords = {'去', '要', '会', '的', '了', '在', '到', '我', '你', '他', '她', '它', '和', '与', '或', '是', '有', '没', '不'};
    return stopWords.contains(word);
  }

  /// 🔥 新增：验证提醒信息的有效性
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

    // 检查事件描述是否为空
    final eventDescription = info['event_description']?.toString() ?? '';
    if (eventDescription.trim().isEmpty) {
      return false;
    }

    // 检查时间表达是否为空
    final timeExpression = info['time_expression']?.toString() ?? '';
    if (timeExpression.trim().isEmpty) {
      return false;
    }

    return true;
  }

  /// 🔥 新增：记录已处理的内容
  void _recordProcessedContent(String content) {
    final contentHash = content.hashCode.toString();
    _processedTexts.add(content);

    // 更新重复检测记录
    _recentContentHashes.add(contentHash);

    // 限制处理历史记录数量
    if (_processedTexts.length > _maxProcessedTextsHistory) {
      final oldestText = _processedTexts.removeAt(0);
      final oldestHash = oldestText.hashCode.toString();
      _recentContentHashes.remove(oldestHash);
      _lastReminderByType.remove(oldestHash);
    }

    print('[NLReminderService] 📝 记录已处理内容: "${content.length > 50 ? content.substring(0, 50) + '...' : content}"');
  }

  /// 🔥 新增：检查数据库中是否存在重复提醒
  Future<bool> _isDuplicateReminderInDatabase(String content) async {
    try {
      final reminders = allReminders;
      final now = DateTime.now();

      // 🔥 修复：使用更简单直接的重复检测
      // 1. 检查是否有完全相同的原始文本
      for (final reminder in reminders) {
        if (reminder.originalText != null && reminder.originalText!.trim() == content.trim()) {
          print('[NLReminderService] 🔍 发现完全相同的原始文本，视为重复: "$content"');
          return true;
        }
      }

      // 2. 检查最近5分钟内创建的提醒中是否有高度相似的内容
      final recentTime = now.subtract(Duration(minutes: 5));
      final recentReminders = reminders.where((reminder) {
        if (reminder.createdAt == null) return false;
        final createdTime = DateTime.fromMillisecondsSinceEpoch(reminder.createdAt!);
        return createdTime.isAfter(recentTime);
      }).toList();

      // 3. 对最近创建的提醒进行更严格的相似度检查
      for (final reminder in recentReminders) {
        if (reminder.originalText != null) {
          final similarity = _calculateContentSimilarity(content, reminder.originalText!);
          if (similarity > 0.5) { // 🔥 降低阈值到0.5，更容易检测重复
            print('[NLReminderService] 🔍 发现相似内容的提醒(相似度: ${similarity.toStringAsFixed(2)}): "${reminder.originalText}" vs "$content"');
            return true;
          }
        }
      }

      return false;
    } catch (e) {
      print('[NLReminderService] ❌ 检查重复提醒失败: $e');
      return false;
    }
  }

  /// 🔥 新增：检查是否为完全相同的提醒
  Future<bool> _isExactDuplicateInDatabase(TodoEntity newTodo) async {
    try {
      final reminders = allReminders;

      if (newTodo.deadline == null) return false;

      final newTime = DateTime.fromMillisecondsSinceEpoch(newTodo.deadline!);

      for (final existing in reminders) {
        if (existing.deadline == null) continue;

        if (existing.originalText?.trim() == newTodo.originalText?.trim()) {
          print('[NLReminderService] ⚠️ originalText 完全一致，判定为重复提醒');
          return true;
        }

        final existingTime = DateTime.fromMillisecondsSinceEpoch(existing.deadline!);

        // 🕒 时间间隔不超过2分钟（忽略秒和毫秒）
        final timeDiff = existingTime.difference(newTime).inMinutes.abs();
        final timeCloseEnough = timeDiff <= 2;

        if (timeCloseEnough) {
          // 🧠 内容相似度计算
          final taskSimilarity = _calculateContentSimilarity(
            existing.task ?? '',
            newTodo.task ?? '',
          );

          final detailSimilarity = _calculateContentSimilarity(
            existing.detail ?? '',
            newTodo.detail ?? '',
          );

          if (taskSimilarity > 0.9 || detailSimilarity > 0.9) {
            print('[NLReminderService] 🔍 检测到时间接近且内容相似的提醒，视为重复');
            return true;
          }
        }
      }

      return false;
    } catch (e) {
      print('[NLReminderService] ❌ 检查完全重复提醒失败: $e');
      return false;
    }
  }

  /// 🔥 新增：计算内容相似度
  double _calculateContentSimilarity(String text1, String text2) {
    if (text1.isEmpty || text2.isEmpty) return 0.0;

    final words1 = text1.toLowerCase().split(RegExp(r'\s+'));
    final words2 = text2.toLowerCase().split(RegExp(r'\s+'));

    final set1 = words1.toSet();
    final set2 = words2.toSet();

    final intersection = set1.intersection(set2);
    final union = set1.union(set2);

    return union.isEmpty ? 0.0 : intersection.length / union.length;
  }

  /// 🔥 新增：检查是否为无意义的提醒类型描述
  bool _isGenericReminderDescription(Map<String, dynamic> info) {
    final eventDescription = info['event_description']?.toString() ?? '';
    final reminderType = info['reminder_type']?.toString() ?? '';

    // 如果事件描述就是提醒类型，说明LLM没有提取到具体内容
    final genericDescriptions = ['任务提醒', '约会提醒', '会议提醒', '事件提醒', '提醒', '检查提醒'];

    if (genericDescriptions.contains(eventDescription)) {
      return true;
    }

    // 如果事件描述太短且只包含提醒相关词汇
    if (eventDescription.length <= 4 && eventDescription.contains('提醒')) {
      return true;
    }

    return false;
  }

  /// 🔥 新增：检查是否为无效的事件描述
  bool _isInvalidDescription(String description) {
    final invalidDescriptions = [
      '任务提醒', '约会提醒', '会议提醒', '事件提醒',
      '提醒', '检查提醒', '通知', '提示'
    ];

    return invalidDescriptions.contains(description.trim());
  }

  /// 🔥 修改：生成更具体的提醒标题
  String _generateSpecificReminderTitle(String description, String type, String originalText) {
    // 如果描述是具体的，直接使用
    if (description.length > 4 && !_isInvalidDescription(description)) {
      return description.length > 20 ? description.substring(0, 20) + '...' : description;
    }

    // 从原始文本中提取关键信息
    final extractedContent = _extractKeyContentFromText(originalText);
    if (extractedContent.isNotEmpty) {
      return extractedContent.length > 20 ? extractedContent.substring(0, 20) + '...' : extractedContent;
    }

    // 最后的备选方案
    switch (type) {
      case 'appointment':
        return '约会安排';
      case 'meeting':
        return '会议安排';
      case 'task':
        return '待办事项';
      default:
        return '智能提醒';
    }
  }

  /// 🔥 修改：生成更具体的提醒详情
  String _generateSpecificReminderDetail(String description, String type, String timeExpression) {
    // 如果描述是具体的且不是无效描述，直接使用
    if (!_isInvalidDescription(description) && description.length > 4) {
      return description;
    }

    // 根据类型生成有意义的描述
    switch (type) {
      case 'appointment':
        return '您有一个约会安排，时间：$timeExpression';
      case 'meeting':
        return '您有一个会议安排，时间：$timeExpression';
      case 'task':
        return '您有一个任务需要处理，时间：$timeExpression';
      default:
        return '智能提醒：$timeExpression';
    }
  }

  /// 🔥 新增：从文本中提取关键内容
  String _extractKeyContentFromText(String text) {
    // 移除时间相关词汇
    String cleanText = text
        .replaceAll(RegExp(r'\d+点半?'), '')
        .replaceAll(RegExp(r'\d+:\d+'), '')
        .replaceAll(RegExp(r'明天|后天|上午|下午|晚上|等一下|一下|分钟后|小时后'), '')
        .replaceAll(RegExp(r'提醒我?'), '')
        .trim();

    // 提取动词+名词组合
    final actionPatterns = [
      RegExp(r'(买|购买|去买)\s*([^，。！？\s]+)'),
      RegExp(r'(吃|喝|用)\s*([^，。！？\s]+)'),
      RegExp(r'(看|听|读)\s*([^，。！？\s]+)'),
      RegExp(r'(做|完成|处理)\s*([^，。！？\s]+)'),
      RegExp(r'(见|会面|约)\s*([^，。！？\s]+)'),
    ];

    for (final pattern in actionPatterns) {
      final match = pattern.firstMatch(cleanText);
      if (match != null) {
        return '${match.group(1)}${match.group(2)}';
      }
    }

    // 如果没有匹配的模式，返回清理后的文本（限制长度）
    if (cleanText.length > 2) {
      return cleanText.length > 10 ? cleanText.substring(0, 10) : cleanText;
    }

    return '';
  }
}
