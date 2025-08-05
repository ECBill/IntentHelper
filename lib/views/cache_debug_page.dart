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
      _cacheStats = _chatManager.getCachePerformance();
      _cacheItems = _chatManager.getAllCacheItems();
      _currentContext = _chatManager.getCurrentConversationContext();
      _userContext = _chatManager.getUserPersonalContext();
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
          _buildRealtimeCacheStatus(),
          const SizedBox(height: 16),
          _buildRecentCacheActivity(),
          const SizedBox(height: 16),
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
            _buildStatItem('对话状态', _currentContext!.state.toString()),
            _buildStatItem('用户意图', _currentContext!.primaryIntent.toString()),
            _buildStatItem('用户情绪', _currentContext!.userEmotion.toString()),
            _buildStatItem('开始时间', _currentContext!.startTime.toIso8601String()),
          ]),
          const SizedBox(height: 16),
          _buildStatsCard('话题信息', [
            _buildStatItem('当前话题', _currentContext!.currentTopics.join(', ')),
            _buildStatItem('参与者', _currentContext!.participants.join(', ')),
          ]),
          const SizedBox(height: 16),
          if (_recentSummaries.isNotEmpty) _buildSummariesCard(),
        ],
      ),
    );
  }

  Widget _buildPersonalTab() {
    final personalFocusSummary = _chatManager.getCurrentPersonalFocusSummary();
    final personalInfoForGeneration = _chatManager.getRelevantPersonalInfoForGeneration();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPersonalFocusCard(personalFocusSummary),
          const SizedBox(height: 16),
          _buildPersonalInfoStatsCard(personalInfoForGeneration),
        ],
      ),
    );
  }

  Widget _buildTestTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCacheQueryTestCard(),
          const SizedBox(height: 16),
          if (_testResult != null) _buildTestResult(),
        ],
      ),
    );
  }

  Widget _buildControlTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCacheControlCard(),
          const SizedBox(height: 16),
          _buildSystemStatusCard(),
        ],
      ),
    );
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
            Text('总缓存项: ${_getTotalCacheSize()}'),
            Text('知识储备: ${_chatManager.getCacheItemsByCategory('knowledge_reserve').length}'),
            Text('个人信息: ${_chatManager.getCacheItemsByCategory('personal_info').length}'),
          ],
        ),
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
            item.content,
            style: const TextStyle(fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCacheEffectivenessAnalysis() {
    final totalItems = _getTotalCacheSize();

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
            Text('总缓存项: $totalItems'),
            Text('活跃分类: ${_getActiveCategoriesCount()}'),
            Text('缓存利用率: ${_calculateCacheUtilization()}'),
          ],
        ),
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
            Text('意图: ${_currentContext!.primaryIntent}'),
            Text('状态: ${_currentContext!.state}'),
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
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
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

  Widget _buildPersonalInfoStatsCard(Map<String, dynamic> personalInfoForGeneration) {
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
            Text('活跃关注点: $activeFocusesCount'),
            Text('总检索项目: $totalItems'),
            Text('检索效率: ${totalItems > 0 ? (totalItems / (activeFocusesCount == 0 ? 1 : activeFocusesCount)).toStringAsFixed(1) : "0"}项/关注点'),
            if (totalItems == 0) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
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
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('测试查询'),
              onPressed: _isLoading ? null : _testCacheQuery,
            ),
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
            _buildStatusItem('ChatManager状态', '已初始化', Colors.green),
            _buildStatusItem('缓存服务', '运行中', Colors.green),
            _buildStatusItem('知识图谱连接', '已连接', Colors.green),
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
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
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
                Text('优先级: ${item.priority.toString().split('.').last}'),
                Text('创建时间: ${item.createdAt.toString()}'),
                Text('访问次数: ${item.accessCount.toString()}'),
                Text('相关话题: ${item.relatedTopics.join(', ')}'),
                Text('相关性分数: ${item.relevanceScore.toStringAsFixed(3)}'),
                const SizedBox(height: 8),
                const Text('内容:', style: TextStyle(fontWeight: FontWeight.bold)),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: Text(
                    item.content,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 工具方法
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
        return Colors.purple;
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

  int _getTotalCacheSize() {
    return _cacheStats['totalItems'] ?? 0;
  }

  int _getActiveCategoriesCount() {
    final categories = {'conversation_grasp', 'intent_understanding', 'knowledge_reserve', 'personal_info', 'proactive_data'};
    return categories.where((cat) => _chatManager.getCacheItemsByCategory(cat).isNotEmpty).length;
  }

  String _calculateCacheUtilization() {
    if (_getTotalCacheSize() == 0) return '0%';
    final utilizationRate = (_getTotalCacheSize() / 500.0 * 100).clamp(0, 100);
    return '${utilizationRate.toStringAsFixed(1)}%';
  }

  // 控制方法
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
}
