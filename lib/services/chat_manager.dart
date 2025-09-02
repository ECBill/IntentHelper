import 'dart:async';
import 'dart:convert';

import 'package:app/services/enhanced_kg_service.dart';
import 'package:app/services/conversation_cache.dart';
import 'package:app/services/personalized_understanding_service.dart';
import 'package:app/services/human_understanding_system.dart'; // 🔥 新增：导入人类理解系统
import 'package:intl/intl.dart';

import '../models/chat_session.dart';
import '../models/record_entity.dart';
import '../services/llm.dart';
import '../services/objectbox_service.dart';

class ChatManager {
  final ChatSession chatSession = ChatSession();
  late LLM _llm;
  late EnhancedKGService _enhancedKGService;
  late PersonalizedUnderstandingService _personalizedService; // 🔥 新增：个性化理解服务
  late ConversationCache _conversationCache;

  ChatManager();

  Future<void> init({required String selectedModel, String? systemPrompt}) async {
    print('[ChatManager] 🚀 初始化ChatManager...');

    try {
      _llm = await LLM.create(selectedModel, systemPrompt: systemPrompt);
      _enhancedKGService = EnhancedKGService();
      _conversationCache = ConversationCache();
      _personalizedService = PersonalizedUnderstandingService(); // 初始化个性化理解服务

      // 初始化缓存系统
      print('[ChatManager] 🔄 初始化对话缓存系统...');
      await _conversationCache.initialize();

      // 🔥 新增：初始化个性化理解服务
      print('[ChatManager] 🧠 初始化个性化理解服务...');
      await _personalizedService.initialize();

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
    } catch (e) {
      print('[ChatManager] ❌ ChatManager初始化失败: $e');
      // 不抛出异常，允许系统继续运行
    }
  }

  Stream<String> createStreamingRequest({required String text}) async* {
    print('[ChatManager] 🚀 开始处理用户输入: "${text.substring(0, text.length > 50 ? 50 : text.length)}..."');

    // 🔥 关键修复：立即处��背景对话，更新缓存
    print('[ChatManager] 📝 触发对话缓存分析...');
    await _conversationCache.processBackgroundConversation(text);

    RegExp pattern = RegExp(r'[。！？；：.!?;:](?=\s)');

    var lastIndex = 0;
    var content = "";
    var jsonObj = {};

    // 🔥 修复：使用智能选择的输入构建方法
    var userInputWithKG = await buildOptimalInput(text);
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
      print('[ChatManager] 🤖 处理助手回复缓存: "${content.substring(0, content.length > 30 ? 30 : content.length)}..."');
      await _conversationCache.processBackgroundConversation(content);
    }

    messages.add({"role": "assistant", "content": content});
    content = '';
  }

  Future<String> createRequest({required String text}) async {
    print('[ChatManager] 🚀 处理非流式请求: "${text.substring(0, text.length > 50 ? 50 : text.length)}..."');

    // 🔥 关键修复：处理用户输入
    print('[ChatManager] 📝 触发对话缓存分析...');
    await _conversationCache.processBackgroundConversation(text);

    // 🔥 修复：使用智能选择的输入构建方法
    final content = await buildOptimalInput(text);
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
    // 修复��获取ChatSession对象而不是String
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
        // 🔥 修复：使用重构后的ConversationCache来获取快速响应
        final cacheResponse = _conversationCache.getQuickResponse(userInput);
        if (cacheResponse != null && cacheResponse['hasCache'] == true) {
          final cacheContent = cacheResponse['content'] as List<String>? ?? [];
          final relevanceScores = cacheResponse['relevanceScores'] as List<double>? ?? [];
          final hitCount = cacheResponse['cacheHitCount'] as int? ?? 0;

          // 构建知识图谱信息
          final kgInfoBuffer = StringBuffer();
          kgInfoBuffer.writeln('缓存响应结果:');
          for (int i = 0; i < cacheContent.length && i < 3; i++) {
            final content = cacheContent[i];
            final score = i < relevanceScores.length ? relevanceScores[i] : 0.0;
            kgInfoBuffer.writeln('- $content (相关性: ${score.toStringAsFixed(2)})');
          }

          kgInfo = kgInfoBuffer.toString();
          performanceInfo = '缓存命中 $hitCount 项 | 响应时间：极快';
        } else {
          // 如果缓存未命中，尝试使用知识图谱增强服务分析
          try {
            final kgResult = await _enhancedKGService.performKGAnalysis(userInput);
            if (kgResult.nodes.isNotEmpty) {
              final kgInfoBuffer = StringBuffer();
              kgInfoBuffer.writeln('知识图谱分析结果:');
              for (final node in kgResult.nodes.take(3)) {
                kgInfoBuffer.writeln('- ${node.name} (${node.type})');
              }
              kgInfo = kgInfoBuffer.toString();
              performanceInfo = '知识图谱分析 ${kgResult.nodes.length} 个节点 | 响应时间：正常';
            } else {
              kgInfo = '暂无相���知识图谱信息';
              performanceInfo = '知识图谱分析无结果 | 响应时间：正常';
            }
          } catch (e) {
            print('[ChatManager] 知识图谱分析失败: $e');
            kgInfo = '知识图谱服务暂时不可用';
            performanceInfo = '知识图谱分析失败 | 响应时间：慢';
          }
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

  // 🔥 新增：基于人类理解系统的LLM输入构建方法
  /// 使用人类理解系统构建个性化的LLM输入
  /// 这是基于语义理解的新方法，比传统知识图谱方法更准确
  Future<String> buildInputWithSemanticUnderstanding(String userInput) async {
    print('[ChatManager] 🧠 使用人类理解系统构建个性化输入...');

    try {
      // 提取用户输入中的关键词
      final keywords = _extractKeywords(userInput);

      // 从个性化理解服务获取结构化的LLM输入
      final llmInput = await _personalizedService.buildLLMInput(
        userInput: userInput,
        contextKeywords: keywords,
        includeDetailedHistory: false, // 默认不包含详细历史，提高响应速度
      );

      // 构建最终的LLM提示
      final contextualPrompt = _buildContextualPrompt(userInput, llmInput);

      print('[ChatManager] ✅ 基于语义理解的个性化输入构建完成');
      return contextualPrompt;

    } catch (e) {
      print('[ChatManager] ❌ 语义理解输入构建失败: $e');
      // 降级到基础输入
      return _buildBasicInput(userInput);
    }
  }

  // 🔥 修复：智能选择最佳输入构建方法
  /// 智能选择使用哪种方法构建LLM输入
  /// 优先使用人类理解系统的用户状态信息，然后是语义理解，最后降级到知识图谱缓存
  Future<String> buildOptimalInput(String userInput) async {
    print('[ChatManager] 🎯 智能选择最佳输入构建方法...');

    try {
      // 🔥 修复：首先尝试使用人类理解系统的用户状态信息
      final userStateInput = await buildInputWithUserState(userInput);
      if (userStateInput.isNotEmpty && !userStateInput.contains('基础输入')) {
        print('[ChatManager] ✅ 使用人类理解系统用户状态构建输入');
        return userStateInput;
      }
    } catch (e) {
      print('[ChatManager] ⚠️ 人类理解系统构建失败，降级到语义理解: $e');
    }

    try {
      // 降级到语义理解系统
      final semanticInput = await buildInputWithSemanticUnderstanding(userInput);
      if (semanticInput.isNotEmpty && !semanticInput.contains('基础输入')) {
        print('[ChatManager] ✅ 使用语义理解系统构建输入');
        return semanticInput;
      }
    } catch (e) {
      print('[ChatManager] ⚠️ 语义理解系统构建失败，降级到知识图谱: $e');
    }

    try {
      // 降级到知识图谱缓存方法
      final kgInput = await buildInputWithKG(userInput);
      print('[ChatManager] ✅ 使用知识图谱缓存构建输入');
      return kgInput;
    } catch (e) {
      print('[ChatManager] ⚠️ 知识图谱方法也失败，使用基础输入: $e');
      return _buildBasicInput(userInput);
    }
  }

  // 🔥 新增：获取个性化对话建议
  /// 基于人类理解系统获取对话建议
  Future<Map<String, dynamic>> getPersonalizedConversationSuggestions() async {
    try {
      final personalizedContext = await _personalizedService.generatePersonalizedContext();

      return {
        'suggestions': personalizedContext.contextualRecommendations,
        'current_state': personalizedContext.currentSemanticState,
        'user_profile': personalizedContext.longTermProfile,
        'generated_at': personalizedContext.generatedAt.toIso8601String(),
      };
    } catch (e) {
      print('[ChatManager] ❌ 获取个性化建议失败: $e');
      return {};
    }
  }

  // 🔥 新增：获取用户当前理解状态
  /// 获取人类理解系统对用户的当前理解状态
  Map<String, dynamic> getCurrentUnderstandingState() {
    try {
      return _personalizedService.getDebugInfo();
    } catch (e) {
      print('[ChatManager] ❌ 获取理解状态失败: $e');
      return {};
    }
  }

  // 🔥 新增：主动生成对话响应
  /// 基于用户状态主动生成有价值的对话内容
  Future<String> generateProactiveResponse() async {
    try {
      print('[ChatManager] 🤖 生成主动对话响应...');

      // 获取个性化上下文
      final personalizedContext = await _personalizedService.generatePersonalizedContext();

      // 构建主动响应的LLM输入
      final proactivePrompt = _buildProactivePrompt(personalizedContext);

      // 调用LLM生成主动响应
      final response = await _llm.createRequest(content: proactivePrompt);

      print('[ChatManager] ✅ 主动响应生成完成');
      return response;

    } catch (e) {
      print('[ChatManager] ❌ 生成主动响应失败: $e');
      return '我正在学习更好地理解你，有什么我可以帮助你的吗？';
    }
  }

  // 🔥 新增：辅助方法 - 提取关键词
  List<String> _extractKeywords(String input) {
    final keywords = <String>[];
    final content = input.toLowerCase();

    // 技术相关关键词
    if (content.contains('flutter')) keywords.add('flutter');
    if (content.contains('编程') || content.contains('代码')) keywords.add('编程');
    if (content.contains('学习')) keywords.add('学习');
    if (content.contains('项目')) keywords.add('项目');
    if (content.contains('工作')) keywords.add('工作');
    if (content.contains('问题')) keywords.add('问题');
    if (content.contains('计划') || content.contains('规划')) keywords.add('规划');

    return keywords;
  }

  // 🔥 新增：构建上下文化提示
  String _buildContextualPrompt(String userInput, Map<String, dynamic> llmInput) {
    final currentState = llmInput['user_current_state'] as Map<String, dynamic>? ?? {};
    final profileSummary = llmInput['user_profile_summary'] as Map<String, dynamic>? ?? {};
    final suggestions = llmInput['contextual_suggestions'] as Map<String, dynamic>? ?? {};
    final guidelines = llmInput['conversation_guidelines'] as Map<String, dynamic>? ?? {};

    final contextHistory = chatSession.chatHistory.items.take(5).map((chat) {
      return "${chat.role}: ${chat.txt}";
    }).join('\n');

    final timeContext = DateFormat('yyyy年MM月dd日 HH:mm').format(DateTime.now());

    return """
## 用户输入
$userInput

## 对话历史
$contextHistory

## 当前时间
$timeContext

## 用户当前状态
焦点水平: ${currentState['focus_level'] ?? '中等'}
主要意图: ${(currentState['primary_intents'] as List?)?.join('、') ?? '无明确意图'}
认知容量: ${(currentState['cognitive_capacity'] as Map?)?['load_level'] ?? '正常'}
当前话题: ${(currentState['current_topics'] as List?)?.join('、') ?? '无特定话题'}

## 用户档案概览
专业领域: ${(profileSummary['expertise_areas'] as List?)?.join('、') ?? '待了解'}
互动风格: ${profileSummary['interaction_style'] ?? '平衡型'}
偏好话题: ${(profileSummary['preferred_topics'] as List?)?.join('、') ?? '多样化'}
目标导向: ${profileSummary['goal_orientation'] ?? '中等'}

## 个性化建议
${_formatSuggestions(suggestions)}

## 对话指导原则
交流风格: ${guidelines['communication_style'] ?? '平衡'}
回复长度: ${guidelines['response_length'] ?? '适中'}
个性化程度: ${guidelines['personalization_level'] ?? '中等'}

请基于以上个性化信息，用自然、贴切的方式回答用户问题。要体现出对用户状态和偏好的理解，但不要明显暴露这些分析信息。
""";
  }

  // 🔥 新增：构建基础输入（降级方案）
  String _buildBasicInput(String userInput) {
    final contextHistory = chatSession.chatHistory.items.take(5).map((chat) {
      return "${chat.role}: ${chat.txt}";
    }).join('\n');

    final timeContext = DateFormat('yyyy年MM月dd日 HH:mm').format(DateTime.now());

    return """
用户输入：$userInput

对话历史：
$contextHistory

时间：$timeContext

请基于以上信息回答用户的问题。
""";
  }

  // 🔥 新增：构建主动响应提示
  String _buildProactivePrompt(personalizedContext) {
    final currentState = personalizedContext.currentSemanticState;
    final recommendations = personalizedContext.contextualRecommendations;

    return """
## 用户状态分析
${_formatCurrentState(currentState)}

## 个性化建议
${_formatRecommendations(recommendations)}

## 任务指令
基于用户���前状态和个性��建议，生成一条主动的、有价值的对话内容。要求：
1. 自然、不突兀，像朋友间的关心
2. 具体、实用，能够帮助用户
3. 简洁明了，不超过100字
4. 体现个性化理解，但不明显暴露分析过程

请生成一条主动对话：
""";
  }

  // 🔥 新增：格���化当前状态
  String _formatCurrentState(Map<String, dynamic> currentState) {
    final cognitiveState = currentState['cognitive_state'] as Map<String, dynamic>? ?? {};
    final activeIntents = currentState['active_intents'] as Map<String, dynamic>? ?? {};

    return """
认知状态: ${cognitiveState['load_level'] ?? '正常'}
活跃意图数量: ${activeIntents['count'] ?? 0}
主要关注领域: ${(activeIntents['categories'] as Map?)?.keys.join('、') ?? '无'}
""";
  }

  // 🔥 新增：格式化建议
  String _formatSuggestions(Map<String, dynamic> suggestions) {
    final buffer = StringBuffer();

    suggestions.forEach((key, value) {
      if (value is String && value.isNotEmpty) {
        buffer.writeln('- $value');
      }
    });

    return buffer.toString().isEmpty ? '暂无特殊建议' : buffer.toString();
  }

  // 🔥 新增：格式化推荐
  String _formatRecommendations(Map<String, dynamic> recommendations) {
    final buffer = StringBuffer();

    final immediateActions = recommendations['immediate_actions'] as Map<String, dynamic>? ?? {};
    final optimizationOpportunities = recommendations['optimization_opportunities'] as Map<String, dynamic>? ?? {};

    if (immediateActions.isNotEmpty) {
      buffer.writeln('立即行动建议:');
      immediateActions.values.forEach((action) {
        if (action is String) buffer.writeln('- $action');
      });
    }

    if (optimizationOpportunities.isNotEmpty) {
      buffer.writeln('优��机会:');
      optimizationOpportunities.values.forEach((opportunity) {
        if (opportunity is String) buffer.writeln('- $opportunity');
      });
    }

    return buffer.toString().isEmpty ? '继续保持当前状态' : buffer.toString();
  }

  // 🔥 新增：添加缺失的方法
  /// 获取当前用户个人信息关注点摘要
  List<String> getCurrentPersonalFocusSummary() {
    return _conversationCache.getCurrentPersonalFocusSummary();
  }

  /// 获取相关的个人信息用于生成
  Map<String, dynamic> getRelevantPersonalInfoForGeneration() {
    return _conversationCache.getRelevantPersonalInfoForGeneration();
  }

  /// 获取缓存性能统计
  Map<String, dynamic> getCachePerformance() {
    return _conversationCache.getCacheStats();
  }

  /// 获取所有缓存项
  List<CacheItem> getAllCacheItems() {
    return _conversationCache.getAllCacheItems();
  }

  /// 按分类获取缓存项
  List<CacheItem> getCacheItemsByCategory(String category) {
    return _conversationCache.getCacheItemsByCategory(category);
  }

  /// 获取最近的对话摘要
  List<ConversationSummary> getRecentSummaries({int limit = 10}) {
    return _conversationCache.getRecentSummaries(limit: limit);
  }

  /// 获取当前对话��下文
  ConversationContext? getCurrentConversationContext() {
    return _conversationCache.getCurrentConversationContext();
  }

  /// 获取用户个人上下文
  UserPersonalContext? getUserPersonalContext() {
    return _conversationCache.getUserPersonalContext();
  }

  /// 获取主动交互建议
  Map<String, dynamic> getProactiveInteractionSuggestions() {
    return _conversationCache.getProactiveInteractionSuggestions();
  }

  /// 获取缓存项详细信息
  Map<String, dynamic> getCacheItemDetails(String key) {
    return _conversationCache.getCacheItemDetails(key);
  }

  /// 清空缓存
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

  // 🔥 新增：构建包含用户状态的聊天输入
  /// 构建包含人类理解系统状态信息的聊天输入
  Future<String> buildInputWithUserState(String userInput) async {
    print('[ChatManager] 🧠 构建包含用户状态的聊天输入...');

    try {
      // 获取人类理解系统的当前状态
      final humanUnderstanding = HumanUnderstandingSystem();
      final currentState = humanUnderstanding.getCurrentState();

      // 构建基本的对话历史
      final contextHistory = chatSession.chatHistory.items.take(5).map((chat) {
        return "${chat.role}: ${chat.txt}";
      }).join('\n');

      final timeContext = DateFormat('yyyy年MM月dd日 HH:mm').format(DateTime.now());

      // 构建用户状态信息
      final userStateBuffer = StringBuffer();

      // 活跃意图信息
      final activeIntents = currentState.activeIntents;
      if (activeIntents.isNotEmpty) {
        userStateBuffer.writeln('\n## 用户当前活跃意图:');
        for (final intent in activeIntents.take(3)) {
          userStateBuffer.writeln('- ${intent.description} (状态: ${intent.state.toString().split('.').last}, 类别: ${intent.category}, 置信度: ${intent.confidence.toStringAsFixed(2)})');
        }
      }

      // 活跃主题信息
      final activeTopics = currentState.activeTopics;
      if (activeTopics.isNotEmpty) {
        userStateBuffer.writeln('\n## 用户当前关注主题:');
        for (final topic in activeTopics.take(3)) {
          userStateBuffer.writeln('- ${topic.name} (类别: ${topic.category}, 相关性: ${topic.relevanceScore.toStringAsFixed(2)})');
          if (topic.keywords.isNotEmpty) {
            userStateBuffer.writeln('  关键词: ${topic.keywords.take(3).join('、')}');
          }
        }
      }

      // 认知负载信息
      final cognitiveLoad = currentState.currentCognitiveLoad;
      userStateBuffer.writeln('\n## 用户认知状态:');
      userStateBuffer.writeln('- 认知负载级别: ${cognitiveLoad.level.toString().split('.').last}');
      userStateBuffer.writeln('- 负载分数: ${cognitiveLoad.score.toStringAsFixed(2)}');
      userStateBuffer.writeln('- 活跃意图数量: ${cognitiveLoad.activeIntentCount}');
      userStateBuffer.writeln('- 活跃主题数量: ${cognitiveLoad.activeTopicCount}');

      // 因果关系信息
      final recentCausalChains = currentState.recentCausalChains;
      if (recentCausalChains.isNotEmpty) {
        userStateBuffer.writeln('\n## 最近的因果关系:');
        for (final causal in recentCausalChains.take(2)) {
          userStateBuffer.writeln('- ${causal.cause} → ${causal.effect} (置信度: ${causal.confidence.toStringAsFixed(2)})');
        }
      }

      print('[ChatManager] ✅ 用户状态信息构建完成: ${activeIntents.length}个意图, ${activeTopics.length}个主题, 认知负载: ${cognitiveLoad.level}');

      return """
用户输入：$userInput

对话历史：
$contextHistory

时间：$timeContext

${userStateBuffer.toString()}

请基于以上用户状态信息，提供个性化的、符合用户当前关注点和认知状态的回答。
""";

    } catch (e) {
      print('[ChatManager] ❌ 构建用户状态输入失败: $e');
      // 降级到基础输入
      return _buildBasicInput(userInput);
    }
  }
}
