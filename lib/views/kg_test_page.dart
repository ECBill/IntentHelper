import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:app/services/chat_manager.dart';
import 'package:app/services/objectbox_service.dart';
import 'package:app/services/knowledge_graph_service.dart';
import 'package:app/models/graph_models.dart';
import 'package:app/models/record_entity.dart';
import 'package:intl/intl.dart';

class KGTestPage extends StatefulWidget {
  const KGTestPage({Key? key}) : super(key: key);

  @override
  State<KGTestPage> createState() => _KGTestPageState();
}

class _KGTestPageState extends State<KGTestPage> with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ChatManager _chatManager = ChatManager();

  String _result = '';
  List<Node> _allNodes = [];
  List<Edge> _allEdges = [];
  List<EventNode> _allEventNodes = [];
  List<EventEntityRelation> _allEventRelations = [];
  bool _isLoading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadKGData();
    _initChatManager();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _inputController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initChatManager() async {
    try {
      await _chatManager.init(selectedModel: 'gpt-4o-mini', systemPrompt: '你是一个知识图谱测试助手');
    } catch (e) {
      print('初始化ChatManager失败: $e');
    }
  }

  Future<void> _loadKGData() async {
    setState(() => _isLoading = true);
    try {
      final objectBox = ObjectBoxService();
      _allNodes = objectBox.queryNodes();
      _allEdges = objectBox.queryEdges();
      _allEventNodes = objectBox.queryEventNodes();
      _allEventRelations = objectBox.queryEventEntityRelations();
    } catch (e) {
      print('加载知识图谱数据失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('知识图谱调试工具'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: '对话测试'),
            Tab(text: '数据浏览'),
            Tab(text: '图谱维护'),
            Tab(text: '性能分析'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadKGData,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildConversationTestTab(),
                _buildDataBrowseTab(),
                _buildMaintenanceTab(),
                _buildAnalysisTab(),
              ],
            ),
    );
  }

  // Tab 1: 对话测试 - 测试知识图谱抽取功能
  Widget _buildConversationTestTab() {
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('测试对话知识图谱抽取', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
          SizedBox(height: 16.h),

          // 预设测试用例
          Text('快速测试用例：', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
          SizedBox(height: 8.h),
          Wrap(
            spacing: 8.w,
            children: [
              _buildTestCaseChip('我今天去苹果店买了一台iPhone 15 Pro'),
              _buildTestCaseChip('明天下午2点要和张总开会讨论新项目'),
              _buildTestCaseChip('我用ChatGPT写了一个Flutter应用'),
              _buildTestCaseChip('周末计划和朋友去看电影《沙丘2》'),
            ],
          ),

          SizedBox(height: 16.h),

          // 输入框
          TextField(
            controller: _inputController,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: '输入测试对话',
              hintText: '输入一段对话，测试知识图谱抽取效果...',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 16.h),

          // 操作按钮
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _testKGExtraction,
                icon: Icon(Icons.psychology),
                label: Text('测试抽取'),
              ),
              SizedBox(width: 8.w),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _testChatWithKG,
                icon: Icon(Icons.chat),
                label: Text('测试对话'),
              ),
              SizedBox(width: 8.w),
              OutlinedButton(
                onPressed: () {
                  _inputController.clear();
                  setState(() => _result = '');
                },
                child: Text('清空'),
              ),
            ],
          ),

          SizedBox(height: 16.h),

          // 结果显示
          if (_result.isNotEmpty) ...[
            Text('测试结果：', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
            SizedBox(height: 8.h),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8.r),
                  color: Colors.grey[50],
                ),
                child: SingleChildScrollView(
                  child: Text(_result, style: TextStyle(fontSize: 12.sp)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTestCaseChip(String text) {
    return ActionChip(
      label: Text(text, style: TextStyle(fontSize: 11.sp)),
      onPressed: () {
        _inputController.text = text;
      },
    );
  }

  // Tab 2: 数据浏览 - 浏览现有的知识图谱数据
  Widget _buildDataBrowseTab() {
    return Column(
      children: [
        // 搜索栏
        Padding(
          padding: EdgeInsets.all(16.w),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: '搜索实体或事件',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              setState(() => _searchQuery = value.toLowerCase());
            },
          ),
        ),

        // 数据统计
        Container(
          margin: EdgeInsets.symmetric(horizontal: 16.w),
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('实体', _allNodes.length, Icons.account_circle),
              _buildStatItem('关系', _allEdges.length, Icons.link),
              _buildStatItem('事件', _allEventNodes.length, Icons.event),
              _buildStatItem('事件关系', _allEventRelations.length, Icons.hub),
            ],
          ),
        ),

        SizedBox(height: 16.h),

        // 数据列表
        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                TabBar(
                  tabs: [
                    Tab(text: '实体 (${_filteredNodes.length})'),
                    Tab(text: '事件 (${_filteredEvents.length})'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildNodesList(),
                      _buildEventsList(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, int count, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 24, color: Colors.blue),
        SizedBox(height: 4.h),
        Text(count.toString(), style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 12.sp, color: Colors.grey[600])),
      ],
    );
  }

  List<Node> get _filteredNodes {
    if (_searchQuery.isEmpty) return _allNodes;
    return _allNodes.where((node) =>
      node.name.toLowerCase().contains(_searchQuery) ||
      node.type.toLowerCase().contains(_searchQuery)
    ).toList();
  }

  List<EventNode> get _filteredEvents {
    if (_searchQuery.isEmpty) return _allEventNodes;
    return _allEventNodes.where((event) =>
      event.name.toLowerCase().contains(_searchQuery) ||
      event.type.toLowerCase().contains(_searchQuery) ||
      (event.description?.toLowerCase().contains(_searchQuery) ?? false)
    ).toList();
  }

  Widget _buildNodesList() {
    if (_filteredNodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey),
            Text('没有找到匹配的实体'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: _filteredNodes.length,
      itemBuilder: (context, index) {
        final node = _filteredNodes[index];
        return Card(
          margin: EdgeInsets.only(bottom: 8.h),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getEntityTypeColor(node.type),
              child: Text(node.type[0], style: TextStyle(color: Colors.white)),
            ),
            title: Text(node.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('类型: ${node.type}'),
                if (node.attributes.isNotEmpty)
                  Text('属性: ${node.attributes.entries.take(2).map((e) => '${e.key}: ${e.value}').join(', ')}'),
              ],
            ),
            trailing: IconButton(
              icon: Icon(Icons.info_outline),
              onPressed: () => _showNodeDetails(node),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEventsList() {
    if (_filteredEvents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 64, color: Colors.grey),
            Text('没有找到匹配的事件'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: _filteredEvents.length,
      itemBuilder: (context, index) {
        final event = _filteredEvents[index];
        return Card(
          margin: EdgeInsets.only(bottom: 8.h),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getEventTypeColor(event.type),
              child: Icon(Icons.event, color: Colors.white, size: 20),
            ),
            title: Text(event.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('类型: ${event.type}'),
                if (event.startTime != null)
                  Text('时间: ${DateFormat('MM-dd HH:mm').format(event.startTime!)}'),
                if (event.location != null)
                  Text('地点: ${event.location}'),
              ],
            ),
            trailing: IconButton(
              icon: Icon(Icons.info_outline),
              onPressed: () => _showEventDetails(event),
            ),
          ),
        );
      },
    );
  }

  // Tab 3: 图谱维护 - 清理和维护操作
  Widget _buildMaintenanceTab() {
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('知识图谱维护工具', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
          SizedBox(height: 16.h),

          _buildMaintenanceCard(
            '数据完整性检查',
            '检查图谱中的孤立节点、重复边和无效引用',
            Icons.health_and_safety,
            _validateGraphIntegrity,
          ),

          _buildMaintenanceCard(
            '生成测试数据',
            '创建一些示例数据用于测试',
            Icons.data_object,
            _generateTestData,
          ),

          _buildMaintenanceCard(
            '清空事件数据',
            '清除所有事件相关数据（保留基础实体）',
            Icons.event_busy,
            _clearEventData,
          ),

          _buildMaintenanceCard(
            '完全重置',
            '清空所有知识图谱数据',
            Icons.delete_forever,
            _clearAllData,
            isDestructive: true,
          ),

          SizedBox(height: 16.h),

          if (_result.isNotEmpty) ...[
            Text('操作结果：', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
            SizedBox(height: 8.h),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8.r),
                  color: Colors.grey[50],
                ),
                child: SingleChildScrollView(
                  child: Text(_result, style: TextStyle(fontSize: 12.sp)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMaintenanceCard(String title, String description, IconData icon, VoidCallback onPressed, {bool isDestructive = false}) {
    return Card(
      margin: EdgeInsets.only(bottom: 12.h),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isDestructive ? Colors.red[100] : Colors.blue[100],
          child: Icon(icon, color: isDestructive ? Colors.red : Colors.blue),
        ),
        title: Text(title),
        subtitle: Text(description),
        trailing: ElevatedButton(
          onPressed: _isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: isDestructive ? Colors.red : null,
          ),
          child: Text(isDestructive ? '执行' : '运行'),
        ),
      ),
    );
  }

  // Tab 4: 性能分析
  Widget _buildAnalysisTab() {
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('知识图谱性能分析', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
          SizedBox(height: 16.h),

          _buildAnalysisCard('实体类型分布', _buildEntityTypeAnalysis()),
          SizedBox(height: 16.h),
          _buildAnalysisCard('事件类型分布', _buildEventTypeAnalysis()),
          SizedBox(height: 16.h),
          _buildAnalysisCard('连接度分析', _buildConnectivityAnalysis()),
        ],
      ),
    );
  }

  Widget _buildAnalysisCard(String title, Widget content) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
            SizedBox(height: 12.h),
            content,
          ],
        ),
      ),
    );
  }

  Widget _buildEntityTypeAnalysis() {
    final typeStats = <String, int>{};
    for (final node in _allNodes) {
      typeStats[node.type] = (typeStats[node.type] ?? 0) + 1;
    }

    if (typeStats.isEmpty) {
      return Text('暂无数据');
    }

    return Column(
      children: typeStats.entries.map((entry) =>
        Padding(
          padding: EdgeInsets.symmetric(vertical: 4.h),
          child: Row(
            children: [
              Container(
                width: 12.w,
                height: 12.h,
                decoration: BoxDecoration(
                  color: _getEntityTypeColor(entry.key),
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 8.w),
              Text(entry.key),
              Spacer(),
              Text('${entry.value}'),
            ],
          ),
        )
      ).toList(),
    );
  }

  Widget _buildEventTypeAnalysis() {
    final typeStats = <String, int>{};
    for (final event in _allEventNodes) {
      typeStats[event.type] = (typeStats[event.type] ?? 0) + 1;
    }

    if (typeStats.isEmpty) {
      return Text('暂无数据');
    }

    return Column(
      children: typeStats.entries.map((entry) =>
        Padding(
          padding: EdgeInsets.symmetric(vertical: 4.h),
          child: Row(
            children: [
              Container(
                width: 12.w,
                height: 12.h,
                decoration: BoxDecoration(
                  color: _getEventTypeColor(entry.key),
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 8.w),
              Text(entry.key),
              Spacer(),
              Text('${entry.value}'),
            ],
          ),
        )
      ).toList(),
    );
  }

  Widget _buildConnectivityAnalysis() {
    final entityConnections = <String, int>{};
    for (final relation in _allEventRelations) {
      entityConnections[relation.entityId] = (entityConnections[relation.entityId] ?? 0) + 1;
    }

    final avgConnections = entityConnections.isEmpty ? 0 :
        entityConnections.values.reduce((a, b) => a + b) / entityConnections.length;

    final maxConnections = entityConnections.isEmpty ? 0 :
        entityConnections.values.reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('平均连接度: ${avgConnections.toStringAsFixed(1)}'),
        Text('最大连接度: $maxConnections'),
        Text('已连接实体: ${entityConnections.length}'),
        Text('孤立实体: ${_allNodes.length - entityConnections.length}'),
      ],
    );
  }

  // 测试功能实现
  Future<void> _testKGExtraction() async {
    if (_inputController.text.trim().isEmpty) {
      setState(() => _result = '请输入测试文本');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final startTime = DateTime.now();

      // 调用知识图谱抽取
      await KnowledgeGraphService.processEventsFromConversation(
        _inputController.text,
        contextId: 'test_${startTime.millisecondsSinceEpoch}',
        conversationTime: startTime,
      );

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      // 重新加载数据
      await _loadKGData();

      setState(() {
        _result = '''测试完成！
        
处理时间: ${duration.inMilliseconds}ms
        
抽取的数据已保存到知识图谱中。
请切换到"数据浏览"标签查看结果。

统计信息:
- 总实体数: ${_allNodes.length}
- 总事件数: ${_allEventNodes.length}
- 事件-实体关系: ${_allEventRelations.length}
''';
      });
    } catch (e) {
      setState(() => _result = '抽取失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testChatWithKG() async {
    if (_inputController.text.trim().isEmpty) {
      setState(() => _result = '请输入测试文本');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await _chatManager.createRequest(text: _inputController.text);
      setState(() {
        _result = '''对话测试完成！

用户输入: ${_inputController.text}

AI回复: $response

此测试会自动使用知识图谱中的相关信息来增强回复。
''';
      });
    } catch (e) {
      setState(() => _result = '对话测试失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _validateGraphIntegrity() async {
    setState(() => _isLoading = true);
    try {
      final issues = await KnowledgeGraphService.validateGraphIntegrity();

      final buffer = StringBuffer();
      buffer.writeln('知识图谱完整性检查结果:\n');

      buffer.writeln('孤立节点 (${issues['orphaned_nodes']?.length ?? 0}个):');
      for (final nodeId in issues['orphaned_nodes'] ?? []) {
        buffer.writeln('  - $nodeId');
      }

      buffer.writeln('\n重复边 (${issues['duplicate_edges']?.length ?? 0}个):');
      for (final edge in issues['duplicate_edges'] ?? []) {
        buffer.writeln('  - $edge');
      }

      buffer.writeln('\n无效引用 (${issues['invalid_references']?.length ?? 0}个):');
      for (final ref in issues['invalid_references'] ?? []) {
        buffer.writeln('  - $ref');
      }

      setState(() => _result = buffer.toString());
    } catch (e) {
      setState(() => _result = '检查失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _generateTestData() async {
    setState(() => _isLoading = true);
    try {
      // 生成测试数据
      final testConversations = [
        '我今天去苹果店买了一台iPhone 15 Pro，花了9999元',
        '明天下午2点要和张总开会讨论新项目的进展',
        '我用ChatGPT写了一个Flutter应用，功能很强大',
        '周末计划和女朋友去电影院看《沙丘2》',
        '昨天在星巴克用MacBook写代码，效率很高',
      ];

      for (int i = 0; i < testConversations.length; i++) {
        await KnowledgeGraphService.processEventsFromConversation(
          testConversations[i],
          contextId: 'test_data_$i',
          conversationTime: DateTime.now().subtract(Duration(days: i)),
        );
      }

      await _loadKGData();
      setState(() => _result = '测试数据生成完成！\n生成了${testConversations.length}条测试对话的知识图谱数据。');
    } catch (e) {
      setState(() => _result = '生成测试数据失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _clearEventData() async {
    final confirmed = await _showConfirmDialog('清空事件数据', '这将清除所有事件、事件关系数据，但保留基础实体。确定继续吗？');
    if (!confirmed) return;

    setState(() => _isLoading = true);
    try {
      final objectBox = ObjectBoxService();
      await objectBox.clearEventNodes();
      await objectBox.clearEventEntityRelations();
      await objectBox.clearEventRelations();

      await _loadKGData();
      setState(() => _result = '事件数据已清空');
    } catch (e) {
      setState(() => _result = '清空失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _clearAllData() async {
    final confirmed = await _showConfirmDialog('完全重置', '这将清除所有知识图谱数据，此操作不可恢复！确定继续吗？');
    if (!confirmed) return;

    setState(() => _isLoading = true);
    try {
      final objectBox = ObjectBoxService();
      await objectBox.clearAllKnowledgeGraph();

      await _loadKGData();
      setState(() => _result = '所有知识图谱数据已清空');
    } catch (e) {
      setState(() => _result = '清空失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<bool> _showConfirmDialog(String title, String content) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('确定'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showNodeDetails(Node node) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(node.name),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ID: ${node.id}'),
            Text('类型: ${node.type}'),
            if (node.aliases.isNotEmpty)
              Text('别名: ${node.aliases.join(', ')}'),
            if (node.attributes.isNotEmpty) ...[
              SizedBox(height: 8.h),
              Text('属性:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...node.attributes.entries.map((e) => Text('  ${e.key}: ${e.value}')),
            ],
            SizedBox(height: 8.h),
            Text('更新时间: ${DateFormat('yyyy-MM-dd HH:mm').format(node.lastUpdated)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showEventDetails(EventNode event) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(event.name),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('类型: ${event.type}'),
            if (event.description != null)
              Text('描述: ${event.description}'),
            if (event.location != null)
              Text('地点: ${event.location}'),
            if (event.purpose != null)
              Text('目的: ${event.purpose}'),
            if (event.result != null)
              Text('结果: ${event.result}'),
            if (event.startTime != null)
              Text('开始时间: ${DateFormat('yyyy-MM-dd HH:mm').format(event.startTime!)}'),
            Text('更新时间: ${DateFormat('yyyy-MM-dd HH:mm').format(event.lastUpdated)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('关闭'),
          ),
        ],
      ),
    );
  }

  Color _getEntityTypeColor(String type) {
    switch (type.toLowerCase()) {
      case '人': case 'person': return Colors.red[300]!;
      case '地点': case 'location': return Colors.green[300]!;
      case '工具': case 'tool': return Colors.blue[300]!;
      case '物品': case 'item': return Colors.orange[300]!;
      case '概念': case 'concept': return Colors.purple[300]!;
      default: return Colors.grey[300]!;
    }
  }

  Color _getEventTypeColor(String type) {
    switch (type.toLowerCase()) {
      case '会议': case 'meeting': return Colors.blue;
      case '购买': case 'purchase': return Colors.green;
      case '学习': case 'study': return Colors.purple;
      case '娱乐': case 'entertainment': return Colors.orange;
      case '工作': case 'work': return Colors.teal;
      case '生活': case 'life': return Colors.pink;
      case '计划': case 'plan': return Colors.indigo;
      case '讨论': case 'discussion': return Colors.amber;
      default: return Colors.grey;
    }
  }
}
