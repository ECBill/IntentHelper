import 'package:flutter/material.dart';
import 'package:app/services/chat_manager.dart';
import 'package:app/services/conversation_cache.dart';
import 'package:app/services/enhanced_kg_service.dart';
import 'package:app/models/graph_models.dart';
import 'dart:convert';

class CacheDebugPage extends StatefulWidget {
  const CacheDebugPage({Key? key}) : super(key: key);

  @override
  State<CacheDebugPage> createState() => _CacheDebugPageState();
}

class _CacheDebugPageState extends State<CacheDebugPage> {
  late ChatManager _chatManager;
  late EnhancedKGService _enhancedKGService;

  // 核心数据
  List<String> _currentFocusPoints = [];
  Map<String, List<CacheItem>> _focusKnowledgeMap = {};
  Map<String, KGAnalysisResult> _kgAnalysisResults = {};

  // UI状态
  bool _isLoading = true;
  String? _selectedFocus;
  String _testQuery = '';

  @override
  void initState() {
    super.initState();
    _chatManager = ChatManager();
    _enhancedKGService = EnhancedKGService();
    _initServices();
  }

  Future<void> _initServices() async {
    try {
      await _chatManager.init(selectedModel: 'gpt-4o-mini', systemPrompt: '你是一个智能助手');
      await _enhancedKGService.initialize();
      await _loadCacheData();
    } catch (e) {
      print('初始化服务失败: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCacheData() async {
    setState(() => _isLoading = true);

    try {
      // 获取当前关注点
      _currentFocusPoints = _chatManager.getCurrentPersonalFocusSummary();

      if (_currentFocusPoints.isNotEmpty) {
        // 批量分析关注点的知识图谱信息
        _kgAnalysisResults = await _enhancedKGService.batchAnalyzeFocusPoints(_currentFocusPoints);

        // 整理每个关注点对应的知识
        _focusKnowledgeMap.clear();
        for (final focus in _currentFocusPoints) {
          _focusKnowledgeMap[focus] = _getKnowledgeForFocus(focus);
        }
      }

    } catch (e) {
      print('加载缓存数据失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<CacheItem> _getKnowledgeForFocus(String focus) {
    // 获取与该关注点相关的所有缓存项
    final allItems = _chatManager.getAllCacheItems();
    final relatedItems = <CacheItem>[];

    for (final item in allItems) {
      // 检查是否与关注点相关
      if (item.content.contains(focus) ||
          item.relatedTopics.any((topic) => focus.contains(topic) || topic.contains(focus))) {
        relatedItems.add(item);
      }
    }

    // 按相关性排序
    relatedItems.sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
    return relatedItems;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('智能缓存分析'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCacheData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildMainContent(),
    );
  }

  Widget _buildMainContent() {
    if (_currentFocusPoints.isEmpty) {
      return _buildEmptyState();
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          // 上方：关注点列表
          _buildFocusPointsList(),
          // 下方：选中关注点的详细信息
          if (_selectedFocus != null)
            _buildFocusDetailsContent(_selectedFocus!),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.psychology_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无活跃关注点',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '开始对话后，系统会自动识别您的关注点',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.chat),
            label: const Text('开始对话'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusPointsList() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.psychology, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  '当前关注点',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade700,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_currentFocusPoints.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _currentFocusPoints.length,
            itemBuilder: (context, index) {
              final focus = _currentFocusPoints[index];
              final isSelected = focus == _selectedFocus;
              final knowledgeCount = _focusKnowledgeMap[focus]?.length ?? 0;

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue.shade100 : null,
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(color: Colors.blue.shade300, width: 2)
                      : null,
                ),
                child: ExpansionTile(
                  title: Text(
                    focus,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.blue.shade800 : null,
                    ),
                  ),
                  subtitle: Text('相关知识: $knowledgeCount 条'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (knowledgeCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$knowledgeCount',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      else
                        Icon(Icons.info_outline, color: Colors.grey.shade400),
                      const SizedBox(width: 8),
                      Icon(
                        isSelected ? Icons.expand_less : Icons.expand_more,
                        color: Colors.grey.shade600,
                      ),
                    ],
                  ),
                  onExpansionChanged: (expanded) {
                    setState(() {
                      _selectedFocus = expanded ? focus : null;
                    });
                  },
                  children: [
                    if (isSelected) _buildFocusDetailsContent(focus),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFocusHeader(String focus) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.center_focus_strong,
                    color: Colors.blue.shade700,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    focus,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '关注点分析：系统识别到您对此话题的持续关注',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKGAnalysisCard(KGAnalysisResult analysis) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_tree, color: Colors.purple.shade700),
                const SizedBox(width: 8),
                const Text(
                  '知识图谱分析',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('发现相关节点: ${analysis.nodes.length} 个'),
            Text('分析时间: ${_formatDateTime(analysis.timestamp)}'),
            const SizedBox(height: 12),
            if (analysis.nodes.isNotEmpty) ...[
              const Text(
                '主要相关节点:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...analysis.nodes.take(5).map((node) => _buildNodeChip(node)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNodeChip(Node node) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Chip(
        label: Text('${node.name} (${node.type})'),
        backgroundColor: Colors.purple.shade50,
        labelStyle: TextStyle(
          fontSize: 12,
          color: Colors.purple.shade800,
        ),
      ),
    );
  }

  Widget _buildKnowledgeItemsCard(List<CacheItem> items) {
    // 按分类合并相似的缓存项
    final Map<String, List<CacheItem>> groupedItems = {};
    for (final item in items) {
      final category = item.category;
      groupedItems.putIfAbsent(category, () => []).add(item);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage, color: Colors.green.shade700),
                const SizedBox(width: 8),
                const Text(
                  '相关知识缓存',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${items.length} 条',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (groupedItems.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('暂无相关知识缓存'),
                ),
              )
            else
              ...groupedItems.entries.map((entry) =>
                  _buildCategoryGroup(entry.key, entry.value)),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryGroup(String category, List<CacheItem> items) {
    final categoryName = _getCategoryDisplayName(category);

    return ExpansionTile(
      title: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: _getCategoryColor(category),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 8),
          Text(categoryName),
          const Spacer(),
          Text(
            '${items.length} 条',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      children: items.map((item) => _buildKnowledgeItem(item)).toList(),
    );
  }

  Widget _buildKnowledgeItem(CacheItem item) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '相关性: ${(item.relevanceScore * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              const Spacer(),
              Text(
                _formatTimeAgo(item.createdAt),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.content,
            style: const TextStyle(fontSize: 14),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (item.relatedTopics.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: item.relatedTopics.take(3).map((topic) =>
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    topic,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
              ).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickTestCard(String focus) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.science, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Text(
                  '快速测试',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                hintText: '基于"$focus"提问...',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _testFocusQuery(focus),
                ),
              ),
              onChanged: (value) => _testQuery = value,
              onSubmitted: (_) => _testFocusQuery(focus),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testFocusQuery(String focus) async {
    if (_testQuery.trim().isEmpty) return;

    try {
      final response = await _chatManager.buildInputWithKG(_testQuery);
      _showTestResult(response);
    } catch (e) {
      _showTestResult('测试失败: $e');
    }
  }

  void _showTestResult(String result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('测试结果'),
        content: SingleChildScrollView(
          child: Text(result),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // 工具方法
  String _getCategoryDisplayName(String category) {
    const categoryNames = {
      'conversation_grasp': '对话理解',
      'intent_understanding': '意图分析',
      'knowledge_reserve': '知识储备',
      'personal_info': '个人信息',
      'proactive_data': '主动数据',
      'general': '通用',
    };
    return categoryNames[category] ?? category;
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'conversation_grasp': return Colors.green;
      case 'intent_understanding': return Colors.purple;
      case 'knowledge_reserve': return Colors.blue;
      case 'personal_info': return Colors.orange;
      case 'proactive_data': return Colors.teal;
      default: return Colors.grey;
    }
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) return '刚刚';
    if (difference.inMinutes < 60) return '${difference.inMinutes}分钟前';
    if (difference.inHours < 24) return '${difference.inHours}小时前';
    return '${difference.inDays}天前';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildFocusDetailsContent(String focus) {
    final knowledgeItems = _focusKnowledgeMap[focus] ?? [];
    final kgAnalysis = _kgAnalysisResults[focus];

    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFocusHeader(focus),
          const SizedBox(height: 16),
          if (kgAnalysis != null) _buildKGAnalysisCard(kgAnalysis),
          const SizedBox(height: 16),
          _buildKnowledgeItemsCard(knowledgeItems),
          const SizedBox(height: 16),
          _buildQuickTestCard(focus),
        ],
      ),
    );
  }

  Widget _buildWelcomePanel() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.touch_app,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            '点击关注点展开详情',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '查看相关的知识图谱信息',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}
