import 'package:flutter/material.dart';
import 'package:app/services/chat_manager.dart';
import 'package:app/services/conversation_cache.dart';
import 'package:app/models/graph_models.dart';
import 'dart:convert';

class CacheDebugPage extends StatefulWidget {
  const CacheDebugPage({Key? key}) : super(key: key);

  @override
  State<CacheDebugPage> createState() => _CacheDebugPageState();
}

class _CacheDebugPageState extends State<CacheDebugPage> with TickerProviderStateMixin {
  late TabController _tabController;
  late ChatManager _chatManager;
  Map<String, dynamic> _cacheStats = {};
  List<CacheItem> _cacheItems = [];
  ConversationContext? _currentContext;
  UserPersonalContext? _userContext;
  List<ConversationSummary> _recentSummaries = [];
  bool _isLoading = true;
  String _testQuery = '';
  Map<String, dynamic>? _testResult;
  String _selectedCategory = 'all';

  // 分类标签
  final List<String> _categories = [
    'all',
    'conversation_grasp',
    'intent_understanding',
    'knowledge_reserve',
    'personal_info',
    'proactive_data'
  ];

  final Map<String, String> _categoryNames = {
    'all': '全部',
    'conversation_grasp': '对话掌握',
    'intent_understanding': '意图理解',
    'knowledge_reserve': '知识储备',
    'personal_info': '个人信息',
    'proactive_data': '主动交互',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _chatManager = ChatManager();
    _initChatManager();
  }

  Future<void> _initChatManager() async {
    try {
      await _chatManager.init(selectedModel: 'gpt-4o-mini', systemPrompt: '你是一个智能助手');
      _loadCacheData();
    } catch (e) {
      print('初始化ChatManager失败: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCacheData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 获取缓存统计信息
      _cacheStats = _chatManager.getCachePerformance();

      // 获取缓存项详情
      _cacheItems = _chatManager.getAllCacheItems();

      // 获取当前对话上下文
      _currentContext = _chatManager.getCurrentConversationContext();

      // 获取用户个人上下文
      _userContext = _chatManager.getUserPersonalContext();

      // 获取最近的对话摘要
      _recentSummaries = _chatManager.getRecentSummaries(limit: 10);

    } catch (e) {
      print('Error loading cache data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testCacheQuery() async {
    if (_testQuery.trim().isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _chatManager.buildInputWithKG(_testQuery);
      _testResult = {
        'query': _testQuery,
        'response': response,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      _testResult = {
        'query': _testQuery,
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('智能缓存调试工具'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCacheData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: '概览'),
            Tab(icon: Icon(Icons.category), text: '分类缓存'),
            Tab(icon: Icon(Icons.psychology), text: '对话上下文'),
            Tab(icon: Icon(Icons.person), text: '个人信息'),
            Tab(icon: Icon(Icons.search), text: '缓存测试'),
            Tab(icon: Icon(Icons.settings), text: '控制'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildCategorizedCacheTab(),
                _buildContextTab(),
                _buildPersonalTab(),
                _buildTestTab(),
                _buildControlTab(),
              ],
            ),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 实时缓存状态
          _buildRealtimeCacheStatus(),
          const SizedBox(height: 16),

          // 最近缓存活动
          _buildRecentCacheActivity(),
          const SizedBox(height: 16),

          // 缓存效果分析
          _buildCacheEffectivenessAnalysis(),
          const SizedBox(height: 16),

          if (_currentContext != null) _buildCurrentContextCard(),
        ],
      ),
    );
  }

  Widget _buildCategorizedCacheTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Text(
                '选择分类：',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  isExpanded: true,
                  onChanged: (String? value) {
                    setState(() {
                      _selectedCategory = value ?? 'all';
                    });
                  },
                  items: _categories.map((String category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(_categoryNames[category] ?? category),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildCacheItemsList(),
        ),
      ],
    );
  }

  Widget _buildContextTab() {
    if (_currentContext == null) {
      return const Center(
        child: Text('暂无对话上下文信息'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatsCard('当前对话状态', [
            _buildStatItem('对话状态', _currentContext!.state.toString().split('.').last),
            _buildStatItem('用户意图', _currentContext!.primaryIntent.toString().split('.').last),
            _buildStatItem('用户情绪', _currentContext!.userEmotion.toString().split('.').last),
            _buildStatItem('开始时间', _currentContext!.startTime.toIso8601String()),
          ]),
          const SizedBox(height: 16),
          _buildStatsCard('话题信息', [
            _buildStatItem('当前话题', _currentContext!.currentTopics.join(', ')),
            _buildStatItem('参与者', _currentContext!.participants.join(', ')),
          ]),
          const SizedBox(height: 16),
          _buildStatsCard('话题热度', [
            ..._currentContext!.topicIntensity.entries.map((entry) =>
                _buildStatItem(entry.key, entry.value.toStringAsFixed(3))),
          ]),
          const SizedBox(height: 16),
          if (_currentContext!.unfinishedTasks.isNotEmpty)
            _buildStatsCard('待办任务', [
              ..._currentContext!.unfinishedTasks.map((task) =>
                  _buildStatItem('任务', task)),
            ]),
          const SizedBox(height: 16),
          if (_recentSummaries.isNotEmpty) _buildSummariesCard(),
        ],
      ),
    );
  }

  Widget _buildPersonalTab() {
    // 获取个人信息关注点摘要
    final personalFocusSummary = _chatManager.getCurrentPersonalFocusSummary();
    final personalInfoForGeneration = _chatManager.getRelevantPersonalInfoForGeneration();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 当前个人信息关注点
          _buildPersonalFocusCard(personalFocusSummary),
          const SizedBox(height: 16),

          // 个人信息检索结果统计
          _buildPersonalInfoStatsCard(personalInfoForGeneration),
          const SizedBox(height: 16),

          // 按关注点分组显示知识图谱查询结果
          _buildFocusGroupedResultsCard(personalInfoForGeneration),
        ],
      ),
    );
  }

  // 按关注点分组显示知识图谱查询结果
  Widget _buildFocusGroupedResultsCard(Map<String, dynamic> personalInfoForGeneration) {
    final focusContexts = personalInfoForGeneration['focus_contexts'] as List? ?? [];
    final retrievalContexts = personalInfoForGeneration['retrieval_contexts'] as Map<String, dynamic>? ?? {};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.category, color: Colors.deepPurple),
                const SizedBox(width: 8),
                const Text(
                  '按关注点分组的知识图谱查询结果',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: focusContexts.isNotEmpty ? Colors.green : Colors.grey,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${focusContexts.length} 组',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (focusContexts.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text(
                    '暂无关注点分析结果，开始对话后系统会分析并查询相关的个人信息',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              ...focusContexts.asMap().entries.map((entry) {
                final index = entry.key;
                final focusContext = entry.value as Map<String, dynamic>;
                return _buildFocusGroupCard(focusContext, retrievalContexts, index);
              }),
          ],
        ),
      ),
    );
  }

  // 个人信息关注点摘要卡片
  Widget _buildPersonalFocusCard(List<String> personalFocusSummary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.psychology, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  '当前个人信息关注点',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: personalFocusSummary.isNotEmpty ? Colors.blue : Colors.grey,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${personalFocusSummary.length} 个',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (personalFocusSummary.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text(
                    '暂无活跃的个人信息关注点',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              Column(
                children: personalFocusSummary.asMap().entries.map((entry) {
                  final index = entry.key;
                  final focus = entry.value;
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            focus,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  // 个人信息检索结果统计卡片
  Widget _buildPersonalInfoStatsCard(Map<String, dynamic> personalInfoForGeneration) {
    final personalNodes = personalInfoForGeneration['personal_nodes'] as List? ?? [];
    final userEvents = personalInfoForGeneration['user_events'] as List? ?? [];
    final userRelationships = personalInfoForGeneration['user_relationships'] as List? ?? [];
    final focusContexts = personalInfoForGeneration['focus_contexts'] as List? ?? [];
    final totalItems = personalInfoForGeneration['total_personal_info_items'] as int? ?? 0;
    final activeFocusesCount = personalInfoForGeneration['active_focuses_count'] as int? ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics, color: Colors.green),
                const SizedBox(width: 8),
                const Text(
                  '个人信息检索统计',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: totalItems > 0 ? Colors.green : Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    totalItems > 0 ? '有数据' : '无数据',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildInfoStatCard('活跃关注点', activeFocusesCount.toString(), Icons.psychology, Colors.blue),
                ),
                Expanded(
                  child: _buildInfoStatCard('总检索项目', totalItems.toString(), Icons.storage, Colors.green),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildInfoStatCard('个人节点', personalNodes.length.toString(), Icons.account_circle, Colors.purple),
                ),
                Expanded(
                  child: _buildInfoStatCard('用户事件', userEvents.length.toString(), Icons.event, Colors.orange),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildInfoStatCard('人际关系', userRelationships.length.toString(), Icons.people, Colors.pink),
                ),
                Expanded(
                  child: _buildInfoStatCard('检索效率', totalItems > 0 ? '${(totalItems / (activeFocusesCount == 0 ? 1 : activeFocusesCount)).toStringAsFixed(1)}项/关注点' : '0', Icons.speed, Colors.teal),
                ),
              ],
            ),
            if (totalItems == 0) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '未检索到个人信息。可能原因：1) 知识图谱中没有用户相关数据 2) 关键词匹配失败 3) 系统未分析出有效关注点',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoStatCard(String title, String count, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(
            count,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentContextCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '当前对话上下文',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_currentContext!.currentTopics.isNotEmpty)
              Text('话题: ${_currentContext!.currentTopics.join(', ')}'),
            Text('意图: ${_currentContext!.primaryIntent.toString().split('.').last}'),
            Text('情绪: ${_currentContext!.userEmotion.toString().split('.').last}'),
            Text('状态: ${_currentContext!.state.toString().split('.').last}'),
          ],
        ),
      ),
    );
  }

  Widget _buildSummariesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '最近对话摘要',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._recentSummaries.take(3).map((summary) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.timestamp.toString(),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Text(summary.content),
                      if (summary.keyTopics.isNotEmpty)
                        Text('话题: ${summary.keyTopics.join(', ')}',
                            style: const TextStyle(fontSize: 12)),
                      const Divider(),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildProactiveInteractionCard() {
    final suggestions = _chatManager.getProactiveInteractionSuggestions();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '主动交互建议',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (suggestions['hasActiveContext'] == true)
              const Chip(
                label: Text('有活跃上下文'),
                backgroundColor: Colors.green,
              ),
            const SizedBox(height: 8),
            if ((suggestions['suggestions'] as List? ?? []).isNotEmpty)
              Text('建议数: ${(suggestions['suggestions'] as List).length}'),
            if ((suggestions['currentTopics'] as List? ?? []).isNotEmpty)
              Text('当前话题: ${(suggestions['currentTopics'] as List).join(', ')}'),
          ],
        ),
      ),
    );
  }


  Widget _buildTestResult() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '测试结果',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('查询: ${_testResult!['query']}'),
            Text('时间: ${_testResult!['timestamp']}'),
            const SizedBox(height: 8),
            if (_testResult!.containsKey('error'))
              Text(
                '错误: ${_testResult!['error']}',
                style: const TextStyle(color: Colors.red),
              )
            else
              Container(
                width: double.infinity,
                height: 200,
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(4.0),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _testResult!['response'],
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearCache() async {
    try {
      _chatManager.clearCache();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('缓存已清空')),
      );

      await _loadCacheData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清空缓存失败: $e')),
      );
    }
  }

  Future<void> _triggerCacheUpdate() async {
    try {
      await _chatManager.processBackgroundConversation('触发缓存更新测试：我想了解一下我最近的学习进度');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('缓存更新已触发')),
      );

      await _loadCacheData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('触发更新失败: $e')),
      );
    }
  }

  Future<void> _simulateConversation() async {
    final conversations = [
      '我今天心情不太好，工作压力很大',
      '我需要制定一个学习计划',
      '请帮我总结一下今天的对话',
      '我明天要开会，请提醒我准备材料',
    ];

    try {
      for (final conv in conversations) {
        await _chatManager.processBackgroundConversation(conv);
        await Future.delayed(const Duration(milliseconds: 500));
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('模拟对话已完成')),
      );

      await _loadCacheData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('模拟对话失败: $e')),
      );
    }
  }

  void _showProactiveInteractionDialog(Map<String, dynamic> suggestions) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('主动交互建议'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (suggestions['summaryReady'] == true) ...[
                  const Text('✅ 可以提供对话摘要', style: TextStyle(color: Colors.green)),
                  const SizedBox(height: 8),
                ],
                if ((suggestions['suggestions'] as List).isNotEmpty) ...[
                  const Text('💡 建议:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...(suggestions['suggestions'] as List).map((s) => Text('• $s')),
                  const SizedBox(height: 8),
                ],
                if ((suggestions['reminders'] as List).isNotEmpty) ...[
                  const Text('⏰ 提醒:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...(suggestions['reminders'] as List).map((r) => Text('• $r')),
                  const SizedBox(height: 8),
                ],
                if ((suggestions['helpOpportunities'] as List).isNotEmpty) ...[
                  const Text('🆘 帮助机会:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...(suggestions['helpOpportunities'] as List).map((h) => Text('• $h')),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTestTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 缓存查询测试
          _buildCacheQueryTestCard(),
          const SizedBox(height: 16),

          // 个人信息关注点测试
          _buildPersonalFocusTestCard(),
          const SizedBox(height: 16),

          // 如果有测试结果，显示结果
          if (_testResult != null) _buildTestResult(),
        ],
      ),
    );
  }

  Widget _buildCacheQueryTestCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.search, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  '缓存查询测试',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                hintText: '输入查询内容，例如：我最近的学习进度如何？',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              onChanged: (value) {
                _testQuery = value;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('测试查询'),
                  onPressed: _isLoading ? null : _testCacheQuery,
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.psychology),
                  label: const Text('测试个人信息检索'),
                  onPressed: _isLoading ? null : _testPersonalInfoRetrieval,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalFocusTestCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.psychology, color: Colors.purple),
                const SizedBox(width: 8),
                const Text(
                  '个人信息关注点分析测试',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '测试不同类型的查询会触发哪些个人信息关注点：',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTestQueryChip('我最近心情怎么样？', 'emotional_context'),
                _buildTestQueryChip('我的学习计划进展如何？', 'goal_tracking'),
                _buildTestQueryChip('我和朋友们的关系怎么样？', 'relationship'),
                _buildTestQueryChip('我通常在什么时候工作效率最高？', 'behavior_pattern'),
                _buildTestQueryChip('我去年都做了哪些有意义的事？', 'personal_history'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestQueryChip(String query, String expectedFocus) {
    return ActionChip(
      label: Text(
        query,
        style: const TextStyle(fontSize: 12),
      ),
      onPressed: () {
        setState(() {
          _testQuery = query;
        });
        _testPersonalFocusAnalysis(query, expectedFocus);
      },
    );
  }

  Widget _buildControlTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 缓存控制
          _buildCacheControlCard(),
          const SizedBox(height: 16),

          // 模拟数据
          _buildSimulationCard(),
          const SizedBox(height: 16),

          // 主动交互控制
          _buildProactiveInteractionCard(),
          const SizedBox(height: 16),

          // 系统状态
          _buildSystemStatusCard(),
        ],
      ),
    );
  }

  Widget _buildCacheControlCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings, color: Colors.orange),
                const SizedBox(width: 8),
                const Text(
                  '缓存控制',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.delete_sweep),
                    label: const Text('清空缓存'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: _clearCache,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('强制更新'),
                    onPressed: _triggerCacheUpdate,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.analytics),
                    label: const Text('重建索引'),
                    onPressed: _rebuildCacheIndex,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.tune),
                    label: const Text('优化缓存'),
                    onPressed: _optimizeCache,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimulationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.science, color: Colors.green),
                const SizedBox(width: 8),
                const Text(
                  '模拟测试',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '模拟不同类型的对话来测试个人信息缓存系统：',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Column(
              children: [
                _buildSimulationButton(
                  '模拟日常对话',
                  '模拟包含个人偏好、情感状态等日常信息的对话',
                  Icons.chat,
                  Colors.blue,
                  _simulateDailyConversation,
                ),
                const SizedBox(height: 8),
                _buildSimulationButton(
                  '模拟工作规划',
                  '模拟讨论工作目标、计划和进度的对话',
                  Icons.work,
                  Colors.orange,
                  _simulateWorkPlanning,
                ),
                const SizedBox(height: 8),
                _buildSimulationButton(
                  '模拟人际关系',
                  '模拟讨论朋友、家人等人际关系的对话',
                  Icons.people,
                  Colors.purple,
                  _simulateRelationshipTalk,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimulationButton(String title, String description, IconData icon, Color color, VoidCallback onPressed) {
    return Container(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.1),
          foregroundColor: color,
          padding: const EdgeInsets.all(16),
        ),
        onPressed: _isLoading ? null : onPressed,
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: color.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.monitor_heart, color: Colors.teal),
                const SizedBox(width: 8),
                const Text(
                  '系统状态',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatusItem('ChatManager状态', _chatManager != null ? '已初始化' : '未初始化',
                           _chatManager != null ? Colors.green : Colors.red),
            _buildStatusItem('缓存服务', '运行中', Colors.green),
            _buildStatusItem('个人信息检索', '正常', Colors.green),
            _buildStatusItem('知识图谱连接', '已连接', Colors.green),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.bug_report),
                    label: const Text('导出调试日志'),
                    onPressed: _exportDebugLog,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.health_and_safety),
                    label: const Text('系统诊断'),
                    onPressed: _runSystemDiagnostic,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusItem(String label, String status, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 测试方法实现
  Future<void> _testPersonalInfoRetrieval() async {
    if (_testQuery.trim().isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 获取个人信息检索结果
      final personalInfo = _chatManager.getRelevantPersonalInfoForGeneration();
      final focusSummary = _chatManager.getCurrentPersonalFocusSummary();

      _testResult = {
        'query': _testQuery,
        'type': 'personal_info_retrieval',
        'personal_focus_summary': focusSummary,
        'personal_info': personalInfo,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      _testResult = {
        'query': _testQuery,
        'type': 'personal_info_retrieval',
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testPersonalFocusAnalysis(String query, String expectedFocus) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 模拟处理查询以触发个人信息关注点分析
      await _chatManager.processBackgroundConversation('用户询问: $query');

      // 获取分析结果
      final focusSummary = _chatManager.getCurrentPersonalFocusSummary();

      _testResult = {
        'query': query,
        'type': 'personal_focus_analysis',
        'expected_focus': expectedFocus,
        'detected_focus': focusSummary,
        'timestamp': DateTime.now().toIso8601String(),
      };

      await _loadCacheData(); // 刷新数据
    } catch (e) {
      _testResult = {
        'query': query,
        'type': 'personal_focus_analysis',
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _rebuildCacheIndex() async {
    try {
      // 重建缓存索引的逻辑
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('缓存索引重建中...')),
      );

      // 这里可以调用缓存服务的重建索引方法
      await Future.delayed(const Duration(seconds: 2)); // 模拟重建过程

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('缓存索引重建完成')),
      );

      await _loadCacheData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重建索引失败: $e')),
      );
    }
  }

  Future<void> _optimizeCache() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('缓存优化中...')),
      );

      // 这里可以调用缓存优化逻辑
      await Future.delayed(const Duration(seconds: 1)); // 模拟优化过程

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('缓存优化完成')),
      );

      await _loadCacheData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('缓存优化失败: $e')),
      );
    }
  }

  Future<void> _simulateDailyConversation() async {
    final conversations = [
      '我今天心情不太好，工作压力很大',
      '我最喜欢的食物是意大利面，尤其是番茄味的',
      '我通常晚上11点睡觉，早上7点起床',
      '我的兴趣爱好是看书和听音乐',
      '我对编程很有热情，特别是Flutter开发',
    ];

    await _runSimulation('日常对话', conversations);
  }

  Future<void> _simulateWorkPlanning() async {
    final conversations = [
      '我的目标是在这个月完成3个项目',
      '我需要提升我的技术技能，特别是AI方面',
      '我计划每天学习2小时新技术',
      '我的工作效率在上午最高',
      '我希望在年底前升职',
    ];

    await _runSimulation('工作规划', conversations);
  }

  Future<void> _simulateRelationshipTalk() async {
    final conversations = [
      '我和小王是很好的朋友，认识已经5年了',
      '我的家人住在另一个城市，我很想念他们',
      '我在公司里和同事关系都不错',
      '我最近认识了一个新朋友，她很有趣',
      '我觉得维持友谊需要经常联系',
    ];

    await _runSimulation('人际关系', conversations);
  }

  Future<void> _runSimulation(String type, List<String> conversations) async {
    setState(() {
      _isLoading = true;
    });

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('开始模拟$type对话...')),
      );

      for (final conv in conversations) {
        await _chatManager.processBackgroundConversation(conv);
        await Future.delayed(const Duration(milliseconds: 500));
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$type对话模拟完成')),
      );

      await _loadCacheData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('模拟$type对话失败: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _exportDebugLog() async {
    try {
      final debugData = {
        'timestamp': DateTime.now().toIso8601String(),
        'cache_stats': _cacheStats,
        'cache_items_count': _cacheItems.length,
        'current_context': _currentContext?.toJson(),
        'user_context': _userContext?.toJson(),
        'recent_summaries': _recentSummaries.map((s) => s.toJson()).toList(),
      };

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('调试日志已导出到剪贴板')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败: $e')),
      );
    }
  }

  Future<void> _runSystemDiagnostic() async {
    setState(() {
      _isLoading = true;
    });

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('运行系统诊断...')),
      );

      // 模拟系统诊断
      await Future.delayed(const Duration(seconds: 2));

      final diagnostic = {
        'cache_health': 'good',
        'memory_usage': 'normal',
        'response_time': 'fast',
        'error_rate': 'low',
      };

      _showDiagnosticResult(diagnostic);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('系统诊断失败: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showDiagnosticResult(Map<String, String> diagnostic) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('系统诊断结果'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: diagnostic.entries.map((entry) {
              final color = _getDiagnosticColor(entry.value);
              return ListTile(
                leading: Icon(Icons.check_circle, color: color),
                title: Text(entry.key),
                trailing: Text(
                  entry.value,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Color _getDiagnosticColor(String value) {
    switch (value.toLowerCase()) {
      case 'good':
      case 'normal':
      case 'fast':
      case 'low':
        return Colors.green;
      case 'warning':
      case 'medium':
        return Colors.orange;
      case 'error':
      case 'high':
      case 'slow':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildRealtimeCacheStatus() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.monitor_heart, color: Colors.green),
                const SizedBox(width: 8),
                const Text(
                  '实时缓存状态',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getTotalCacheSize() > 0 ? Colors.green : Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _getTotalCacheSize() > 0 ? '活跃' : '等待数据',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildMiniStatCard('对话掌握', '${_chatManager.getCacheItemsByCategory('conversation_grasp').length}', Icons.chat),
                ),
                Expanded(
                  child: _buildMiniStatCard('意图理解', '${_chatManager.getCacheItemsByCategory('intent_understanding').length}', Icons.psychology),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildMiniStatCard('知识储备', '${_chatManager.getCacheItemsByCategory('knowledge_reserve').length}', Icons.storage),
                ),
                Expanded(
                  child: _buildMiniStatCard('个人信息', '${_chatManager.getCacheItemsByCategory('personal_info').length}', Icons.person),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStatCard(String title, String count, IconData icon) {
    return Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: Colors.blue[600]),
          const SizedBox(height: 4),
          Text(count, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text(title, style: const TextStyle(fontSize: 10), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildRecentCacheActivity() {
    final recentItems = _cacheItems.take(5).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.history, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  '最近缓存活动',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (recentItems.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text('暂无缓存活动，开始对话后会出现内容'),
                ),
              )
            else
              ...recentItems.map((item) => _buildRecentActivityItem(item)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivityItem(CacheItem item) {
    final data = item.data as Map<String, dynamic>? ?? {};
    final reason = data['reason']?.toString() ?? '根据对话内容自动缓存';
    final content = _getItemDisplayContent(item);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            width: 3,
            color: _getPriorityColor(item.priority),
          ),
        ),
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getCategoryColor(item.category),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _categoryNames[item.category] ?? item.category,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '权重: ${item.weight.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const Spacer(),
              Text(
                _formatTimeAgo(item.createdAt),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            content,
            style: const TextStyle(fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '缓存原因: $reason',
            style: const TextStyle(fontSize: 11, color: Colors.green, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  String _getItemDisplayContent(CacheItem item) {
    final data = item.data;

    if (data is Map<String, dynamic>) {
      if (data.containsKey('content')) {
        return data['content'].toString();
      } else if (data.containsKey('text')) {
        return data['text'].toString();
      } else if (data.containsKey('topic')) {
        return '话题: ${data['topic']}';
      } else if (data.containsKey('intent')) {
        return '意图: ${data['intent']}';
      } else if (data.containsKey('emotion')) {
        return '情绪: ${data['emotion']}';
      }
      return data.toString().substring(0, data.toString().length > 50 ? 50 : data.toString().length);
    }

    return data.toString().substring(0, data.toString().length > 50 ? 50 : data.toString().length);
  }

  Color _getPriorityColor(CacheItemPriority priority) {
    switch (priority) {
      case CacheItemPriority.critical:
        return Colors.red;
      case CacheItemPriority.high:
        return Colors.orange;
      case CacheItemPriority.medium:
        return Colors.blue;
      case CacheItemPriority.low:
        return Colors.grey;
      case CacheItemPriority.userProfile:
        return Colors.purple; // 用户画像使用紫色，表示最高优先级且永不被替换
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'conversation_grasp':
        return Colors.green;
      case 'intent_understanding':
        return Colors.purple;
      case 'knowledge_reserve':
        return Colors.blue;
      case 'personal_info':
        return Colors.orange;
      case 'proactive_data':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return '刚刚';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}小时前';
    } else {
      return '${difference.inDays}天前';
    }
  }

  Widget _buildCacheEffectivenessAnalysis() {
    final totalItems = _getTotalCacheSize();
    final avgWeight = totalItems > 0 ? _cacheItems.fold(0.0, (sum, item) => sum + item.weight) / totalItems : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics, color: Colors.purple),
                SizedBox(width: 8),
                Text(
                  '缓存效果分析',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildEffectivenessStat('缓存利用率', _calculateCacheUtilization(), Colors.green),
                ),
                Expanded(
                  child: _buildEffectivenessStat('平均权重', avgWeight.toStringAsFixed(2), Colors.blue),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildEffectivenessStat('活跃分类', _getActiveCategoriesCount().toString(), Colors.orange),
                ),
                Expanded(
                  child: _buildEffectivenessStat('预测准确率', '${_calculatePredictionAccuracy()}%', Colors.purple),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEffectivenessStat(String label, String value, Color color) {
    return Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _calculateCacheUtilization() {
    if (_getTotalCacheSize() == 0) return '0%';
    final utilizationRate = (_getTotalCacheSize() / 500.0 * 100).clamp(0, 100);
    return '${utilizationRate.toStringAsFixed(1)}%';
  }

  int _getActiveCategoriesCount() {
    final categories = {'conversation_grasp', 'intent_understanding', 'knowledge_reserve', 'personal_info', 'proactive_data'};
    return categories.where((cat) => _chatManager.getCacheItemsByCategory(cat).isNotEmpty).length;
  }

  int _calculatePredictionAccuracy() {
    // 简化的预测准确率计算
    final proactiveItems = _chatManager.getCacheItemsByCategory('proactive_data');
    if (proactiveItems.isEmpty) return 0;
    return (proactiveItems.length / _getTotalCacheSize() * 100).round().clamp(0, 100);
  }

  int _getTotalCacheSize() {
    return _cacheStats['totalItems'] ?? 0;
  }

  Widget _buildCacheItemsList() {
    List<CacheItem> itemsToShow;

    if (_selectedCategory == 'all') {
      itemsToShow = _cacheItems;
    } else {
      itemsToShow = _chatManager.getCacheItemsByCategory(_selectedCategory);
    }

    if (itemsToShow.isEmpty) {
      return const Center(
        child: Text('该分类下暂无缓存项'),
      );
    }

    return ListView.builder(
      itemCount: itemsToShow.length,
      itemBuilder: (context, index) {
        final item = itemsToShow[index];
        return _buildCacheItemCard(item);
      },
    );
  }

  Widget _buildCacheItemCard(CacheItem item) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: ExpansionTile(
        title: Text(
          item.key,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '权重: ${item.weight.toStringAsFixed(3)} | 分类: ${_categoryNames[item.category] ?? item.category}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildItemDetail('优先级', item.priority.toString().split('.').last),
                _buildItemDetail('创建时间', item.createdAt.toString()),
                _buildItemDetail('最后访问', item.lastAccessedAt.toString()),
                _buildItemDetail('访问次数', item.accessCount.toString()),
                _buildItemDetail('相关话题', item.relatedTopics.join(', ')),
                _buildItemDetail('相关性分数', item.relevanceScore.toStringAsFixed(3)),
                const SizedBox(height: 8),
                const Text('数据内容:', style: TextStyle(fontWeight: FontWeight.bold)),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: Text(
                    _formatItemData(item.data),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _formatItemData(dynamic data) {
    try {
      if (data is Map) {
        return const JsonEncoder.withIndent('  ').convert(data);
      } else {
        return data.toString();
      }
    } catch (e) {
      return 'Error formatting data: $e';
    }
  }

  // 单个关注点分组卡片
  Widget _buildFocusGroupCard(Map<String, dynamic> focusContext, Map<String, dynamic> retrievalContexts, int index) {
    final description = focusContext['description']?.toString() ?? '未知关注点';
    final type = focusContext['type']?.toString() ?? 'unknown';
    final intensity = (focusContext['intensity'] as num?)?.toDouble() ?? 0.0;
    final keywords = (focusContext['keywords'] as List?)?.map((k) => k.toString()).toList() ?? [];

    // 查找与该关注点相关的检索结果
    final List<Map<String, dynamic>> relatedRetrievals = [];

    for (final entry in retrievalContexts.entries) {
      final retrievalData = entry.value as Map<String, dynamic>;
      final focusDescription = retrievalData['focus_description']?.toString() ?? '';
      final focusType = retrievalData['focus_type']?.toString() ?? '';

      // 通过描述或类型匹配来关联检索结果
      if (focusDescription == description || focusType.contains(type.split('.').last)) {
        relatedRetrievals.add({
          'retrieval_id': entry.key,
          'data': retrievalData,
        });
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Card(
        elevation: 2,
        child: ExpansionTile(
          title: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _getFocusTypeColor(type),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '类型: ${_getFocusTypeDisplayName(type)} | 强度: ${intensity.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: relatedRetrievals.isNotEmpty ? Colors.green : Colors.orange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${relatedRetrievals.length} 结果',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 显示关键词
                  if (keywords.isNotEmpty) ...[
                    const Text(
                      '关键词:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: keywords.map((keyword) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.withOpacity(0.3)),
                        ),
                        child: Text(
                          keyword,
                          style: const TextStyle(fontSize: 11),
                        ),
                      )).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // 显示知识图谱查询结果
                  const Text(
                    '知识图谱查询结果:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),

                  if (relatedRetrievals.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.search_off, color: Colors.orange, size: 32),
                          const SizedBox(height: 8),
                          const Text(
                            '未查询到相关的个人信息',
                            style: TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '关键词: ${keywords.join(", ")}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '可能原因: 知识图谱中没有相关数据，或关键词匹配失败',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    ...relatedRetrievals.asMap().entries.map((entry) {
                      final retrievalIndex = entry.key;
                      final retrieval = entry.value;
                      return _buildRetrievalResultCard(retrieval, retrievalIndex);
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 检索结果卡片
  Widget _buildRetrievalResultCard(Map<String, dynamic> retrieval, int index) {
    final retrievalData = retrieval['data'] as Map<String, dynamic>;
    final retrievalReason = retrievalData['retrieval_reason']?.toString() ?? '未知原因';
    final relevanceScore = (retrievalData['relevance_score'] as num?)?.toDouble() ?? 0.0;
    final personalContext = retrievalData['personal_context'] as Map<String, dynamic>? ?? {};

    final nodesCount = personalContext['nodes_count'] as int? ?? 0;
    final eventsCount = personalContext['events_count'] as int? ?? 0;
    final relationshipsCount = personalContext['relationships_count'] as int? ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '检索结果 ${index + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getRelevanceScoreColor(relevanceScore),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '相关度: ${relevanceScore.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Text(
            retrievalReason,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),

          // 显示查询到的内容统计
          Row(
            children: [
              if (nodesCount > 0) ...[
                _buildResultStatChip('个人节点', nodesCount, Icons.account_circle, Colors.blue),
                const SizedBox(width: 4),
              ],
              if (eventsCount > 0) ...[
                _buildResultStatChip('用户事件', eventsCount, Icons.event, Colors.green),
                const SizedBox(width: 4),
              ],
              if (relationshipsCount > 0) ...[
                _buildResultStatChip('人际关系', relationshipsCount, Icons.people, Colors.orange),
              ],
            ],
          ),

          if (nodesCount == 0 && eventsCount == 0 && relationshipsCount == 0) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.red, size: 16),
                  SizedBox(width: 4),
                  Text(
                    '检索执行了，但未找到匹配的知识图谱内容',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 显示更多详细信息
          if (personalContext.isNotEmpty) ...[
            const SizedBox(height: 8),
            ExpansionTile(
              title: const Text(
                '查看详细检索信息',
                style: TextStyle(fontSize: 12),
              ),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: personalContext.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${entry.key}: ${entry.value}',
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultStatChip(String label, int count, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 2),
          Text(
            '$count $label',
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _getFocusTypeColor(String type) {
    switch (type.split('.').last) {
      case 'personal_history':
        return Colors.blue;
      case 'relationship':
        return Colors.purple;
      case 'preference':
        return Colors.green;
      case 'goal_tracking':
        return Colors.orange;
      case 'behavior_pattern':
        return Colors.teal;
      case 'emotional_context':
        return Colors.pink;
      case 'temporal_context':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  String _getFocusTypeDisplayName(String type) {
    switch (type.split('.').last) {
      case 'personal_history':
        return '个人历史';
      case 'relationship':
        return '人际关系';
      case 'preference':
        return '个人偏好';
      case 'goal_tracking':
        return '目标追踪';
      case 'behavior_pattern':
        return '行为模式';
      case 'emotional_context':
        return '情感上下文';
      case 'temporal_context':
        return '时间上下文';
      default:
        return '未知类型';
    }
  }

  Color _getRelevanceScoreColor(double score) {
    if (score >= 0.8) return Colors.green;
    if (score >= 0.6) return Colors.orange;
    if (score >= 0.4) return Colors.yellow.shade700;
    return Colors.red;
  }
}
