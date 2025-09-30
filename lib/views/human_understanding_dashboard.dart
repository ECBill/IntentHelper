/// 人类理解系统可视化界面
/// 提供系统状态、分析结果和统计信息的可视化展示

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:app/models/human_understanding_models.dart' as hum;
import 'package:app/services/human_understanding_system.dart';
import 'package:app/services/knowledge_graph_manager.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'dart:convert';

class HumanUnderstandingDashboard extends StatefulWidget {
  const HumanUnderstandingDashboard({super.key});

  @override
  State<HumanUnderstandingDashboard> createState() => _HumanUnderstandingDashboardState();
}

class _HumanUnderstandingDashboardState extends State<HumanUnderstandingDashboard>
    with TickerProviderStateMixin {
  final HumanUnderstandingSystem _system = HumanUnderstandingSystem();
  final KnowledgeGraphManager _kgManager = KnowledgeGraphManager();

  late TabController _tabController;
  StreamSubscription? _systemStateSubscription;

  hum.HumanUnderstandingSystemState? _currentState;
  Map<String, dynamic>? _systemMetrics;
  Map<String, dynamic>? _userPatterns;
  Map<String, dynamic>? _intelligentSuggestions;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this); // 🔥 修改：改为6个标签页
    _initializeSystem();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _systemStateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeSystem() async {
    try {
      print('[Dashboard] 🚀 开始初始化人类理解系统...');

      await _system.initialize();
      print('[Dashboard] ✅ 人类理解系统初始化完成');

      _loadSystemData();

      // 监听系统状态更新
      _systemStateSubscription = _system.systemStateUpdates.listen((state) {
        if (mounted) {
          setState(() {
            _currentState = state;
          });
        }
      });

      // 延迟重新加载数据，确保系统处理完测试数据
      Future.delayed(Duration(seconds: 3), () {
        if (mounted) {
          _loadSystemData();
        }
      });
    } catch (e) {
      print('[Dashboard] ❌ 初始化人类理解系统失败: $e');
    }
  }

  void _loadSystemData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final currentState = _system.getCurrentState();
      final metrics = _system.getSystemMetrics();
      final patterns = _system.analyzeUserPatterns();
      final suggestions = _system.getIntelligentSuggestions();

      setState(() {
        _currentState = currentState;
        _systemMetrics = metrics;
        _userPatterns = patterns;
        _intelligentSuggestions = suggestions;
        _isLoading = false;
      });
    } catch (e) {
      print('加载系统数据失败: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('类人意图理解系统', style: TextStyle(fontSize: 18.sp)),
        backgroundColor: Theme
            .of(context)
            .primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadSystemData,
          ),
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (context) =>
            [
              PopupMenuItem(value: 'export', child: Text('导出数据')),
              PopupMenuItem(value: 'reset', child: Text('重置系统')),
              PopupMenuItem(value: 'test', child: Text('测试分析')),
              PopupMenuItem(
                  value: 'trigger_check', child: Text('手动检查对话')),
              PopupMenuItem(
                  value: 'reset_monitoring', child: Text('重置监听状态')),
              PopupMenuItem(value: 'debug_info', child: Text('调试信息')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: '概览'),
            Tab(text: '意图管理'),
            Tab(text: '主题追踪'),
            Tab(text: '知识图谱'), // 🔥 新增：知识图谱标签页
            Tab(text: '因果分析'),
            Tab(text: '认知负载'),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildIntentsTab(),
          _buildTopicsTab(),
          _buildKnowledgeGraphTab(), // 🔥 新增：知识图谱页面
          _buildCausalTab(),
          _buildCognitiveLoadTab(),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    if (_currentState == null) {
      return Center(child: Text('暂无数据', style: TextStyle(fontSize: 16.sp)));
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSystemStatusCard(),
          SizedBox(height: 16.h),
          _buildQuickStatsCard(),
          SizedBox(height: 16.h),
          _buildIntelligentSuggestionsCard(),
          SizedBox(height: 16.h),
          _buildRecentActivityCard(),
        ],
      ),
    );
  }

  Widget _buildSystemStatusCard() {
    final metrics = _systemMetrics ?? {};
    final isInitialized = metrics['system_initialized'] ?? false;
    final uptime = metrics['uptime_minutes'] ?? 0;

    // 🔥 新增：获取监听状态
    final monitoringStatus = _system.getMonitoringStatus();

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isInitialized ? Icons.check_circle : Icons.error,
                  color: isInitialized ? Colors.green : Colors.red,
                  size: 24.sp,
                ),
                SizedBox(width: 8.w),
                Text(
                  '系统状态',
                  style: TextStyle(
                      fontSize: 18.sp, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            Text(
              '状态: ${isInitialized ? "运行中" : "未初始化"}',
              style: TextStyle(fontSize: 14.sp),
            ),
            Text(
              '运行时间: ${uptime}分钟',
              style: TextStyle(fontSize: 14.sp),
            ),

            // 🔥 新增：监听状态信息
            SizedBox(height: 8.h),
            Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '监听状态',
                    style: TextStyle(
                        fontSize: 12.sp, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    '监听中: ${monitoringStatus['is_monitoring'] ?? false
                        ? "是"
                        : "否"}',
                    style: TextStyle(fontSize: 11.sp),
                  ),
                  Text(
                    '已处理记录: ${monitoringStatus['processed_record_count'] ??
                        0}',
                    style: TextStyle(fontSize: 11.sp),
                  ),
                  Text(
                    '检查间隔: ${monitoringStatus['monitor_interval_seconds'] ??
                        0}秒',
                    style: TextStyle(fontSize: 11.sp),
                  ),
                ],
              ),
            ),

            if (_currentState != null) ...[
              SizedBox(height: 8.h),
              Text(
                '认知负载: ${_getCognitiveLoadText(
                    _currentState!.currentCognitiveLoad.level)}',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: _getCognitiveLoadColor(
                      _currentState!.currentCognitiveLoad.level),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStatsCard() {
    if (_currentState == null) return Container();

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '快速统计',
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    '活跃意图',
                    '${_currentState!.activeIntents.length}',
                    Icons.lightbulb,
                    Colors.orange,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    '讨论主题',
                    '${_currentState!.activeTopics.length}',
                    Icons.topic,
                    Colors.blue,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    '因果关系',
                    '${_currentState!.recentCausalChains.length}',
                    Icons.link,
                    Colors.green,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    '语义三元组',
                    '${_currentState!.recentTriples.length}',
                    Icons.account_tree,
                    Colors.purple,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon,
      Color color) {
    return Container(
      padding: EdgeInsets.all(12.w),
      margin: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24.sp),
          SizedBox(height: 4.h),
          Text(
            value,
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildIntelligentSuggestionsCard() {
    final suggestions = _intelligentSuggestions?['suggestions'] as Map<
        String,
        dynamic>? ?? {};
    final priorityActions = _intelligentSuggestions?['priority_actions'] as List? ??
        [];

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology, color: Colors.indigo, size: 24.sp),
                SizedBox(width: 8.w),
                Text(
                  '智能建议',
                  style: TextStyle(
                      fontSize: 18.sp, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            if (priorityActions.isNotEmpty) ...[
              Text(
                '优先行动:',
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
              ),
              ...priorityActions.map((action) =>
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 2.h),
                    child: Row(
                      children: [
                        Icon(Icons.arrow_right, size: 16.sp,
                            color: Colors.orange),
                        SizedBox(width: 4.w),
                        Expanded(
                          child: Text(
                            action.toString(),
                            style: TextStyle(fontSize: 13.sp),
                          ),
                        ),
                      ],
                    ),
                  )),
              SizedBox(height: 8.h),
            ],
            if (suggestions.isNotEmpty) ...[
              Text(
                '系统建议:',
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
              ),
              ...suggestions.entries.map((entry) =>
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 2.h),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lightbulb_outline, size: 16.sp,
                            color: Colors.amber),
                        SizedBox(width: 4.w),
                        Expanded(
                          child: Text(
                            entry.value.toString(),
                            style: TextStyle(fontSize: 13.sp),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
            if (suggestions.isEmpty && priorityActions.isEmpty)
              Text(
                '暂无特别建议',
                style: TextStyle(fontSize: 14.sp, color: Colors.grey[600]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivityCard() {
    if (_currentState == null) return Container();

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '最近活动',
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12.h),
            if (_currentState!.recentTriples.isNotEmpty) ...[
              Text(
                '最新语义关系:',
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
              ),
              ..._currentState!.recentTriples.take(3).map((triple) =>
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 2.h),
                    child: Text(
                      '${triple.subject} → ${triple.predicate} → ${triple
                          .object}',
                      style: TextStyle(
                          fontSize: 12.sp, color: Colors.grey[700]),
                    ),
                  )),
            ],
            if (_currentState!.recentCausalChains.isNotEmpty) ...[
              SizedBox(height: 8.h),
              Text(
                '最新因果关系:',
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
              ),
              ..._currentState!.recentCausalChains.take(2).map((causal) =>
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 2.h),
                    child: Text(
                      '${causal.cause} → ${causal.effect}',
                      style: TextStyle(
                          fontSize: 12.sp, color: Colors.grey[700]),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIntentsTab() {
    if (_currentState == null) return Container();

    final intents = _currentState!.activeIntents;

    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        children: [
          _buildIntentStatsHeader(intents),
          SizedBox(height: 16.h),
          Expanded(
            child: intents.isEmpty
                ? Center(child: Text('暂无活跃意图'))
                : ListView.builder(
              itemCount: intents.length,
              itemBuilder: (context, index) => _buildIntentCard(intents[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntentStatsHeader(List<hum.Intent> intents) {
    final stateGroups = <String, int>{};
    for (final intent in intents) {
      final state = intent.state
          .toString()
          .split('.')
          .last;
      stateGroups[state] = (stateGroups[state] ?? 0) + 1;
    }

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '意图统计',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8.h),
            Wrap(
              spacing: 8.w,
              children: stateGroups.entries.map((entry) =>
                  Chip(
                    label: Text('${entry.key}: ${entry.value}'),
                    backgroundColor: _getIntentStateColor(entry.key),
                  )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntentCard(hum.Intent intent) {
    return Card(
        margin: EdgeInsets.only(bottom: 8.h),
        child: Padding(
          padding: EdgeInsets.all(12.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      intent.description,
                      style: TextStyle(
                          fontSize: 14.sp, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                    decoration: BoxDecoration(
                      color: _getIntentStateColor(intent.state
                          .toString()
                          .split('.')
                          .last),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Text(
                      intent.state
                          .toString()
                          .split('.')
                          .last,
                      style: TextStyle(fontSize: 10.sp, color: Colors.white),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              Row(
                children: [
                  Text(
                    '类别: ${intent.category}',
                    style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
                  ),
                  SizedBox(width: 16.w),
                  Text(
                    '置信度: ${(intent.confidence * 100).toInt()}%',
                    style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
                  ),
                ],
              ),
              if (intent.relatedEntities.isNotEmpty) ...[
                SizedBox(height: 4.h),
                Text(
                  '相关实体: ${intent.relatedEntities.join(', ')}',
                  style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
                ),
              ],
            ],
          ),
        ));
  }

  Widget _buildTopicsTab() {
    if (_currentState == null) return Container();

    final topics = _currentState!.activeTopics;

    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        children: [
          Expanded(
            child: topics.isEmpty
                ? Center(child: Text('暂无活跃主题'))
                : ListView.builder(
              itemCount: topics.length,
              itemBuilder: (context, index) =>
                  _buildEnhancedTopicCard(topics[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedTopicCard(hum.Topic topic) {
    final relatedIntents = _currentState?.intentTopicRelations?[topic.name] ??
        [];

    // 提取上下文的三个核心字段
    final ctx = (topic.context ?? {}) as Map<String, dynamic>;
    final importance = (ctx['importance'] ?? '').toString();
    final timeSensitivity = (ctx['time_sensitivity'] ?? '').toString();
    final emotionalTone = (ctx['emotional_tone'] ?? '').toString();

    return Card(
        margin: EdgeInsets.only(bottom: 8.h),
        child: Padding(
          padding: EdgeInsets.all(12.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      topic.name,
                      style: TextStyle(
                          fontSize: 14.sp, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Text(
                      '权重: ${topic.weight.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 10.sp),
                    ),
                  ),
                ],
              ),

              // 上下文三要素展示
              if (importance.isNotEmpty || timeSensitivity.isNotEmpty ||
                  emotionalTone.isNotEmpty) ...[
                SizedBox(height: 8.h),
                Wrap(
                  spacing: 6.w,
                  runSpacing: 4.h,
                  children: [
                    if (importance.isNotEmpty)
                      Chip(
                        label: Text('重要性: $importance',
                            style: TextStyle(fontSize: 10.sp)),
                        backgroundColor: Colors.deepPurple.withOpacity(0.1),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    if (timeSensitivity.isNotEmpty)
                      Chip(
                        label: Text('时效性: $timeSensitivity',
                            style: TextStyle(fontSize: 10.sp)),
                        backgroundColor: Colors.teal.withOpacity(0.1),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    if (emotionalTone.isNotEmpty)
                      Chip(
                        label: Text('情绪: $emotionalTone',
                            style: TextStyle(fontSize: 10.sp)),
                        backgroundColor: Colors.pink.withOpacity(0.1),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ],

              // 关键词
              if (topic.keywords.isNotEmpty) ...[
                SizedBox(height: 8.h),
                Text('关键词:', style: TextStyle(
                    fontSize: 12.sp, fontWeight: FontWeight.w600)),
                SizedBox(height: 4.h),
                Wrap(
                  spacing: 4.w,
                  runSpacing: 4.h,
                  children: topic.keywords.map((keyword) =>
                      Chip(
                        label: Text(keyword, style: TextStyle(fontSize: 10.sp)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      )).toList(),
                ),
              ],

              // 实体
              if (topic.entities.isNotEmpty) ...[
                SizedBox(height: 8.h),
                Text('相关实体:', style: TextStyle(
                    fontSize: 12.sp, fontWeight: FontWeight.w600)),
                SizedBox(height: 4.h),
                Wrap(
                  spacing: 4.w,
                  runSpacing: 4.h,
                  children: topic.entities.map((ent) =>
                      Chip(
                        label: Text(ent, style: TextStyle(fontSize: 10.sp)),
                        backgroundColor: Colors.blueGrey.withOpacity(0.1),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      )).toList(),
                ),
              ],

              if (relatedIntents.isNotEmpty) ...[
                SizedBox(height: 8.h),
                Text(
                  '相关意图:',
                  style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600),
                ),
                ...relatedIntents.map((intent) =>
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 2.h),
                      child: Text(
                        intent.toString(),
                        style: TextStyle(
                            fontSize: 12.sp, color: Colors.grey[700]),
                      ),
                    )),
              ],
            ],
          ),
        ));
  }

  Widget _buildKnowledgeGraphTab() {
    final kgResults = _kgManager.getLastResult()?['results'] as List? ?? [];
    final isDataEmpty = kgResults.isEmpty;

    // 字段顺序与 eventMap 保持一致
    final List<MapEntry<String, String>> fieldOrder = [
      MapEntry('id', 'ID'),
      MapEntry('title', '标题'),
      MapEntry('name', '名称'),
      MapEntry('type', '类型'),
      MapEntry('description', '描述'),
      MapEntry('similarity', '相关度'),
      MapEntry('matched_topic', '查询来源主题'),
      MapEntry('startTime', '开始时间'),
      MapEntry('endTime', '结束时间'),
      MapEntry('location', '地点'),
      MapEntry('purpose', '目的'),
      MapEntry('result', '结果'),
    ];

    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: isDataEmpty ? Colors.red[50] : Colors.white,
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(
                color: isDataEmpty ? Colors.red.withOpacity(0.2) : Colors.grey.withOpacity(0.18),
                width: 1.0,
              ),
              boxShadow: [
                if (!isDataEmpty)
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.08),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  isDataEmpty ? Icons.error_outline : Icons.hub,
                  size: 22.sp,
                  color: isDataEmpty ? Colors.red[400] : Colors.blueGrey[700],
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    isDataEmpty ? '未找到相关知识图谱节点' : '知识图谱节点 · 向量匹配结果',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: isDataEmpty ? Colors.red[700] : Colors.blueGrey[800],
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 14.h),
          if (isDataEmpty)
            Center(
              child: Text('暂无知识图谱节点', style: TextStyle(fontSize: 16.sp, color: Colors.grey, fontWeight: FontWeight.w500)),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: kgResults.length,
                separatorBuilder: (_, __) => SizedBox(height: 12.h),
                itemBuilder: (context, idx) {
                  final node = kgResults[idx] as Map<String, dynamic>;
                  return InkWell(
                    borderRadius: BorderRadius.circular(14.r),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(node['title']?.toString() ?? node['name']?.toString() ?? '未命名节点', style: TextStyle(fontWeight: FontWeight.bold)),
                          content: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final entry in fieldOrder)
                                  if (node[entry.key] != null && node[entry.key].toString().isNotEmpty)
                                    Padding(
                                      padding: EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('${entry.value}: ', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700])),
                                          Expanded(child: Text(
                                            entry.key == 'similarity' && node[entry.key] is num
                                                ? (node[entry.key] as num).toStringAsFixed(3)
                                                : node[entry.key].toString(),
                                            style: TextStyle(color: Colors.grey[900]),
                                          )),
                                        ],
                                      ),
                                    ),
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
                    },
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r),
                        side: BorderSide(color: Colors.grey.withOpacity(0.13), width: 1),
                      ),
                      color: Colors.white,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 标题
                            Text(
                              node['title']?.toString() ?? node['name']?.toString() ?? '未命名节点',
                              style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.bold, color: Colors.blueGrey[900]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 6.h),
                            // 主题标签单独一行
                            if (node['matched_topic'] != null)
                              Row(
                                children: [
                                  Icon(Icons.label, size: 15.sp, color: Colors.blue[400]),
                                  SizedBox(width: 4.w),
                                  Flexible(
                                    child: Text(
                                      '主题: ${node['matched_topic']}',
                                      style: TextStyle(fontSize: 13.sp, color: Colors.blue[600], fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            if (node['description'] != null && node['description'].toString().trim().isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(top: 8.h, bottom: 2.h),
                                child: Text(
                                  node['description'].toString(),
                                  style: TextStyle(fontSize: 13.sp, color: Colors.grey[800], fontWeight: FontWeight.w400, height: 1.32),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (node['similarity'] != null || node['score'] != null)
                              Padding(
                                padding: EdgeInsets.only(top: 6.h, bottom: 2.h),
                                child: Row(
                                  children: [
                                    Icon(Icons.auto_awesome, color: Colors.blue[300], size: 15.sp),
                                    SizedBox(width: 4.w),
                                    Text('相关度', style: TextStyle(fontSize: 12.sp, color: Colors.blue[400], fontWeight: FontWeight.w500)),
                                    SizedBox(width: 8.w),
                                    Text(
                                      ((node['similarity'] ?? node['score']) is num)
                                          ? (((node['similarity'] ?? node['score']) as num).toStringAsFixed(3))
                                          : '',
                                      style: TextStyle(fontSize: 12.sp, color: Colors.blue[700], fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }


  Widget _buildCausalTab() {
    if (_currentState == null) return Container();

    final causalChains = _currentState!.recentCausalChains;

    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        children: [
          _buildCausalCard(causalChains),
          SizedBox(height: 16.h),
          if (_currentState!.cognitiveLoadHistory.isNotEmpty)
            _buildCognitiveLoadHistoryCard(_currentState!.cognitiveLoadHistory),
        ],
      ),
    );
  }

  Widget _buildCausalCard(List<hum.CausalRelation> causalChains) {
    if (causalChains.isEmpty) {
      return Center(child: Text('暂无因果关系', style: TextStyle(fontSize: 16.sp)));
    }

    return Column(
      children: causalChains.map<Widget>((causal) {
        return Card(
          margin: EdgeInsets.only(bottom: 8.h),
          child: Padding(
            padding: EdgeInsets.all(12.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${causal.cause} → ${causal.effect}',
                        style: TextStyle(
                            fontSize: 14.sp, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Text(
                        '置信度: ${(causal.confidence * 100).toInt()}%',
                        style: TextStyle(fontSize: 10.sp),
                      ),
                    ),
                  ],
                ),
                if (causal.reasoning.isNotEmpty) ...[
                  SizedBox(height: 8.h),
                  Text(
                    '推理: ${causal.reasoning}',
                    style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCognitiveLoadTab() {
    if (_currentState == null) return Container();

    final cognitiveLoad = _currentState!.currentCognitiveLoad;

    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        children: [
          _buildCognitiveLoadCard(cognitiveLoad),
          SizedBox(height: 16.h),
          if (_currentState!.cognitiveLoadHistory.isNotEmpty)
            _buildCognitiveLoadHistoryCard(_currentState!.cognitiveLoadHistory),
        ],
      ),
    );
  }

  Widget _buildCognitiveLoadCard(hum.CognitiveLoad cognitiveLoad) {
    return Card(
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '当前认知负载',
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12.h),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '级别: ${_getCognitiveLoadText(cognitiveLoad.level)}',
                          style: TextStyle(
                            fontSize: 16.sp,
                            color: _getCognitiveLoadColor(cognitiveLoad.level),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        LinearProgressIndicator(
                          value: _getCognitiveLoadValue(cognitiveLoad.level),
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _getCognitiveLoadColor(cognitiveLoad.level),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (cognitiveLoad.factors.isNotEmpty) ...[
                SizedBox(height: 12.h),
                Text(
                  '影响因素:',
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                ),
                ...cognitiveLoad.factors.entries.map((entry) =>
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 2.h),
                      child: Row(
                        children: [
                          Icon(
                              Icons.arrow_right, size: 16.sp, color: Colors.grey),
                          SizedBox(width: 4.w),
                          Expanded(
                            child: Text(
                              '${entry.key}: ${(entry.value * 100).toInt()}%',
                              style: TextStyle(fontSize: 12.sp),
                            ),
                          ),
                        ],
                      ),
                    )).toList(),
              ],
            ],
          ),
        ));
  }

  Widget _buildCognitiveLoadHistoryCard(List<hum.CognitiveLoad> history) {
    return Card(
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '认知负载历史',
                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12.h),
              Container(
                height: 200.h,
                child: ListView.builder(
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final load = history[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        _getCognitiveLoadText(load.level),
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: _getCognitiveLoadColor(load.level),
                        ),
                      ),
                      subtitle: Text(
                        load.timestamp.toString().substring(11, 19),
                        style: TextStyle(fontSize: 10.sp),
                      ),
                      trailing: Container(
                        width: 8.w,
                        height: 8.w,
                        decoration: BoxDecoration(
                          color: _getCognitiveLoadColor(load.level),
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ));
  }

  void _handleMenuAction(String action) async {
    switch (action) {
      case 'export':
        await _exportSystemData();
        break;
      case 'reset':
        await _resetSystem();
        break;
      case 'test':
        await _testAnalysis();
        break;
      case 'trigger_check': // 🔥 新增：手动检查对话
        await _triggerCheck();
        break;
      case 'reset_monitoring': // 🔥 新增：重置监听状态
        await _resetMonitoring();
        break;
      case 'debug_info': // 🔥 新增：查看调试信息
        _showDebugInfo();
        break;
    }
  }

  Future<void> _exportSystemData() async {
    try {
      final data = _system.exportSystemData();
      final jsonStr = JsonEncoder.withIndent('  ').convert(data);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('数据导出完成，共 ${jsonStr.length} 字符')),
      );

      // 这里可以实现保存到文件的逻辑
      print('导出的数据长度: ${jsonStr.length}');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败: $e')),
      );
    }
  }

  Future<void> _resetSystem() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: Text('确认重置'),
            content: Text('这将清空所有理解系统数据，确定要继续吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('确定'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        await _system.resetSystem();
        _loadSystemData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('系统重置完成')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重置失败: $e')),
        );
      }
    }
  }

  Future<void> _testAnalysis() async {
    // 创建测试数据
    final testInput = hum.SemanticAnalysisInput(
      entities: ['用户', '工作', '项目'],
      intent: 'planning',
      emotion: 'positive',
      content: '我需要制定一个新项���的计划，这个项目很重要',
      timestamp: DateTime.now(),
      additionalContext: {'test': true},
    );

    try {
      await _system.processSemanticInput(testInput);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('测试分析完成')),
      );
      _loadSystemData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('测试失败: $e')),
      );
    }
  }

  Future<void> _triggerCheck() async {
    try {
      await _system.triggerDialogueCheck();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('手动检查对话完成')),
      );
      _loadSystemData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('检查失败: $e')),
      );
    }
  }

  Future<void> _resetMonitoring() async {
    try {
      await _system.resetMonitoringStatus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('监听状态重置完成')),
      );
      _loadSystemData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重置失败: $e')),
      );
    }
  }

  void _showDebugInfo() {
    final debugInfo = _system.getDebugInfo();

    showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: Text('调试信息'),
            content: SingleChildScrollView(
              child: Text(
                debugInfo.toString(),
                style: TextStyle(fontSize: 12.sp),
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

  // 辅助方法
  String _getCognitiveLoadText(hum.CognitiveLoadLevel level) {
    switch (level) {
      case hum.CognitiveLoadLevel.low:
        return '负载较低';
      case hum.CognitiveLoadLevel.moderate:
        return '负载适中';
      case hum.CognitiveLoadLevel.high:
        return '负载较高';
      case hum.CognitiveLoadLevel.overload:
        return '负载过重';
    }
  }

  Color _getCognitiveLoadColor(hum.CognitiveLoadLevel level) {
    switch (level) {
      case hum.CognitiveLoadLevel.low:
        return Colors.green;
      case hum.CognitiveLoadLevel.moderate:
        return Colors.blue;
      case hum.CognitiveLoadLevel.high:
        return Colors.orange;
      case hum.CognitiveLoadLevel.overload:
        return Colors.red;
    }
  }

  double _getCognitiveLoadValue(hum.CognitiveLoadLevel level) {
    switch (level) {
      case hum.CognitiveLoadLevel.low:
        return 0.25;
      case hum.CognitiveLoadLevel.moderate:
        return 0.5;
      case hum.CognitiveLoadLevel.high:
        return 0.75;
      case hum.CognitiveLoadLevel.overload:
        return 1.0;
    }
  }

  Color _getIntentStateColor(String state) {
    switch (state.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'active':
        return Colors.green;
      case 'completed':
        return Colors.blue;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getCausalTypeColor(hum.CausalRelationType type) {
    switch (type) {
      case hum.CausalRelationType.directCause:
        return Colors.red;
      case hum.CausalRelationType.indirectCause:
        return Colors.orange;
      case hum.CausalRelationType.enabler:
        return Colors.green;
      case hum.CausalRelationType.inhibitor:
        return Colors.blue;
      case hum.CausalRelationType.correlation:
        return Colors.purple;
    }
  }

  String _getFactorDisplayName(String factor) {
    switch (factor) {
      case 'intent_count':
        return '意图数量';
      case 'topic_count':
        return '主题数量';
      case 'emotional_intensity':
        return '情绪强度';
      case 'topic_switch_rate':
        return '话题切换频率';
      case 'complexity_score':
        return '语言复杂度';
      case 'temporal_pressure':
        return '时间压力';
      default:
        return factor;
    }
  }

  Color _getFactorColor(double value) {
    if (value < 0.3) return Colors.green;
    if (value < 0.6) return Colors.orange;
    return Colors.red;
  }

  // 在合适位置补充 _buildVectorMatchEntitiesCard 实现：
  Widget _buildVectorMatchEntitiesCard(List entities) {
    if (entities.isEmpty) {
      return Text('暂无相关实体', style: TextStyle(color: Colors.grey));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('相关实体 (${entities.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ...entities.take(8).map<Widget>((entity) {
          final name = entity['name']?.toString() ?? '未知实体';
          final type = entity['type']?.toString() ?? '';
          return ListTile(
            title: Text(name),
            subtitle: type.isNotEmpty ? Text('类型: $type') : null,
          );
        }).toList(),
      ],
    );
  }
}
