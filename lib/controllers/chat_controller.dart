import 'dart:async';
import 'dart:convert';

import 'package:app/constants/prompt_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/intl.dart';
// 🔥 新增：智能提醒管理器导入
import 'package:app/services/intelligent_reminder_manager.dart';
import 'package:app/models/human_understanding_models.dart'; // 🔥 新增：添加模型导入
import '../constants/voice_constants.dart';
import '../models/record_entity.dart';
import '../models/summary_entity.dart';
import '../services/chat_manager.dart';
import '../services/natural_language_reminder_service.dart';
import '../services/summary.dart';
import 'package:uuid/uuid.dart';
import '../services/objectbox_service.dart';

class ChatController extends ChangeNotifier {
  late final ChatManager chatManager;
  final String _selectedModel = 'gpt-4o';
  final ObjectBoxService _objectBoxService = ObjectBoxService();
  final List<Map<String, dynamic>> historyMessages = [];
  final List<Map<String, dynamic>> newMessages = [];
  final TextEditingController textController = TextEditingController();
  final Function onNewMessage;
  final ScrollController scrollController = ScrollController();
  Map<String, String?> userToResponseMap = {};

  final ValueNotifier<Set<String>> unReadMessageId = ValueNotifier({});

  // 🔥 新增：智能提醒管理器实例
  final IntelligentReminderManager _reminderManager = IntelligentReminderManager();
  final NaturalLanguageReminderService _naturalReminderService = NaturalLanguageReminderService();

  int countHelp = 0;
  static const int _pageSize = 10;
  bool isLoading = false;
  bool hasMoreMessages = true;

  // ✅ 添加消息去重缓存
  final Set<String> _processedMessages = {};

  ChatController({required this.onNewMessage}) {
    _initialize();
  }

  Future<void> _initialize() async {
    chatManager = ChatManager();
    chatManager.init(selectedModel: _selectedModel, systemPrompt: '$systemPromptOfChat\n\n${systemPromptOfScenario['text']}');

    await loadMoreMessages(reset: true);

    // ✅ 先移除可能存在的旧回调，然后添加新回调，避免重复注册
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);

    // 🔥 新增：注册摘要生成回调
    _setupSummaryCallback();

    // 🔥 新增：初始化智能提醒管理器
    await _initializeReminderManager();
  }

  // 🔥 新增：初始化智能提醒管理器
  Future<void> _initializeReminderManager() async {
    try {
      await _reminderManager.initialize(chatController: this);
      await _naturalReminderService.initialize(chatController: this);

      print('[ChatController] ✅ 智能提醒管理器已初始化');
    } catch (e) {
      print('[ChatController] ❌ 智能提醒管理器初始化失败: $e');
    }
  }

  // 🔥 新增：添加系统消息的公共方法（供智能提醒管理器调用）
  void addSystemMessage(Map<String, dynamic> messageData) {
    try {
      final messageText = messageData['text']?.toString() ?? '';
      final previewLength = messageText.length > 50 ? 50 : messageText.length;
      print('[ChatController] 📬 接收系统消息: ${messageText.substring(0, previewLength)}...');

      // 确保消息格式正确
      final systemMessage = {
        'id': messageData['id'] ?? const Uuid().v4(),
        'text': messageData['text'] ?? '',
        'isUser': 'assistant', // 智能提醒以assistant角色显示
        'timestamp': messageData['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
        'type': messageData['type'] ?? 'intelligent_reminder',
        'rule_type': messageData['rule_type'],
      };

      // 插入消息到聊天列表
      insertNewMessage(systemMessage);

      // 可选：保存到数据库（如果需要持久化）
      _objectBoxService.insertDialogueRecord(
        RecordEntity(
          role: 'assistant',
          content: systemMessage['text'],
        )
      );

      print('[ChatController] ✅ 系统消息已添加到聊天中');

    } catch (e) {
      print('[ChatController] ❌ 添加系统消息失败: $e');
    }
  }

  // 🔥 新增：发送系统消息方法（供提醒服务调用）
  Future<void> sendSystemMessage(String message) async {
    try {
      final systemMessage = {
        'id': const Uuid().v4(),
        'text': message,
        'isUser': 'assistant',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'type': 'system_reminder',
      };

      // 添加到聊天中
      addSystemMessage(systemMessage);

      print('[ChatController] 📤 系统消息已发送: $message');
    } catch (e) {
      print('[ChatController] ❌ 发送系统消息失败: $e');
    }
  }

  // 🔥 新增：手动触发智能分析（用于测试或手动同步）
  Future<void> triggerIntelligentAnalysis() async {
    try {
      // 获取最近的对话内容
      final recentMessages = newMessages.take(5).toList();
      if (recentMessages.isEmpty) return;

      // 构建综合内容用于分析
      final contentBuilder = StringBuffer();
      for (final message in recentMessages) {
        final role = message['isUser'] ?? 'unknown';
        final text = message['text'] ?? '';
        if (text.toString().trim().isNotEmpty) {
          contentBuilder.writeln('$role: $text');
        }
      }

      final combinedContent = contentBuilder.toString().trim();
      if (combinedContent.isEmpty) return;

      // 创建语义分析输入（简化版）
      final semanticInput = SemanticAnalysisInput(
        entities: _extractBasicEntities(combinedContent),
        intent: _inferBasicIntent(combinedContent),
        emotion: _inferBasicEmotion(combinedContent),
        content: combinedContent,
        timestamp: DateTime.now(),
        additionalContext: {
          'source': 'manual_trigger',
          'trigger_method': 'chat_controller',
        },
      );

      // 提交给智能提醒管理器处理
      await _reminderManager.processSemanticAnalysis(semanticInput);
      await _naturalReminderService.processSemanticAnalysis(semanticInput);

      print('[ChatController] ✅ 手动智能分析完成');

    } catch (e) {
      print('[ChatController] ❌ 手动智能分析失败: $e');
    }
  }

  // 🔥 新增：基础实体提取
  List<String> _extractBasicEntities(String content) {
    final entities = <String>[];
    final lowerContent = content.toLowerCase();

    if (lowerContent.contains('flutter')) entities.add('Flutter');
    if (lowerContent.contains('ai') || lowerContent.contains('人工智能')) entities.add('AI');
    if (lowerContent.contains('学习')) entities.add('学习');
    if (lowerContent.contains('项目')) entities.add('项目');
    if (lowerContent.contains('工作')) entities.add('工作');
    if (lowerContent.contains('bug') || lowerContent.contains('问题')) entities.add('问题解决');

    return entities.isEmpty ? ['对话'] : entities;
  }

  // 🔥 新增：基础意图推断
  String _inferBasicIntent(String content) {
    final lowerContent = content.toLowerCase();

    if (lowerContent.contains('学习') || lowerContent.contains('教程')) return 'learning';
    if (lowerContent.contains('计划') || lowerContent.contains('规划')) return 'planning';
    if (lowerContent.contains('问题') || lowerContent.contains('bug')) return 'problem_solving';
    if (lowerContent.contains('完成') || lowerContent.contains('进展')) return 'sharing_experience';

    return 'casual_chat';
  }

  // 🔥 新增：基础情绪推断
  String _inferBasicEmotion(String content) {
    final lowerContent = content.toLowerCase();

    if (lowerContent.contains('好') || lowerContent.contains('完成')) return 'positive';
    if (lowerContent.contains('困难') || lowerContent.contains('问题')) return 'frustrated';
    if (lowerContent.contains('想') || lowerContent.contains('希望')) return 'curious';

    return 'neutral';
  }

  // 🔥 新增：设置摘要回调函数
  void _setupSummaryCallback() {
    DialogueSummary.onSummaryGenerated = _handleSummaryGenerated;
    print('[ChatController] 📋 摘要回调已注册');
  }

  // 🔥 新增：处理摘要生成完成的回调
  void _handleSummaryGenerated(List<SummaryEntity> summaries) {
    print('[ChatController] 📋 收到摘要生成完成通知，摘要数量: ${summaries.length}');
    
    if (summaries.isEmpty) return;

    try {
      // 构建摘要显示内容
      String summaryContent = _formatSummaryForDisplay(summaries);
      
      // 在聊天框中插入系统摘要消息
      insertNewMessage({
        'id': const Uuid().v4(),
        'text': summaryContent,
        'isUser': 'system', // 使用 'system' 角色标识这是系统生成的摘要
      });

      print('[ChatController] ✅ 摘要消息已插入聊天中');

      // 自���滚动到底部显示新消息
      firstScrollToBottom();
      
    } catch (e) {
      print('[ChatController] ❌ 处理摘要显示时出错: $e');
    }
  }

  // 🔥 新增：格式化摘要内容用于显示
  String _formatSummaryForDisplay(List<SummaryEntity> summaries) {
    StringBuffer buffer = StringBuffer();
    buffer.writeln('📋 **对话总结**');
    buffer.writeln('');
    
    for (int i = 0; i < summaries.length; i++) {
      SummaryEntity summary = summaries[i];
      
      // 格式化时间
      String startTimeStr = DateFormat('HH:mm').format(
        DateTime.fromMillisecondsSinceEpoch(summary.startTime)
      );
      String endTimeStr = DateFormat('HH:mm').format(
        DateTime.fromMillisecondsSinceEpoch(summary.endTime)
      );
      
      buffer.writeln('**${i + 1}. ${summary.subject}** (${startTimeStr}-${endTimeStr})');
      buffer.writeln(summary.content);
      
      if (i < summaries.length - 1) {
        buffer.writeln('');
      }
    }
    
    return buffer.toString();
  }

  // 🔥 新增：手动触发摘要生成的方法
  Future<void> triggerSummaryGeneration({int? startTime}) async {
    try {
      print('[ChatController] 🚀 手动触发摘要生成...');
      await DialogueSummary.start(
        startTime: startTime, 
        onSummaryCallback: _handleSummaryGenerated
      );
    } catch (e) {
      print('[ChatController] ❌ 摘要生成失败: $e');
      // 显示错误消息
      insertNewMessage({
        'id': const Uuid().v4(),
        'text': '❌ 摘要生成失败，请稍后再试',
        'isUser': 'system',
      });
    }
  }

  Future<void> loadMoreMessages({bool reset = false}) async {
    if (isLoading) return;

    isLoading = true;

    if (reset) {
      historyMessages.clear();
      newMessages.clear();
      hasMoreMessages = true;
      chatManager.updateChatHistory();
    }

    List<RecordEntity>? records = _objectBoxService.getChatRecords(
      offset: historyMessages.length + newMessages.length,
      limit: _pageSize,
    );

    if (records != null && records.isNotEmpty) {
      List<Map<String, dynamic>> loadMessages = records.map((record) {
        return {
          'id': record.id.toString(), // ✅ 使用数据库记录的真实 ID
          'text': record.content,
          'isUser': record.role,
        };
      }).toList();
      if (newMessages.isEmpty) {
        newMessages.insertAll(0, loadMessages.toList());
        firstScrollToBottom();
      } else {
        historyMessages.insertAll(0, loadMessages.reversed.toList());
      }
      // 只调用一次 tryNotifyListeners()
      tryNotifyListeners();
    } else {
      hasMoreMessages = false;
    }

    isLoading = false;
  }

  ValueNotifier<bool> isSpeakValueNotifier = ValueNotifier(false);

  void _onReceiveTaskData(Object data) {
    if (data == 'refresh') {
      loadMoreMessages(reset: true);
      return;
    }

    if (data is Map<String, dynamic>) {
      final text = data['text'] as String?;
      final currentText = data['currentText'] as String?;
      final speaker = data['speaker'] as String?;
      final isEndpoint = data['isEndpoint'] as bool?;
      final inDialogMode = data['inDialogMode'] as bool?;
      final isMeeting = data['isMeeting'] as bool?;
      final isFinished = data['isFinished'] as bool?;
      final delta = data['content'] as String?;
      final isSpeaking = data['isVadDetected'] as bool?;

      // ✅ 添加消息去重逻辑：对于文本消息，检查是否已经处理过
      if (text != null && text.isNotEmpty && isEndpoint == true) {
        final messageKey = '$text|$speaker';
        if (_processedMessages.contains(messageKey)) {
          print('DEBUG: Duplicate message detected, skipping: $text (speaker: $speaker)');
          return;
        }
        _processedMessages.add(messageKey);

        // 保持缓存大小，避免内存泄漏
        if (_processedMessages.length > 100) {
          final firstElement = _processedMessages.first;
          _processedMessages.remove(firstElement);
        }
      }


      if (isSpeaking != null && isSpeaking) {
        isSpeakValueNotifier.value = true;
      } else if (isSpeaking != null && !isSpeaking) {
        isSpeakValueNotifier.value = false;
      }

      // ✅ 修复：使用 else if 确保条件互斥，避免重复处理
      if (isEndpoint != null &&
          text != null &&
          isMeeting != null &&
          isMeeting) {
        // 会议模式优先
        print('DEBUG: Processing as MEETING mode');
        isSpeakValueNotifier.value = false;
        insertNewMessage({
          'id': const Uuid().v4(),
          'text': text,
          'isUser': 'user',
        });
        countHelp = countHelp + 1;
        if (countHelp == 6) {
          chatManager.updateChatHistory();
          sendMessage(initialText: systemPromptOfHelp);
          countHelp = 0;
        }
      } else if (isEndpoint != null &&
          text != null &&
          inDialogMode != null &&
          inDialogMode) {
        // 对话模式次之
        print('DEBUG: Processing as DIALOG mode');
        if(isEndpoint == true){
          isSpeakValueNotifier.value = false;
          String userInputId = const Uuid().v4();
          insertNewMessage({
            'id': userInputId,
            'text': text,
            'isUser': 'user',
          });
          userToResponseMap[userInputId] = null;
        }
      } else if (isEndpoint != null && text != null) {
        // 通用处理最后
        print('DEBUG: Processing as GENERAL mode with speaker: $speaker');
        isSpeakValueNotifier.value = false;
        insertNewMessage({
          'id': const Uuid().v4(),
          'text': text,
          'isUser': speaker,
        });
      }

      if (isFinished != null && delta != null) {
        print('DEBUG: Processing STREAMING response');
        int userIndex = newMessages.indexWhere(
                (msg) => msg['text'] == currentText && msg['isUser'] == 'user');

        if (userIndex != -1) {
          String? responseId = userToResponseMap[newMessages[userIndex]['id']];
          bool isInBottom = checkInBottom();

          if (responseId == null) {
            responseId = const Uuid().v4();
            userToResponseMap[newMessages[userIndex]['id']] = responseId;
            // ✅ 使用 insertNewMessage 而不是直���插入
            insertNewMessage({
              'id': responseId,
              'text': '',
              'isUser': 'assistant',
            });
          }

          int botIndex =
          newMessages.indexWhere((msg) => msg['id'] == responseId);
          if (botIndex != -1) {
            newMessages[botIndex]['text'] += "$delta ";
            tryNotifyListeners();

            if (isInBottom) {
              firstScrollToBottom();
            }
            if (isFinished) {
              newMessages[botIndex]['text'] =
                  newMessages[botIndex]['text'].trim();
              userToResponseMap.remove(newMessages[userIndex]['id']);
            }
          }
        }
      }
    }
  }

  tryNotifyListeners() {
    onNewMessage();
    if (hasListeners) {
      notifyListeners();
    }
  }

  Future<void> sendMessage({String? initialText}) async {
    String text = initialText ?? textController.text;
    String displayText;

    if (text.isNotEmpty) {
      textController.clear();
      if (text == systemPromptOfHelp) {
        displayText = "Help me Buddie.";
        chatManager.updateChatHistory();
      } else {
        displayText = text;
      }
      insertNewMessage({
        'id': const Uuid().v4(),
        'text': displayText,
        'isUser': 'user',
      });
      _objectBoxService.insertDialogueRecord(
          RecordEntity(role: 'user', content: displayText));
      firstScrollToBottom();

      chatManager.addChatSession('user', displayText);
      await _getBotResponse(text);
    }
  }

  Future<void> _getBotResponse(String userInput) async {
    try {
      tryNotifyListeners();

      String? responseId;

      chatManager.createStreamingRequest(text: userInput).listen(
            (jsonString) {
          try {
            final jsonObj = jsonDecode(jsonString);
            bool isInBottom = checkInBottom();

            if (responseId == null) {
              responseId = const Uuid().v4();
              // ✅ 使用 insertNewMessage 而不是直接插入
              insertNewMessage({'id': responseId, 'text': '', 'isUser': 'assistant'});
            }

            if (jsonObj.containsKey('delta')) {
              final delta = jsonObj['delta'];
              updateMessageText(responseId!, delta);
            }

            if (jsonObj['isFinished'] == true) {
              final completeResponse = jsonObj['content'];
              updateMessageText(responseId!, completeResponse,
                  isFinal: true);
              responseId = null;

              _objectBoxService.insertDialogueRecord(RecordEntity(
                  role: 'assistant', content: completeResponse));
              chatManager.addChatSession('assistant', completeResponse);
            }
            if (isInBottom) {
              firstScrollToBottom();
            }
          } catch (e) {
            updateMessageText(responseId!, 'Error parsing response');
          }
        },
        onDone: () {},
        onError: (error) {
          bool isInBottom = checkInBottom();
          if (responseId != null) {
            updateMessageText(responseId!, 'Error: ${error.toString()}');
          } else {
            // ✅ 使用 insertNewMessage 而不是直接插入
            insertNewMessage({
              'id': const Uuid().v4(),
              'text': 'Error: ${error.toString()}',
              'isUser': 'assistant'
            });
          }
          tryNotifyListeners();
          if (isInBottom) {
            firstScrollToBottom();
          }
        },
      );
    } catch (e) {
      // ✅ 使用 insertNewMessage 而不是直接插入
      insertNewMessage({
        'id': Uuid().v4(),
        'text': 'Error: ${e.toString()}',
        'isUser': 'assistant'
      });

      tryNotifyListeners();
    }
  }

  void updateMessageText(String messageId, String text,
      {bool isFinal = false}) {
    int index = newMessages.indexWhere((msg) => msg['id'] == messageId);
    if (index != -1) {
      if (!isFinal) {
        newMessages[index]['text'] += text;
      } else {
        newMessages[index]['text'] = text;
      }
      tryNotifyListeners();
    }
  }

  void insertNewMessage(Map<String, dynamic> data) {
    // 添加调用栈追踪来找出谁在调用这个方法
    final stackTrace = StackTrace.current;
    final caller = stackTrace.toString().split('\n')[1]; // 获取调用者信息

    print('DEBUG: ===== insertNewMessage DETAILED LOG =====');
    print('DEBUG: Called by: $caller');
    print('DEBUG: Data received:');
    print('DEBUG:   id: ${data['id']}');
    print('DEBUG:   text: ${data['text']?.toString().substring(0, (data['text']?.toString().length ?? 0) > 30 ? 30 : (data['text']?.toString().length ?? 0))}...');
    print('DEBUG:   role (isUser): ${data['isUser']}');
    print('DEBUG:   role type: ${data['isUser'].runtimeType}');
    print('DEBUG: Current newMessages count before insert: ${newMessages.length}');

    // ✅ 特别关注 assistant 角色的创建
    if (data['isUser'] == 'assistant') {
      print('DEBUG: ⚠️ ⚠️ ⚠️ ASSISTANT MESSAGE DETECTED! ⚠️ ⚠️ ⚠️');
      print('DEBUG: Caller details: $caller');
      print('DEBUG: Full stack trace:');
      print(stackTrace.toString());
      print('DEBUG: ⚠️ ⚠️ ⚠️ END ASSISTANT ALERT ⚠️ ⚠️ ⚠️');
    }

    // 检查是否已经存在相同 ID 的消息
    bool isDuplicateId = newMessages.any((msg) => msg['id'] == data['id']);

    if (isDuplicateId) {
      print('DEBUG: WARNING - Duplicate ID detected, skipping insert: ${data['id']}');
      return;
    }

    // ✅ 修复重复内容检测逻辑 - 只检查相同文本内容，不管角色
    bool isDuplicateContent = newMessages.any((msg) =>
    msg['text'] == data['text'] && msg['text'] != null && msg['text'].toString().trim().isNotEmpty
    );

    if (isDuplicateContent) {
      print('DEBUG: WARNING - Duplicate content detected, skipping insert: ${data['text']}');
      print('DEBUG: ============= EARLY RETURN - MESSAGE NOT INSERTED =============');
      return;
    }

    bool isInBottom = checkInBottom();
    if(!isInBottom){
      unReadMessageId.value.add(data['id']);
    }
    newMessages.insert(0, data);
    print('DEBUG: Message inserted successfully. New count: ${newMessages.length}');
    print('DEBUG: ============= END insertNewMessage LOG =============');
    tryNotifyListeners();
    if (isInBottom) {
      firstScrollToBottom();
    }
  }

  void copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied to clipboard!'),
        duration: Duration(milliseconds: 500),
      ),
    );
  }

  void dispose() {
    super.dispose();
    textController.dispose();
    scrollController.dispose();
  }

  bool isInAnimation = false;

  bool checkInBottom() {
    if (!scrollController.hasClients) return true;
    double maxScroll = scrollController.position.maxScrollExtent;
    double currentScroll = scrollController.offset;
    return currentScroll >= maxScroll - 20;
  }

  firstScrollToBottom({bool isAnimated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!scrollController.hasClients) return;
      if (isInAnimation) return;
      isInAnimation = true;
      double maxScroll = scrollController.position.maxScrollExtent;
      double currentScroll = scrollController.offset;
      while (currentScroll < maxScroll) {
        if (isAnimated) {
          // Perform the animated scroll only on the first call
          await scrollController.animateTo(
            maxScroll,
            duration: const Duration(milliseconds: 100),
            curve: Curves.linear,
          );
          await Future.delayed(const Duration(milliseconds: 10));
        } else {
          // Perform an immediate jump to the bottom on subsequent recursive calls
          scrollController.jumpTo(maxScroll);
        }
        maxScroll = scrollController.position.maxScrollExtent;
        currentScroll = scrollController.offset;
      }
      isInAnimation = false;
    });
  }

  bool checkAndNavigateToWelcomeRecordScreen() {
    final speakers = _objectBoxService.getUserSpeaker();
    int? userUtteranceCount = speakers?.length;

    if (userUtteranceCount! < 3) {
      _objectBoxService.deleteAllSpeakers();
      FlutterForegroundTask.sendDataToTask(voice_constants.voiceprintStart);
      return true;
    }
    return false;
  }
}
