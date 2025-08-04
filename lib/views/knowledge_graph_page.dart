import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../services/objectbox_service.dart';
import '../models/graph_models.dart';

class KnowledgeGraphPage extends StatefulWidget {
  @override
  _KnowledgeGraphPageState createState() => _KnowledgeGraphPageState();
}

class _KnowledgeGraphPageState extends State<KnowledgeGraphPage> with TickerProviderStateMixin {
  late TabController _tabController;

  // 新的数据结构
  List<EventNode> _eventNodes = [];
  List<EventEntityRelation> _eventEntityRelations = [];
  List<EventRelation> _eventRelations = [];
  List<Node> _entities = [];

  bool _isLoading = false;
  String _selectedTimeRange = '最近一周';
  String _selectedEventType = '全部';

  // 时间范围选项
  final Map<String, int> _timeRangeOptions = {
    '今天': 1,
    '最近一周': 7,
    '最近一月': 30,
    '最近三月': 90,
    '全部': -1,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
      final objectBox = ObjectBoxService();

      // 加载事件节点
      final eventNodes = objectBox.queryEventNodes();

      // 根据时间范围过滤
      final filteredEvents = _filterEventsByTimeRange(eventNodes);

      // 加载相关的实体关系和事件关系
      final eventEntityRelations = objectBox.queryEventEntityRelations();
      final eventRelations = objectBox.queryEventRelations();
      final entities = objectBox.queryNodes();

      setState(() {
        _eventNodes = filteredEvents;
        _eventEntityRelations = eventEntityRelations;
        _eventRelations = eventRelations;
        _entities = entities;
      });
    } catch (e) {
      print('Error loading knowledge graph data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<EventNode> _filterEventsByTimeRange(List<EventNode> events) {
    if (_selectedTimeRange == '全部') return events;

    final days = _timeRangeOptions[_selectedTimeRange] ?? 7;
    final cutoffDate = DateTime.now().subtract(Duration(days: days));

    return events.where((event) {
      if (event.startTime != null) {
        return event.startTime!.isAfter(cutoffDate);
      }
      return event.lastUpdated.isAfter(cutoffDate);
    }).toList();
  }

  List<EventNode> get _filteredEventsByType {
    if (_selectedEventType == '全部') return _eventNodes;
    return _eventNodes.where((event) => event.type == _selectedEventType).toList();
  }

  Set<String> get _availableEventTypes {
    final types = _eventNodes.map((e) => e.type).toSet();
    return {'全部', ...types};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('知识图谱'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: '事件时间线'),
            Tab(text: '知识网络'),
            Tab(text: '智能洞察'),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() {
                _selectedTimeRange = value;
              });
              _loadData();
            },
            itemBuilder: (context) => _timeRangeOptions.keys.map((range) =>
              PopupMenuItem(
                value: range,
                child: Row(
                  children: [
                    if (_selectedTimeRange == range) Icon(Icons.check, size: 16),
                    SizedBox(width: 8.w),
                    Text(range),
                  ],
                ),
              )
            ).toList(),
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildEventTimelineTab(),
                _buildKnowledgeNetworkTab(),
                _buildInsightsTab(),
              ],
            ),
    );
  }

  Widget _buildEventTimelineTab() {
    if (_eventNodes.isEmpty) {
      return _buildEmptyState(
        icon: Icons.timeline,
        title: '暂无事件记录',
        subtitle: '与我聊天后，我会自动记录重要事件',
        actionText: '开始对话',
        onAction: () => Navigator.pop(context),
      );
    }

    final filteredEvents = _filteredEventsByType;

    // 按时间排序
    filteredEvents.sort((a, b) {
      final timeA = a.startTime ?? a.lastUpdated;
      final timeB = b.startTime ?? b.lastUpdated;
      return timeB.compareTo(timeA);
    });

    return Column(
      children: [
        // 筛选器
        Container(
          padding: EdgeInsets.all(16.w),
          child: Row(
            children: [
              Text('事件类型：', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(width: 8.w),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _availableEventTypes.map((type) =>
                      Padding(
                        padding: EdgeInsets.only(right: 8.w),
                        child: FilterChip(
                          label: Text(type),
                          selected: _selectedEventType == type,
                          onSelected: (selected) {
                            setState(() {
                              _selectedEventType = type;
                            });
                          },
                        ),
                      )
                    ).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 事件列表
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            itemCount: filteredEvents.length,
            itemBuilder: (context, index) => _buildEventCard(filteredEvents[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildEventCard(EventNode event) {
    // 获取参与的实体
    final participantRelations = _eventEntityRelations
        .where((r) => r.eventId == event.id)
        .toList();

    final participants = participantRelations
        .map((r) => _entities.firstWhere(
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

  Widget _buildKnowledgeNetworkTab() {
    if (_eventNodes.isEmpty) {
      return _buildEmptyState(
        icon: Icons.device_hub,
        title: '知识网络为空',
        subtitle: '需要先积累一些对话记录',
      );
    }

    // 使用分层列表展示，更清晰地显示关系
    return _buildHierarchicalNetworkView();
  }

  Widget _buildHierarchicalNetworkView() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 控制面板
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700]),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    '以事件为中心的关系网络视图，展示事件与相关实体的关系',
                    style: TextStyle(color: Colors.blue[700], fontSize: 13.sp),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 20.h),

          // 按事件类型分组展示
          ...(_buildEventGroupsWithRelations()),
        ],
      ),
    );
  }

  List<Widget> _buildEventGroupsWithRelations() {
    // 按事件类型分组
    final eventsByType = <String, List<EventNode>>{};
    for (final event in _eventNodes) {
      eventsByType.putIfAbsent(event.type, () => []).add(event);
    }

    final widgets = <Widget>[];

    for (final entry in eventsByType.entries) {
      final eventType = entry.key;
      final events = entry.value;

      widgets.add(_buildEventTypeSection(eventType, events));
      widgets.add(SizedBox(height: 24.h));
    }

    return widgets;
  }

  Widget _buildEventTypeSection(String eventType, List<EventNode> events) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 事件类型标题
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: _getEventTypeColor(eventType),
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.category, color: Colors.white, size: 16),
              SizedBox(width: 6.w),
              Text(
                '$eventType (${events.length})',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14.sp,
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: 12.h),

        // 事件列表
        ...events.map((event) => _buildEventWithRelationsCard(event)),
      ],
    );
  }

  Widget _buildEventWithRelationsCard(EventNode event) {
    // 获取与此事件相关的实体
    final relatedEntityRelations = _eventEntityRelations
        .where((r) => r.eventId == event.id)
        .toList();

    final relatedEntities = relatedEntityRelations
        .map((r) => _entities.firstWhere(
            (e) => e.id == r.entityId,
            orElse: () => Node(id: r.entityId, name: r.entityId, type: '未知')))
        .toList();

    // 按角色分组实体
    final entitiesByRole = <String, List<Node>>{};
    for (int i = 0; i < relatedEntityRelations.length; i++) {
      final relation = relatedEntityRelations[i];
      final entity = relatedEntities[i];
      entitiesByRole.putIfAbsent(relation.role, () => []).add(entity);
    }

    return Container(
      margin: EdgeInsets.only(bottom: 16.h, left: 20.w),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12.r),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 事件信息头部
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: _getEventTypeColor(event.type).withOpacity(0.1),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12.r),
                topRight: Radius.circular(12.r),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: _getEventTypeColor(event.type),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Icon(Icons.event, color: Colors.white, size: 20),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.name,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (event.description != null) ...[
                        SizedBox(height: 4.h),
                        Text(
                          event.description!,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.grey[600],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (event.startTime != null)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Text(
                      DateFormat('MM/dd HH:mm').format(event.startTime!),
                      style: TextStyle(fontSize: 11.sp, color: Colors.grey[700]),
                    ),
                  ),
              ],
            ),
          ),

          // 关系网络展示
          if (entitiesByRole.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.all(16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '关联关系',
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  SizedBox(height: 12.h),

                  // 按角色展示相关实体
                  ...entitiesByRole.entries.map((roleEntry) =>
                    _buildRoleRelationGroup(roleEntry.key, roleEntry.value)
                  ),
                ],
              ),
            ),
          ] else ...[
            Padding(
              padding: EdgeInsets.all(16.w),
              child: Text(
                '暂无关联实体',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRoleRelationGroup(String role, List<Node> entities) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 角色标签
          Container(
            width: 80.w,
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Text(
              role,
              style: TextStyle(
                fontSize: 11.sp,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          SizedBox(width: 12.w),

          // 连接线
          Container(
            width: 20.w,
            height: 32.h,
            child: CustomPaint(
              painter: ConnectionLinePainter(),
            ),
          ),

          // 实体列表
          Expanded(
            child: Wrap(
              spacing: 6.w,
              runSpacing: 6.h,
              children: entities.map((entity) => _buildEntityChip(entity)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntityChip(Node entity) {
    return InkWell(
      onTap: () => _showEntityDetails(entity),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: _getEntityTypeColor(entity.type),
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6.w,
              height: 6.h,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: 6.w),
            Text(
              entity.name,
              style: TextStyle(
                color: Colors.white,
                fontSize: 11.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(width: 4.w),
            Text(
              '(${entity.type})',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 9.sp,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEntityDetails(Node entity) {
    // 查找与该实体相关的所有事件
    final relatedEventRelations = _eventEntityRelations
        .where((r) => r.entityId == entity.id)
        .toList();

    final relatedEvents = relatedEventRelations
        .map((r) => _eventNodes.firstWhere(
            (e) => e.id == r.eventId,
            orElse: () => EventNode(id: r.eventId, name: '未知事件', type: '未知')))
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        builder: (context, scrollController) => Container(
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: relatedEvents.length,
                  itemBuilder: (context, index) {
                    final event = relatedEvents[index];
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
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
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

  Widget _buildInsightsTab() {
    return ListView(
      padding: EdgeInsets.all(16.w),
      children: [
        _buildInsightCard(
          '📊 数据概览',
          [
            _buildStatRow('记录的事件', _eventNodes.length.toString(), Icons.event),
            _buildStatRow('涉及实体', _entities.length.toString(), Icons.person),
            _buildStatRow('事件关系', _eventRelations.length.toString(), Icons.link),
          ],
        ),

        SizedBox(height: 16.h),

        _buildInsightCard(
          '🎯 事件类型分布',
          _buildEventTypeStats(),
        ),

        SizedBox(height: 16.h),

        _buildInsightCard(
          '📅 最近活动',
          _buildRecentActivityStats(),
        ),

        SizedBox(height: 16.h),

        _buildInsightCard(
          '🔗 核心实体',
          _buildCoreEntitiesStats(),
        ),
      ],
    );
  }

  Widget _buildInsightCard(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
            SizedBox(height: 12.h),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, IconData icon) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.blue),
          SizedBox(width: 8.w),
          Text(label, style: TextStyle(fontSize: 14.sp)),
          Spacer(),
          Text(value, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  List<Widget> _buildEventTypeStats() {
    final typeStats = <String, int>{};
    for (final event in _eventNodes) {
      typeStats[event.type] = (typeStats[event.type] ?? 0) + 1;
    }

    final sortedTypes = typeStats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedTypes.map((entry) =>
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
            Text(entry.key, style: TextStyle(fontSize: 14.sp)),
            Spacer(),
            Text('${entry.value}', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
          ],
        ),
      )
    ).toList();
  }

  List<Widget> _buildRecentActivityStats() {
    final now = DateTime.now();
    final today = _eventNodes.where((e) =>
      (e.startTime ?? e.lastUpdated).isAfter(DateTime(now.year, now.month, now.day))
    ).length;

    final thisWeek = _eventNodes.where((e) =>
      (e.startTime ?? e.lastUpdated).isAfter(now.subtract(Duration(days: 7)))
    ).length;

    return [
      _buildStatRow('今日事件', today.toString(), Icons.today),
      _buildStatRow('本周事件', thisWeek.toString(), Icons.date_range),
    ];
  }

  List<Widget> _buildCoreEntitiesStats() {
    // 统计实体参与事件的频次
    final entityFreq = <String, int>{};
    for (final relation in _eventEntityRelations) {
      entityFreq[relation.entityId] = (entityFreq[relation.entityId] ?? 0) + 1;
    }

    final sortedEntities = entityFreq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedEntities.take(5).map((entry) {
      final entity = _entities.firstWhere(
        (e) => e.id == entry.key,
        orElse: () => Node(id: entry.key, name: entry.key, type: '未知'),
      );

      return Padding(
        padding: EdgeInsets.symmetric(vertical: 4.h),
        child: Row(
          children: [
            Container(
              width: 12.w,
              height: 12.h,
              decoration: BoxDecoration(
                color: _getEntityTypeColor(entity.type),
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: 8.w),
            Text(entity.name, style: TextStyle(fontSize: 14.sp)),
            SizedBox(width: 4.w),
            Text('(${entity.type})', style: TextStyle(fontSize: 12.sp, color: Colors.grey[600])),
            Spacer(),
            Text('${entry.value}次', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionText,
    VoidCallback? onAction,
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
          if (actionText != null && onAction != null) ...[
            SizedBox(height: 16.h),
            ElevatedButton(
              onPressed: onAction,
              child: Text(actionText),
            ),
          ],
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
        builder: (context, scrollController) => Container(
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
      case '用餐': case 'dining': return Colors.brown;
      case '经历': case 'experience': return Colors.cyan;
      default: return Colors.grey;
    }
  }

  Color _getEntityTypeColor(String type) {
    switch (type.toLowerCase()) {
      case '人': case 'person': case '人物': return Colors.red[300]!;
      case '地点': case 'location': return Colors.green[300]!;
      case '工具': case 'tool': return Colors.blue[300]!;
      case '物品': case 'item': return Colors.orange[300]!;
      case '概念': case 'concept': return Colors.purple[300]!;
      case '组织': case 'organization': return Colors.teal[300]!;
      case '技能': case 'skill': return Colors.indigo[300]!;
      case '状态': case 'state': return Colors.pink[300]!;
      default: return Colors.grey[300]!;
    }
  }
}

// 连接线绘制器
class ConnectionLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[400]!
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(0, size.height / 2);
    path.lineTo(size.width, size.height / 2);

    // 添加箭头
    final arrowSize = 4.0;
    path.moveTo(size.width - arrowSize, size.height / 2 - arrowSize);
    path.lineTo(size.width, size.height / 2);
    path.lineTo(size.width - arrowSize, size.height / 2 + arrowSize);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
