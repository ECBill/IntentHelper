import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:app/services/objectbox_service.dart';
import 'package:app/services/knowledge_graph_service.dart';
import 'package:app/services/semantic_clustering_service.dart';
import 'package:app/models/graph_models.dart';
import 'package:app/models/record_entity.dart';
import 'package:intl/intl.dart';

import '../services/embedding_service.dart';

class KGTestPage extends StatefulWidget {
  const KGTestPage({Key? key}) : super(key: key);

  @override
  State<KGTestPage> createState() => _KGTestPageState();
}

class _KGTestPageState extends State<KGTestPage> with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  String _result = '';
  List<Node> _allNodes = [];
  List<EventNode> _allEventNodes = [];
  List<EventEntityRelation> _allEventRelations = [];
  bool _isLoading = false;
  String _searchQuery = '';

  // 新增：手动整理相关变量
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  bool _isProcessing = false;
  String _processResult = '';

  // 向量查询相关状态提升为成员变量
  final TextEditingController _vectorSearchController = TextEditingController();
  final FocusNode _vectorSearchFocusNode = FocusNode();
  List<Map<String, dynamic>> _vectorResults = [];
  bool _isVectorSearching = false;

  // 聚类相关状态变量
  bool _isClusterting = false;
  String _clusteringProgress = '';
  Map<String, dynamic>? _clusteringResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadKGData();

    // 默认设置为最近一周
    _selectedEndDate = DateTime.now();
    _selectedStartDate = _selectedEndDate!.subtract(Duration(days: 7));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _vectorSearchController.dispose();
    _vectorSearchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadKGData() async {
    setState(() => _isLoading = true);
    try {
      final objectBox = ObjectBoxService();
      _allNodes = objectBox.queryNodes();
      _allEventNodes = objectBox.queryEventNodes();
      _allEventRelations = objectBox.queryEventEntityRelations();
    } catch (e) {
      print('加载知识图谱数据失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _generateEmbeddingForAllEvents() async {
    // KnowledgeGraphService.debugPrintAllEventEmbeddingTexts();
    setState(() {
      _isProcessing = true;
      _processResult = '🔄 正在为所有事件生成嵌入向量...\n';
    });

    try {
      await KnowledgeGraphService.generateEmbeddingsForAllEvents(force: false);
      _processResult += '✅ 向量生成完成，请刷新查看效果\n';
      await _loadKGData();
    } catch (e) {
      _processResult += '❌ 生成过程中出错：$e\n';
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _regenerateEmbeddingForAllEvents() async {
    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('⚠️ 确认覆盖向量'),
        content: Text(
          '该操作会重新计算并覆盖所有事件的现有向量。\n\n'
              '这适用于嵌入生成逻辑更新后，需要更新所有现存节点的场景。\n\n'
              '⚠️ 此操作不可撤销，确认继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('确认覆盖'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
      _processResult = '🔄 正在重新生成所有事件的嵌入向量（覆盖模式）...\n';
    });

    try {
      await KnowledgeGraphService.regenerateEmbeddingsForAllEvents();
      _processResult += '✅ 向量重新生成完成，所有现有向量已覆盖更新\n';
      await _loadKGData();
    } catch (e) {
      _processResult += '❌ 重新生成过程中出错：$e\n';
    } finally {
      setState(() {
        _isProcessing = false;
      });
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
            Tab(text: '数据浏览'),
            Tab(text: '图谱维护'),
            Tab(text: '数据验证'),
            Tab(text: '图谱清理'),
            Tab(text: '事件向量查询'),
            Tab(text: '聚类管理'),
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
          _buildDataBrowseTab(),
          _buildMaintenanceTab(),
          _buildValidationTab(),
          _buildCleanupTab(),
          _buildVectorSearchTab(),
          _buildClusteringTab(),
        ],
      ),
    );
  }

  // Tab 1: 数据浏览 - 类似knowledge_graph_page的展示方式
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
            onSubmitted: (value) {
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
              _buildStatItem('事件', _allEventNodes.length, Icons.event),
              _buildStatItem('实体', _allNodes.length, Icons.account_circle),
              _buildStatItem('关联关系', _allEventRelations.length, Icons.hub),
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
                    Tab(text: '事件 (${_filteredEvents.length})'),
                    Tab(text: '实体 (${_filteredNodes.length})'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildEventsList(),
                      _buildNodesList(),
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

  Widget _buildStatItem(String label, int count, IconData icon, [Color? color]) {
    return Column(
      children: [
        Icon(icon, size: 24, color: color ?? Colors.blue),
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

  Widget _buildEventsList() {
    if (_filteredEvents.isEmpty) {
      return _buildEmptyState(
        icon: Icons.event_busy,
        title: '暂无事件记录',
        subtitle: '与AI聊天后，事件会自动记录到知识图谱中',
      );
    }

    // 按时间排序
    final sortedEvents = List<EventNode>.from(_filteredEvents);
    sortedEvents.sort((a, b) {
      final timeA = a.startTime ?? a.lastUpdated;
      final timeB = b.startTime ?? b.lastUpdated;
      return timeB.compareTo(timeA);
    });

    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: sortedEvents.length,
      itemBuilder: (context, index) => _buildEventCard(sortedEvents[index]),
    );
  }

  Widget _buildEventCard(EventNode event) {
    // 获取参与的实体
    final participantRelations = _allEventRelations
        .where((r) => r.eventId == event.id)
        .toList();

    final participants = participantRelations
        .map((r) => _allNodes.firstWhere(
            (e) => e.id == r.entityId,
        orElse: () => Node(id: r.entityId, name: r.entityId, type: '未知')))
        .toList();

    return Card(
      margin: EdgeInsets.only(bottom: 16.h),
      child: InkWell(
        onTap: () => _showEventDetails(event, participants),
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 事件标题和类型
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                    decoration: BoxDecoration(
                      color: _getEventTypeColor(event.type),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Text(
                      event.type,
                      style: TextStyle(color: Colors.white, fontSize: 12.sp),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      event.name,
                      style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (event.startTime != null)
                    Text(
                      DateFormat('MM/dd HH:mm').format(event.startTime!),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12.sp),
                    ),
                ],
              ),

              if (event.description != null) ...[
                SizedBox(height: 8.h),
                Text(
                  event.description!,
                  style: TextStyle(color: Colors.grey[700]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // 地点和目的
              if (event.location != null || event.purpose != null) ...[
                SizedBox(height: 8.h),
                Row(
                  children: [
                    if (event.location != null) ...[
                      Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                      SizedBox(width: 4.w),
                      Text(event.location!, style: TextStyle(fontSize: 12.sp, color: Colors.grey[600])),
                      SizedBox(width: 16.w),
                    ],
                    if (event.purpose != null) ...[
                      Icon(Icons.flag, size: 16, color: Colors.grey[600]),
                      SizedBox(width: 4.w),
                      Expanded(
                        child: Text(
                          event.purpose!,
                          style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],

              // 参与者
              if (participants.isNotEmpty) ...[
                SizedBox(height: 8.h),
                Wrap(
                  spacing: 4.w,
                  children: participants.take(3).map((participant) =>
                      Chip(
                        label: Text(participant.name, style: TextStyle(fontSize: 10.sp)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      )
                  ).toList()
                    ..addAll(participants.length > 3 ? [
                      Chip(
                        label: Text('+${participants.length - 3}', style: TextStyle(fontSize: 10.sp)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      )
                    ] : []),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNodesList() {
    if (_filteredNodes.isEmpty) {
      return _buildEmptyState(
        icon: Icons.search_off,
        title: '没有找到匹配的实体',
        subtitle: '尝试使用不同的搜索关键词',
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: _filteredNodes.length,
      itemBuilder: (context, index) {
        final node = _filteredNodes[index];
        final relatedEventCount = _allEventRelations
            .where((r) => r.entityId == node.id)
            .length;

        return Card(
          margin: EdgeInsets.only(bottom: 8.h),
          child: InkWell(
            onTap: () => _showEntityDetails(node),
            child: ListTile(
              leading: Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: _getEntityTypeColor(node.type),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(
                  _getEntityTypeIcon(node.type),
                  color: Colors.white,
                  size: 20,
                ),
              ),
              title: Text(node.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('类型: ${node.type}'),
                  Text('关联事件: $relatedEventCount 个'),
                  if (node.attributes.isNotEmpty)
                    Text('属性: ${node.attributes.entries.take(2).map((e) => '${e.key}: ${e.value}').join(', ')}'),
                ],
              ),
              trailing: Icon(Icons.arrow_forward_ios, size: 16),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          SizedBox(height: 16.h),
          Text(title, style: TextStyle(fontSize: 18.sp, color: Colors.grey[600])),
          SizedBox(height: 8.h),
          Text(subtitle, style: TextStyle(fontSize: 14.sp, color: Colors.grey[500])),
        ],
      ),
    );
  }

  void _showEventDetails(EventNode event, List<Node> participants) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          padding: EdgeInsets.all(16.w),
          child: ListView(
            controller: scrollController,
            children: [
              Text(event.name, style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
              SizedBox(height: 8.h),
              if (event.description != null)
                Text(event.description!, style: TextStyle(color: Colors.grey[700])),
              SizedBox(height: 16.h),
              _buildDetailRow('类型', event.type),
              if (event.location != null) _buildDetailRow('地点', event.location!),
              if (event.purpose != null) _buildDetailRow('目的', event.purpose!),
              if (event.result != null) _buildDetailRow('结果', event.result!),
              if (event.startTime != null)
                _buildDetailRow('时间', DateFormat('yyyy-MM-dd HH:mm').format(event.startTime!)),
              SizedBox(height: 16.h),
              Text('参与实体', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8.h),
              ...participants.map((p) => ListTile(
                dense: true,
                leading: Container(
                  width: 8.w,
                  height: 8.h,
                  decoration: BoxDecoration(
                    color: _getEntityTypeColor(p.type),
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(p.name),
                subtitle: Text(p.type),
              )),
            ],
          ),
        ),
      ),
    );
  }

  void _showEntityDetails(Node entity) {
    // 查找与该实体相关的所有事件
    final relatedEventRelations = _allEventRelations
        .where((r) => r.entityId == entity.id)
        .toList();

    final relatedEvents = relatedEventRelations
        .map((r) => _allEventNodes.firstWhere(
            (e) => e.id == r.eventId,
        orElse: () => EventNode(id: r.eventId, name: '未知事件', type: '未知')))
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          padding: EdgeInsets.all(16.w),
          child: ListView(
            controller: scrollController,
            children: [
              // 实体信息
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: _getEntityTypeColor(entity.type),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Icon(
                      _getEntityTypeIcon(entity.type),
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entity.name,
                          style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          entity.type,
                          style: TextStyle(fontSize: 14.sp, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              SizedBox(height: 16.h),

              // 属性信息
              if (entity.attributes.isNotEmpty) ...[
                Text('属性信息', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8.h),
                ...entity.attributes.entries.map((attr) =>
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 2.h),
                      child: Row(
                        children: [
                          Text('${attr.key}: ', style: TextStyle(color: Colors.grey[600])),
                          Expanded(child: Text(attr.value)),
                        ],
                      ),
                    )
                ),
                SizedBox(height: 16.h),
              ],

              // 相关事件
              Text('相关事件 (${relatedEvents.length})', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8.h),
              if (relatedEvents.isEmpty) ...[
                Container(
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(
                    '该实体暂未关联任何事件',
                    style: TextStyle(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ),
              ] else ...[
                ...relatedEvents.asMap().entries.map((entry) {
                  final index = entry.key;
                  final event = entry.value;
                  final relation = relatedEventRelations[index];

                  return Card(
                    margin: EdgeInsets.only(bottom: 8.h),
                    child: ListTile(
                      leading: Container(
                        padding: EdgeInsets.all(4.w),
                        decoration: BoxDecoration(
                          color: _getEventTypeColor(event.type),
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                        child: Icon(Icons.event, color: Colors.white, size: 16),
                      ),
                      title: Text(event.name),
                      subtitle: Text('${event.type} • ${relation.role}'),
                      trailing: event.startTime != null
                          ? Text(
                        DateFormat('MM/dd').format(event.startTime!),
                        style: TextStyle(fontSize: 11.sp, color: Colors.grey[600]),
                      )
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        final participants = [entity]; // 至少包含当前实体
                        _showEventDetails(event, participants);
                      },
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60.w,
            child: Text(label, style: TextStyle(color: Colors.grey[600])),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  IconData _getEntityTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case '人': case 'person': case '人物': return Icons.person;
      case '地点': case 'location': return Icons.location_on;
      case '工具': case 'tool': return Icons.build;
      case '物品': case 'item': return Icons.inventory;
      case '概念': case 'concept': return Icons.lightbulb;
      case '组织': case 'organization': return Icons.business;
      case '技能': case 'skill': return Icons.star;
      case '状态': case 'state': return Icons.circle;
      default: return Icons.help_outline;
    }
  }

  // Tab 2: 图谱维护 - 手动整理知识图谱
  Widget _buildMaintenanceTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('手动整理知识图谱', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
          SizedBox(height: 16.h),

          // 提示信息
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: Colors.amber[50],
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: Colors.amber[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber[700]),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    '当对话意外结束时，可以手动整理指定日期范围内的对话记录到知识图谱中',
                    style: TextStyle(color: Colors.amber[700], fontSize: 13.sp),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 20.h),

          // 日期选择
          Text('选择日期范围：', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
          SizedBox(height: 8.h),

          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _selectStartDate(),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 16.h),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, size: 20, color: Colors.grey[600]),
                        SizedBox(width: 8.w),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('开始日期', style: TextStyle(fontSize: 12.sp, color: Colors.grey[600])),
                            Text(
                              _selectedStartDate != null
                                  ? DateFormat('yyyy-MM-dd').format(_selectedStartDate!)
                                  : '选择开始日期',
                              style: TextStyle(fontSize: 14.sp),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              SizedBox(width: 12.w),

              Expanded(
                child: InkWell(
                  onTap: () => _selectEndDate(),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 16.h),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, size: 20, color: Colors.grey[600]),
                        SizedBox(width: 8.w),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('结束日期', style: TextStyle(fontSize: 12.sp, color: Colors.grey[600])),
                            Text(
                              _selectedEndDate != null
                                  ? DateFormat('yyyy-MM-dd').format(_selectedEndDate!)
                                  : '选择结束日期',
                              style: TextStyle(fontSize: 14.sp),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: 16.h),

          // 快速选择按钮
          Text('快速选择：', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
          SizedBox(height: 8.h),
          Wrap(
            spacing: 8.w,
            children: [
              _buildQuickDateChip('今天', 0),
              _buildQuickDateChip('最近3天', 3),
              _buildQuickDateChip('最近一周', 7),
              _buildQuickDateChip('最近一月', 30),
            ],
          ),

          SizedBox(height: 20.h),

          // 预览信息
          FutureBuilder<Map<String, dynamic>>(
            future: _getDateRangeInfo(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                final info = snapshot.data!;
                return Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('预计处理：', style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 4.h),
                      Text('• 对话记录：${info['recordCount']} 条'),
                      Text('• 预计Token消耗：约 ${info['estimatedTokens']} tokens'),
                      Text('• 处理时间：约 ${info['estimatedTime']} 分钟'),
                    ],
                  ),
                );
              }
              return SizedBox.shrink();
            },
          ),

          SizedBox(height: 20.h),

          // 操作按钮
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_isProcessing || _selectedStartDate == null || _selectedEndDate == null)
                      ? null
                      : _processDateRangeKG,
                  icon: _isProcessing
                      ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : Icon(Icons.auto_fix_high),
                  label: Text(_isProcessing ? '处理中...' : '开始整理'),
                ),
              ),
              SizedBox(width: 12.w),
              OutlinedButton.icon(
                onPressed: _isProcessing ? null : _showLastUnprocessedConversations,
                icon: Icon(Icons.search),
                label: Text('查找未处理'),
              ),
            ],
          ),

          SizedBox(height: 20.h),

          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _generateEmbeddingForAllEvents,
            icon: Icon(Icons.memory),
            label: Text('为所有事件生成向量'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
          ),

          SizedBox(height: 12.h),

          // 新增：重新生成所有事件向量（覆盖）按钮
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _regenerateEmbeddingForAllEvents,
            icon: Icon(Icons.refresh),
            label: Text('重新生成所有事件向量（覆盖）'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),

          SizedBox(height: 12.h),

          // 新增：整理图谱按钮
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _organizeGraph,
            icon: Icon(Icons.auto_awesome),
            label: Text('整理图谱（两阶段聚类）'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
          ),

          SizedBox(height: 12.h),

          // 新增：全量初始化聚类按钮
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _clusterInitAll,
            icon: Icon(Icons.refresh),
            label: Text('全量初始化聚类'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),

          SizedBox(height: 12.h),

          // 新增：按日期聚类按钮
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _clusterByDateRange,
            icon: Icon(Icons.date_range),
            label: Text('按日期范围聚类'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
          ),

          SizedBox(height: 12.h),

          // 新增：清空聚类按钮
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _clearAllClusters,
            icon: Icon(Icons.delete_sweep),
            label: Text('清空所有聚类'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),

          SizedBox(height: 20.h),

          // 处理结果显示（移除 Expanded，使用可滚动容器避免溢出）
          if (_processResult.isNotEmpty) ...[
            Text('处理结果：', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
            SizedBox(height: 8.h),
            Container(
              constraints: BoxConstraints(
                maxHeight: 300.h,
              ),
              width: double.infinity,
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8.r),
                color: Colors.grey[50],
              ),
              child: SingleChildScrollView(
                child: Text(_processResult, style: TextStyle(fontSize: 12.sp)),
              ),
            ),
          ],

          // 底部安全间距，避免被系统手势/导航条遮挡
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16.h),
        ],
      ),
    );
  }

  Widget _buildQuickDateChip(String label, int daysBack) {
    return ActionChip(
      label: Text(label, style: TextStyle(fontSize: 11.sp)),
      onPressed: () {
        setState(() {
          _selectedEndDate = DateTime.now();
          _selectedStartDate = daysBack == 0
              ? DateTime(_selectedEndDate!.year, _selectedEndDate!.month, _selectedEndDate!.day)
              : _selectedEndDate!.subtract(Duration(days: daysBack));
        });
      },
    );
  }

  Future<void> _selectStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedStartDate ?? DateTime.now().subtract(Duration(days: 7)),
      firstDate: DateTime.now().subtract(Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      setState(() {
        _selectedStartDate = date;
      });
    }
  }

  Future<void> _selectEndDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedEndDate ?? DateTime.now(),
      firstDate: _selectedStartDate ?? DateTime.now().subtract(Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      setState(() {
        _selectedEndDate = date;
      });
    }
  }

  Future<Map<String, dynamic>> _getDateRangeInfo() async {
    if (_selectedStartDate == null || _selectedEndDate == null) {
      return {'recordCount': 0, 'estimatedTokens': 0, 'estimatedTime': 0};
    }

    try {
      final objectBox = ObjectBoxService();
      final startMs = _selectedStartDate!.millisecondsSinceEpoch;
      final endMs = _selectedEndDate!.add(Duration(days: 1)).millisecondsSinceEpoch;

      final records = objectBox.queryRecords().where((r) =>
      r.createdAt != null &&
          r.createdAt! >= startMs &&
          r.createdAt! < endMs &&
          r.content != null &&
          r.content!.trim().isNotEmpty
      ).toList();

      final totalChars = records.fold<int>(0, (sum, r) => sum + (r.content?.length ?? 0));
      final estimatedTokens = (totalChars * 0.3).round(); // 粗略估算
      final estimatedTime = (records.length / 20).ceil(); // 假设每20条记录需要1分钟

      return {
        'recordCount': records.length,
        'estimatedTokens': estimatedTokens,
        'estimatedTime': estimatedTime,
      };
    } catch (e) {
      return {'recordCount': 0, 'estimatedTokens': 0, 'estimatedTime': 0};
    }
  }

  Future<void> _processDateRangeKG() async {
    if (_selectedStartDate == null || _selectedEndDate == null) return;

    setState(() {
      _isProcessing = true;
      _processResult = '';
    });

    try {
      final objectBox = ObjectBoxService();
      final startMs = _selectedStartDate!.millisecondsSinceEpoch;
      final endMs = _selectedEndDate!.add(Duration(days: 1)).millisecondsSinceEpoch;

      // 获取指定日期范围内的对话记录
      final records = objectBox.queryRecords().where((r) =>
      r.createdAt != null &&
          r.createdAt! >= startMs &&
          r.createdAt! < endMs &&
          r.content != null &&
          r.content!.trim().isNotEmpty
      ).toList();

      if (records.isEmpty) {
        setState(() {
          _processResult = '❌ 指定日期范围内没有找到对话记录';
        });
        return;
      }

      _processResult = '🔄 开始处理 ${records.length} 条对话记录...\n\n';
      setState(() {});

      // 按会话分组处理（使用时间间隔判断）
      final sessionGroups = _groupRecordsIntoSessions(records);

      int processedSessions = 0;

      for (int i = 0; i < sessionGroups.length; i++) {
        final session = sessionGroups[i];

        _processResult += '处理第 ${i + 1} 个会话 (${session.length} 条记录)...\n';
        setState(() {});

        try {
          // 使用分段处理
          await KnowledgeGraphService.processEventsFromConversationBySegments(session);

          processedSessions++;
          _processResult += '✅ 会话 ${i + 1} 处理完成\n';
        } catch (e) {
          _processResult += '❌ 会话 ${i + 1} 处理失败: $e\n';
        }

        setState(() {});

        // 添加延迟避免API调用过于频繁
        await Future.delayed(Duration(milliseconds: 500));
      }

      // 刷新数据
      await _loadKGData();

      _processResult += '\n📊 处理完成统计:\n';
      _processResult += '• 处理会话数: $processedSessions/${sessionGroups.length}\n';
      _processResult += '• 当前事件总数: ${_allEventNodes.length}\n';
      _processResult += '• 当前实体总数: ${_allNodes.length}\n';

    } catch (e) {
      _processResult += '\n❌ 处理过程中发生错误: $e';
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  List<List<RecordEntity>> _groupRecordsIntoSessions(List<RecordEntity> records) {
    if (records.isEmpty) return [];

    // 按时间排序
    records.sort((a, b) => (a.createdAt ?? 0).compareTo(b.createdAt ?? 0));

    final sessions = <List<RecordEntity>>[];
    List<RecordEntity> currentSession = [];
    int? lastTime;

    const sessionGapMinutes = 30; // 30分钟间隔认为是不同会话

    for (final record in records) {
      if (lastTime != null && record.createdAt != null &&
          record.createdAt! - lastTime > sessionGapMinutes * 60 * 1000) {
        if (currentSession.isNotEmpty) {
          sessions.add(List.from(currentSession));
          currentSession.clear();
        }
      }
      currentSession.add(record);
      lastTime = record.createdAt;
    }

    if (currentSession.isNotEmpty) {
      sessions.add(currentSession);
    }

    return sessions;
  }

  Future<void> _showLastUnprocessedConversations() async {
    // 查找最近可能未处理的对话
    final objectBox = ObjectBoxService();
    final allRecords = objectBox.queryRecords();

    // 找到最近的几个会话
    final recentRecords = allRecords.where((r) =>
    r.createdAt != null &&
        r.createdAt! > DateTime.now().subtract(Duration(days: 3)).millisecondsSinceEpoch
    ).toList();

    final sessions = _groupRecordsIntoSessions(recentRecords);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('最近的对话会话'),
        content: Container(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              final firstRecord = session.first;
              final lastRecord = session.last;
              final duration = Duration(
                  milliseconds: (lastRecord.createdAt ?? 0) - (firstRecord.createdAt ?? 0)
              );

              return ListTile(
                title: Text('会话 ${index + 1}'),
                subtitle: Text(
                    '${DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(firstRecord.createdAt ?? 0))}\n'
                        '${session.length} 条记录，持续 ${duration.inMinutes} 分钟'
                ),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedStartDate = DateTime.fromMillisecondsSinceEpoch(firstRecord.createdAt ?? 0);
                    _selectedEndDate = DateTime.fromMillisecondsSinceEpoch(lastRecord.createdAt ?? 0);
                  });
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('关闭'),
          ),
        ],
      ),
    );
  }

  // Tab 3: 数据验证 - 改为图谱分析
  Widget _buildValidationTab() {
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('图谱分析与统计', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
          SizedBox(height: 16.h),

          // 功能按钮组
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              ElevatedButton.icon(
                onPressed: _analyzeGraphStructure,
                icon: Icon(Icons.analytics),
                label: Text('结构分析'),
              ),
              ElevatedButton.icon(
                onPressed: _analyzeEntityRelations,
                icon: Icon(Icons.hub),
                label: Text('实体关联分析'),
              ),
              ElevatedButton.icon(
                onPressed: _analyzeTimePatterns,
                icon: Icon(Icons.timeline),
                label: Text('时间模式分析'),
              ),
              ElevatedButton.icon(
                onPressed: _analyzeOrphanedEntities,
                icon: Icon(Icons.warning_amber),
                label: Text('孤立实体分析'),
              ),
              ElevatedButton.icon(
                onPressed: _validateGraphIntegrity,
                icon: Icon(Icons.check_circle),
                label: Text('完整性检查'),
              ),
              // 新增 embedding 检查按钮
              ElevatedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: Text('事件 embedding 检查'),
                        content: SizedBox(
                          width: 400,
                          height: 400,
                          child: Scrollbar(
                            child: ListView(
                              children: _allEventNodes.map((event) {
                                final emb = EmbeddingService().getEventEmbedding(event);
                                return Text(
                                  '事件: \\${event.name}\nembedding 长度: \\${emb?.length ?? 0}\n前5: \\${emb != null ? emb.take(5).toList() : '无'}\n',
                                  style: TextStyle(fontSize: 13),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text('关闭'),
                          ),
                        ],
                      );
                    },
                  );
                },
                icon: Icon(Icons.check),
                label: Text('检查事件 embedding'),
              ),
            ],
          ),

          SizedBox(height: 16.h),

          // 实时统计面板
          _buildRealTimeStats(),

          SizedBox(height: 16.h),

          // 结果显示
          if (_result.isNotEmpty) ...[
            Text('分析结果：', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
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

  Widget _buildRealTimeStats() {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('实时统计', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp)),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(
                child: _buildQuickStat('事件节点', _allEventNodes.length, Icons.event, Colors.blue),
              ),
              Expanded(
                child: _buildQuickStat('实体节点', _allNodes.length, Icons.account_circle, Colors.green),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(
                child: _buildQuickStat('关联关系', _allEventRelations.length, Icons.link, Colors.orange),
              ),
              Expanded(
                child: _buildQuickStat('孤立实体', _getOrphanedEntitiesCount(), Icons.warning, Colors.red),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          _buildGraphDensityIndicator(),
        ],
      ),
    );
  }

  Widget _buildQuickStat(String label, int value, IconData icon, Color color) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 4.w),
      padding: EdgeInsets.all(8.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          SizedBox(height: 4.h),
          Text(value.toString(), style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(fontSize: 10.sp, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildGraphDensityIndicator() {
    final density = _calculateGraphDensity();
    final densityText = density > 0.7 ? '密集' : density > 0.4 ? '适中' : '稀疏';
    final densityColor = density > 0.7 ? Colors.red : density > 0.4 ? Colors.orange : Colors.green;

    return Container(
      padding: EdgeInsets.all(8.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Row(
        children: [
          Icon(Icons.device_hub, color: densityColor, size: 20),
          SizedBox(width: 8.w),
          Text('图谱密度: ', style: TextStyle(fontSize: 12.sp)),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
            decoration: BoxDecoration(
              color: densityColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Text(
              '$densityText (${(density * 100).toStringAsFixed(1)}%)',
              style: TextStyle(fontSize: 11.sp, color: densityColor, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  int _getOrphanedEntitiesCount() {
    // 修正：使用新的事件中心结构来检测孤立节点
    return _allNodes.where((node) =>
    !_allEventRelations.any((rel) => rel.entityId == node.id)
    ).length;
  }

  double _calculateGraphDensity() {
    if (_allNodes.isEmpty || _allEventNodes.isEmpty) return 0.0;
    final maxPossibleRelations = _allNodes.length * _allEventNodes.length;
    return _allEventRelations.length / maxPossibleRelations;
  }

  Future<void> _analyzeGraphStructure() async {
    setState(() => _isLoading = true);
    try {
      final buffer = StringBuffer();
      buffer.writeln('📊 知识图谱结构分析报告\n');
      buffer.writeln('=' * 40);

      // 基础统计
      buffer.writeln('\n🔢 基础统计:');
      buffer.writeln('• 事件节点: ${_allEventNodes.length} 个');
      buffer.writeln('• 实体节点: ${_allNodes.length} 个');
      buffer.writeln('• 关联关系: ${_allEventRelations.length} 个');

      // 事件类型分布
      final eventTypeStats = <String, int>{};
      for (final event in _allEventNodes) {
        eventTypeStats[event.type] = (eventTypeStats[event.type] ?? 0) + 1;
      }

      buffer.writeln('\n📋 事件类型分布:');
      eventTypeStats.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value))
        ..forEach((entry) {
          buffer.writeln('• ${entry.key}: ${entry.value} 个');
        });

      // 实体类型分布
      final entityTypeStats = <String, int>{};
      for (final entity in _allNodes) {
        entityTypeStats[entity.type] = (entityTypeStats[entity.type] ?? 0) + 1;
      }

      buffer.writeln('\n👥 实体类型分布:');
      entityTypeStats.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value))
        ..forEach((entry) {
          buffer.writeln('• ${entry.key}: ${entry.value} 个');
        });

      // 图谱健康度评估
      buffer.writeln('\n💊 图谱健康度评估:');
      final orphanedEntities = _getOrphanedEntitiesCount();
      final density = _calculateGraphDensity();

      buffer.writeln('• 孤立实体: ${orphanedEntities} 个 ${orphanedEntities > 0 ? "⚠️" : "✅"}');
      buffer.writeln('• 图谱密度: ${(density * 100).toStringAsFixed(1)}%');
      buffer.writeln('• 平均每事件关联实体: ${_allEventRelations.isEmpty ? 0 : (_allEventRelations.length / _allEventNodes.length).toStringAsFixed(1)} 个');

      // 时间分布
      if (_allEventNodes.where((e) => e.startTime != null).isNotEmpty) {
        buffer.writeln('\n📅 时间分布分析:');
        final now = DateTime.now();
        final today = _allEventNodes.where((e) =>
            (e.startTime ?? e.lastUpdated).isAfter(DateTime(now.year, now.month, now.day))
        ).length;
        final thisWeek = _allEventNodes.where((e) =>
            (e.startTime ?? e.lastUpdated).isAfter(now.subtract(Duration(days: 7)))
        ).length;
        final thisMonth = _allEventNodes.where((e) =>
            (e.startTime ?? e.lastUpdated).isAfter(now.subtract(Duration(days: 30)))
        ).length;

        buffer.writeln('• 今日事件: $today 个');
        buffer.writeln('• 本周事件: $thisWeek 个');
        buffer.writeln('• 本月事件: $thisMonth 个');
      }

      setState(() => _result = buffer.toString());
    } catch (e) {
      setState(() => _result = '分析失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _analyzeEntityRelations() async {
    setState(() => _isLoading = true);
    try {
      final buffer = StringBuffer();
      buffer.writeln('🔗 实体关联关系分析报告\n');
      buffer.writeln('=' * 40);

      // 实体连接度分析
      final entityConnections = <String, int>{};
      for (final relation in _allEventRelations) {
        entityConnections[relation.entityId] = (entityConnections[relation.entityId] ?? 0) + 1;
      }

      final sortedEntities = entityConnections.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      buffer.writeln('\n🌟 核心实体排行 (按关联事件数):');
      for (int i = 0; i < sortedEntities.take(10).length; i++) {
        final entry = sortedEntities[i];
        final entity = _allNodes.firstWhere(
              (e) => e.id == entry.key,
          orElse: () => Node(id: entry.key, name: entry.key, type: '未知'),
        );
        buffer.writeln('${i + 1}. ${entity.name} (${entity.type}) - ${entry.value} 个事件');
      }

      // 角色分析
      final roleStats = <String, int>{};
      for (final relation in _allEventRelations) {
        roleStats[relation.role] = (roleStats[relation.role] ?? 0) + 1;
      }

      buffer.writeln('\n🎭 角色分布统计:');
      roleStats.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value))
        ..forEach((entry) {
          buffer.writeln('• ${entry.key}: ${entry.value} 次');
        });

      // 孤立实体详情
      final orphanedEntities = _allNodes.where((node) =>
      !_allEventRelations.any((rel) => rel.entityId == node.id)
      ).toList();

      if (orphanedEntities.isNotEmpty) {
        buffer.writeln('\n⚠️ 孤立实体列表:');
        for (final entity in orphanedEntities.take(20)) {
          buffer.writeln('• ${entity.name} (${entity.type})');
        }
        if (orphanedEntities.length > 20) {
          buffer.writeln('... 还有 ${orphanedEntities.length - 20} 个孤立实体');
        }
      }

      setState(() => _result = buffer.toString());
    } catch (e) {
      setState(() => _result = '分析失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _analyzeTimePatterns() async {
    setState(() => _isLoading = true);
    try {
      final buffer = StringBuffer();
      buffer.writeln('⏰ 时间模式分析报告\n');
      buffer.writeln('=' * 40);

      final eventsWithTime = _allEventNodes.where((e) => e.startTime != null).toList();

      if (eventsWithTime.isEmpty) {
        buffer.writeln('\n❌ 没有找到包含时间信息的事件');
        setState(() => _result = buffer.toString());
        return;
      }

      // 按小时分布
      final hourStats = <int, int>{};
      for (final event in eventsWithTime) {
        final hour = event.startTime!.hour;
        hourStats[hour] = (hourStats[hour] ?? 0) + 1;
      }

      buffer.writeln('\n🕐 小时分布统计:');
      for (int hour = 0; hour < 24; hour++) {
        final count = hourStats[hour] ?? 0;
        if (count > 0) {
          final percentage = (count / eventsWithTime.length * 100).toStringAsFixed(1);
          buffer.writeln('${hour.toString().padLeft(2, '0')}:00 - ${count} 个事件 ($percentage%)');
        }
      }

      // 按星期分布
      final weekdayStats = <int, int>{};
      final weekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

      for (final event in eventsWithTime) {
        final weekday = event.startTime!.weekday - 1; // 0-6
        weekdayStats[weekday] = (weekdayStats[weekday] ?? 0) + 1;
      }

      buffer.writeln('\n📅 星期分布统计:');
      for (int i = 0; i < 7; i++) {
        final count = weekdayStats[i] ?? 0;
        if (count > 0) {
          final percentage = (count / eventsWithTime.length * 100).toStringAsFixed(1);
          buffer.writeln('${weekdayNames[i]} - ${count} 个事件 ($percentage%)');
        }
      }

      // 最活跃的时间段
      final maxHour = hourStats.entries.reduce((a, b) => a.value > b.value ? a : b);
      final maxWeekday = weekdayStats.entries.reduce((a, b) => a.value > b.value ? a : b);

      buffer.writeln('\n🎯 活跃时间总结:');
      buffer.writeln('• 最活跃小时: ${maxHour.key}:00 (${maxHour.value} 个事件)');
      buffer.writeln('• 最活跃星期: ${weekdayNames[maxWeekday.key]} (${maxWeekday.value} 个事件)');

      // 时间跨度分析
      final sortedByTime = eventsWithTime..sort((a, b) => a.startTime!.compareTo(b.startTime!));
      if (sortedByTime.length >= 2) {
        final timeSpan = sortedByTime.last.startTime!.difference(sortedByTime.first.startTime!);
        buffer.writeln('• 数据时间跨度: ${timeSpan.inDays} 天');
        buffer.writeln('• 平均每天事件: ${(eventsWithTime.length / (timeSpan.inDays + 1)).toStringAsFixed(1)} 个');
      }

      setState(() => _result = buffer.toString());
    } catch (e) {
      setState(() => _result = '分析失败: $e');
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

  // Tab 4: 图谱清理
  Widget _buildCleanupTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('知识图谱清理', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
          SizedBox(height: 16.h),

          // 清理选项
          Card(
            child: Padding(
              padding: EdgeInsets.all(16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('清理选项', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12.h),

                  // 新增：清除孤立节点
                  ListTile(
                    leading: Icon(Icons.cleaning_services, color: Colors.amber),
                    title: Text('清除孤立节点'),
                    subtitle: Text('删除所有没有与事件关联的孤立实体节点'),
                    trailing: ElevatedButton(
                      onPressed: _clearOrphanedNodes,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                      child: Text('清除', style: TextStyle(color: Colors.white)),
                    ),
                  ),

                  Divider(),

                  ListTile(
                    leading: Icon(Icons.delete_outline, color: Colors.orange),
                    title: Text('清空事件数据'),
                    subtitle: Text('清除所有事件、事件关系数据，但保留基础实体'),
                    trailing: ElevatedButton(
                      onPressed: _clearEventData,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                      child: Text('清空', style: TextStyle(color: Colors.white)),
                    ),
                  ),

                  Divider(),

                  ListTile(
                    leading: Icon(Icons.delete_forever, color: Colors.red),
                    title: Text('完全重置图谱'),
                    subtitle: Text('清除所有知识图谱数据，此操作不可恢复'),
                    trailing: ElevatedButton(
                      onPressed: _clearAllData,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: Text('重置', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 16.h),

          // 测试数据生成
          Card(
            child: Padding(
              padding: EdgeInsets.all(16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('测试数据', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12.h),

                  ListTile(
                    leading: Icon(Icons.data_object, color: Colors.blue),
                    title: Text('生成测试数据'),
                    subtitle: Text('创建一些示例事件和实体用于测试'),
                    trailing: ElevatedButton(
                      onPressed: _generateTestData,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                      child: Text('生成', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 16.h),

          // 安全提示
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.warning, color: Colors.red[700]),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    '注意：清空操作不可恢复，请谨慎操作！建议在清空前先进行数据备份。',
                    style: TextStyle(color: Colors.red[700], fontSize: 13.sp),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 16.h),

          // 结果显示 - 修复溢出问题
          if (_result.isNotEmpty) ...[
            Text('操作结果：', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
            SizedBox(height: 8.h),
            Container(
              constraints: BoxConstraints(
                maxHeight: 300.h, // 限制最大高度
              ),
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
          ],

          // 添加底部安全间距
          SizedBox(height: MediaQuery.of(context).padding.bottom + 20.h),
        ],
      ),
    );
  }

  Widget _buildVectorSearchTab() {
    // 统一提取相似度分数的方法（支持多种字段名与类型）
    double? _extractSimilarity(Map<String, dynamic> r) {
      final dynamic v = r['cosine_similarity'] ?? r['similarity'] ?? r['score'] ?? r['final_score'] ?? r['distance'];
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    Future<void> _doVectorSearch() async {
      final query = _vectorSearchController.text.trim();
      if (query.isEmpty) return;
      setState(() => _isVectorSearching = true);
      final results = await KnowledgeGraphService.searchEventsByText(query);
      // 按相似度从高到低排序（基于与卡片展示一致的分数提取逻辑）
      final sorted = List<Map<String, dynamic>>.from(results);
      sorted.sort((a, b) => (_extractSimilarity(b) ?? double.negativeInfinity)
          .compareTo(_extractSimilarity(a) ?? double.negativeInfinity));
      setState(() {
        _vectorResults = sorted;
        _isVectorSearching = false;
      });
    }

    // 新增：事件类型对应卡片背景色 - 高级配色方案
    Color _getEventCardColor(String type) {
      switch (type.toLowerCase()) {
        case '讨论': case 'discussion':
          return Color(0xFFFFF4E6); // 柔和橙色背景
        case '生活': case 'life':
          return Color(0xFFFCE4EC); // 温暖粉红
        case '工作': case 'work':
          return Color(0xFFE8F5E9); // 专业绿色
        case '娱乐': case 'entertainment':
          return Color(0xFFFFF9C4); // 明亮黄色
        case '学习': case 'study':
          return Color(0xFFF3E5F5); // 优雅紫色
        case '计划': case 'plan':
          return Color(0xFFE3F2FD); // 清爽蓝色
        case '会议': case 'meeting':
          return Color(0xFFE1F5FE); // 天蓝色
        case '购买': case 'purchase':
          return Color(0xFFE0F2F1); // 青绿色
        default:
          return Color(0xFFFAFAFA); // 高级灰白
      }
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(16.w),
            child: Text('事件向量查询', style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(16.r),
              child: TextField(
                controller: _vectorSearchController,
                focusNode: _vectorSearchFocusNode,
                decoration: InputDecoration(
                  contentPadding: EdgeInsets.symmetric(vertical: 18.h, horizontal: 20.w),
                  labelText: '输入一段话，匹配相关事件',
                  hintText: '例如：我昨天在星巴克用MacBook写代码',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16.r)),
                  suffixIcon: AnimatedContainer(
                    duration: Duration(milliseconds: 200),
                    width: 48,
                    height: 48,
                    child: IconButton(
                      icon: Icon(Icons.search, size: 28, color: _isVectorSearching ? Colors.grey : Colors.blue),
                      onPressed: _isVectorSearching ? null : () async {
                        await _doVectorSearch();
                        _vectorSearchFocusNode.unfocus();
                      },
                      tooltip: '查询',
                    ),
                  ),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) async {
                  await _doVectorSearch();
                  _vectorSearchFocusNode.unfocus();
                },
                style: TextStyle(fontSize: 16.sp),
                enabled: !_isVectorSearching,
              ),
            ),
          ),
          SizedBox(height: 18.h),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.vertical(top: Radius.circular(18.r)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.08),
                    blurRadius: 8,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: _isVectorSearching
                  ? Center(child: CircularProgressIndicator())
                  : _vectorResults.isEmpty
                  ? Center(
                child: Text('没有找到匹配的事件', style: TextStyle(color: Colors.grey, fontSize: 15.sp)),
              )
                  : Column(
                      children: [
                        // 排序提示标签
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                          child: Row(
                            children: [
                              Icon(Icons.sort, size: 16.sp, color: Color(0xFF7C4DFF)),
                              SizedBox(width: 6.w),
                              Text(
                                '按相似度从高到低排序',
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  color: Color(0xFF7C4DFF),
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              Spacer(),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                                decoration: BoxDecoration(
                                  color: Color(0xFF7C4DFF).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8.r),
                                  border: Border.all(color: Color(0xFF7C4DFF).withOpacity(0.3)),
                                ),
                                child: Text(
                                  '${_vectorResults.length} 个结果',
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    color: Color(0xFF7C4DFF),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                  itemCount: _vectorResults.length,
                  separatorBuilder: (_, __) => Divider(height: 18.h, color: Colors.grey[300]),
                  itemBuilder: (context, index) {
                    final result = _vectorResults[index];
                    // 使用统一的相似度提取逻辑，确保排序与显示一致
                    final double? similarityValue = _extractSimilarity(result);
                    final similarity = similarityValue != null
                        ? similarityValue.toStringAsFixed(3)
                        : '-';

                    final event = result['event'] as EventNode?;
                    if (event == null) return SizedBox.shrink();

                    // 根据相似度值确定颜色 - 高级渐变配色
                    Color similarityColor = Color(0xFF9E9E9E); // 默认中性灰
                    if (similarityValue != null) {
                      if (similarityValue >= 0.8) {
                        similarityColor = Color(0xFF4CAF50); // 鲜活绿色 - 极高相关
                      } else if (similarityValue >= 0.6) {
                        similarityColor = Color(0xFF66BB6A); // 浅绿色 - 高相关
                      } else if (similarityValue >= 0.4) {
                        similarityColor = Color(0xFFFFB74D); // 温暖橙色 - 中等相关
                      } else if (similarityValue >= 0.2) {
                        similarityColor = Color(0xFF64B5F6); // 柔和蓝色 - 低相关
                      } else {
                        similarityColor = Color(0xFFBDBDBD); // 浅灰色 - 极低相关
                      }
                    }

                    return Card(
                        elevation: 3,
                        color: _getEventCardColor(event.type),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.r),
                          side: BorderSide(
                            color: similarityColor.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        shadowColor: similarityColor.withOpacity(0.3),
                        child: ListTile(
                          contentPadding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 18.w),
                          title: Text(
                            event.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16.sp,
                              color: Color(0xFF212121),
                              letterSpacing: 0.2,
                            ),
                          ),
                          subtitle: Padding(
                            padding: EdgeInsets.only(top: 6.h),
                            child: Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(6.r),
                                  ),
                                  child: Text(
                                    '${event.type}',
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      color: Color(0xFF424242),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 10.w),
                               Container(
                                 padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                                 decoration: BoxDecoration(
                                   gradient: LinearGradient(
                                     colors: [
                                       similarityColor.withOpacity(0.15),
                                       similarityColor.withOpacity(0.25),
                                     ],
                                     begin: Alignment.topLeft,
                                     end: Alignment.bottomRight,
                                   ),
                                   borderRadius: BorderRadius.circular(12.r),
                                   border: Border.all(color: similarityColor.withOpacity(0.6), width: 1.2),
                                   boxShadow: [
                                     BoxShadow(
                                       color: similarityColor.withOpacity(0.2),
                                       blurRadius: 4,
                                       offset: Offset(0, 2),
                                     ),
                                   ],
                                 ),
                                 child: Row(
                                   mainAxisSize: MainAxisSize.min,
                                   children: [
                                     Icon(Icons.analytics_outlined, size: 13, color: similarityColor),
                                     SizedBox(width: 5.w),
                                     Text(
                                       similarity,
                                       style: TextStyle(
                                         fontSize: 12.sp,
                                         fontWeight: FontWeight.w600,
                                         color: similarityColor,
                                         letterSpacing: 0.3,
                                       ),
                                     ),
                                   ],
                                 ),
                               ),
                             ],
                           ),
                         ),
                          trailing: event.startTime != null
                              ? Container(
                                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.04),
                                    borderRadius: BorderRadius.circular(8.r),
                                  ),
                                  child: Text(
                                    DateFormat('MM/dd HH:mm').format(event.startTime!),
                                    style: TextStyle(
                                      fontSize: 11.sp,
                                      color: Color(0xFF616161),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                )
                              : null,
                          onTap: () {
                            final participants = _allNodes.where((n) =>
                                _allEventRelations.any((r) => r.eventId == event.id && r.entityId == n.id)
                            ).toList();
                            _showEventDetails(event, participants);
                          },
                        ));
                   }
               ),
                         ),
                       ],
                     ),
             ),
           ),
         ],
       ),
     );
   }


  // 新增：分析孤立实体的详细调试方法
  Future<void> _analyzeOrphanedEntities() async {
    setState(() => _isLoading = true);
    try {
      final buffer = StringBuffer();
      buffer.writeln('🔍 孤立实体详细分析报告\n');
      buffer.writeln('=' * 50);

      final objectBox = ObjectBoxService();
      final allNodes = objectBox.queryNodes();
      final allEventRelations = objectBox.queryEventEntityRelations();
      final allEvents = objectBox.queryEventNodes();
      final allEdges = objectBox.queryEdges(); // 旧的边数据

      buffer.writeln('\n📊 数据总览:');
      buffer.writeln('• 总实体数: ${allNodes.length}');
      buffer.writeln('• 总事件数: ${allEvents.length}');
      buffer.writeln('• 事件-实体关系数: ${allEventRelations.length}');
      buffer.writeln('• 旧边数据数: ${allEdges.length}');

      // 分析孤立实体
      final orphanedEntities = allNodes.where((node) =>
      !allEventRelations.any((rel) => rel.entityId == node.id)
      ).toList();

      buffer.writeln('\n⚠️ 孤立实体分析:');
      buffer.writeln('• 孤立实体总数: ${orphanedEntities.length}');

      // 按类型分组孤立实体
      final orphanedByType = <String, List<Node>>{};
      for (final entity in orphanedEntities) {
        orphanedByType.putIfAbsent(entity.type, () => []).add(entity);
      }

      buffer.writeln('\n📋 按类型分布:');
      orphanedByType.entries.toList()
        ..sort((a, b) => b.value.length.compareTo(a.value.length))
        ..forEach((entry) {
          buffer.writeln('• ${entry.key}: ${entry.value.length} 个');
        });

      // 检查是否有旧的Edge数据关联
      final entitiesWithOldEdges = <String>[];
      for (final entity in orphanedEntities) {
        final hasOldEdge = allEdges.any((edge) =>
        edge.source == entity.id || edge.target == entity.id);
        if (hasOldEdge) {
          entitiesWithOldEdges.add(entity.id);
        }
      }

      buffer.writeln('\n🔗 旧数据结构关联:');
      buffer.writeln('• 有旧Edge关联的孤立实体: ${entitiesWithOldEdges.length} 个');

      // 显示一些具体的孤立实体示例
      buffer.writeln('\n📝 孤立实体示例 (前20个):');
      for (int i = 0; i < orphanedEntities.take(20).length; i++) {
        final entity = orphanedEntities[i];
        final hasOldEdge = entitiesWithOldEdges.contains(entity.id);
        final lastUpdated = entity.lastUpdated;
        buffer.writeln('${i + 1}. ${entity.name} (${entity.type})');
        buffer.writeln('   ID: ${entity.id}');
        buffer.writeln('   更新时间: ${DateFormat('yyyy-MM-dd HH:mm').format(lastUpdated)}');
        buffer.writeln('   有旧Edge: ${hasOldEdge ? "是" : "否"}');
        if (entity.sourceContext != null) {
          buffer.writeln('   来源: ${entity.sourceContext}');
        }
        buffer.writeln('');
      }

      // 检查最近创建的孤立实体
      final now = DateTime.now();
      final recentOrphaned = orphanedEntities.where((entity) =>
          entity.lastUpdated.isAfter(now.subtract(Duration(days: 7)))
      ).toList();

      buffer.writeln('\n⏰ 最近一周的孤立实体:');
      buffer.writeln('• 数量: ${recentOrphaned.length}');

      if (recentOrphaned.isNotEmpty) {
        buffer.writeln('• 示例:');
        for (final entity in recentOrphaned.take(10)) {
          buffer.writeln('  - ${entity.name} (${entity.type}) - ${DateFormat('MM-dd HH:mm').format(entity.lastUpdated)}');
        }
      }

      setState(() => _result = buffer.toString());
    } catch (e) {
      setState(() => _result = '分析失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 新增：清除孤立节点功能
  Future<void> _clearOrphanedNodes() async {
    final confirmed = await _showConfirmDialog(
        '清除孤立节点',
        '这将删除所有没有与事件关联的孤立实体节点。\n\n注意：此操作不可恢复，建议先进行"孤立实体分析"确认要删除的节点。\n\n确定继续吗？'
    );
    if (!confirmed) return;

    setState(() => _isLoading = true);
    try {
      final objectBox = ObjectBoxService();

      // 查找所有孤立节点
      final allNodes = objectBox.queryNodes();
      final allEventRelations = objectBox.queryEventEntityRelations();

      final orphanedEntities = allNodes.where((node) =>
      !allEventRelations.any((rel) => rel.entityId == node.id)
      ).toList();

      if (orphanedEntities.isEmpty) {
        setState(() => _result = '✅ 没有发现孤立节点，图谱状态良好！');
        return;
      }

      // 记录清除前的统计信息
      final orphanedByType = <String, List<Node>>{};
      for (final entity in orphanedEntities) {
        orphanedByType.putIfAbsent(entity.type, () => []).add(entity);
      }

      // 删除孤立节点 - 🔥 修复：使用正确的删除方法
      int deletedCount = 0;
      final deleteErrors = <String>[];

      for (final entity in orphanedEntities) {
        try {
          // 使用ObjectBox的remove方法删除节点（通过数据库ID）
          if (entity.obxId != null && entity.obxId! > 0) {
            final success = ObjectBoxService.nodeBox.remove(entity.obxId!);
            if (success) {
              deletedCount++;
            } else {
              deleteErrors.add('删除 ${entity.name} (${entity.id}) 失败');
            }
          } else {
            deleteErrors.add('删除 ${entity.name} 失败: 无效的数据库ID');
          }
        } catch (e) {
          deleteErrors.add('删除 ${entity.name} 时出错: $e');
        }
      }

      // 刷新数据
      await _loadKGData();

      // 生成结果报告
      final buffer = StringBuffer();
      buffer.writeln('🧹 孤立节点清除完成！\n');
      buffer.writeln('=' * 40);

      buffer.writeln('\n📊 清除统计:');
      buffer.writeln('• 发现孤立节点: ${orphanedEntities.length} 个');
      buffer.writeln('• 成功删除: $deletedCount 个');
      buffer.writeln('• 删除失败: ${deleteErrors.length} 个');

      if (orphanedByType.isNotEmpty) {
        buffer.writeln('\n📋 按类型清除统计:');
        orphanedByType.entries.toList()
          ..sort((a, b) => b.value.length.compareTo(a.value.length))
          ..forEach((entry) {
            final deletedInType = entry.value.where((entity) =>
            !_allNodes.any((node) => node.id == entity.id)
            ).length;
            buffer.writeln('• ${entry.key}: 清除 $deletedInType/${entry.value.length} 个');
          });
      }

      if (deleteErrors.isNotEmpty) {
        buffer.writeln('\n❌ 删除失败的节点:');
        for (final error in deleteErrors.take(10)) {
          buffer.writeln('• $error');
        }
        if (deleteErrors.length > 10) {
          buffer.writeln('... 还有 ${deleteErrors.length - 10} 个错误');
        }
      }

      buffer.writeln('\n📈 清除后状态:');
      buffer.writeln('• 当前实体总数: ${_allNodes.length}');
      buffer.writeln('• 当前事件总数: ${_allEventNodes.length}');
      buffer.writeln('• 当前关联关系: ${_allEventRelations.length}');

      final remainingOrphaned = _getOrphanedEntitiesCount();
      buffer.writeln('• 剩余孤立节点: $remainingOrphaned 个 ${remainingOrphaned == 0 ? "✅" : "⚠️"}');

      setState(() => _result = buffer.toString());
    } catch (e) {
      setState(() => _result = '清除孤立节点失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ========== 聚类相关方法 ==========

  /// 执行图谱整理（语义聚类）
  Future<void> _organizeGraph() async {
    setState(() {
      _isClusterting = true;
      _clusteringProgress = '';
      _clusteringResult = null;
    });

    try {
      final clusteringService = SemanticClusteringService();

      final result = await clusteringService.organizeGraph(
        forceRecluster: false,
        useTwoStage: true, // 使用两阶段聚类
        onProgress: (progress) {
          setState(() {
            _clusteringProgress += '$progress\n';
          });
        },
      );

      setState(() {
        _clusteringResult = result;
      });

      // 刷新数据以显示新的聚类
      await _loadKGData();

      // 显示结果对话框
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(result['success'] ? '✅ 聚类完成' : '❌ 聚类失败'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (result['success']) ...[
                    Text('创建聚类: ${result['clusters_created']} 个'),
                    Text('处理事件: ${result['events_processed']} 个'),
                    Text('已聚类事件: ${result['events_clustered']} 个'),
                    if (result['avg_cluster_size'] != null)
                      Text('平均聚类大小: ${result['avg_cluster_size'].toStringAsFixed(1)} 个'),
                    if (result['avg_similarity'] != null)
                      Text('平均相似度: ${result['avg_similarity'].toStringAsFixed(2)}'),
                    if (result['duration_seconds'] != null)
                      Text('耗时: ${result['duration_seconds']} 秒'),
                  ] else ...[
                    Text('错误: ${result['error'] ?? "未知错误"}'),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('关闭'),
              ),
              if (result['success'])
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // 切换到聚类管理标签
                    _tabController.animateTo(5);
                  },
                  child: Text('查看聚类'),
                ),
            ],
          ),
        );
      }

    } catch (e) {
      setState(() {
        _clusteringProgress += '\n❌ 错误: $e';
      });
    } finally {
      setState(() {
        _isClusterting = false;
      });
    }
  }

  /// 聚类管理标签页
  Widget _buildClusteringTab() {
    return FutureBuilder<List<ClusterNode>>(
      future: _loadClusters(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red),
                SizedBox(height: 16.h),
                Text('加载聚类失败'),
                SizedBox(height: 8.h),
                Text(
                  '${snapshot.error}',
                  style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16.h),
                ElevatedButton.icon(
                  onPressed: () => setState(() {}),
                  icon: Icon(Icons.refresh),
                  label: Text('重试'),
                ),
              ],
            ),
          );
        }

        final clusters = snapshot.data ?? [];

        if (clusters.isEmpty) {
          return _buildEmptyState(
            icon: Icons.workspaces_outline,
            title: '暂无聚类',
            subtitle: '点击"图谱维护"标签页中的"整理图谱"按钮创建聚类',
          );
        }

        return Column(
          children: [
            // 聚类统计面板
            Container(
              margin: EdgeInsets.all(16.w),
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.teal[50],
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: Colors.teal[200]!),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem('聚类总数', clusters.length, Icons.workspaces, Colors.teal),
                  _buildStatItem(
                    '平均大小',
                    clusters.isEmpty ? 0 : (clusters.fold(0, (sum, c) => sum + c.memberCount) / clusters.length).round(),
                    Icons.groups,
                    Colors.blue,
                  ),
                  _buildStatItem(
                    '事件总数',
                    clusters.fold(0, (sum, c) => sum + c.memberCount),
                    Icons.event,
                    Colors.orange,
                  ),
                ],
              ),
            ),

            // 质量监控和操作按钮
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _showQualityMetrics,
                      icon: Icon(Icons.analytics, size: 18),
                      label: Text('质量监控', style: TextStyle(fontSize: 12.sp)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 8.h),
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _detectOutliers,
                      icon: Icon(Icons.search, size: 18),
                      label: Text('检测离群点', style: TextStyle(fontSize: 12.sp)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 8.h),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 聚类列表
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                itemCount: clusters.length,
                itemBuilder: (context, index) => _buildClusterCard(clusters[index]),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 加载所有聚类节点
  Future<List<ClusterNode>> _loadClusters() async {
    try {
      final clusteringService = SemanticClusteringService();
      return await clusteringService.getAllClusters();
    } catch (e) {
      print('加载聚类失败: $e');
      // 如果Schema还未生成，返回空列表
      return <ClusterNode>[];
    }
  }

  /// 构建聚类卡片
  Widget _buildClusterCard(ClusterNode cluster) {
    return Card(
      margin: EdgeInsets.only(bottom: 12.h),
      elevation: 2,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: Colors.teal[100],
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(Icons.workspaces, color: Colors.teal[700], size: 24),
          ),
          title: Text(
            cluster.name,
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 4.h),
              Text(
                cluster.description,
                style: TextStyle(fontSize: 13.sp, color: Colors.grey[600]),
              ),
              SizedBox(height: 4.h),
              Row(
                children: [
                  Icon(Icons.event, size: 14, color: Colors.grey[600]),
                  SizedBox(width: 4.w),
                  Text(
                    '${cluster.memberCount} 个事件',
                    style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
                  ),
                  SizedBox(width: 12.w),
                  Icon(Icons.timeline, size: 14, color: Colors.grey[600]),
                  SizedBox(width: 4.w),
                  Text(
                    cluster.earliestEventTime != null && cluster.latestEventTime != null
                        ? '${DateFormat('MM/dd').format(cluster.earliestEventTime!)} - ${DateFormat('MM/dd').format(cluster.latestEventTime!)}'
                        : '时间未知',
                    style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
                  ),
                ],
              ),
            ],
          ),
          children: [
            FutureBuilder<List<EventNode>>(
              future: _loadClusterMembers(cluster.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Padding(
                    padding: EdgeInsets.all(16.w),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final members = snapshot.data ?? [];

                if (members.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.all(16.w),
                    child: Text(
                      '无法加载成员事件',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  );
                }

                return Column(
                  children: [
                    Divider(height: 1),
                    Container(
                      padding: EdgeInsets.all(12.w),
                      color: Colors.grey[50],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, size: 16, color: Colors.grey[700]),
                              SizedBox(width: 4.w),
                              Text(
                                '聚类成员 (${members.length}个)',
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8.h),
                          ...members.map((event) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                            leading: Container(
                              padding: EdgeInsets.all(4.w),
                              decoration: BoxDecoration(
                                color: _getEventTypeColor(event.type).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4.r),
                              ),
                              child: Icon(
                                Icons.event_note,
                                color: _getEventTypeColor(event.type),
                                size: 16,
                              ),
                            ),
                            title: Text(
                              event.name,
                              style: TextStyle(fontSize: 14.sp),
                            ),
                            subtitle: Text(
                              '${event.type}${event.startTime != null ? " • ${DateFormat('yyyy-MM-dd').format(event.startTime!)}" : ""}',
                              style: TextStyle(fontSize: 12.sp),
                            ),
                            onTap: () {
                              // 获取参与实体
                              final participants = _allNodes.where((n) =>
                                  _allEventRelations.any((r) => r.eventId == event.id && r.entityId == n.id)
                              ).toList();
                              _showEventDetails(event, participants);
                            },
                          )),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 加载聚类的成员事件
  Future<List<EventNode>> _loadClusterMembers(String clusterId) async {
    try {
      final clusteringService = SemanticClusteringService();
      return await clusteringService.getClusterMembers(clusterId);
    } catch (e) {
      print('加载聚类成员失败: $e');
      return <EventNode>[];
    }
  }

  /// 全量初始化聚类
  Future<void> _clusterInitAll() async {
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('⚠️ 确认全量初始化聚类'),
        content: Text(
          '这将对所有历史事件重新执行两阶段聚类。\n\n'
              '• 会更新所有事件的联合嵌入\n'
              '• 会清除现有聚类并重新计算\n'
              '• 可能需要较长时间\n\n'
              '确定要继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('确定'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isClusterting = true;
      _clusteringProgress = '';
      _clusteringResult = null;
    });

    try {
      final clusteringService = SemanticClusteringService();

      final result = await clusteringService.clusterInitAll(
        onProgress: (progress) {
          setState(() {
            _clusteringProgress += '$progress\n';
          });
        },
      );

      setState(() {
        _clusteringResult = result;
      });

      // 刷新数据
      await _loadKGData();

      // 显示结果对话框
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(result['success'] ? '✅ 全量聚类完成' : '❌ 聚类失败'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (result['success']) ...[
                    Text('第一阶段聚类: ${result['stage1_clusters']} 个'),
                    Text('第二阶段聚类: ${result['stage2_clusters']} 个'),
                    Text('处理事件: ${result['events_processed']} 个'),
                    if (result['duration_seconds'] != null)
                      Text('耗时: ${result['duration_seconds']} 秒'),
                  ] else ...[
                    Text('错误: ${result['error'] ?? "未知错误"}'),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('关闭'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print('全量聚类失败: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('❌ 聚类失败'),
            content: Text('错误: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('关闭'),
              ),
            ],
          ),
        );
      }
    } finally {
      setState(() {
        _isClusterting = false;
      });
    }
  }

  /// 按日期范围聚类
  Future<void> _clusterByDateRange() async {
    // 显示日期选择对话框
    DateTime? startDate;
    DateTime? endDate;

    final result = await showDialog<Map<String, DateTime>>(
      context: context,
      builder: (context) {
        DateTime tempStart = _selectedStartDate ?? DateTime.now().subtract(Duration(days: 30));
        DateTime tempEnd = _selectedEndDate ?? DateTime.now();

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('选择日期范围'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text('开始日期'),
                    subtitle: Text(
                      '${tempStart.year}-${tempStart.month.toString().padLeft(2, '0')}-${tempStart.day.toString().padLeft(2, '0')}',
                    ),
                    trailing: Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: tempStart,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => tempStart = picked);
                      }
                    },
                  ),
                  ListTile(
                    title: Text('结束日期'),
                    subtitle: Text(
                      '${tempEnd.year}-${tempEnd.month.toString().padLeft(2, '0')}-${tempEnd.day.toString().padLeft(2, '0')}',
                    ),
                    trailing: Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: tempEnd,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => tempEnd = picked);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, {
                    'start': tempStart,
                    'end': tempEnd,
                  }),
                  child: Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    startDate = result['start'];
    endDate = result['end'];

    if (startDate == null || endDate == null) return;

    setState(() {
      _isClusterting = true;
      _clusteringProgress = '';
      _clusteringResult = null;
    });

    try {
      final clusteringService = SemanticClusteringService();

      final clusterResult = await clusteringService.clusterByDateRange(
        startDate: startDate,
        endDate: endDate,
        onProgress: (progress) {
          setState(() {
            _clusteringProgress += '$progress\n';
          });
        },
      );

      setState(() {
        _clusteringResult = clusterResult;
      });

      // 刷新数据
      await _loadKGData();

      // 显示结果对话框
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(clusterResult['success'] ? '✅ 日期范围聚类完成' : '❌ 聚类失败'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (clusterResult['success']) ...[
                    Text('处理事件: ${clusterResult['events_processed']} 个'),
                    Text('合并到现有聚类: ${clusterResult['merged_events']} 个'),
                    Text('新建聚类: ${clusterResult['new_clusters']} 个'),
                    if (clusterResult['duration_seconds'] != null)
                      Text('耗时: ${clusterResult['duration_seconds']} 秒'),
                  ] else ...[
                    Text('错误: ${clusterResult['error'] ?? "未知错误"}'),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('关闭'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print('日期范围聚类失败: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('❌ 聚类失败'),
            content: Text('错误: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('关闭'),
              ),
            ],
          ),
        );
      }
    } finally {
      setState(() {
        _isClusterting = false;
      });
    }
  }

  /// 显示质量监控指标
  Future<void> _showQualityMetrics() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );

    try {
      final clusteringService = SemanticClusteringService();
      final metrics = await clusteringService.getClusteringQualityMetrics();

      Navigator.pop(context); // 关闭加载对话框

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.analytics, color: Colors.blue),
                SizedBox(width: 8.w),
                Text('聚类质量监控'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (metrics.containsKey('error')) ...[
                    Text('错误: ${metrics['error']}', style: TextStyle(color: Colors.red)),
                  ] else ...[
                    _buildMetricItem(
                      '聚类总数',
                      '${metrics['total_clusters']} 个',
                      Icons.workspaces,
                    ),
                    _buildMetricItem(
                      '平均类内相似度',
                      (metrics['avg_intra_similarity'] as double).toStringAsFixed(3),
                      Icons.favorite,
                    ),
                    _buildMetricItem(
                      '平均聚类大小',
                      (metrics['avg_cluster_size'] as double).toStringAsFixed(1),
                      Icons.groups,
                    ),
                    _buildMetricItem(
                      '离群点比例',
                      '${((metrics['outlier_ratio'] as double) * 100).toStringAsFixed(1)}%',
                      Icons.warning,
                    ),
                    _buildMetricItem(
                      '平均类间距离',
                      (metrics['avg_inter_distance'] as double).toStringAsFixed(3),
                      Icons.compare_arrows,
                    ),
                    Divider(),
                    _buildMetricItem(
                      '综合质量评分',
                      (metrics['quality_score'] as double).toStringAsFixed(3),
                      Icons.star,
                      color: _getQualityColor(metrics['quality_score'] as double),
                    ),
                    SizedBox(height: 8.h),
                    Container(
                      padding: EdgeInsets.all(8.w),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                      child: Text(
                        _getQualityComment(metrics['quality_score'] as double),
                        style: TextStyle(fontSize: 12.sp, color: Colors.grey[700]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('关闭'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // 关闭加载对话框
      print('获取质量指标失败: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('❌ 获取失败'),
            content: Text('错误: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('关闭'),
              ),
            ],
          ),
        );
      }
    }
  }

  Widget _buildMetricItem(String label, String value, IconData icon, {Color? color}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? Colors.grey),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 14.sp)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.bold,
              color: color ?? Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Color _getQualityColor(double score) {
    if (score >= 0.8) return Colors.green;
    if (score >= 0.6) return Colors.orange;
    return Colors.red;
  }

  String _getQualityComment(double score) {
    if (score >= 0.8) return '✅ 聚类质量优秀，簇内相似度高且簇间区分明显';
    if (score >= 0.6) return '⚠️ 聚类质量良好，可能存在少量离群点或混杂';
    return '❌ 聚类质量较差，建议重新调整参数或执行离群点重分配';
  }

  /// 检测并重分配离群点
  Future<void> _detectOutliers() async {
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('🔍 离群点检测与重分配'),
        content: Text(
          '这将检测所有聚类中的离群点（与簇中心相似度低的事件），并尝试将它们重分配到更合适的聚类中。\n\n'
              '确定要继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('确定'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );

    try {
      final clusteringService = SemanticClusteringService();

      String progressText = '';
      final result = await clusteringService.detectAndReassignOutliers(
        onProgress: (progress) {
          progressText = progress;
        },
      );

      Navigator.pop(context); // 关闭加载对话框

      // 刷新数据
      await _loadKGData();

      // 显示结果
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(result['success'] ? '✅ 离群点处理完成' : '❌ 处理失败'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (result['success']) ...[
                    Text('发现离群点: ${result['outliers_detected']} 个'),
                    Text('成功重分配: ${result['reassigned']} 个'),
                    Text('无法重分配: ${result['new_singletons']} 个'),
                    SizedBox(height: 8.h),
                    Container(
                      padding: EdgeInsets.all(8.w),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                      child: Text(
                        '提示：无法重分配的离群点已被标记为独立事件，可以在下次聚类时重新评估。',
                        style: TextStyle(fontSize: 12.sp, color: Colors.grey[700]),
                      ),
                    ),
                  ] else ...[
                    Text('错误: ${result['error'] ?? "未知错误"}'),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('关闭'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // 关闭加载对话框
      print('离群点检测失败: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('❌ 处理失败'),
            content: Text('错误: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('关闭'),
              ),
            ],
          ),
        );
      }
    }
  }

  /// 清空所有聚类
  Future<void> _clearAllClusters() async {
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('⚠️ 确认清空所有聚类'),
        content: Text(
          '这将删除所有聚类节点和聚类元数据，并清除所有事件的聚类关联。\n\n'
              '⚠️ 此操作不可撤销！\n\n'
              '确定要继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('确定清空'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isClusterting = true;
      _clusteringProgress = '';
      _clusteringResult = null;
    });

    try {
      final clusteringService = SemanticClusteringService();

      final result = await clusteringService.clearAllClusters(
        onProgress: (progress) {
          setState(() {
            _clusteringProgress += '$progress\n';
          });
        },
      );

      setState(() {
        _clusteringResult = result;
      });

      // 刷新数据
      await _loadKGData();

      // 显示结果对话框
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(result['success'] ? '✅ 聚类清空完成' : '❌ 清空失败'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (result['success']) ...[
                    Text('删除聚类节点: ${result['clusters_removed']} 个'),
                    Text('清除事件关联: ${result['events_cleared']} 个'),
                    Text('删除元数据: ${result['meta_removed']} 条'),
                    SizedBox(height: 8.h),
                    Container(
                      padding: EdgeInsets.all(8.w),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(4.r),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Text(
                        '✅ 所有聚类数据已清空，现在可以重新进行聚类测试了。',
                        style: TextStyle(fontSize: 12.sp, color: Colors.green[700]),
                      ),
                    ),
                  ] else ...[
                    Text('错误: ${result['error'] ?? "未知错误"}'),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('关闭'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print('清空聚类失败: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('❌ 清空失败'),
            content: Text('错误: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('关闭'),
              ),
            ],
          ),
        );
      }
    } finally {
      setState(() {
        _isClusterting = false;
      });
    }
  }
}
