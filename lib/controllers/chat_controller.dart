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

  ChatController({required this.onNewMessage}) {
    _initialize();
  }

  Future<void> _initialize() async {
    chatManager = ChatManager();
    chatManager.init(selectedModel: _selectedModel, systemPrompt: '$systemPromptOfChat\n\n${systemPromptOfScenario['text']}');

    await loadMoreMessages(reset: true);
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
          'id': Uuid().v4(),
          'text': record.content,
          'isUser': record.role,
        };
      }).toList();
      if (newMessages.isEmpty) {
        newMessages.insertAll(0, loadMessages.toList());
        tryNotifyListeners();
        firstScrollToBottom();
      } else {
        historyMessages.insertAll(0, loadMessages.reversed.toList());
      }
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

      if (isSpeaking != null && isSpeaking) {
        isSpeakValueNotifier.value = true;
      } else if (isSpeaking != null && !isSpeaking) {
        isSpeakValueNotifier.value = false;
      }

      if (isEndpoint != null &&
          text != null &&
          isMeeting != null &&
          inDialogMode != null &&
          !isMeeting &&
          !inDialogMode!) {
        isSpeakValueNotifier.value = false;
        insertNewMessage({
          'id': const Uuid().v4(),
          'text': text,
          'isUser': speaker,
        });
      }

      if (isEndpoint != null &&
          text != null &&
          isMeeting != null &&
          isMeeting) {
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
      }

      if (isEndpoint != null &&
          text != null &&
          inDialogMode != null &&
          inDialogMode) {
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
      }

      if (isFinished != null && delta != null) {
        int userIndex = newMessages.indexWhere(
                (msg) => msg['text'] == currentText && msg['isUser'] == 'user');

        if (userIndex != -1) {
          String? responseId = userToResponseMap[newMessages[userIndex]['id']];
          bool isInBottom = checkInBottom();

          if (responseId == null) {
            responseId = const Uuid().v4();
            userToResponseMap[newMessages[userIndex]['id']] = responseId;
            newMessages.insert(0, {
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
              newMessages.insert(
                  0, {'id': responseId, 'text': '', 'isUser': 'assistant'});
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
            newMessages.insert(0, {
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
      newMessages.insert(0, {
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
    bool isInBottom = checkInBottom();
    if(!isInBottom){
      unReadMessageId.value.add(data['id']);
    }
    newMessages.insert(0, data);
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