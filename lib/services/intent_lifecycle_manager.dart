/// 意图生命周期管理器
/// 负责意图对象的状态跟踪、流转和生命周期管理

import 'dart:async';
import 'dart:convert';
import 'package:app/models/human_understanding_models.dart';
import 'package:app/services/llm.dart';

class IntentLifecycleManager {
  static final IntentLifecycleManager _instance = IntentLifecycleManager._internal();
  factory IntentLifecycleManager() => _instance;
  IntentLifecycleManager._internal();

  final Map<String, Intent> _activeIntents = {};
  final List<Intent> _completedIntents = [];
  final StreamController<Intent> _intentUpdatesController = StreamController.broadcast();

  Timer? _periodicCleanupTimer;
  bool _initialized = false;

  /// 意图更新流
  Stream<Intent> get intentUpdates => _intentUpdatesController.stream;

  /// 初始化管理器
  Future<void> initialize() async {
    if (_initialized) return;

    print('[IntentLifecycleManager] 🚀 初始化意图生命周期管理器...');

    // 启动定期清理任务
    _startPeriodicCleanup();

    _initialized = true;
    print('[IntentLifecycleManager] ✅ 意图生命周期管理器初始化完成');
  }

  /// 处理新的语义分析结果，识别和管理意图
  Future<List<Intent>> processSemanticAnalysis(SemanticAnalysisInput analysis) async {
    if (!_initialized) await initialize();

    print('[IntentLifecycleManager] 🔍 处理语义分析结果: "${analysis.content.substring(0, analysis.content.length > 50 ? 50 : analysis.content.length)}..."');

    try {
      // 1. 提取潜在的新意图
      final newIntents = await _extractNewIntents(analysis);

      // 2. 更新现有意图状态
      await _updateExistingIntents(analysis);

      // 3. 检查意图完成或放弃
      await _checkIntentCompletion(analysis);

      // 4. 返回所有受影响的意图
      final affectedIntents = <Intent>[];
      affectedIntents.addAll(newIntents);

      print('[IntentLifecycleManager] ✅ 处理完成，新增 ${newIntents.length} 个意图，当前活跃意图 ${_activeIntents.length} 个');

      return affectedIntents;

    } catch (e) {
      print('[IntentLifecycleManager] ❌ 处理语义分析失败: $e');
      return [];
    }
  }

  /// 提取新意图
  Future<List<Intent>> _extractNewIntents(SemanticAnalysisInput analysis) async {
    // 🔥 修复：首先尝试LLM提取，失败则使用规则提取
    try {
      final llmIntents = await _extractIntentsWithLLM(analysis);
      if (llmIntents.isNotEmpty) {
        print('[IntentLifecycleManager] ✅ LLM成功提取 ${llmIntents.length} 个意图');
        return llmIntents;
      }
    } catch (e) {
      print('[IntentLifecycleManager] ⚠️ LLM提取失败，使用规则提取: $e');
    }

    // 🔥 备用方案：基于规则的意图提取
    final ruleBasedIntents = _extractIntentsWithRules(analysis);
    if (ruleBasedIntents.isNotEmpty) {
      print('[IntentLifecycleManager] ✅ 规则提取 ${ruleBasedIntents.length} 个意图');
    }

    return ruleBasedIntents;
  }

  /// 使用LLM提取意图
  Future<List<Intent>> _extractIntentsWithLLM(SemanticAnalysisInput analysis) async {
    final intentExtractionPrompt = '''
你是一个意图识�����专家。请从用户的对话中识别具体的意图，重点关注用户想要做什么、计划什么、需要什么。

【重要原则】：
1. 只识别明确的、可执行的意图，避免过度解读
2. 区分短期意图（今天内）、中期意图（一周内）、长期意图（一个月内）
3. 考虑意图的紧急性和重要性
4. 注意意图之间的依赖关系

【意图分类】：
- planning: 规划类（制定计划、安排时间等）
- task: 任务类（具体要做的事情）
- learning: 学习类（想要学习、了解某事）
- communication: 沟通类（想要联系某人、讨论某事）
- decision: 决策类（需要做出选择或决定）
- problem_solving: 解决问题类
- entertainment: 娱乐休闲类
- maintenance: 维护类（保持某种状态或习惯）

输出格式为JSON数组，每个意图包含：
{
  "description": "意图的详细描述",
  "category": "意图分类",
  "confidence": 0.8,
  "urgency": "high|medium|low",
  "timeframe": "short|medium|long",
  "trigger_phrases": ["触发这个意图的关键短语"],
  "related_entities": ["相关的实体"],
  "context": {
    "additional_info": "额外的上下文信息"
  }
}

如果没有明确的意图，返回空数组 []。

当前用户说的话：
"${analysis.content}"

当前检测到的实体：${analysis.entities}
当前检测到的情绪：${analysis.emotion}
''';

    final llm = await LLM.create('gpt-4o-mini', systemPrompt: intentExtractionPrompt);
    final response = await llm.createRequest(content: analysis.content);

    print('[IntentLifecycleManager] 🤖 LLM响应: ${response.substring(0, response.length > 200 ? 200 : response.length)}...');

    final jsonStart = response.indexOf('[');
    final jsonEnd = response.lastIndexOf(']');
    if (jsonStart == -1 || jsonEnd == -1) {
      print('[IntentLifecycleManager] ⚠️ LLM响应中未找到JSON数组');
      return [];
    }

    final jsonStr = response.substring(jsonStart, jsonEnd + 1);
    print('[IntentLifecycleManager] 📄 提取的JSON: $jsonStr');

    final List<dynamic> intentsData = jsonDecode(jsonStr);

    final newIntents = <Intent>[];
    for (final intentData in intentsData) {
      if (intentData is Map) {
        final intent = Intent(
          description: intentData['description']?.toString() ?? '',
          category: intentData['category']?.toString() ?? 'task',
          confidence: (intentData['confidence'] as num?)?.toDouble() ?? 0.5,
          triggerPhrases: (intentData['trigger_phrases'] as List?)?.map((e) => e.toString()).toList() ?? [],
          relatedEntities: (intentData['related_entities'] as List?)?.map((e) => e.toString()).toList() ?? analysis.entities,
          context: {
            'urgency': intentData['urgency']?.toString() ?? 'medium',
            'timeframe': intentData['timeframe']?.toString() ?? 'medium',
            'source_emotion': analysis.emotion,
            'source_content': analysis.content,
            'extraction_method': 'llm',
            ...((intentData['context'] as Map?) ?? {}),
          },
        );

        // 🔥 修复：放宽重复检查条件
        if (!_isDuplicateIntent(intent)) {
          _activeIntents[intent.id] = intent;
          newIntents.add(intent);
          _intentUpdatesController.add(intent);
          print('[IntentLifecycleManager] 🎯 新增意图: ${intent.description}');
        } else {
          print('[IntentLifecycleManager] 🔄 跳过重复意图: ${intent.description}');
        }
      }
    }

    return newIntents;
  }

  /// 🔥 新增：基于规则的意图提取（备用方案）
  List<Intent> _extractIntentsWithRules(SemanticAnalysisInput analysis) {
    final content = analysis.content.toLowerCase();
    final intents = <Intent>[];

    // 学习意图
    if (content.contains('学习') || content.contains('教程') || content.contains('了解') || content.contains('学会')) {
      final intent = Intent(
        description: '学习新知识或技能',
        category: 'learning',
        confidence: 0.7,
        triggerPhrases: ['学习', '教程', '了解'],
        relatedEntities: analysis.entities,
        context: {
          'urgency': 'medium',
          'timeframe': 'medium',
          'source_emotion': analysis.emotion,
          'source_content': analysis.content,
          'extraction_method': 'rule_based',
        },
      );
      if (!_isDuplicateIntent(intent)) {
        intents.add(intent);
      }
    }

    // 规划意图
    if (content.contains('计划') || content.contains('规划') || content.contains('准备') || content.contains('安排')) {
      final intent = Intent(
        description: '制定计划或安排时间',
        category: 'planning',
        confidence: 0.8,
        triggerPhrases: ['计划', '规划', '准备', '安排'],
        relatedEntities: analysis.entities,
        context: {
          'urgency': 'high',
          'timeframe': 'short',
          'source_emotion': analysis.emotion,
          'source_content': analysis.content,
          'extraction_method': 'rule_based',
        },
      );
      if (!_isDuplicateIntent(intent)) {
        intents.add(intent);
      }
    }

    // 问题解决意图
    if (content.contains('问题') || content.contains('bug') || content.contains('错误') || content.contains('修复') || content.contains('优化')) {
      final intent = Intent(
        description: '解决技术问题或优化',
        category: 'problem_solving',
        confidence: 0.8,
        triggerPhrases: ['问题', 'bug', '错误', '修复', '优化'],
        relatedEntities: analysis.entities,
        context: {
          'urgency': 'high',
          'timeframe': 'short',
          'source_emotion': analysis.emotion,
          'source_content': analysis.content,
          'extraction_method': 'rule_based',
        },
      );
      if (!_isDuplicateIntent(intent)) {
        intents.add(intent);
      }
    }

    // 任务执行意图
    if (content.contains('做') || content.contains('完成') || content.contains('实现') || content.contains('开发')) {
      final intent = Intent(
        description: '执行具体任务',
        category: 'task',
        confidence: 0.6,
        triggerPhrases: ['做', '完成', '实现', '开发'],
        relatedEntities: analysis.entities,
        context: {
          'urgency': 'medium',
          'timeframe': 'medium',
          'source_emotion': analysis.emotion,
          'source_content': analysis.content,
          'extraction_method': 'rule_based',
        },
      );
      if (!_isDuplicateIntent(intent)) {
        intents.add(intent);
      }
    }

    // 沟通意图
    if (content.contains('讨论') || content.contains('交流') || content.contains('分享') || content.contains('会议')) {
      final intent = Intent(
        description: '进行沟通或交流',
        category: 'communication',
        confidence: 0.7,
        triggerPhrases: ['讨论', '交流', '分享', '会议'],
        relatedEntities: analysis.entities,
        context: {
          'urgency': 'medium',
          'timeframe': 'short',
          'source_emotion': analysis.emotion,
          'source_content': analysis.content,
          'extraction_method': 'rule_based',
        },
      );
      if (!_isDuplicateIntent(intent)) {
        intents.add(intent);
      }
    }

    // 🔥 兜底：如果没有识别到任何意图，创建一个通用意图
    if (intents.isEmpty && analysis.content.trim().isNotEmpty) {
      final intent = Intent(
        description: '基于对话内容的一般性意图',
        category: 'task',
        confidence: 0.4,
        triggerPhrases: [analysis.content.split(' ').first],
        relatedEntities: analysis.entities,
        context: {
          'urgency': 'medium',
          'timeframe': 'medium',
          'source_emotion': analysis.emotion,
          'source_content': analysis.content,
          'extraction_method': 'fallback',
        },
      );
      intents.add(intent);
    }

    // 添加到活跃意图列表
    for (final intent in intents) {
      _activeIntents[intent.id] = intent;
      _intentUpdatesController.add(intent);
      print('[IntentLifecycleManager] 🎯 规则提取意图: ${intent.description}');
    }

    return intents;
  }

  /// 检查是否为重复意图
  bool _isDuplicateIntent(Intent newIntent) {
    // 🔥 修复：放宽重复检查条件，避免误判
    return _activeIntents.values.any((existing) {
      // 检查描述相似性
      final descSimilarity = _calculateSimilarity(existing.description, newIntent.description);
      
      // 检查类别是否相同
      final categorySame = existing.category == newIntent.category;
      
      // 检查关键词重叠
      final keywordOverlap = _calculateKeywordOverlap(existing, newIntent);
      
      // 🔥 修复：提高阈值，只有非常相似的才认为是重复
      // 原来是 0.7，现在改为 0.85，并且需要多个条件同时满足
      final isHighSimilarity = descSimilarity > 0.85;
      final isSignificantOverlap = keywordOverlap > 0.8;
      
      // 只有在描述高度相似、类别相同且关键词大量重叠时才认为重复
      final isDuplicate = isHighSimilarity && categorySame && isSignificantOverlap;
      
      if (isDuplicate) {
        print('[IntentLifecycleManager] 🔍 重复检查: "${newIntent.description}" vs "${existing.description}"');
        print('[IntentLifecycleManager] 📊 相似度: ${(descSimilarity * 100).toInt()}%, 关键词重叠: ${(keywordOverlap * 100).toInt()}%');
      }
      
      return isDuplicate;
    });
  }

  /// 🔥 新增：计算关键词重叠率
  double _calculateKeywordOverlap(Intent existing, Intent newIntent) {
    final existingKeywords = <String>{};
    existingKeywords.addAll(existing.triggerPhrases);
    existingKeywords.addAll(existing.relatedEntities);
    existingKeywords.addAll(existing.description.toLowerCase().split(' '));
    
    final newKeywords = <String>{};
    newKeywords.addAll(newIntent.triggerPhrases);
    newKeywords.addAll(newIntent.relatedEntities);
    newKeywords.addAll(newIntent.description.toLowerCase().split(' '));
    
    if (existingKeywords.isEmpty || newKeywords.isEmpty) return 0.0;
    
    final intersection = existingKeywords.intersection(newKeywords);
    final union = existingKeywords.union(newKeywords);
    
    return intersection.length / union.length;
  }

  /// 简单的字符串相似性计算
  double _calculateSimilarity(String str1, String str2) {
    if (str1 == str2) return 1.0;
    if (str1.isEmpty || str2.isEmpty) return 0.0;

    final words1 = str1.toLowerCase().split(' ').toSet();
    final words2 = str2.toLowerCase().split(' ').toSet();

    final intersection = words1.intersection(words2);
    final union = words1.union(words2);

    return intersection.length / union.length;
  }

  /// 更新现有意图状态
  Future<void> _updateExistingIntents(SemanticAnalysisInput analysis) async {
    final updatePrompt = '''
你是一个意图状态追踪专家。请分析用户的新对话，判断是否影响现有的意图状态。

【状态转换规则】：
- forming → clarifying: 用户开始详细描述或询问细节
- forming/clarifying → executing: 用户开始实际行动
- executing → paused: 用户暂停或转向其他事情
- paused → executing: 用户重新开始
- any → completed: 用户明确表示完成
- any → abandoned: 用户明确放弃或转向完全不同的方向

【分析要点】：
1. 寻找与现有意图相关的关键词或实体
2. 识别状态变化的信号词（"开始"、"完成"、"暂停"、"放弃"等）
3. 考虑时间因素（长时间没提及可能意味着暂停或放弃）

输出格式为JSON数组：
[
  {
    "intent_id": "意图ID",
    "new_state": "新状态",
    "reason": "状态变化原因",
    "confidence": 0.8
  }
]

如果没有影响任何现有意图，返回 []。

当前用户说的话：
"${analysis.content}"

现有活跃意图：
${_activeIntents.values.map((i) => '${i.id}: ${i.description} (${i.state})').join('\n')}
''';

    try {
      if (_activeIntents.isEmpty) return;

      final llm = await LLM.create('gpt-4o-mini', systemPrompt: updatePrompt);
      final response = await llm.createRequest(content: analysis.content);

      final jsonStart = response.indexOf('[');
      final jsonEnd = response.lastIndexOf(']');
      if (jsonStart == -1 || jsonEnd == -1) return;

      final jsonStr = response.substring(jsonStart, jsonEnd + 1);
      final List<dynamic> updates = jsonDecode(jsonStr);

      for (final update in updates) {
        if (update is Map) {
          final intentId = update['intent_id']?.toString();
          final newStateStr = update['new_state']?.toString();
          final reason = update['reason']?.toString() ?? '状态更新';
          final confidence = (update['confidence'] as num?)?.toDouble() ?? 0.5;

          if (intentId != null && newStateStr != null && _activeIntents.containsKey(intentId)) {
            final intent = _activeIntents[intentId]!;
            final newState = _parseIntentState(newStateStr);

            if (newState != null && newState != intent.state && confidence > 0.6) {
              intent.updateState(newState, reason);
              _intentUpdatesController.add(intent);

              print('[IntentLifecycleManager] 🔄 意图状态更新: ${intent.description} -> ${newState}');

              // 如果意图完成或放弃，移到完成列表
              if (newState == IntentLifecycleState.completed || newState == IntentLifecycleState.abandoned) {
                _activeIntents.remove(intentId);
                _completedIntents.add(intent);
              }
            }
          }
        }
      }

    } catch (e) {
      print('[IntentLifecycleManager] ❌ 更新意图状态失败: $e');
    }
  }

  /// 解析意图状态字符串
  IntentLifecycleState? _parseIntentState(String stateStr) {
    switch (stateStr.toLowerCase()) {
      case 'forming':
        return IntentLifecycleState.forming;
      case 'clarifying':
        return IntentLifecycleState.clarifying;
      case 'executing':
        return IntentLifecycleState.executing;
      case 'paused':
        return IntentLifecycleState.paused;
      case 'completed':
        return IntentLifecycleState.completed;
      case 'abandoned':
        return IntentLifecycleState.abandoned;
      default:
        return null;
    }
  }

  /// 检查意图完成情况
  Future<void> _checkIntentCompletion(SemanticAnalysisInput analysis) async {
    // 基于时间的自动状态更新
    final now = DateTime.now();
    final intentsToUpdate = <Intent>[];

    for (final intent in _activeIntents.values) {
      final timeSinceUpdate = now.difference(intent.lastUpdated).inHours;

      // 超过24小时没有更新的意图可能需要暂停
      if (timeSinceUpdate > 24 && intent.state == IntentLifecycleState.executing) {
        intent.updateState(IntentLifecycleState.paused, '长时间无活动，自动暂停');
        intentsToUpdate.add(intent);
      }

      // 超过一周没有更新的形成中意图可能需要放弃
      if (timeSinceUpdate > 168 && intent.state == IntentLifecycleState.forming) {
        intent.updateState(IntentLifecycleState.abandoned, '长时间无进展，自动放弃');
        intentsToUpdate.add(intent);
      }
    }

    // 移除完成或放弃的意图
    for (final intent in intentsToUpdate) {
      if (intent.state == IntentLifecycleState.completed || intent.state == IntentLifecycleState.abandoned) {
        _activeIntents.remove(intent.id);
        _completedIntents.add(intent);
      }
      _intentUpdatesController.add(intent);
    }
  }

  /// 启动定期清理
  void _startPeriodicCleanup() {
    _periodicCleanupTimer = Timer.periodic(Duration(hours: 1), (timer) {
      _performCleanup();
    });
  }

  /// 执行清理操作
  void _performCleanup() {
    final now = DateTime.now();

    // ���理过期的完成意图（保留最近30天）
    _completedIntents.removeWhere((intent) {
      return intent.completedAt != null &&
             now.difference(intent.completedAt!).inDays > 30;
    });

    print('[IntentLifecycleManager] 🧹 定期清理完成，保留 ${_completedIntents.length} 个完成意图');
  }

  /// 获取活跃意图列表
  List<Intent> getActiveIntents() {
    return _activeIntents.values.toList();
  }

  /// 获取特定状态的意图
  List<Intent> getIntentsByState(IntentLifecycleState state) {
    return _activeIntents.values.where((intent) => intent.state == state).toList();
  }

  /// 获取特定类别的意图
  List<Intent> getIntentsByCategory(String category) {
    return _activeIntents.values.where((intent) => intent.category == category).toList();
  }

  /// 手动更新意图状态
  bool updateIntentState(String intentId, IntentLifecycleState newState, String reason) {
    final intent = _activeIntents[intentId];
    if (intent == null) return false;

    intent.updateState(newState, reason);
    _intentUpdatesController.add(intent);

    // 移除完成或放弃的意图
    if (newState == IntentLifecycleState.completed || newState == IntentLifecycleState.abandoned) {
      _activeIntents.remove(intentId);
      _completedIntents.add(intent);
    }

    return true;
  }

  /// 获取意图统计信息
  Map<String, dynamic> getIntentStatistics() {
    final stateDistribution = <String, int>{};
    final categoryDistribution = <String, int>{};

    for (final intent in _activeIntents.values) {
      final state = intent.state.toString().split('.').last;
      final category = intent.category;

      stateDistribution[state] = (stateDistribution[state] ?? 0) + 1;
      categoryDistribution[category] = (categoryDistribution[category] ?? 0) + 1;
    }

    return {
      'total_active': _activeIntents.length,
      'total_completed': _completedIntents.length,
      'state_distribution': stateDistribution,
      'category_distribution': categoryDistribution,
      'last_update': DateTime.now().toIso8601String(),
    };
  }

  /// 搜索意图
  List<Intent> searchIntents(String query) {
    final queryLower = query.toLowerCase();
    final results = <Intent>[];

    // 搜索活跃意图
    for (final intent in _activeIntents.values) {
      if (intent.description.toLowerCase().contains(queryLower) ||
          intent.category.toLowerCase().contains(queryLower) ||
          intent.triggerPhrases.any((phrase) => phrase.toLowerCase().contains(queryLower))) {
        results.add(intent);
      }
    }

    return results;
  }

  /// 释放资源
  void dispose() {
    _periodicCleanupTimer?.cancel();
    _intentUpdatesController.close();
    _activeIntents.clear();
    _completedIntents.clear();
    _initialized = false;
    print('[IntentLifecycleManager] 🔌 意图生命周期管理器已释放');
  }
}
