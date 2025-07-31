import 'dart:async';
import 'dart:convert';

import 'package:app/constants/prompt_constants.dart';
import 'package:app/extension/map_extension.dart';
import 'package:flutter/material.dart';
import 'dart:developer' as dev;
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../constants/voice_constants.dart';
import '../models/record_entity.dart';
import '../services/chat_manager.dart';
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
            // ✅ 使用 insertNewMessage 而不是直接插入
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
