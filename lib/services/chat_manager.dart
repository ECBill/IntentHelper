import 'dart:async';
import 'dart:convert';

import 'package:app/services/smart_kg_service.dart';
import 'package:app/services/enhanced_kg_service.dart';
import 'package:app/services/conversation_cache.dart';
import 'package:app/models/graph_models.dart';
import 'package:intl/intl.dart';

import '../models/chat_session.dart';
import '../models/record_entity.dart';
import '../services/llm.dart';
import '../services/objectbox_service.dart';
import '../services/knowledge_graph_service.dart';

class ChatManager {
  final ChatSession chatSession = ChatSession();
  late LLM _llm;
  late EnhancedKGService _enhancedKGService;
  late ConversationCache _conversationCache;

  ChatManager();

  Future<void> init({required String selectedModel, String? systemPrompt}) async {
    print('[ChatManager] 🚀 初始化ChatManager...');
    _llm = await LLM.create(selectedModel, systemPrompt: systemPrompt);
    _enhancedKGService = EnhancedKGService();
    _conversationCache = ConversationCache();

    // 初始化缓存系统
    print('[ChatManager] 🔄 初始化对话缓存系统...');
    await _conversationCache.initialize();

    List<RecordEntity>? recentRecords = ObjectBoxService().getTermRecords();
    print('[ChatManager] 📚 加载最近对话记录: ${recentRecords?.length ?? 0} 条');

    recentRecords?.forEach((RecordEntity recordEntity) {
      String formattedTime = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(recordEntity.createdAt!));
      addChatSession(recordEntity.role!, recordEntity.content!, time: formattedTime);

      // 🔥 关键修复：将历史对话也添加到缓存系统进行分析
      final content = recordEntity.content ?? '';
      if (content.trim().isNotEmpty) {
        print('[ChatManager] 📝 处理历史对话: "${content.substring(0, content.length > 30 ? 30 : content.length)}..."');
        _conversationCache.processBackgroundConversation(content);
      }
    });

    print('[ChatManager] ✅ ChatManager初始化完成');
  }

  Stream<String> createStreamingRequest({required String text}) async* {
    print('[ChatManager] 🚀 开始处理用户输入: "${text.substring(0, text.length > 50 ? 50 : text.length)}..."');

    // 🔥 关键修复：立即处理背景对话，更新缓存
    print('[ChatManager] 📝 触发对话缓存分析...');
    await _conversationCache.processBackgroundConversation(text);

    RegExp pattern = RegExp(r'[。！？；：.!?;:](?=\s)');

    var lastIndex = 0;
    var content = "";
    var jsonObj = {};

    var userInputWithKG = await buildInputWithKG(text);
    var messages = [{"role": "user", "content": userInputWithKG}];

    final responseStream = _llm.createStreamingRequest(messages: messages);

    await for (var chunk in responseStream) {
      final jsonString = completeJsonIfIncomplete(chunk);
      try {
        jsonObj = jsonDecode(jsonString);

        if (jsonObj.containsKey('content')) {
          content = jsonObj['content'];

          Iterable<RegExpMatch> matches = pattern.allMatches(content);
          if (matches.isNotEmpty && matches.last.start + 1 > lastIndex) {
            final delta = content.substring(lastIndex, matches.last.start + 1);
            lastIndex = matches.last.start + 1;
            yield jsonEncode({
              "content": content,
              "delta": delta,
              "isFinished": false,
              "isEnd": jsonObj['isEnd'] ?? false,
            });
          }
        }
      } catch (e) {
        print("JSON string is incomplete, continue accumulating: $jsonString");
      }
    }

    if (lastIndex < content.length) {
      final remainingText = content.substring(lastIndex);
      yield jsonEncode({
        "content": content,
        "delta": remainingText,
        "isFinished": true,
        "isEnd": jsonObj['isEnd'] ?? false,
      });
    }

    // 🔥 关键修复：处理助手回复，也添加到缓存系统
    if (content.trim().isNotEmpty) {
      print('[ChatManager] 🤖 处理助手回��缓存: "${content.substring(0, content.length > 30 ? 30 : content.length)}..."');
      await _conversationCache.processBackgroundConversation(content);
    }

    messages.add({"role": "assistant", "content": content});
    content = '';
  }

  Future<String> createRequest({required String text}) async {
    print('[ChatManager] 🚀 处理非流式请求: "${text.substring(0, text.length > 50 ? 50 : text.length)}..."');

    // 🔥 关键修复：处理用户输入
    print('[ChatManager] 📝 ��发对话缓存分析...');
    await _conversationCache.processBackgroundConversation(text);

    final content = await buildInputWithKG(text);
    final response = await _llm.createRequest(content: content);

    // 🔥 关键修复：处理助手回复
    if (response.trim().isNotEmpty) {
      print('[ChatManager] 🤖 处理助手回复缓存: "${response.substring(0, response.length > 30 ? 30 : response.length)}..."');
      await _conversationCache.processBackgroundConversation(response);
    }

    return response;
  }

  /// 处理背景对话 - 供外部调用
  Future<void> processBackgroundConversation(String text) async {
    print('[ChatManager] 🔄 外部调用处理背景对话');
    await _conversationCache.processBackgroundConversation(text);
  }

  // 智能版本：构建个性化输入，注入知识图谱信息
  Future<String> buildInputWithKG(String userInput) async {
    // 修复：获取ChatSession对象而不是String
    final chatSessionObj = chatSession; // 使用类的chatSession属性
    DateTime now = DateTime.now();

    try {
      // 尝试从新缓存系统获取快速响应
      final quickResponse = _conversationCache.getQuickResponse(userInput);
      
      String kgInfo = '';
      String performanceInfo = '';
      
      if (quickResponse != null) {
        // 使用新缓存系统的响应
        final personalInfo = quickResponse['personal_info'] as Map<String, dynamic>? ?? {};
        final focusSummary = quickResponse['focus_summary'] as List? ?? [];

        // 从个人信息中构建知识图谱信息
        final kgInfoBuffer = StringBuffer();

        // 个人关注点摘要
        if (focusSummary.isNotEmpty) {
          kgInfoBuffer.writeln('\n## 用户个人信息关注点：');
          for (final focus in focusSummary.take(3)) {
            kgInfoBuffer.writeln('- $focus');
          }
        }

        // 个人节点信息
        final personalNodes = personalInfo['personal_nodes'] as List? ?? [];
        if (personalNodes.isNotEmpty) {
          kgInfoBuffer.writeln('\n## 用户个人相关信息���');
          for (final node in personalNodes.take(3)) {
            final nodeData = node as Map<String, dynamic>? ?? {};
            final name = nodeData['name'] ?? '未知';
            final type = nodeData['type'] ?? '未知类型';
            kgInfoBuffer.writeln('- $name ($type)');
          }
        }

        // 用户事件信息
        final userEvents = personalInfo['user_events'] as List? ?? [];
        if (userEvents.isNotEmpty) {
          kgInfoBuffer.writeln('\n## 用户最近事件：');
          for (final event in userEvents.take(2)) {
            final eventData = event as Map<String, dynamic>? ?? {};
            final name = eventData['name'] ?? '未知事件';
            final description = eventData['description'];
            if (description != null) {
              kgInfoBuffer.writeln('- $name: $description');
            } else {
              kgInfoBuffer.writeln('- $name');
            }
          }
        }

        // 用户关系信息
        final userRelationships = personalInfo['user_relationships'] as List? ?? [];
        if (userRelationships.isNotEmpty) {
          kgInfoBuffer.writeln('\n## 用户人际关系：');
          for (final relationship in userRelationships.take(2)) {
            final relData = relationship as Map<String, dynamic>? ?? {};
            final source = relData['source'] ?? '未知';
            final target = relData['target'] ?? '未知';
            final relation = relData['relation'] ?? '未知关系';
            kgInfoBuffer.writeln('- $source $relation $target');
          }
        }

        kgInfo = kgInfoBuffer.toString();
        performanceInfo = '个人信息缓存命中 | 响应时间：快速';
      } else {
        // 回退到原有的增强KG服务
        final oldQuickResponse = await _enhancedKGService.getQuickResponse(userInput);
        if (oldQuickResponse != null) {
          kgInfo = oldQuickResponse['kgInfo'] ?? '';
          performanceInfo = oldQuickResponse['performanceInfo'] ?? '';
        }
      }

      final contextHistory = chatSessionObj.chatHistory.items.take(10).map((chat) {
        return "${chat.role}: ${chat.txt}";
      }).join('\n');

      final timeContext = DateFormat('yyyy年MM月dd日 HH:mm').format(now);

      return """
用户输入：$userInput

对话历史：
$contextHistory

时间：$timeContext

$kgInfo

性能信息：$performanceInfo

请基于以上信息回答用户的问题。
""";
    } catch (e) {
      print('Error building input with KG: $e');
      return userInput;
    }
  }

  // 获取当前用户个人信息关注点摘要
  List<String> getCurrentPersonalFocusSummary() {
    return _conversationCache.getCurrentPersonalFocusSummary();
  }

  // 获取相关的个人信息用于生成
  Map<String, dynamic> getRelevantPersonalInfoForGeneration() {
    return _conversationCache.getRelevantPersonalInfoForGeneration();
  }

  // 获取缓存性能统计
  Map<String, dynamic> getCachePerformance() {
    return _conversationCache.getCacheStats();
  }

  // 获取所有缓存项
  List<CacheItem> getAllCacheItems() {
    return _conversationCache.getAllCacheItems();
  }

  // 按分类获取缓存项
  List<CacheItem> getCacheItemsByCategory(String category) {
    return _conversationCache.getCacheItemsByCategory(category);
  }

  // 获取最近的对话摘要
  List<ConversationSummary> getRecentSummaries({int limit = 10}) {
    return _conversationCache.getRecentSummaries(limit: limit);
  }

  // 获取当前对话上下文
  ConversationContext? getCurrentConversationContext() {
    return _conversationCache.getCurrentConversationContext();
  }

  // 获取用户个人上下文
  UserPersonalContext? getUserPersonalContext() {
    return _conversationCache.getUserPersonalContext();
  }

  // 获取主动交互建议
  Map<String, dynamic> getProactiveInteractionSuggestions() {
    return _conversationCache.getProactiveInteractionSuggestions();
  }

  // 获取缓存项详细信息
  Map<String, dynamic> getCacheItemDetails(String key) {
    return _conversationCache.getCacheItemDetails(key);
  }

  // 清空缓存
  void clearCache() {
    _conversationCache.clearCache();
  }

  // Retrieve recent chat history
  List<Chat> getChatSession() {
    return chatSession.chatHistory.items;
  }

  // Update work status
  void updateWorkingState(String state) {
    chatSession.workingState = state;
  }

  // Clear chat history
  void clearChatHistory() {
    chatSession.chatHistory.clear();
  }

  // Delete chat records with a specified timestamp
  void removeChatByTime(int time) {
    chatSession.chatHistory.removeWhere((chat) => chat.time == time);
  }

  // Update chatHistory (e.g. when a user initiates a search)
  void updateChatHistory([List<Chat>? filteredChats]) {
    chatSession.chatHistory.clear();

    if (filteredChats != null && filteredChats.isNotEmpty) {
      for (var chat in filteredChats) {
        chatSession.chatHistory.add(chat);
      }
    } else {
      List<RecordEntity>? recentRecords = ObjectBoxService().getTermRecords();
      recentRecords?.forEach((RecordEntity recordEntity) {
        String formattedTime = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(recordEntity.createdAt!));
        addChatSession(recordEntity.role!, recordEntity.content!, time: formattedTime);
      });
    }
  }

  // Filter chat records based on roles
  void filterChatsByRole(String role) {
    chatSession.chatHistory = LimitedQueue<Chat>(chatSession.chatHistory.maxLength)
      ..addAll(chatSession.chatHistory.items.where((chat) => chat.role == role));
  }

  String loadChatHistory(queryStartTime, queryEndTime) {
    if (queryStartTime == 0 || queryEndTime == 0) {
      return '';
    }
    StringBuffer ret = StringBuffer();
    final historyList = ObjectBoxService().getChatRecordsByTimeRange(queryStartTime, queryEndTime);
    for (var history in historyList!) {
      // Append each chat record to the result string
      String formattedTime = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(history.createdAt!));
      ret.write("$formattedTime ${history.role}: ${history.content}\n");
    }
    return ret.toString();
  }

  String loadChatSession() {
    StringBuffer ret = StringBuffer();
    List<Chat> sessionList = getChatSession();

    if (sessionList.isNotEmpty) {
      for (var i = 0; i < sessionList.length - 1; i++) {
        var session = sessionList[i];
        ret.write("${session.time} ${session.role}: ${session.txt}\n");
      }
    }

    return ret.toString();
  }

  // Common method: Add a chat record
  void addChatSession(String role, String txt, {String? time}) {
    time ??= DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    Chat newChat = Chat(role: role, txt: txt, time: time);
    chatSession.chatHistory.add(newChat);
  }

  String completeJsonIfIncomplete(String jsonString) {
    if (jsonString.trim().endsWith('"}')) {
      return jsonString;
    } else if (jsonString.trim().endsWith('"')) {
      return '$jsonString}';
    } else if (jsonString.endsWith(',')) {
      return '${jsonString.substring(0, jsonString.length - 1)}}';
    } else {
      return '$jsonString"}';
    }
  }
}
