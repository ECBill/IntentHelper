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
你是一个专业的意图识别专家。请从用户的对话中识别具体的、明确的、可执行的意图。

【重要原则】：
1. 只识别用户明确表达的、具有实际行动价值的意图
2. 避免过度解读或创造不存在的意图
3. 如果对话仅是闲聊、确认、或者没有明确行动导向，返回空数组
4. 意图必须具备以下特征之一：
   - 明确的行动计划（"我要做..."、"准备..."、"计划..."）
   - 具体的学习目标（"学习..."、"了解..."、"掌握..."）
   - 明确的问题解决需求（"解决..."、"修复..."、"优化..."）
   - 具体的沟通需求（"讨论..."、"会议..."、"联系..."）
   - 明确的决策需求（"选择..."、"决定..."、"考虑..."）

【严格过滤条件】：
- 置信度必须≥0.7才输出
- 避免识别模糊的、通用的意图
- 如果用户只是在描述现状、表达感受、或进行日常对话，不要强行识别意图

【意图分类】：
- learning: 学习类（明确的学习目标）
- planning: 规划类（具体的计划制定）
- task: 任务类（明确的执行任务）
- communication: 沟通类（具体的沟通需求）
- decision: 决策类（明确的选择或决定）
- problem_solving: 解决问题类（具体的问题和解决方案）
- research: 研究类（深入了解某个领域）
- optimization: 优化类（改进现有的事物）

输出格式为JSON数组，每个意图包含：
{
  "description": "简洁明确的意图描述，描述用户想要做什么",
  "category": "意图分类",
  "confidence": 0.8,
  "urgency": "high|medium|low",
  "timeframe": "short|medium|long",
  "trigger_phrases": ["触发这个意图的关键短语"],
  "related_entities": ["相关的实体"],
  "actionable": true,
  "specific_context": "具体的上下文信息"
}

重要：如果没有明确的、可执行的意图，必须返回空数组 []。不要创造不存在的意图。

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
        final confidence = (intentData['confidence'] as num?)?.toDouble() ?? 0.5;
        final actionable = intentData['actionable'] as bool? ?? false;

        // 🔥 新增：严格的质量检查
        if (confidence < 0.7 || !actionable) {
          print('[IntentLifecycleManager] ❌ 跳过低质量意图: ${intentData['description']} (置信度: $confidence, 可执行: $actionable)');
          continue;
        }

        final description = intentData['description']?.toString() ?? '';

        // 🔥 新增：过滤通用描述
        if (_isGenericDescription(description)) {
          print('[IntentLifecycleManager] ❌ 跳过通用描述: $description');
          continue;
        }

        final intent = Intent(
          description: description,
          category: intentData['category']?.toString() ?? 'task',
          confidence: confidence,
          triggerPhrases: (intentData['trigger_phrases'] as List?)?.map((e) => e.toString()).toList() ?? [],
          relatedEntities: (intentData['related_entities'] as List?)?.map((e) => e.toString()).toList() ?? analysis.entities,
          context: {
            'urgency': intentData['urgency']?.toString() ?? 'medium',
            'timeframe': intentData['timeframe']?.toString() ?? 'medium',
            'source_emotion': analysis.emotion,
            'source_content': analysis.content,
            'extraction_method': 'llm',
            'actionable': actionable,
            'specific_context': intentData['specific_context']?.toString() ?? '',
          },
        );

        // 🔥 增强：更严格的重复检查
        if (!_isDuplicateIntent(intent)) {
          _activeIntents[intent.id] = intent;
          newIntents.add(intent);
          _intentUpdatesController.add(intent);
          print('[IntentLifecycleManager] 🎯 新增高质量意图: ${intent.description} (置信度: ${(confidence * 100).toInt()}%)');
        } else {
          print('[IntentLifecycleManager] 🔄 跳过重复意图: ${intent.description}');
        }
      }
    }

    return newIntents;
  }

  /// 🔥 新增：检查是否为通用描述
  bool _isGenericDescription(String description) {
    final genericPatterns = [
      '基于对话内容',
      '一般性意图',
      '通用意图',
      '普通',
      '基础',
      '简单',
      '常规',
      '默认',
      'general',
      'generic',
      'basic',
      'common',
      'normal',
    ];

    final lowerDesc = description.toLowerCase();
    return genericPatterns.any((pattern) => lowerDesc.contains(pattern.toLowerCase()));
  }

  /// 🔥 优化：基于规则的意图提取（更严格的条件）
  List<Intent> _extractIntentsWithRules(SemanticAnalysisInput analysis) {
    final content = analysis.content.toLowerCase();
    final intents = <Intent>[];

    // 🔥 新增：内容质量预检查
    if (!_isContentMeaningful(content)) {
      print('[IntentLifecycleManager] ℹ️ 内容不具备意图分析价值，跳过规则提取');
      return intents;
    }

    // 学习意图 - 更严格的匹配
    if (_hasLearningIntent(content)) {
      final specificLearningGoal = _extractLearningGoal(content, analysis.entities);
      if (specificLearningGoal.isNotEmpty) {
        final intent = Intent(
          description: '学习：$specificLearningGoal',
          category: 'learning',
          confidence: 0.8,
          triggerPhrases: _extractLearningTriggers(content),
          relatedEntities: analysis.entities,
          context: {
            'urgency': 'medium',
            'timeframe': 'medium',
            'source_emotion': analysis.emotion,
            'source_content': analysis.content,
            'extraction_method': 'rule_based_enhanced',
            'specific_goal': specificLearningGoal,
          },
        );
        if (!_isDuplicateIntent(intent)) {
          intents.add(intent);
        }
      }
    }

    // 规划意图 - 更具体的匹配
    if (_hasPlanningIntent(content)) {
      final specificPlan = _extractPlanningGoal(content, analysis.entities);
      if (specificPlan.isNotEmpty) {
        final intent = Intent(
          description: '规划：$specificPlan',
          category: 'planning',
          confidence: 0.85,
          triggerPhrases: _extractPlanningTriggers(content),
          relatedEntities: analysis.entities,
          context: {
            'urgency': 'high',
            'timeframe': 'short',
            'source_emotion': analysis.emotion,
            'source_content': analysis.content,
            'extraction_method': 'rule_based_enhanced',
            'specific_plan': specificPlan,
          },
        );
        if (!_isDuplicateIntent(intent)) {
          intents.add(intent);
        }
      }
    }

    // 问题解决意图 - 识别具体问题
    if (_hasProblemSolvingIntent(content)) {
      final specificProblem = _extractProblemDescription(content, analysis.entities);
      if (specificProblem.isNotEmpty) {
        final intent = Intent(
          description: '解决问题：$specificProblem',
          category: 'problem_solving',
          confidence: 0.85,
          triggerPhrases: _extractProblemTriggers(content),
          relatedEntities: analysis.entities,
          context: {
            'urgency': 'high',
            'timeframe': 'short',
            'source_emotion': analysis.emotion,
            'source_content': analysis.content,
            'extraction_method': 'rule_based_enhanced',
            'specific_problem': specificProblem,
          },
        );
        if (!_isDuplicateIntent(intent)) {
          intents.add(intent);
        }
      }
    }

    // 任务执行意图 - 识别具体任务
    if (_hasTaskIntent(content)) {
      final specificTask = _extractTaskDescription(content, analysis.entities);
      if (specificTask.isNotEmpty) {
        final intent = Intent(
          description: '执行任务：$specificTask',
          category: 'task',
          confidence: 0.75,
          triggerPhrases: _extractTaskTriggers(content),
          relatedEntities: analysis.entities,
          context: {
            'urgency': 'medium',
            'timeframe': 'medium',
            'source_emotion': analysis.emotion,
            'source_content': analysis.content,
            'extraction_method': 'rule_based_enhanced',
            'specific_task': specificTask,
          },
        );
        if (!_isDuplicateIntent(intent)) {
          intents.add(intent);
        }
      }
    }

    // 沟通意图 - 识别具体沟通目标
    if (_hasCommunicationIntent(content)) {
      final specificCommunication = _extractCommunicationGoal(content, analysis.entities);
      if (specificCommunication.isNotEmpty) {
        final intent = Intent(
          description: '沟通：$specificCommunication',
          category: 'communication',
          confidence: 0.8,
          triggerPhrases: _extractCommunicationTriggers(content),
          relatedEntities: analysis.entities,
          context: {
            'urgency': 'medium',
            'timeframe': 'short',
            'source_emotion': analysis.emotion,
            'source_content': analysis.content,
            'extraction_method': 'rule_based_enhanced',
            'specific_communication': specificCommunication,
          },
        );
        if (!_isDuplicateIntent(intent)) {
          intents.add(intent);
        }
      }
    }

    // 🔥 移除：删除兜底逻辑，不再创建通用意图

    // 添加到活跃意图列表
    for (final intent in intents) {
      _activeIntents[intent.id] = intent;
      _intentUpdatesController.add(intent);
      print('[IntentLifecycleManager] 🎯 规则提取高质量意图: ${intent.description}');
    }

    print('[IntentLifecycleManager] 📊 规则提取结果: ${intents.length} 个高质量意图');
    return intents;
  }

  /// 🔥 新增：检查内容是否有意义
  bool _isContentMeaningful(String content) {
    // 过滤太短的内容
    if (content.trim().length < 3) return false;

    // 过滤纯标点或数字
    if (RegExp(r'^[\s\d\p{P}]+$', unicode: true).hasMatch(content)) return false;

    // 过滤系统消息
    final systemMessages = [
      '录音开始', '录音结束', '系统启动', '连接成功', '断开连接',
      '开始录音', '停止录音', '检测到', '正在处理', '完成处理',
      'ok', 'yes', 'no', '好的', '是的', '不是', '嗯', '哦', '啊'
    ];

    return !systemMessages.any((msg) => content.contains(msg));
  }

  /// 🔥 新增：检查学习意图
  bool _hasLearningIntent(String content) {
    final learningKeywords = [
      '学习', '学会', '掌握', '了解', '研究', '深入', '教程', '课程',
      '知识', '技能', '方法', '原理', '概念', '理论', '实践'
    ];

    // 需要有明确的学习动词 + 学习对象
    return learningKeywords.any((keyword) => content.contains(keyword)) &&
           (content.contains('如何') || content.contains('怎么') ||
            content.contains('想要') || content.contains('需要') ||
            content.contains('希望'));
  }

  /// 🔥 新增：提取学习目标
  String _extractLearningGoal(String content, List<String> entities) {
    // 尝试从实体中找到学习目标
    final techEntities = entities.where((e) =>
      e.toLowerCase().contains('flutter') ||
      e.toLowerCase().contains('ai') ||
      e.toLowerCase().contains('编程') ||
      e.toLowerCase().contains('技术') ||
      e.toLowerCase().contains('语言')
    ).toList();

    if (techEntities.isNotEmpty) {
      return techEntities.first;
    }

    // 从内容中提取
    final patterns = [
      RegExp(r'学习(.{1,20}?)(?:[，。！？\s]|$)'),
      RegExp(r'了解(.{1,20}?)(?:[，。！？\s]|$)'),
      RegExp(r'掌握(.{1,20}?)(?:[，。！？\s]|$)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(content);
      if (match != null && match.group(1) != null) {
        final goal = match.group(1)!.trim();
        if (goal.isNotEmpty && goal.length > 1) {
          return goal;
        }
      }
    }

    return '';
  }

  /// 🔥 新增：提取学习触发词
  List<String> _extractLearningTriggers(String content) {
    final triggers = <String>[];
    final learningWords = ['学习', '了解', '掌握', '学会', '研究'];

    for (final word in learningWords) {
      if (content.contains(word)) {
        triggers.add(word);
      }
    }

    return triggers;
  }

  /// 🔥 新增：检查规划意图
  bool _hasPlanningIntent(String content) {
    final planningKeywords = ['计划', '规划', '准备', '安排', '制定', '设计', '策划'];
    final actionKeywords = ['做', '进行', '开始', '执行', '实施'];

    return planningKeywords.any((keyword) => content.contains(keyword)) ||
           (actionKeywords.any((keyword) => content.contains(keyword)) &&
            (content.contains('项目') || content.contains('工作') || content.contains('任务')));
  }

  /// 🔥 新增：提取规划目标
  String _extractPlanningGoal(String content, List<String> entities) {
    final projectEntities = entities.where((e) =>
      e.contains('项目') || e.contains('工作') || e.contains('计划') || e.contains('任务')
    ).toList();

    if (projectEntities.isNotEmpty) {
      return projectEntities.first;
    }

    final patterns = [
      RegExp(r'计划(.{1,30}?)(?:[，。！？\s]|$)'),
      RegExp(r'规划(.{1,30}?)(?:[，。！？\s]|$)'),
      RegExp(r'准备(.{1,30}?)(?:[，。！？\s]|$)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(content);
      if (match != null && match.group(1) != null) {
        final goal = match.group(1)!.trim();
        if (goal.isNotEmpty && goal.length > 1) {
          return goal;
        }
      }
    }

    return '';
  }

  List<String> _extractPlanningTriggers(String content) {
    final triggers = <String>[];
    final planningWords = ['计划', '规划', '准备', '安排', '制定'];

    for (final word in planningWords) {
      if (content.contains(word)) {
        triggers.add(word);
      }
    }

    return triggers;
  }

  /// 🔥 新增：检查问题解决意图
  bool _hasProblemSolvingIntent(String content) {
    final problemKeywords = ['问题', 'bug', '错误', '故障', '异常', '失败'];
    final solutionKeywords = ['解决', '修复', '优化', '改进', '处理', '调试'];

    return problemKeywords.any((keyword) => content.toLowerCase().contains(keyword.toLowerCase())) ||
           solutionKeywords.any((keyword) => content.contains(keyword));
  }

  String _extractProblemDescription(String content, List<String> entities) {
    final problemEntities = entities.where((e) =>
      e.toLowerCase().contains('bug') || e.toLowerCase().contains('问题') ||
      e.toLowerCase().contains('错误') || e.toLowerCase().contains('优化')
    ).toList();

    if (problemEntities.isNotEmpty) {
      return problemEntities.first;
    }

    final patterns = [
      RegExp(r'问题(.{1,30}?)(?:[，。！？\s]|$)'),
      RegExp(r'错误(.{1,30}?)(?:[，。！？\s]|$)'),
      RegExp(r'优化(.{1,30}?)(?:[，。！？\s]|$)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(content);
      if (match != null && match.group(1) != null) {
        final problem = match.group(1)!.trim();
        if (problem.isNotEmpty && problem.length > 1) {
          return problem;
        }
      }
    }

    return '';
  }

  List<String> _extractProblemTriggers(String content) {
    final triggers = <String>[];
    final problemWords = ['问题', '错误', '优化', '修复', '解决'];

    for (final word in problemWords) {
      if (content.toLowerCase().contains(word.toLowerCase())) {
        triggers.add(word);
      }
    }

    return triggers;
  }

  /// 🔥 新增：检查任务意图
  bool _hasTaskIntent(String content) {
    final taskKeywords = ['做', '完成', '实现', '开发', '构建', '创建', '制作'];
    final objectKeywords = ['功能', '模块', '组件', '页面', '接口', '系统'];

    return taskKeywords.any((keyword) => content.contains(keyword)) &&
           (objectKeywords.any((keyword) => content.contains(keyword)) ||
            content.contains('需要') || content.contains('要'));
  }

  String _extractTaskDescription(String content, List<String> entities) {
    final taskEntities = entities.where((e) =>
      e.contains('功能') || e.contains('模块') || e.contains('开发') ||
      e.contains('任务') || e.contains('工作')
    ).toList();

    if (taskEntities.isNotEmpty) {
      return taskEntities.first;
    }

    final patterns = [
      RegExp(r'做(.{1,30}?)(?:[，。！？\s]|$)'),
      RegExp(r'完成(.{1,30}?)(?:[，。！？\s]|$)'),
      RegExp(r'开发(.{1,30}?)(?:[，。！？\s]|$)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(content);
      if (match != null && match.group(1) != null) {
        final task = match.group(1)!.trim();
        if (task.isNotEmpty && task.length > 1) {
          return task;
        }
      }
    }

    return '';
  }

  List<String> _extractTaskTriggers(String content) {
    final triggers = <String>[];
    final taskWords = ['做', '完成', '实现', '开发', '构建'];

    for (final word in taskWords) {
      if (content.contains(word)) {
        triggers.add(word);
      }
    }

    return triggers;
  }

  /// 🔥 新增：检查沟通意图
  bool _hasCommunicationIntent(String content) {
    final commKeywords = ['讨论', '交流', '分享', '会议', '联系', '沟通', '商量'];

    return commKeywords.any((keyword) => content.contains(keyword)) &&
           (content.contains('需要') || content.contains('想要') || content.contains('计划'));
  }

  String _extractCommunicationGoal(String content, List<String> entities) {
    final commEntities = entities.where((e) =>
      e.contains('会议') || e.contains('讨论') || e.contains('交流') ||
      e.contains('团队') || e.contains('协作')
    ).toList();

    if (commEntities.isNotEmpty) {
      return commEntities.first;
    }

    final patterns = [
      RegExp(r'讨论(.{1,30}?)(?:[，。！？\s]|$)'),
      RegExp(r'交流(.{1,30}?)(?:[，。！？\s]|$)'),
      RegExp(r'会议(.{1,30}?)(?:[，。！？\s]|$)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(content);
      if (match != null && match.group(1) != null) {
        final goal = match.group(1)!.trim();
        if (goal.isNotEmpty && goal.length > 1) {
          return goal;
        }
      }
    }

    return '';
  }

  List<String> _extractCommunicationTriggers(String content) {
    final triggers = <String>[];
    final commWords = ['讨论', '交流', '分享', '会议', '沟通'];

    for (final word in commWords) {
      if (content.contains(word)) {
        triggers.add(word);
      }
    }

    return triggers;
  }

  /// 🔥 增强：更严格的重复检查
  bool _isDuplicateIntent(Intent newIntent) {
    return _activeIntents.values.any((existing) {
      // 检查描述相似性
      final descSimilarity = _calculateSimilarity(existing.description, newIntent.description);

      // 检查类别是否相同
      final categorySame = existing.category == newIntent.category;

      // 检查关键词重叠
      final keywordOverlap = _calculateKeywordOverlap(existing, newIntent);

      // 🔥 修复：提高阈值，只有非常相似的才认为是重复
      // 只有在描述高度相似、类别相同且关键词大量重叠时才认为重复
      final isHighSimilarity = descSimilarity > 0.85;
      final isSignificantOverlap = keywordOverlap > 0.8;

      final isDuplicate = isHighSimilarity && categorySame && isSignificantOverlap;

      if (isDuplicate) {
        print('[IntentLifecycleManager] 🔍 重复检查: "${newIntent.description}" vs "${existing.description}"');
        print('[IntentLifecycleManager] 📊 相似度: ${(descSimilarity * 100).toInt()}%, 关键词重叠: ${(keywordOverlap * 100).toInt()}%');
      }

      return isDuplicate;
    });
  }

  /// 计算文本相似性
  double _calculateSimilarity(String text1, String text2) {
    final words1 = text1.toLowerCase().split(RegExp(r'\W+'));
    final words2 = text2.toLowerCase().split(RegExp(r'\W+'));

    if (words1.isEmpty || words2.isEmpty) return 0.0;

    final set1 = words1.toSet();
    final set2 = words2.toSet();

    final intersection = set1.intersection(set2);
    final union = set1.union(set2);

    return union.isEmpty ? 0.0 : intersection.length / union.length;
  }

  /// 计算关键词重叠度
  double _calculateKeywordOverlap(Intent intent1, Intent intent2) {
    final keywords1 = intent1.triggerPhrases.toSet();
    final keywords2 = intent2.triggerPhrases.toSet();

    if (keywords1.isEmpty || keywords2.isEmpty) return 0.0;

    final intersection = keywords1.intersection(keywords2);
    final union = keywords1.union(keywords2);

    return union.isEmpty ? 0.0 : intersection.length / union.length;
  }

  /// 更新现有意图状态
  Future<void> _updateExistingIntents(SemanticAnalysisInput analysis) async {
    for (final intent in _activeIntents.values) {
      // 检查意图是否与当前对话相关
      final isRelated = _isIntentRelatedToContent(intent, analysis);

      if (isRelated) {
        // 更新意图的相关信息
        intent.context['last_mentioned'] = DateTime.now().toIso8601String();
        intent.context['mention_count'] = ((intent.context['mention_count'] as int?) ?? 0) + 1;

        // 可能的状态变化
        if (intent.state == IntentLifecycleState.forming) {
          intent.state = IntentLifecycleState.executing;
          _intentUpdatesController.add(intent);
        }
      }
    }
  }

  /// 检查意图是否与内容相关
  bool _isIntentRelatedToContent(Intent intent, SemanticAnalysisInput analysis) {
    // 检查触发短语
    final hasMatchingPhrases = intent.triggerPhrases.any(
      (phrase) => analysis.content.toLowerCase().contains(phrase.toLowerCase())
    );

    // 检查相关实体
    final hasMatchingEntities = intent.relatedEntities.any(
      (entity) => analysis.entities.any(
        (analysisEntity) => entity.toLowerCase().contains(analysisEntity.toLowerCase()) ||
                           analysisEntity.toLowerCase().contains(entity.toLowerCase())
      )
    );

    // 检查类别相关性
    final hasCategoryMatch = intent.category == analysis.intent;

    return hasMatchingPhrases || hasMatchingEntities || hasCategoryMatch;
  }

  /// 检查意图完成或放弃
  Future<void> _checkIntentCompletion(SemanticAnalysisInput analysis) async {
    final completionKeywords = ['完成', '完成了', '做完', '解决了', '学会了', '已经'];
    final cancellationKeywords = ['不做了', '放弃', '算了', '不需要'];

    final content = analysis.content.toLowerCase();

    for (final intent in _activeIntents.values.toList()) {
      // 检查完成
      if (completionKeywords.any((keyword) => content.contains(keyword))) {
        if (_isIntentRelatedToContent(intent, analysis)) {
          intent.state = IntentLifecycleState.completed;
          intent.context['completion_time'] = DateTime.now().toIso8601String();
          _activeIntents.remove(intent.id);
          _completedIntents.add(intent);
          _intentUpdatesController.add(intent);
          print('[IntentLifecycleManager] ✅ 意图已完成: ${intent.description}');
        }
      }

      // 检查取消
      if (cancellationKeywords.any((keyword) => content.contains(keyword))) {
        if (_isIntentRelatedToContent(intent, analysis)) {
          intent.state = IntentLifecycleState.abandoned;
          intent.context['cancellation_time'] = DateTime.now().toIso8601String();
          _activeIntents.remove(intent.id);
          _intentUpdatesController.add(intent);
          print('[IntentLifecycleManager] ❌ 意图已取消: ${intent.description}');
        }
      }
    }
  }

  /// 启动定期清理任务
  void _startPeriodicCleanup() {
    _periodicCleanupTimer = Timer.periodic(Duration(minutes: 30), (timer) {
      _cleanupOldIntents();
    });
  }

  /// 清理过期意图
  void _cleanupOldIntents() {
    final now = DateTime.now();
    final toRemove = <String>[];

    for (final entry in _activeIntents.entries) {
      final intent = entry.value;
      final createdAt = intent.createdAt;

      // 移除超过24小时的forming意图
      if (intent.state == IntentLifecycleState.forming &&
          now.difference(createdAt).inHours > 24) {
        toRemove.add(entry.key);
      }

      // 移除超过72小时的executing意图
      if (intent.state == IntentLifecycleState.executing &&
          now.difference(createdAt).inHours > 72) {
        toRemove.add(entry.key);
      }
    }

    for (final id in toRemove) {
      final intent = _activeIntents.remove(id);
      if (intent != null) {
        intent.state = IntentLifecycleState.abandoned;
        _intentUpdatesController.add(intent);
        print('[IntentLifecycleManager] ⏰ 意图已过期: ${intent.description}');
      }
    }

    if (toRemove.isNotEmpty) {
      print('[IntentLifecycleManager] 🧹 清理了 ${toRemove.length} 个过期意图');
    }
  }

  /// 获取活跃意图
  List<Intent> getActiveIntents() {
    return _activeIntents.values.toList();
  }

  /// 获取已完成意图
  List<Intent> getCompletedIntents() {
    return _completedIntents;
  }

  /// 搜索意图
  List<Intent> searchIntents(String query) {
    final allIntents = [..._activeIntents.values, ..._completedIntents];
    return allIntents.where((intent) {
      return intent.description.toLowerCase().contains(query.toLowerCase()) ||
             intent.category.toLowerCase().contains(query.toLowerCase()) ||
             intent.triggerPhrases.any((phrase) => phrase.toLowerCase().contains(query.toLowerCase()));
    }).toList();
  }

  /// 获取意图统计
  Map<String, dynamic> getIntentStatistics() {
    final stats = <String, dynamic>{};

    // 按状态分组
    final byState = <String, int>{};
    for (final intent in _activeIntents.values) {
      final state = intent.state.toString().split('.').last;
      byState[state] = (byState[state] ?? 0) + 1;
    }
    stats['by_state'] = byState;

    // 按类别分组
    final byCategory = <String, int>{};
    for (final intent in _activeIntents.values) {
      byCategory[intent.category] = (byCategory[intent.category] ?? 0) + 1;
    }
    stats['by_category'] = byCategory;

    stats['total_active'] = _activeIntents.length;
    stats['total_completed'] = _completedIntents.length;

    return stats;
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

  /// 分析意图（新增方法）
  Future<void> analyzeIntent(String content, String? intentHint) async {
    if (!_initialized) await initialize();

    try {
      // 创建语义分析输入
      final analysis = SemanticAnalysisInput(
        content: content,
        intent: intentHint ?? '',
        entities: [],
        emotion: 'neutral',
        timestamp: DateTime.now(),
        additionalContext: {},
      );

      // 处理语义分析
      await processSemanticAnalysis(analysis);
    } catch (e) {
      print('[IntentLifecycleManager] ❌ 分析意图失败: $e');
    }
  }

  /// 清除所有意图（新增方法）
  Future<void> clearAllIntents() async {
    try {
      _activeIntents.clear();
      _completedIntents.clear();
      print('[IntentLifecycleManager] 🧹 已清除所有意图');
    } catch (e) {
      print('[IntentLifecycleManager] ❌ 清除意图失败: $e');
    }
  }
}
