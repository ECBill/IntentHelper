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
  bool _isLoading = true;
  String _testQuery = '';
  Map<String, dynamic>? _testResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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

      // 获取缓存项详情（需要添加到ConversationCache中）
      _cacheItems = await _getCacheItems();

    } catch (e) {
      print('Error loading cache data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<List<CacheItem>> _getCacheItems() async {
    try {
      // 通过ChatManager获取缓存项
      return _chatManager.getAllCacheItems();
    } catch (e) {
      print('Error getting cache items: $e');
      return [];
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
        title: const Text('缓存调试工具'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCacheData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.analytics), text: '统计'),
            Tab(icon: Icon(Icons.storage), text: '缓存项'),
            Tab(icon: Icon(Icons.search), text: '测试'),
            Tab(icon: Icon(Icons.settings), text: '控制'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildStatsTab(),
                _buildCacheItemsTab(),
                _buildTestTab(),
                _buildControlTab(),
              ],
            ),
    );
  }

  Widget _buildStatsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatsCard('缓存概览', [
            _buildStatItem('总缓存项', '${_cacheStats['totalItems'] ?? 0}'),
            _buildStatItem('总权重', '${(_cacheStats['totalWeight'] ?? 0.0).toStringAsFixed(2)}'),
            _buildStatItem('平均权重', '${(_cacheStats['averageWeight'] ?? 0.0).toStringAsFixed(2)}'),
          ]),
          const SizedBox(height: 16),
          _buildStatsCard('优先级分布', [
            ..._buildPriorityStats(),
          ]),
          const SizedBox(height: 16),
          _buildStatsCard('年龄分布', [
            ..._buildAgeStats(),
          ]),
          const SizedBox(height: 16),
          _buildStatsCard('当前上下文', [
            _buildStatItem('当前话题', '${(_cacheStats['currentTopics'] as List?)?.join(', ') ?? '无'}'),
            _buildStatItem('最后更新', '${_cacheStats['lastUpdate'] ?? '无'}'),
          ]),
        ],
      ),
    );
  }

  Widget _buildCacheItemsTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            '缓存项列表 (${_cacheItems.length})',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _cacheItems.length,
            itemBuilder: (context, index) {
              final item = _cacheItems[index];
              return _buildCacheItemCard(item);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTestTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '缓存测试',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              labelText: '测试查询',
              hintText: '输入要测试的查询内容...',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              _testQuery = value;
            },
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _testCacheQuery,
            child: const Text('测试缓存响应'),
          ),
          const SizedBox(height: 16),
          if (_testResult != null) _buildTestResult(),
        ],
      ),
    );
  }

  Widget _buildControlTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '缓存控制',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('缓存操作', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          // 清理缓存
                          await _clearCache();
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        child: const Text('清空缓存'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          // 手动触发缓存更新
                          await _triggerCacheUpdate();
                        },
                        child: const Text('触发更新'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('模拟对话', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: '模拟对话内容',
                      hintText: '输入要模拟的背景对话...',
                    ),
                    onSubmitted: (value) async {
                      if (value.trim().isNotEmpty) {
                        await _chatManager.processBackgroundConversation(value);
                        _loadCacheData();
                      }
                    },
                  ),
                ],
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
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  List<Widget> _buildPriorityStats() {
    final priorityCounts = _cacheStats['priorityCounts'] as Map<String, dynamic>? ?? {};
    return priorityCounts.entries.map((entry) {
      final priority = entry.key.split('.').last;
      final count = entry.value;
      return _buildStatItem(priority, count.toString());
    }).toList();
  }

  List<Widget> _buildAgeStats() {
    final ageDistribution = _cacheStats['ageDistribution'] as Map<String, dynamic>? ?? {};
    return ageDistribution.entries.map((entry) {
      final ageGroup = entry.key;
      final count = entry.value;
      return _buildStatItem(ageGroup, count.toString());
    }).toList();
  }

  Widget _buildCacheItemCard(CacheItem item) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: ExpansionTile(
        title: Text(
          item.key,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '权重: ${item.weight.toStringAsFixed(3)} | 优先级: ${item.priority.toString().split('.').last}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
      if (data is Node) {
        return 'Node: ${data.name} (${data.type})\n'
               'ID: ${data.id}\n'
               'Attributes: ${data.attributes}';
      } else if (data is Map) {
        return const JsonEncoder.withIndent('  ').convert(data);
      } else {
        return data.toString();
      }
    } catch (e) {
      return 'Error formatting data: $e';
    }
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
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(4.0),
                ),
                child: Text(
                  _testResult!['response'],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
          ],
        ),
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
      // 模拟一个背景对话来触发缓存更新
      await _chatManager.processBackgroundConversation('触发缓存更新测试');

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
