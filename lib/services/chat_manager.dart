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

  ChatManager();

  Future<void> init({required String selectedModel, String? systemPrompt}) async {
    _llm = await LLM.create(selectedModel, systemPrompt: systemPrompt);
    _enhancedKGService = EnhancedKGService();

    List<RecordEntity>? recentRecords = ObjectBoxService().getTermRecords();
    recentRecords?.forEach((RecordEntity recordEntity) {
      String formattedTime = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(recordEntity.createdAt!));
      addChatSession(recordEntity.role!, recordEntity.content!, time: formattedTime);
    });
  }

  Stream<String> createStreamingRequest({required String text}) async* {
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

    messages.add({"role": "assistant", "content": content});
    content = '';
  }

  Future<String> createRequest({required String text}) async {
    final content = await buildInputWithKG(text);
    return _llm.createRequest(content: content);
  }

  // 智能版本：构建个性化输入，注入知识图谱信息
  Future<String> buildInputWithKG(String userInput) async {
    final session = loadChatSession();
    DateTime now = DateTime.now();

    try {
      // 尝试从缓存获取快速响应
      final quickResponse = await _enhancedKGService.getQuickResponse(userInput);

      String kgInfo = '';
      String performanceInfo = '';

      if (quickResponse['source'] == 'cache') {
        // 缓存命中
        final cachedData = quickResponse['data'];
        kgInfo = await _buildKGContextFromCache(cachedData);
        performanceInfo = '⚡ 缓存命中 - 快速响应模式\n';
      } else {
        // 缓存未命中，执行完整分析
        final smartKGService = SmartKGService();
        final analysis = await smartKGService.analyzeUserInput(userInput);
        final relevantNodes = await smartKGService.getRelevantNodes(analysis);

        if (relevantNodes.isNotEmpty) {
          kgInfo = await _buildKGContextString(analysis, relevantNodes);
        }
        performanceInfo = '🔍 完整分析模式 - 结果已缓存\n';
      }

      var input = """
Timestamp: ${now.toIso8601String().split('.').first}
Chat Session: 
$session
---
$performanceInfo$kgInfo
User Input: $userInput""";

      return input;
    } catch (e) {
      print('Enhanced buildInputWithKG error: $e');
      // 降级到原始方法
      return await _buildInputWithKGFallback(userInput);
    }
  }
  // 从缓存数据构建上下文字符串
  Future<String> _buildKGContextFromCache(Map<String, dynamic> cachedData) async {
    final buffer = StringBuffer();

    buffer.writeln('📊 缓存分析结果:');
    buffer.writeln('缓存命中数: ${cachedData['cacheHitCount']}');
    buffer.writeln('数据时间: ${cachedData['timestamp']}');

    // 显示缓存的相关节点
    final relevantNodes = cachedData['relevantNodes'] as List<Node>? ?? [];
    if (relevantNodes.isNotEmpty) {
      buffer.writeln('\n🧠 预缓存知识图谱信息:');

      final nodesByType = <String, List<Node>>{};
      for (final node in relevantNodes.take(15)) { // 限制显示数量
        nodesByType.putIfAbsent(node.type, () => []).add(node);
      }

      for (final type in nodesByType.keys) {
        buffer.writeln('【${type}类】');
        for (final node in nodesByType[type]!) {
          buffer.write('  ├─ ${node.name}');
          if (node.attributes.isNotEmpty) {
            final attrs = node.attributes.entries.take(2)
                .map((e) => '${e.key}: ${e.value}')
                .join(', ');
            buffer.write('（$attrs）');
          }
          buffer.writeln();
        }
      }
    }

    // 显示预计算的问答对
    final qaItems = cachedData['precomputedQA'] as List<Map<String, dynamic>>? ?? [];
    if (qaItems.isNotEmpty) {
      buffer.writeln('\n🎯 预计算问答:');
      for (final qa in qaItems.take(3)) {
        buffer.writeln('Q: ${qa['question']}');
        buffer.writeln('A: ${qa['answer']}');
        buffer.writeln('---');
      }
    }

    buffer.writeln('\n💡 智能缓存策略: 基于对话上下文的预测性信息检索');
    buffer.writeln('🎯 回复指导: 优先使用缓存信息，提供快速响应');

    return buffer.toString();
  }

  // 新增：处理背景对话的方法
  Future<void> processBackgroundConversation(String conversationText) async {
    try {
      await _enhancedKGService.processBackgroundConversation(conversationText);
    } catch (e) {
      print('Error processing background conversation: $e');
    }
  }

  // 新增：获取缓存性能统计
  Map<String, dynamic> getCachePerformance() {
    try {
      return _enhancedKGService.getCachePerformance();
    } catch (e) {
      print('Error getting cache performance: $e');
      return {'error': e.toString()};
    }
  }

  // 新增：获取所有缓存项
  List<CacheItem> getAllCacheItems() {
    try {
      return _enhancedKGService.getAllCacheItems();
    } catch (e) {
      print('Error getting all cache items: $e');
      return [];
    }
  }

  // 新增：清空缓存
  void clearCache() {
    try {
      _enhancedKGService.clearCache();
    } catch (e) {
      print('Error clearing cache: $e');
    }
  }

  // 新增：初始化增强服务
  Future<void> initializeEnhancedServices() async {
    try {
      _enhancedKGService.initialize();
    } catch (e) {
      print('Error initializing enhanced services: $e');
    }
  }


  // 构建知识图谱上下文字符串 - 增强版
  Future<String> _buildKGContextString(IntentAnalysis analysis, List<Node> relevantNodes) async {
    final buffer = StringBuffer();

    // 1. 意图信息
    buffer.writeln('📊 对话分析:');
    buffer.writeln('意图类型: ${_getIntentDescription(analysis.intent)}');
    buffer.writeln('置信度: ${(analysis.confidence * 100).toStringAsFixed(1)}%');

    if (analysis.entities.isNotEmpty) {
      buffer.writeln('识别实体: ${analysis.entities.map((e) => e.entityName).join(', ')}');
    }

    if (analysis.keywords.isNotEmpty) {
      buffer.writeln('关键词: ${analysis.keywords.join(', ')}');
    }

    // 2. 简化的相关性信息显示（移除了错误的AdvancedKGRetrievalService调用）
    buffer.writeln('\n🧠 知识图谱检索结果:');
    buffer.writeln('检索到 ${relevantNodes.length} 个相关节点');

    // 按类型分组显示
    final nodesByType = <String, List<Node>>{};
    for (final node in relevantNodes) {
      nodesByType.putIfAbsent(node.type, () => []).add(node);
    }

    for (final type in nodesByType.keys) {
      final nodes = nodesByType[type]!;
      buffer.writeln('\n【${type}类】(${nodes.length}个节点)');

      for (final node in nodes.take(5)) { // 限制每类显示数量
        buffer.writeln('  ├─ ${node.name}');

        if (node.attributes.isNotEmpty) {
          final keyAttrs = node.attributes.entries.take(2);
          final attrs = keyAttrs.map((e) => '${e.key}: ${e.value}').join(', ');
          buffer.writeln('     属性: $attrs');
        }
      }

      if (nodes.length > 5) {
        buffer.writeln('     └─ 还有 ${nodes.length - 5} 个相关节点...');
      }
    }

    // 3. 检索统计信息
    buffer.writeln('\n📈 检索统计:');
    buffer.writeln('节点总数: ${relevantNodes.length}');
    buffer.writeln('节点类型: ${nodesByType.keys.length} 种');

    // 4. 根据意图提供特定上下文
    buffer.writeln('\n💡 智能检索策略:');
    buffer.writeln(_getIntentSpecificContext(analysis, relevantNodes));

    // 5. 提供个性化回复指导
    buffer.writeln('\n🎯 回复指导:');
    buffer.writeln(_generateReplyGuidance(analysis, relevantNodes));

    return buffer.toString();
  }

  // 生成个性化回复指导
  String _generateReplyGuidance(IntentAnalysis analysis, List<Node> relevantNodes) {
    final guidance = StringBuffer();

    // 基于意图的回复策略
    switch (analysis.intent) {
      case IntentType.purchase:
        guidance.writeln('重点关注：价格比较、性价比分析、购买渠道建议');
        if (relevantNodes.any((n) => n.type.toLowerCase().contains('review'))) {
          guidance.writeln('可引用用户评价和使用体验');
        }
        break;

      case IntentType.compare:
        guidance.writeln('提供客观对比：从功能、价格、适用场景等维度分析');
        final productNodes = relevantNodes.where((n) => n.type.toLowerCase().contains('product')).length;
        if (productNodes >= 2) {
          guidance.writeln('已检索到 $productNodes 个产品，可进行详细对比');
        }
        break;

      case IntentType.recommend:
        guidance.writeln('个性化推荐：根据用户可能的需求和预算');
        guidance.writeln('优先推荐高相关度和好评产品');
        break;

      case IntentType.query:
        guidance.writeln('提供准确详细信息，引用具体属性和数据');
        break;

      case IntentType.general:
        guidance.writeln('自然对话，适当引用相关知识');
        break;
    }

    // 基于实体类型的特殊指导
    final entityTypes = analysis.entities.map((e) => e.entityType).toSet();
    if (entityTypes.contains('product')) {
      guidance.writeln('产品相关问题：重点说明功能特点和使用场景');
    }
    if (entityTypes.contains('brand')) {
      guidance.writeln('品牌相关问题：可介绍品牌特色和产品线');
    }

    return guidance.toString();
  }

  // 获取意图描述
  String _getIntentDescription(IntentType intent) {
    switch (intent) {
      case IntentType.query:
        return '信息查询';
      case IntentType.purchase:
        return '购买咨询';
      case IntentType.compare:
        return '产品比较';
      case IntentType.recommend:
        return '推荐请求';
      case IntentType.general:
        return '一般对话';
    }
  }

  // 获取意图特定的上下文提示
  String _getIntentSpecificContext(IntentAnalysis analysis, List<Node> relevantNodes) {
    switch (analysis.intent) {
      case IntentType.purchase:
        return '用户有购买意图，请重点关注产品的价格、性能、优缺点等信息，并提供购买建议。';

      case IntentType.compare:
        return '用户想要比较产品，请客观分析各产品的优缺点，从性能、价格、适用场景等维度进行对比。';

      case IntentType.recommend:
        return '用户需要推荐，请根据用户可能的需求和预算，推荐最适合的产品。';

      case IntentType.query:
        return '用户想了解信息，请提供准确、详细的产品信息和相关知识。';

      case IntentType.general:
        return '常规对话，请自然回应用户，适当引用相关知识图谱信息。';
    }
  }

  // 降级方法：当智能服务失败时使用原始方法
  Future<String> _buildInputWithKGFallback(String userInput) async {
    final session = loadChatSession();
    DateTime now = DateTime.now();

    // 原始的简单关键词提取
    final keywordReg = RegExp(r'[\u4e00-\u9fa5A-Za-z0-9_]+');
    final keywords = keywordReg.allMatches(userInput).map((m) => m.group(0)!).toSet().toList();

    // 使用原始的知识图谱服务
    final relatedNodes = await KnowledgeGraphService.getRelatedNodesByKeywords(keywords);
    String kgInfo = '';
    if (relatedNodes.isNotEmpty) {
      kgInfo = '与当前话题相关的知识图谱信息：\n';
      for (var node in relatedNodes) {
        kgInfo += '- ${node.name}（类型：${node.type}）';
        if (node.attributes.isNotEmpty) {
          kgInfo += '，属性：';
          node.attributes.forEach((k, v) {
            kgInfo += '$k: $v; ';
          });
        }
        kgInfo += '\n';
      }
    }

    var input = """
Timestamp: ${now.toIso8601String().split('.').first}
Chat Session: 
$session
---
$kgInfo
User Input: $userInput""";
    return input;
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
