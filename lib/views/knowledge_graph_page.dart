import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:graphview/GraphView.dart' as graphview;
import '../models/event_entity.dart';
import '../models/event_relation_entity.dart';
import '../models/record_entity.dart';
import '../services/objectbox_service.dart';
import '../services/knowledge_graph_service.dart';
import '../models/graph_models.dart';

class KnowledgeGraphPage extends StatefulWidget {
  @override
  _KnowledgeGraphPageState createState() => _KnowledgeGraphPageState();
}

class _KnowledgeGraphPageState extends State<KnowledgeGraphPage> with TickerProviderStateMixin {
  late TabController _tabController;
  List<Node> _nodes = [];
  List<Edge> _edges = [];
  List<Attribute> _attributes = [];
  String _selectedCategory = 'All';
  bool _isLoading = false;

  // 调试相关状态
  bool _isProcessingKnowledge = false;
  List<String> _debugLogs = [];
  final ScrollController _debugScrollController = ScrollController();

  // 时间段选择相关状态
  DateTime? _segmentStartTime;
  DateTime? _segmentEndTime;

  int? _highlightedNodeIndex;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this); // 修改标签页数量为4
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final nodes = ObjectBoxService.nodeBox.getAll();
      final edges = ObjectBoxService.edgeBox.getAll();
      final attributes = ObjectBoxService.attributeBox.getAll();
      setState(() {
        _nodes = nodes;
        _edges = edges;
        _attributes = attributes;
      });
    } catch (e) {
      print('Error loading knowledge graph data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<Node> get _filteredNodes {
    if (_selectedCategory == 'All') {
      return _nodes;
    }
    return _nodes.where((node) => node.type == _selectedCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('知识图谱'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: '实体列表'),
            Tab(text: '关系网络'),
            Tab(text: '统计信息'),
            Tab(text: '调试工具'), // 新增调试标签页
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.clear),
            onSelected: (value) async {
              if (value == 'clear_events') {
                await _clearEvents();
              } else if (value == 'clear_relations') {
                await _clearRelations();
              } else if (value == 'clear_all') {
                await _clearAll();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'clear_events', child: Text('清空事件')),
              PopupMenuItem(value: 'clear_relations', child: Text('清空关系')),
              PopupMenuItem(value: 'clear_all', child: Text('清空全部')),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildEventsTab(),
                _buildRelationsTab(),
                _buildStatisticsTab(),
                _buildDebugTab(), // 新增调试标签页
              ],
            ),
    );
  }

  Widget _buildEventsTab() {
    if (_nodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_note, size: 64, color: Colors.grey),
            SizedBox(height: 16.h),
            Text('暂无实体数据', style: TextStyle(color: Colors.grey)),
            SizedBox(height: 8.h),
            Text('进行一些对话后，系统会自动提取实体', style: TextStyle(color: Colors.grey[600], fontSize: 12.sp)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: _nodes.length,
      itemBuilder: (context, index) {
        final node = _nodes[index];
        final nodeAttrs = _attributes.where((a) => a.nodeId == node.id).toList();
        final relatedEdges = _edges.where((e) => e.source == node.id || e.target == node.id).toList();
        relatedEdges.sort((a, b) => (b.timestamp ?? DateTime(1970)).compareTo(a.timestamp ?? DateTime(1970)));
        return Card(
          margin: EdgeInsets.only(bottom: 16.h),
          child: ExpansionTile(
            title: Row(
              children: [
                Text(node.name, style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(width: 8.w),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(node.type, style: TextStyle(fontSize: 12.sp)),
                ),
                Spacer(),
                Text('ID: ${node.id}', style: TextStyle(fontSize: 10.sp, color: Colors.grey[500])),
              ],
            ),
            children: [
              if (nodeAttrs.isNotEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('属性', style: TextStyle(fontWeight: FontWeight.bold)),
                      ...nodeAttrs.map((attr) => Padding(
                        padding: EdgeInsets.symmetric(vertical: 2.h),
                        child: Text('${attr.key}: ${attr.value}', style: TextStyle(fontSize: 13.sp)),
                      )),
                    ],
                  ),
                ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('关系时间轴', style: TextStyle(fontWeight: FontWeight.bold)),
                    ...relatedEdges.map((edge) {
                      final isSource = edge.source == node.id;
                      final otherId = isSource ? edge.target : edge.source;
                      final otherNode = _nodes.firstWhere(
                        (n) => n.id == otherId,
                        orElse: () => Node(id: otherId, name: '', type: ''),
                      );
                      return ListTile(
                        dense: true,
                        leading: Icon(isSource ? Icons.arrow_forward : Icons.arrow_back, size: 18),
                        title: Text('${isSource ? '→' : '←'} ${edge.relation} ${otherNode.name.isNotEmpty ? otherNode.name : otherId}'),
                        subtitle: Text(edge.timestamp != null ? DateFormat('yyyy-MM-dd HH:mm').format(edge.timestamp!) : ''),
                        trailing: edge.context != null ? Icon(Icons.info_outline, size: 16) : null,
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRelationsTab() {
    if (_nodes.isEmpty || _edges.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.device_hub, size: 64, color: Colors.grey),
            SizedBox(height: 16.h),
            Text('暂无关系数据', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    final graph = graphview.Graph();
    final nodeMap = <String, graphview.Node>{};
    for (final node in _nodes) {
      final graphNode = graphview.Node(
        Container(
          padding: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Text('${node.name}\n(${node.type})', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.sp)),
        ),
      );
      nodeMap[node.id] = graphNode;
      graph.addNode(graphNode);
    }
    for (final edge in _edges) {
      final source = nodeMap[edge.source];
      final target = nodeMap[edge.target];
      if (source != null && target != null) {
        graph.addEdge(source, target, paint: Paint()
          ..color = Colors.blueAccent
          ..strokeWidth = 2.5);
      }
    }
    final builder = graphview.FruchtermanReingoldAlgorithm(iterations: 1000);
    return InteractiveViewer(
      constrained: false,
      boundaryMargin: EdgeInsets.all(100),
      minScale: 0.01,
      maxScale: 5.0,
      child: graphview.GraphView(
        graph: graph,
        algorithm: builder,
        builder: (graphview.Node node) => node.key as Widget,
        paint: Paint()
          ..color = Colors.grey[400]!,
      ),
    );
  }

  Widget _buildStatisticsTab() {
    final categoryStats = <String, int>{};
    final relationStats = <String, int>{};

    for (final node in _nodes) {
      final category = node.type;
      categoryStats[category] = (categoryStats[category] ?? 0) + 1;
    }

    for (final edge in _edges) {
      final type = edge.relation;
      relationStats[type] = (relationStats[type] ?? 0) + 1;
    }

    return ListView(
      padding: EdgeInsets.all(16.w),
      children: [
        _buildStatCard('总实体数', _nodes.length.toString(), Icons.event),
        SizedBox(height: 12.h),
        _buildStatCard('总关系数', _edges.length.toString(), Icons.device_hub),
        SizedBox(height: 16.h),
        Text('实体分类统计', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
        SizedBox(height: 8.h),
        ...categoryStats.entries.map((entry) =>
          _buildStatItem(entry.key, entry.value, _getCategoryColor(entry.key))
        ),
        SizedBox(height: 16.h),
        Text('关系类型统计', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
        SizedBox(height: 8.h),
        ...relationStats.entries.map((entry) =>
          _buildStatItem(_getRelationDisplayName(entry.key), entry.value, _getRelationColor(entry.key))
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Row(
          children: [
            Icon(icon, size: 32, color: Theme.of(context).primaryColor),
            SizedBox(width: 16.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 14.sp, color: Colors.grey[600])),
                Text(value, style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        children: [
          Container(
            width: 12.w,
            height: 12.h,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: 8.w),
          Text(label, style: TextStyle(fontSize: 14.sp)),
          Spacer(),
          Text('$count', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDebugTab() {
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 调试工具区域
          Card(
            child: Padding(
              padding: EdgeInsets.all(16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🔧 调试工具',
                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16.h),

                  // 时间段选择器
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _segmentStartTime ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setState(() {
                                _segmentStartTime = DateTime(
                                  picked.year, picked.month, picked.day,
                                  _segmentStartTime?.hour ?? 0, _segmentStartTime?.minute ?? 0);
                              });
                            }
                          },
                          child: Row(
                            children: [
                              Icon(Icons.date_range, size: 18),
                              SizedBox(width: 4.w),
                              Text(_segmentStartTime == null
                                  ? '起始日期'
                                  : DateFormat('yyyy-MM-dd').format(_segmentStartTime!)),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _segmentEndTime ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setState(() {
                                _segmentEndTime = DateTime(
                                  picked.year, picked.month, picked.day,
                                  _segmentEndTime?.hour ?? 23, _segmentEndTime?.minute ?? 59);
                              });
                            }
                          },
                          child: Row(
                            children: [
                              Icon(Icons.date_range, size: 18),
                              SizedBox(width: 4.w),
                              Text(_segmentEndTime == null
                                  ? '结束日期'
                                  : DateFormat('yyyy-MM-dd').format(_segmentEndTime!)),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.clear, size: 18),
                        tooltip: '清除时间段',
                        onPressed: () {
                          setState(() {
                            _segmentStartTime = null;
                            _segmentEndTime = null;
                          });
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: 16.h),

                  // 数据状态显示
                  _buildDataStatusInfo(),

                  SizedBox(height: 16.h),

                  // 手动整理知识图谱按钮
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessingKnowledge ? null : _manualProcessKnowledgeGraph,
                      icon: _isProcessingKnowledge
                          ? SizedBox(
                              width: 16.w,
                              height: 16.h,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.auto_fix_high),
                      label: Text(_isProcessingKnowledge ? '正在处理...' : '手动整理知识图谱'),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                      ),
                    ),
                  ),

                  SizedBox(height: 8.h),

                  // 清空日志按钮
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _clearDebugLogs,
                      icon: Icon(Icons.clear_all),
                      label: Text('清空日志'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 16.h),

          // 日志显示区域
          Text(
            '📝 调试日志',
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8.h),

          Expanded(
            child: Card(
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(12.w),
                child: _debugLogs.isEmpty
                    ? Center(
                        child: Text(
                          '暂无日志信息\n点击"手动整理知识图谱"开始调试',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    : ListView.builder(
                        controller: _debugScrollController,
                        itemCount: _debugLogs.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: EdgeInsets.symmetric(vertical: 2.h),
                            child: Text(
                              _debugLogs[index],
                              style: TextStyle(
                                fontSize: 12.sp,
                                fontFamily: 'monospace',
                                color: _getLogColor(_debugLogs[index]),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataStatusInfo() {
    final recordsCount = ObjectBoxService().getRecords()?.length ?? 0;
    final summariesCount = ObjectBoxService().getSummaries()?.length ?? 0;

    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📊 数据状态',
            style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(
                child: _buildStatusItem('对话记录', recordsCount.toString()),
              ),
              Expanded(
                child: _buildStatusItem('摘要数量', summariesCount.toString()),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(
                child: _buildStatusItem('已提取事件', _nodes.length.toString()),
              ),
              Expanded(
                child: _buildStatusItem('事件关系', _edges.length.toString()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Color _getLogColor(String log) {
    if (log.contains('❌') || log.contains('ERROR') || log.contains('Failed')) {
      return Colors.red[700]!;
    } else if (log.contains('⚠️') || log.contains('WARNING') || log.contains('Warning')) {
      return Colors.orange[700]!;
    } else if (log.contains('✅') || log.contains('SUCCESS') || log.contains('完成')) {
      return Colors.green[700]!;
    } else if (log.contains('🔍') || log.contains('INFO') || log.contains('开始')) {
      return Colors.blue[700]!;
    }
    return Colors.black87;
  }

  void _addDebugLog(String message) {
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    setState(() {
      _debugLogs.add('[$timestamp] $message');
    });

    // 自动滚动到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_debugScrollController.hasClients) {
        _debugScrollController.animateTo(
          _debugScrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearDebugLogs() {
    setState(() {
      _debugLogs.clear();
    });
  }

  Future<void> _manualProcessKnowledgeGraph() async {
    setState(() {
      _isProcessingKnowledge = true;
    });

    _addDebugLog('🔍 开始手动整理知识图谱...');

    try {
      _addDebugLog('📖 正在获取对话记录...');
      final records = ObjectBoxService().getRecords();

      if (records == null || records.isEmpty) {
        _addDebugLog('⚠️ 没有找到对话记录，无法生成知识图谱');
        return;
      }

      // 按时间段筛选
      List<RecordEntity> filteredRecords = records;
      if (_segmentStartTime != null || _segmentEndTime != null) {
        filteredRecords = records.where((r) {
          final t = r.createdAt ?? 0;
          final dt = DateTime.fromMillisecondsSinceEpoch(t);
          final afterStart = _segmentStartTime == null || !dt.isBefore(_segmentStartTime!);
          final beforeEnd = _segmentEndTime == null || !dt.isAfter(_segmentEndTime!);
          return afterStart && beforeEnd;
        }).toList();
      }

      _addDebugLog('✅ 找到 ${filteredRecords.length} 条对话记录');

      if (filteredRecords.isEmpty) {
        _addDebugLog('⚠️ 选定时间段内无对话记录');
        return;
      }

      // 直接分段处理
      _addDebugLog('🔄 正在按时间分段整理对话...');
      await KnowledgeGraphService.processEventsFromConversationBySegments(filteredRecords);
      _addDebugLog('✅ 分段知识图谱处理完成');

      // 重新加载数据
      _addDebugLog('🔄 正在重新加载数据...');
      await _loadData();
      _addDebugLog('✅ 数据加载完成');

      final newEventsCount = _nodes.length;
      final newRelationsCount = _edges.length;
      _addDebugLog('📊 处理结果：生成 $newEventsCount 个事件，$newRelationsCount 个关系');

      if (newEventsCount == 0) {
        _addDebugLog('⚠️ 没有提取到任何事件，可能原因：');
        _addDebugLog('   - 对话内容不包含具体事件');
        _addDebugLog('   - LLM服务响应异常');
        _addDebugLog('   - 事件提取prompt需要调整');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('知识图谱整理完成！生成 $newEventsCount 个事件，$newRelationsCount 个关系'),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e, stackTrace) {
      _addDebugLog('❌ 处理过程中发生错误: $e');
      _addDebugLog('📍 错误堆栈: \\${stackTrace.toString().split('\n').take(3).join('\n')}');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('知识图谱整理失败：$e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isProcessingKnowledge = false;
      });
      _addDebugLog('🏁 知识图谱整理�����程结束\n');
    }
  }

  // 清空事件
  Future<void> _clearEvents() async {
    await ObjectBoxService().clearEvents();
    await _loadData();
  }

  // 清空关系
  Future<void> _clearRelations() async {
    await ObjectBoxService().clearEventRelations();
    await _loadData();
  }

  // 清空全部
  Future<void> _clearAll() async {
    await ObjectBoxService().clearEvents();
    await ObjectBoxService().clearEventRelations();
    await _loadData();
  }

  // 分类颜色
  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Study':
        return Colors.blueAccent;
      case 'Life':
        return Colors.green;
      case 'Work':
        return Colors.orange;
      case 'Entertainment':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  // ��系颜色
  Color _getRelationColor(String relationType) {
    switch (relationType) {
      case 'cause':
        return Colors.redAccent;
      case 'concurrent':
        return Colors.teal;
      case 'association':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  // 关系显示名
  String _getRelationDisplayName(String relationType) {
    switch (relationType) {
      case 'cause':
        return '因果';
      case 'concurrent':
        return '并发';
      case 'association':
        return '关联';
      default:
        return '未知';
    }
  }
}
