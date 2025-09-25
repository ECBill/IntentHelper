import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadKGData();

    // 默认设置为最近一周
    _selectedEndDate = DateTime.now();
    _selectedStartDate = _selectedEndDate!.subtract(Duration(days: 7));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
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
    return Padding(
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


          SizedBox(height: 20.h),

          // 处理结果显示
          if (_processResult.isNotEmpty) ...[
            Text('处理结果：', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
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
                  child: Text(_processResult, style: TextStyle(fontSize: 12.sp)),
                ),
              ),
            ),
          ],
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
                                final emb = event.embedding;
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
    final TextEditingController _vectorSearchController = TextEditingController();
    List<Map<String, dynamic>> _vectorResults = [];
    bool _isSearching = false;

    return StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('事件向量查询', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
            SizedBox(height: 12.h),
            TextField(
              controller: _vectorSearchController,
              decoration: InputDecoration(
                labelText: '输入一段话，匹配相关事件',
                hintText: '例如：我昨天在星巴克用MacBook写代码',
                border: OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(Icons.search),
                  onPressed: _isSearching
                      ? null
                      : () async {
                    final query = _vectorSearchController.text.trim();
                    if (query.isEmpty) return;

                    setState(() => _isSearching = true);

                    final results = await KnowledgeGraphService.searchEventsByText(query);
                    setState(() {
                      _vectorResults = results;
                      _isSearching = false;
                    });
                  },
                ),
              ),
            ),
            SizedBox(height: 20.h),

            if (_isSearching)
              Center(child: CircularProgressIndicator())
            else if (_vectorResults.isEmpty)
              Text('没有找到匹配的事件', style: TextStyle(color: Colors.grey))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _vectorResults.length,
                  itemBuilder: (context, index) {
                    final result = _vectorResults[index];
                    final similarity = (result['similarity'] as double?)?.toStringAsFixed(2) ?? 'N/A';
                    final event = result['event'] as EventNode?;

                    if (event == null) return SizedBox.shrink();

                    return ListTile(
                      title: Text(event.name),
                      subtitle: Text('${event.type} • 相似度: $similarity'),
                      trailing: event.startTime != null
                          ? Text(DateFormat('MM/dd HH:mm').format(event.startTime!))
                          : null,
                      onTap: () {
                        final participants = _allNodes.where((n) =>
                            _allEventRelations.any((r) => r.eventId == event.id && r.entityId == n.id)
                        ).toList();
                        _showEventDetails(event, participants);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
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
          // 使用ObjectBox的remove方法删除节点（通��数据库ID）
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
}
