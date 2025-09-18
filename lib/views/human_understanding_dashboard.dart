/// 人类理解系统可视化界面
/// 提供系统状态、分析结果和统计信息的可视化展示

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:app/models/human_understanding_models.dart' as hum;
import 'package:app/services/human_understanding_system.dart';
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
      ),
    );
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
      ),
    );
  }

  Widget _buildKnowledgeGraphTab() {
    if (_currentState == null) return Container();

    final kgData = _currentState!.knowledgeGraphData;

    // 检查数据
    final events = (kgData?['events'] as List? ?? []);
    final entities = (kgData?['entities'] as List? ?? []);
    final relations = (kgData?['relations'] as List? ?? []);
    final topicStats = (kgData?['topic_match_stats'] as List? ?? []);
    final insights = (kgData?['insights'] as List? ?? []);

    final isDataEmpty = kgData == null || (events.isEmpty && entities.isEmpty && relations.isEmpty);

    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        children: [
          // 状态栏
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDataEmpty
                  ? [Colors.red.withOpacity(0.1), Colors.red.withOpacity(0.05)]
                  : [Colors.blue.withOpacity(0.1), Colors.indigo.withOpacity(0.1)],
              ),
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(
                color: isDataEmpty ? Colors.red.withOpacity(0.3) : Colors.blue.withOpacity(0.3)
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isDataEmpty ? Icons.error_outline : Icons.hub,
                  size: 20.sp,
                  color: isDataEmpty ? Colors.red[600] : Colors.blue[600]
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isDataEmpty
                          ? '向量匹配未找到相关内容'
                          : '向量匹配查询结果',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: isDataEmpty ? Colors.red[700] : Colors.blue[700],
                        ),
                      ),
                      if (!isDataEmpty) ...[
                        SizedBox(height: 4.h),
                        Text(
                          '${events.length}个相关事件 · ${entities.length}个相关实体 · ${topicStats.length}个主题参与匹配',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.blue[600],
                          ),
                        ),
                        Text(
                          '更新时间: ${_formatTimestamp(kgData?['generated_at'])} · 查询方式: ${kgData?['query_method'] ?? '未知'}',
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.refresh, size: 18.sp),
                  onPressed: () {
                    print('[Dashboard] 🔄 手动刷新向量匹配结果');
                    _system.refreshKnowledgeGraphCache();
                    Future.delayed(Duration(milliseconds: 100), () {
                      _loadSystemData();
                    });
                  },
                  tooltip: '刷新匹配结果',
                ),
              ],
            ),
          ),
          SizedBox(height: 16.h),

          Text(
            '知识图谱 - 向量匹配',
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16.h),

          Expanded(
            child: isDataEmpty
                ? _buildEmptyVectorMatchView(kgData)
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        // 主题匹配统计
                        if (topicStats.isNotEmpty) ...[
                          _buildTopicMatchStatsCard(topicStats),
                          SizedBox(height: 16.h),
                        ],

                        // 相关事件（按相似度排序）
                        if (events.isNotEmpty) ...[
                          _buildVectorMatchEventsCard(events),
                          SizedBox(height: 16.h),
                        ],

                        // 相关实体
                        if (entities.isNotEmpty) ...[
                          _buildVectorMatchEntitiesCard(entities),
                          SizedBox(height: 16.h),
                        ],

                        // 洞察分析
                        if (insights.isNotEmpty) ...[
                          _buildVectorInsightsCard(insights),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 主题匹配统计卡片
  Widget _buildTopicMatchStatsCard(List topicStats) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.r),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.indigo.shade50, Colors.purple.shade50],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(20.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Icon(Icons.analytics, color: Colors.indigo, size: 24.sp),
                  ),
                  SizedBox(width: 12.w),
                  Text(
                    '主题匹配统计',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade800,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16.h),

              // 主题匹配列表
              Column(
                children: topicStats.map<Widget>((stat) {
                  final topicName = stat['topic_name']?.toString() ?? '未知主题';
                  final topicWeight = (stat['topic_weight'] as double?) ?? 0.0;
                  final eventsCount = (stat['events_count'] as int?) ?? 0;
                  final entitiesCount = (stat['entities_count'] as int?) ?? 0;
                  final avgSimilarity = (stat['avg_similarity'] as double?) ?? 0.0;
                  final maxSimilarity = (stat['max_similarity'] as double?) ?? 0.0;

                  return Container(
                    margin: EdgeInsets.only(bottom: 12.h),
                    padding: EdgeInsets.all(16.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(color: Colors.indigo.withOpacity(0.2)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.indigo.withOpacity(0.05),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 主题名称和权重
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                topicName,
                                style: TextStyle(
                                  fontSize: 15.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo.shade800,
                                ),
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: Text(
                                '权重: ${topicWeight.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12.h),

                        // 匹配统计
                        Row(
                          children: [
                            Expanded(
                              child: _buildTopicStatItem(
                                '相关事件',
                                eventsCount.toString(),
                                Icons.event,
                                Colors.green,
                              ),
                            ),
                            Expanded(
                              child: _buildTopicStatItem(
                                '相关实体',
                                entitiesCount.toString(),
                                Icons.account_circle,
                                Colors.blue,
                              ),
                            ),
                            Expanded(
                              child: _buildTopicStatItem(
                                '最高相似度',
                                maxSimilarity.toStringAsFixed(2),
                                Icons.star,
                                _getSimilarityColor(maxSimilarity),
                              ),
                            ),
                          ],
                        ),

                        // 平均相似度进度条
                        if (avgSimilarity > 0) ...[
                          SizedBox(height: 12.h),
                          Row(
                            children: [
                              Text(
                                '平均相似度: ${avgSimilarity.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: avgSimilarity,
                                  backgroundColor: Colors.grey.shade300,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _getSimilarityColor(avgSimilarity),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 主题统计项
  Widget _buildTopicStatItem(String label, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(8.w),
      margin: EdgeInsets.symmetric(horizontal: 2.w),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 16.sp),
          SizedBox(height: 4.h),
          Text(
            value,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.sp,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 向量匹配事件卡片
  Widget _buildVectorMatchEventsCard(List events) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.r),
          gradient: LinearGradient(
            colors: [Colors.green.shade50, Colors.teal.shade50],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(20.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Icon(Icons.timeline, color: Colors.green, size: 24.sp),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '相关事件 (${events.length})',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                          ),
                        ),
                        Text(
                          '按向量相似度排序',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.green.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16.h),

              // 事件列表
              Column(
                children: events.take(8).map<Widget>((event) {
                  final eventName = event['name']?.toString() ?? '未知事件';
                  final eventType = event['type']?.toString() ?? '';
                  final description = event['description']?.toString() ?? '';
                  final similarity = (event['similarity_score'] as double?) ?? 0.0;
                  final matchedByTopic = event['matched_by_topic']?.toString() ?? '未知主题';
                  final topicWeight = (event['matched_by_topic_weight'] as double?) ?? 0.0;
                  final formattedDate = event['formatted_date']?.toString() ?? '';
                  final matchDetails = event['match_details'] as Map<String, dynamic>? ?? {};

                  return Container(
                    margin: EdgeInsets.only(bottom: 16.h),
                    padding: EdgeInsets.all(16.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: Colors.green.withOpacity(0.2)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.08),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 事件标题和相似度
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                eventName,
                                style: TextStyle(
                                  fontSize: 15.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    _getSimilarityColor(similarity).withOpacity(0.2),
                                    _getSimilarityColor(similarity).withOpacity(0.1),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(8.r),
                                border: Border.all(
                                  color: _getSimilarityColor(similarity).withOpacity(0.4),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.auto_awesome,
                                    size: 12.sp,
                                    color: _getSimilarityColor(similarity),
                                  ),
                                  SizedBox(width: 4.w),
                                  Text(
                                    similarity.toStringAsFixed(2),
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      fontWeight: FontWeight.bold,
                                      color: _getSimilarityColor(similarity),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // 匹配主题信息
                        SizedBox(height: 8.h),
                        Container(
                          padding: EdgeInsets.all(8.w),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8.r),
                            border: Border.all(color: Colors.blue.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.topic, size: 14.sp, color: Colors.blue.shade600),
                              SizedBox(width: 6.w),
                              Text(
                                '匹配主题: ',
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '$matchedByTopic (权重: ${topicWeight.toStringAsFixed(2)})',
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    color: Colors.blue.shade600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 事件类型和时间
                        if (eventType.isNotEmpty || formattedDate.isNotEmpty) ...[
                          SizedBox(height: 8.h),
                          Row(
                            children: [
                              if (eventType.isNotEmpty) ...[
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6.r),
                                  ),
                                  child: Text(
                                    eventType,
                                    style: TextStyle(
                                      fontSize: 10.sp,
                                      color: Colors.orange.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8.w),
                              ],
                              if (formattedDate.isNotEmpty) ...[
                                Icon(Icons.access_time, size: 12.sp, color: Colors.grey.shade500),
                                SizedBox(width: 4.w),
                                Text(
                                  formattedDate,
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],

                        // 事件描述
                        if (description.isNotEmpty) ...[
                          SizedBox(height: 8.h),
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: Colors.grey.shade600,
                              height: 1.3,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],

                        // 匹配详情
                        if (matchDetails.isNotEmpty) ...[
                          SizedBox(height: 10.h),
                          Container(
                            padding: EdgeInsets.all(8.w),
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(6.r),
                              border: Border.all(color: Colors.grey.withOpacity(0.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '匹配详情:',
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                SizedBox(height: 4.h),
                                if (matchDetails['matched_text'] != null) ...[
                                  Text(
                                    '匹配文本: ${matchDetails['matched_text']}',
                                    style: TextStyle(
                                      fontSize: 10.sp,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                                if (matchDetails['vector_distance'] != null) ...[
                                  Text(
                                    '向量距离: ${(matchDetails['vector_distance'] as double).toStringAsFixed(3)}',
                                    style: TextStyle(
                                      fontSize: 10.sp,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 向量匹配实体卡片
  Widget _buildVectorMatchEntitiesCard(List entities) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.r),
          gradient: LinearGradient(
            colors: [Colors.blue.shade50, Colors.cyan.shade50],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(20.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Icon(Icons.people_outline, color: Colors.blue, size: 24.sp),
                  ),
                  SizedBox(width: 12.w),
                  Text(
                    '相关实体 (${entities.length})',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16.h),

              // 实体网格
              Wrap(
                spacing: 12.w,
                runSpacing: 12.h,
                children: entities.take(15).map<Widget>((entity) {
                  final entityName = entity['name']?.toString() ?? '未知实体';
                  final entityType = entity['type']?.toString() ?? '';
                  final similarity = (entity['similarity_score'] as double?) ?? 0.0;
                  final matchedByTopic = entity['matched_by_topic']?.toString() ?? '未知主题';
                  final aliases = (entity['aliases'] as List?)?.length ?? 0;

                  return Container(
                    constraints: BoxConstraints(maxWidth: 180.w),
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.05),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 实体名称和相似度
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                entityName,
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade800,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.all(3.w),
                              decoration: BoxDecoration(
                                color: _getSimilarityColor(similarity).withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                similarity.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 9.sp,
                                  fontWeight: FontWeight.bold,
                                  color: _getSimilarityColor(similarity),
                                ),
                              ),
                            ),
                          ],
                        ),

                        // 实体类型
                        if (entityType.isNotEmpty) ...[
                          SizedBox(height: 6.h),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                            decoration: BoxDecoration(
                              color: Colors.indigo.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6.r),
                            ),
                            child: Text(
                              entityType,
                              style: TextStyle(
                                fontSize: 9.sp,
                                color: Colors.indigo.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],

                        // 匹配主题
                        SizedBox(height: 8.h),
                        Container(
                          padding: EdgeInsets.all(6.w),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '匹配主题:',
                                style: TextStyle(
                                  fontSize: 9.sp,
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 2.h),
                              Text(
                                matchedByTopic,
                                style: TextStyle(
                                  fontSize: 10.sp,
                                  color: Colors.green.shade600,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),

                        // 别名数量
                        if (aliases > 0) ...[
                          SizedBox(height: 6.h),
                          Text(
                            '$aliases个别名',
                            style: TextStyle(
                              fontSize: 9.sp,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 向量洞察卡片
  Widget _buildVectorInsightsCard(List insights) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.r),
          gradient: LinearGradient(
            colors: [Colors.purple.shade50, Colors.pink.shade50],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(20.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Icon(Icons.psychology, color: Colors.purple, size: 24.sp),
                  ),
                  SizedBox(width: 12.w),
                  Text(
                    '向量匹配洞察',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple.shade800,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16.h),

              Column(
                children: insights.map<Widget>((insight) {
                  return Container(
                    margin: EdgeInsets.only(bottom: 8.h),
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: Colors.purple.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(4.w),
                          decoration: BoxDecoration(
                            color: Colors.purple.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.lightbulb_outline,
                            size: 14.sp,
                            color: Colors.purple.shade600,
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Text(
                            insight.toString(),
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: Colors.grey.shade700,
                              height: 1.3,
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
      ),
    );
  }

  /// 空向量匹配视图
  Widget _buildEmptyVectorMatchView(Map<String, dynamic>? kgData) {
    final hasError = kgData?['error'] != null;
    final activeTopicsCount = kgData?['active_topics_count'] ?? 0;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasError ? Icons.error_outline : Icons.search_off,
            size: 64.sp,
            color: hasError ? Colors.red : Colors.grey[400],
          ),
          SizedBox(height: 16.h),
          Text(
            hasError ? '向量匹配查询失败' : '没有找到相关的知识图谱内容',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
              color: hasError ? Colors.red : Colors.grey[600],
            ),
          ),
          SizedBox(height: 8.h),
          if (hasError) ...[
            Text(
              '错误信息: ${kgData!['error']}',
              style: TextStyle(fontSize: 12.sp, color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ] else ...[
            Text(
              activeTopicsCount > 0
                ? '尝试了 $activeTopicsCount 个活跃主题的向量匹配\n但没有找到相似度足够高的内容'
                : '当前没有活跃主题可用于向量匹配查询',
              style: TextStyle(fontSize: 14.sp, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
          SizedBox(height: 24.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _loadSystemData,
                icon: Icon(Icons.refresh, size: 16.sp),
                label: Text('重新查询'),
              ),
              SizedBox(width: 12.w),
              if (!hasError && activeTopicsCount == 0) ...[
                ElevatedButton.icon(
                  onPressed: () async {
                    await _testAnalysis();
                  },
                  icon: Icon(Icons.science, size: 16.sp),
                  label: Text('生成测试数据'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 相似度颜色映射
  Color _getSimilarityColor(double similarity) {
    if (similarity >= 0.8) return Colors.green;
    if (similarity >= 0.6) return Colors.lime;
    if (similarity >= 0.4) return Colors.orange;
    if (similarity >= 0.2) return Colors.deepOrange;
    return Colors.red;
  }

  // 🔥 新增：空状态视图
  Widget _buildEmptyKnowledgeGraphView(Map<String, dynamic>? kgData) {
    final hasError = kgData?['error'] != null;
    final totalEntityCount = kgData?['entity_count'] ?? 0;
    final totalEventCount = kgData?['event_count'] ?? 0;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasError ? Icons.error_outline : Icons.memory,
            size: 64.sp,
            color: hasError ? Colors.red : Colors.grey[400],
          ),
          SizedBox(height: 16.h),
          Text(
            hasError ? '知识图谱加载失败' : '暂无相关知识图谱数据',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
              color: hasError ? Colors.red : Colors.grey[600],
            ),
          ),
          SizedBox(height: 8.h),
          if (hasError) ...[
            Text(
              '错误信息: ${kgData!['error']}',
              style: TextStyle(fontSize: 12.sp, color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ] else
            ...[
              Text(
                totalEntityCount > 0 || totalEventCount > 0
                    ? '数据库中有 $totalEntityCount 个实体和 $totalEventCount 个事件\n但没有找到与当前主题相关的内容'
                    : '还没有进行过对话，或者对话内容还没有被处理成知识图谱',
                style: TextStyle(fontSize: 14.sp, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          SizedBox(height: 24.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _loadSystemData,
                icon: Icon(Icons.refresh, size: 16.sp),
                label: Text('刷新数据'),
              ),
              SizedBox(width: 12.w),
              if (!hasError && totalEntityCount == 0) ...[
                ElevatedButton.icon(
                  onPressed: () async {
                    await _testAnalysis();
                  },
                  icon: Icon(Icons.science, size: 16.sp),
                  label: Text('生成测试数据'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // 🔥 新增：时间戳格式化函数
  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '未知';

    try {
      final DateTime time;
      if (timestamp is int) {
        time = DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else if (timestamp is String) {
        time = DateTime.parse(timestamp);
      } else {
        return '未知';
      }

      final now = DateTime.now();
      final diff = now.difference(time);

      if (diff.inMinutes < 1) {
        return '刚刚';
      } else if (diff.inMinutes < 60) {
        return '${diff.inMinutes}分钟前';
      } else if (diff.inHours < 24) {
        return '${diff.inHours}小时前';
      } else {
        return '${time.month}/${time.day} ${time.hour.toString().padLeft(
            2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return '格式错误';
    }
  }


  Widget _buildKnowledgeGraphCard(Map<String, dynamic> kgData) {
    final entities = kgData['entities'] as List? ?? [];
    final relations = kgData['relations'] as List? ?? [];
    final events = kgData['events'] as List? ?? [];
    final keywordsUsed = kgData['keywords_used'] as List? ?? [];

    // 🔥 新增：按相关性排序事件
    final sortedEvents = List.from(events);
    sortedEvents.sort((a, b) {
      final scoreA = (a['relevance_score'] as num?)?.toDouble() ?? 0.0;
      final scoreB = (b['relevance_score'] as num?)?.toDouble() ?? 0.0;
      return scoreB.compareTo(scoreA); // 降序排列
    });

    // 🔥 新增：按相关性排序实体
    final sortedEntities = List.from(entities);
    sortedEntities.sort((a, b) {
      final scoreA = (a['relevance_score'] as num?)?.toDouble() ?? 0.0;
      final scoreB = (b['relevance_score'] as num?)?.toDouble() ?? 0.0;
      return scoreB.compareTo(scoreA);
    });

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.r),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.shade50,
              Colors.indigo.shade50,
            ],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(20.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔥 美化：标题部分
              _buildKnowledgeGraphHeader(kgData),
              SizedBox(height: 20.h),

              // 🔥 修复：始终显示查询关键词汇总（如果有的话）
              if (keywordsUsed.isNotEmpty) ...[
                _buildKeywordsSection(keywordsUsed),
                SizedBox(height: 20.h),
              ],

              // 🔥 美化：统计概览
              _buildKnowledgeGraphStats(entities, events, relations),
              SizedBox(height: 24.h),

              // 🔥 改进：事件展示（按相关性排序）
              if (sortedEvents.isNotEmpty) ...[
                _buildEventsSection(sortedEvents),
                SizedBox(height: 20.h),
              ],

              // 🔥 改进：实体展示（按相关性排序）
              if (sortedEntities.isNotEmpty) ...[
                _buildEntitiesSection(sortedEntities),
                SizedBox(height: 16.h),
              ],

              // 🔥 美化：关系网络预览
              if (relations.isNotEmpty) ...[
                _buildRelationsSection(relations),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 🔥 新增：知识图谱标题部分
  Widget _buildKnowledgeGraphHeader(Map<String, dynamic> kgData) {
    final generatedAt = kgData['generated_at'];
    final hasData = kgData['has_data'] ?? false;

    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: Colors.indigo.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: Colors.indigo.withOpacity(0.3)),
          ),
          child: Icon(
            Icons.hub,
            color: Colors.indigo.shade600,
            size: 28.sp,
          ),
        ),
        SizedBox(width: 16.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '知识图谱结构',
                style: TextStyle(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo.shade800,
                ),
              ),
              SizedBox(height: 4.h),
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: hasData ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text(
                      hasData ? '数据就绪' : '数据稀少',
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: hasData ? Colors.green.shade700 : Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    _formatTimestamp(generatedAt),
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 🔥 新增：关键词展示部分
  Widget _buildKeywordsSection(List keywordsUsed) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.search, color: Colors.blue.shade600, size: 18.sp),
              SizedBox(width: 8.w),
              Text(
                '查询关键词 (${keywordsUsed.length})',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: keywordsUsed.take(10).map((keyword) => Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade100, Colors.blue.shade200],
                ),
                borderRadius: BorderRadius.circular(20.r),
                border: Border.all(color: Colors.blue.shade300),
              ),
              child: Text(
                keyword.toString(),
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.blue.shade800,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  // 🔥 改进：统计概览部分
  Widget _buildKnowledgeGraphStats(List entities, List events, List relations) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade50, Colors.purple.shade50],
        ),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.indigo.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              '相关实体',
              '${entities.length}',
              Icons.account_circle_outlined,
              Colors.blue,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: _buildStatCard(
              '相关事件',
              '${events.length}',
              Icons.event_outlined,
              Colors.green,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: _buildStatCard(
              '关系网络',
              '${relations.length}',
              Icons.link,
              Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  // 🔥 改进：统计卡片
  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20.sp),
          ),
          SizedBox(height: 8.h),
          Text(
            value,
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.sp,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // 🔥 新增：事件展示部分（按相关性排序）
  Widget _buildEventsSection(List sortedEvents) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.timeline, color: Colors.green.shade600, size: 20.sp),
            SizedBox(width: 8.w),
            Text(
              '最近相关事件',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
            ),
            Spacer(),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                '按相关性排序',
                style: TextStyle(
                  fontSize: 10.sp,
                  color: Colors.green.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        Column(
          children: sortedEvents.take(5).map<Widget>((event) {
            final relevanceScore = (event['relevance_score'] as num?)?.toDouble() ?? 0.0;
            final matchedKeywords = (event['matched_keywords'] as List?) ?? [];
            final eventName = event['name']?.toString() ?? '未知事件';
            final eventType = event['type']?.toString() ?? '';
            final description = event['description']?.toString() ?? '';
            final formattedDate = event['formatted_date']?.toString() ?? '';

            return Container(
              width: double.infinity,
              margin: EdgeInsets.only(bottom: 12.h),
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.green.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.08),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 事件标题和相关性分数
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          eventName,
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ),
                      if (relevanceScore > 0) ...[
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: _getRelevanceColor(relevanceScore).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8.r),
                            border: Border.all(
                              color: _getRelevanceColor(relevanceScore).withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star,
                                size: 12.sp,
                                color: _getRelevanceColor(relevanceScore),
                              ),
                              SizedBox(width: 2.w),
                              Text(
                                relevanceScore.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  fontWeight: FontWeight.bold,
                                  color: _getRelevanceColor(relevanceScore),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),

                  // 事件类型和时间
                  if (eventType.isNotEmpty || formattedDate.isNotEmpty) ...[
                    SizedBox(height: 6.h),
                    Row(
                      children: [
                        if (eventType.isNotEmpty) ...[
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6.r),
                            ),
                            child: Text(
                              eventType,
                              style: TextStyle(
                                fontSize: 10.sp,
                                color: Colors.blue.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          SizedBox(width: 8.w),
                        ],
                        if (formattedDate.isNotEmpty) ...[
                          Icon(Icons.access_time, size: 12.sp, color: Colors.grey.shade500),
                          SizedBox(width: 4.w),
                          Text(
                            formattedDate,
                            style: TextStyle(
                              fontSize: 11.sp,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],

                  // 事件描述
                  if (description.isNotEmpty) ...[
                    SizedBox(height: 8.h),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.grey.shade600,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  // 🔥 关键：匹配的关键词显示
                  if (matchedKeywords.isNotEmpty) ...[
                    SizedBox(height: 10.h),
                    Row(
                      children: [
                        Icon(
                          Icons.search,
                          size: 12.sp,
                          color: Colors.orange.shade600,
                        ),
                        SizedBox(width: 4.w),
                        Text(
                          '匹配关键词:',
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4.h),
                    Wrap(
                      spacing: 4.w,
                      runSpacing: 4.h,
                      children: matchedKeywords.take(5).map<Widget>((keyword) {
                        return Container(
                          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.orange.shade100,
                                Colors.orange.shade50,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(8.r),
                            border: Border.all(color: Colors.orange.shade300),
                          ),
                          child: Text(
                            keyword.toString(),
                            style: TextStyle(
                              fontSize: 10.sp,
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // 🔥 新增：实体展示部分（按相关性排序）
  Widget _buildEntitiesSection(List sortedEntities) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.people_outline, color: Colors.blue.shade600, size: 20.sp),
            SizedBox(width: 8.w),
            Text(
              '相关实体',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
            Spacer(),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                '按相关性排序',
                style: TextStyle(
                  fontSize: 10.sp,
                  color: Colors.blue.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: sortedEntities.take(12).map<Widget>((entity) {
            final relevanceScore = (entity['relevance_score'] as num?)?.toDouble() ?? 0.0;
            final matchedKeywords = (entity['matched_keywords'] as List?) ?? [];
            final entityName = entity['name']?.toString() ?? '未知实体';
            final entityType = entity['type']?.toString() ?? '';
            final aliasesCount = (entity['aliases'] as List?)?.length ?? 0;

            return Container(
              constraints: BoxConstraints(maxWidth: 160.w),
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.blue.shade50,
                    Colors.blue.shade100 ?? Colors.blue.shade50,
                  ],
                ),
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 实体名称和相关性分数
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entityName,
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade800,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (relevanceScore > 0) ...[
                        SizedBox(width: 4.w),
                        Container(
                          padding: EdgeInsets.all(2.w),
                          decoration: BoxDecoration(
                            color: _getRelevanceColor(relevanceScore).withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.star,
                            size: 10.sp,
                            color: _getRelevanceColor(relevanceScore),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // 实体类型
                  if (entityType.isNotEmpty) ...[
                    SizedBox(height: 4.h),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: Text(
                        entityType,
                        style: TextStyle(
                          fontSize: 9.sp,
                          color: Colors.indigo.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],

                  // 别名数量
                  if (aliasesCount > 0) ...[
                    SizedBox(height: 4.h),
                    Text(
                      '${aliasesCount}个别名',
                      style: TextStyle(
                        fontSize: 9.sp,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],

                  // 🔥 关键：匹配的关键词显示
                  if (matchedKeywords.isNotEmpty) ...[
                    SizedBox(height: 8.h),
                    Text(
                      '匹配:',
                      style: TextStyle(
                        fontSize: 9.sp,
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Wrap(
                      spacing: 2.w,
                      runSpacing: 2.h,
                      children: matchedKeywords.take(3).map<Widget>((keyword) {
                        return Container(
                          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.h),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(6.r),
                            border: Border.all(color: Colors.orange.shade300),
                          ),
                          child: Text(
                            keyword.toString(),
                            style: TextStyle(
                              fontSize: 8.sp,
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // 🔥 新增：关系网络部分
  Widget _buildRelationsSection(List relations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.account_tree, color: Colors.purple.shade600, size: 20.sp),
            SizedBox(width: 8.w),
            Text(
              '关系网络',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: Colors.purple.shade700,
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: Colors.purple.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: Colors.purple.withOpacity(0.2)),
          ),
          child: Column(
            children: relations.take(3).map<Widget>((relation) {
              return Container(
                margin: EdgeInsets.only(bottom: 8.h),
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: Colors.purple.withOpacity(0.1)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: Text(
                        relation['source']?.toString() ?? '',
                        style: TextStyle(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Icon(Icons.arrow_forward, size: 16.sp, color: Colors.purple.shade600),
                    SizedBox(width: 8.w),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: Text(
                        relation['target']?.toString() ?? '',
                        style: TextStyle(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // 🔥 新增：相关性分数颜色映射
  Color _getRelevanceColor(double score) {
    if (score >= 3.0) return Colors.red;
    if (score >= 2.0) return Colors.orange;
    if (score >= 1.0) return Colors.amber;
    return Colors.grey;
  }

  // 🔥 新增：知识图谱统计项组件
  Widget _buildKGStatItem(String label, String value, IconData icon,
      Color color) {
    return Container(
      padding: EdgeInsets.all(8.w),
      margin: EdgeInsets.symmetric(horizontal: 2.w),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 16.sp),
          SizedBox(height: 2.h),
          Text(
            value,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10.sp, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildKnowledgeGraphInsightsCard(Map<String, dynamic> kgData) {
    final insights = kgData['insights'] as List? ?? [];

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '知识图谱洞察',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12.h),
            if (insights.isEmpty) ...[
              Text(
                '暂无洞察信息',
                style: TextStyle(fontSize: 14.sp, color: Colors.grey[600]),
              ),
            ] else
              ...[
                ...insights.map((insight) =>
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 4.h),
                      child: Text(
                        '- ${insight.toString()}',
                        style: TextStyle(fontSize: 14.sp),
                      ),
                    )),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildCausalTab() {
    if (_currentState == null) return Container();

    final causalChains = _currentState!.recentCausalChains;

    return Padding(
      padding: EdgeInsets.all(16.w),
      child: causalChains.isEmpty
          ? Center(child: Text('暂无因果关系'))
          : ListView.builder(
        itemCount: causalChains.length,
        itemBuilder: (context, index) => _buildCausalCard(causalChains[index]),
      ),
    );
  }

  Widget _buildCausalCard(hum.CausalRelation causal) {
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
      ),
    );
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
      ),
    );
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

}
