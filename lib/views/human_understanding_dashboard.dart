/// 人类理解系统可视化界面
/// 提供系统状态、分析结果和统计信息的可视化展示

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:app/models/human_understanding_models.dart' as hum;
import 'package:app/services/human_understanding_system.dart';
import 'package:app/services/knowledge_graph_manager.dart';
import 'package:app/services/kg_history_service.dart'; // 新增
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
    _tabController = TabController(length: 4, vsync: this); // 修改为4个标签页
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

      // 保存当前KG标签页展示内容为历史记录
      final kgList = _kgManager.getLastResult()?['results'] as List<dynamic>? ?? [];
      if (kgList.isNotEmpty) {
        final summary = kgList.map((e) => e['title']?.toString() ?? '').join('\n');
        await KGHistoryService().initialize();
        await KGHistoryService().recordWindow(summary);
      }
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
            Tab(text: '关注点'),
            Tab(text: '知识图谱'),
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
          _buildFocusPointsTab(),
          _buildKnowledgeGraphTab(),
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

    final focusStats = _system.focusStateMachine.getStatistics();
    final activeFocusCount = focusStats['active_focuses_count'] ?? 0;
    final latentFocusCount = focusStats['latent_focuses_count'] ?? 0;
    final kgResults = _kgManager.getLastResult()?['results'] as List? ?? [];

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Colors.blue, size: 20.sp),
                SizedBox(width: 8.w),
                Text(
                  '快速统计',
                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 16.h),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    '活跃关注点',
                    '$activeFocusCount',
                    Icons.visibility,
                    Colors.green,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    '潜在关注点',
                    '$latentFocusCount',
                    Icons.visibility_outlined,
                    Colors.orange,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    '知识图谱',
                    '${kgResults.length}',
                    Icons.hub,
                    Colors.blue,
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

    final activeFocuses = _system.focusStateMachine.getActiveFocuses();
    final kgResults = _kgManager.getLastResult()?['results'] as List? ?? [];

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: Colors.blue, size: 20.sp),
                SizedBox(width: 8.w),
                Text(
                  '最近活动',
                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            if (activeFocuses.isNotEmpty) ...[
              Text(
                '当前活跃关注点:',
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6.h),
              ...activeFocuses.take(5).map((focus) => Padding(
                    padding: EdgeInsets.symmetric(vertical: 3.h),
                    child: Row(
                      children: [
                        Icon(
                          _getFocusTypeIcon(focus.type.toString().split('.').last),
                          size: 14.sp,
                          color: _getFocusTypeColor(focus.type.toString().split('.').last),
                        ),
                        SizedBox(width: 6.w),
                        Expanded(
                          child: Text(
                            focus.canonicalLabel,
                            style: TextStyle(fontSize: 12.sp, color: Colors.grey[700]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          child: Text(
                            focus.salienceScore.toStringAsFixed(2),
                            style: TextStyle(fontSize: 10.sp, color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
            if (kgResults.isNotEmpty) ...[
              SizedBox(height: 12.h),
              Text(
                '最新知识图谱匹配:',
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6.h),
              ...kgResults.take(3).map((node) => Padding(
                    padding: EdgeInsets.symmetric(vertical: 3.h),
                    child: Row(
                      children: [
                        Icon(Icons.hub, size: 14.sp, color: Colors.purple),
                        SizedBox(width: 6.w),
                        Expanded(
                          child: Text(
                            node['title']?.toString() ?? node['name']?.toString() ?? '未命名',
                            style: TextStyle(fontSize: 12.sp, color: Colors.grey[700]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
            if (activeFocuses.isEmpty && kgResults.isEmpty) ...[
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  child: Text(
                    '暂无最近活动',
                    style: TextStyle(fontSize: 13.sp, color: Colors.grey),
                  ),
                ),
              ),
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

  /// 🔥 新增：构建关注点标签页
  Widget _buildFocusPointsTab() {
    final focusStateMachine = _system.focusStateMachine;
    final activeFocuses = focusStateMachine.getActiveFocuses();
    final latentFocuses = focusStateMachine.getLatentFocuses();
    final driftStats = focusStateMachine.getDriftStats();

    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 统计卡片
          _buildFocusStatisticsCard(focusStateMachine.getStatistics(), driftStats),
          SizedBox(height: 16.h),
          
          // 活跃关注点
          _buildFocusSectionHeader('活跃关注点', activeFocuses.length, Colors.green),
          SizedBox(height: 8.h),
          if (activeFocuses.isEmpty)
            Center(child: Text('暂无活跃关注点', style: TextStyle(fontSize: 14.sp, color: Colors.grey)))
          else
            ...activeFocuses.map((focus) => _buildFocusPointCard(focus, isActive: true)),
          
          SizedBox(height: 24.h),
          
          // 潜在关注点
          _buildFocusSectionHeader('潜在关注点', latentFocuses.length, Colors.orange),
          SizedBox(height: 8.h),
          if (latentFocuses.isEmpty)
            Center(child: Text('暂无潜在关注点', style: TextStyle(fontSize: 14.sp, color: Colors.grey)))
          else
            ...latentFocuses.map((focus) => _buildFocusPointCard(focus, isActive: false)),
        ],
      ),
    );
  }

  Widget _buildFocusStatisticsCard(Map<String, dynamic> stats, Map<String, dynamic> driftStats) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Colors.blue, size: 24.sp),
                SizedBox(width: 8.w),
                Text(
                  '关注点统计',
                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            Wrap(
              spacing: 12.w,
              runSpacing: 8.h,
              children: [
                _buildStatChip('活跃', stats['active_focuses_count'].toString(), Colors.green),
                _buildStatChip('潜在', stats['latent_focuses_count'].toString(), Colors.orange),
                _buildStatChip('总数', stats['total_focuses_count'].toString(), Colors.blue),
                _buildStatChip('转移', driftStats['total_transitions'].toString(), Colors.purple),
              ],
            ),
            SizedBox(height: 12.h),
            if (stats['focus_type_distribution'] != null) ...[
              Text('类型分布:', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
              SizedBox(height: 4.h),
              Wrap(
                spacing: 8.w,
                runSpacing: 4.h,
                children: (stats['focus_type_distribution'] as Map<String, int>).entries.map((e) {
                  return Chip(
                    label: Text('${_getFocusTypeLabel(e.key)}: ${e.value}', style: TextStyle(fontSize: 11.sp)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFocusSectionHeader(String title, int count, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 12.sp, color: color),
          SizedBox(width: 8.w),
          Text(
            title,
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: color),
          ),
          SizedBox(width: 8.w),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusPointCard(dynamic focus, {required bool isActive}) {
    // Handle FocusPoint type from focus_models.dart
    final id = focus.id?.toString() ?? '';
    final type = focus.type?.toString().split('.').last ?? 'unknown';
    final label = focus.canonicalLabel?.toString() ?? '未命名';
    final state = focus.state?.toString().split('.').last ?? 'unknown';
    final salienceScore = (focus.salienceScore ?? 0.0) as double;
    final recencyScore = (focus.recencyScore ?? 0.0) as double;
    final repetitionScore = (focus.repetitionScore ?? 0.0) as double;
    final emotionalScore = (focus.emotionalScore ?? 0.0) as double;
    final causalScore = (focus.causalConnectivityScore ?? 0.0) as double;
    final driftScore = (focus.driftPredictiveScore ?? 0.0) as double;
    final mentionCount = focus.mentionCount ?? 0;
    final linkedCount = (focus.linkedFocusIds as List?)?.length ?? 0;

    return Card(
      margin: EdgeInsets.only(bottom: 8.h),
      elevation: isActive ? 2 : 1,
      child: Padding(
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                Icon(
                  _getFocusTypeIcon(type),
                  size: 20.sp,
                  color: _getFocusTypeColor(type),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: _getFocusStateColor(state).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Text(
                    _getFocusStateLabel(state),
                    style: TextStyle(fontSize: 10.sp, color: _getFocusStateColor(state)),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            
            // 显著性分数
            Row(
              children: [
                Text('显著性:', style: TextStyle(fontSize: 12.sp, color: Colors.grey[600])),
                SizedBox(width: 8.w),
                Expanded(
                  child: LinearProgressIndicator(
                    value: salienceScore,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      salienceScore > 0.7 ? Colors.green : salienceScore > 0.4 ? Colors.orange : Colors.red,
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                Text(
                  salienceScore.toStringAsFixed(2),
                  style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            
            SizedBox(height: 8.h),
            
            // 分数详情
            Wrap(
              spacing: 6.w,
              runSpacing: 4.h,
              children: [
                _buildScoreChip('最近', recencyScore, Colors.blue),
                _buildScoreChip('重复', repetitionScore, Colors.green),
                _buildScoreChip('情绪', emotionalScore, Colors.pink),
                _buildScoreChip('因果', causalScore, Colors.purple),
                _buildScoreChip('漂移', driftScore, Colors.orange),
              ],
            ),
            
            SizedBox(height: 8.h),
            
            // 统计信息
            Row(
              children: [
                Icon(Icons.chat_bubble_outline, size: 14.sp, color: Colors.grey),
                SizedBox(width: 4.w),
                Text('提及 $mentionCount 次', style: TextStyle(fontSize: 11.sp, color: Colors.grey[600])),
                SizedBox(width: 12.w),
                Icon(Icons.link, size: 14.sp, color: Colors.grey),
                SizedBox(width: 4.w),
                Text('关联 $linkedCount 个', style: TextStyle(fontSize: 11.sp, color: Colors.grey[600])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 11.sp, color: color, fontWeight: FontWeight.w600)),
          SizedBox(width: 4.w),
          Text(value, style: TextStyle(fontSize: 12.sp, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildScoreChip(String label, double score, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4.r),
        border: Border.all(color: color.withOpacity(0.2), width: 0.5),
      ),
      child: Text(
        '$label:${score.toStringAsFixed(2)}',
        style: TextStyle(fontSize: 10.sp, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }

  String _getFocusTypeLabel(String type) {
    switch (type) {
      case 'event': return '事件';
      case 'topic': return '主题';
      case 'entity': return '实体';
      default: return type;
    }
  }

  IconData _getFocusTypeIcon(String type) {
    switch (type) {
      case 'event': return Icons.event;
      case 'topic': return Icons.topic;
      case 'entity': return Icons.person;
      default: return Icons.circle;
    }
  }

  Color _getFocusTypeColor(String type) {
    switch (type) {
      case 'event': return Colors.blue;
      case 'topic': return Colors.green;
      case 'entity': return Colors.purple;
      default: return Colors.grey;
    }
  }

  String _getFocusStateLabel(String state) {
    switch (state) {
      case 'emerging': return '新兴';
      case 'active': return '活跃';
      case 'background': return '背景';
      case 'latent': return '潜在';
      case 'fading': return '衰退';
      default: return state;
    }
  }

  Color _getFocusStateColor(String state) {
    switch (state) {
      case 'emerging': return Colors.lightGreen;
      case 'active': return Colors.green;
      case 'background': return Colors.grey;
      case 'latent': return Colors.orange;
      case 'fading': return Colors.red;
      default: return Colors.grey;
    }
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
      MapEntry('composite_score', '综合得分'),
      MapEntry('cosine_similarity', '余弦相似度'),
      MapEntry('similarity', '相关度'),
      MapEntry('final_score', '最终排序分数'),
      MapEntry('priority_score', '优先级分数'),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                if (!isDataEmpty) ...[
                  SizedBox(height: 8.h),
                  Row(
                    children: [
                      Icon(Icons.sort_rounded, size: 14.sp, color: Color(0xFF7C4DFF)),
                      SizedBox(width: 4.w),
                      Text(
                        '按优先级评分排序',
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: Color(0xFF7C4DFF),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                        decoration: BoxDecoration(
                          color: Color(0xFF7C4DFF).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6.r),
                        ),
                        child: Text(
                          '${kgResults.length} 个节点',
                          style: TextStyle(
                            fontSize: 10.sp,
                            color: Color(0xFF7C4DFF),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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
                                            (entry.key == 'similarity' || entry.key == 'cosine_similarity' || 
                                             entry.key == 'final_score' || entry.key == 'priority_score') && node[entry.key] is num
                                                ? (node[entry.key] as num).toStringAsFixed(4)
                                                : node[entry.key].toString(),
                                            style: TextStyle(color: Colors.grey[900]),
                                          )),
                                        ],
                                      ),
                                    ),
                                // 显示多约束得分详情
                                if (node['constraint_scores'] != null && (node['constraint_scores'] as Map).isNotEmpty)
                                  Padding(
                                    padding: EdgeInsets.only(top: 12, bottom: 8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('约束得分详情:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700])),
                                        SizedBox(height: 8),
                                        ...(node['constraint_scores'] as Map<String, dynamic>).entries.map((e) {
                                          final constraintName = e.key.toString();
                                          final score = (e.value as num?)?.toDouble() ?? 0.0;
                                          Color scoreColor = Colors.grey[600]!;
                                          IconData icon = Icons.info;
                                          
                                          // 根据约束类型设置颜色和图标
                                          if (constraintName.contains('Time') || constraintName.contains('Temporal')) {
                                            scoreColor = Colors.orange[700]!;
                                            icon = Icons.access_time;
                                          } else if (constraintName.contains('Location')) {
                                            scoreColor = Colors.blue[700]!;
                                            icon = Icons.place;
                                          } else if (constraintName.contains('Freshness')) {
                                            scoreColor = Colors.green[700]!;
                                            icon = Icons.new_releases;
                                          } else if (constraintName.contains('Entity')) {
                                            scoreColor = Colors.purple[700]!;
                                            icon = Icons.account_circle;
                                          }
                                          
                                          return Padding(
                                            padding: EdgeInsets.only(bottom: 4),
                                            child: Row(
                                              children: [
                                                Icon(icon, size: 16, color: scoreColor),
                                                SizedBox(width: 6),
                                                Text('$constraintName: ', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                                                Text(
                                                  score.toStringAsFixed(4),
                                                  style: TextStyle(color: scoreColor, fontWeight: FontWeight.w500),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      ],
                                    ),
                                  ),
                                // 显示四大组件得分
                                if (node['components'] != null)
                                  Padding(
                                    padding: EdgeInsets.only(top: 12, bottom: 8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('优先级组件得分:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700])),
                                        SizedBox(height: 8),
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('  • 时间衰减(f_time): ', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                                            Expanded(child: Text(
                                              (node['components']['f_time'] as num?)?.toStringAsFixed(4) ?? 'N/A',
                                              style: TextStyle(color: Colors.orange[700], fontWeight: FontWeight.w500),
                                            )),
                                          ],
                                        ),
                                        SizedBox(height: 4),
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('  • 再激活(f_react): ', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                                            Expanded(child: Text(
                                              (node['components']['f_react'] as num?)?.toStringAsFixed(4) ?? 'N/A',
                                              style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w500),
                                            )),
                                          ],
                                        ),
                                        SizedBox(height: 4),
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('  • 语义相似(f_sem): ', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                                            Expanded(child: Text(
                                              (node['components']['f_sem'] as num?)?.toStringAsFixed(4) ?? 'N/A',
                                              style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.w500),
                                            )),
                                          ],
                                        ),
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
                            // 相关度（余弦相似度）
                            if (node['cosine_similarity'] != null || node['similarity'] != null || node['score'] != null)
                              Padding(
                                padding: EdgeInsets.only(top: 6.h, bottom: 2.h),
                                child: Row(
                                  children: [
                                    Icon(Icons.auto_awesome, color: Colors.blue[300], size: 15.sp),
                                    SizedBox(width: 4.w),
                                    Text('相关度', style: TextStyle(fontSize: 12.sp, color: Colors.blue[400], fontWeight: FontWeight.w500)),
                                    SizedBox(width: 8.w),
                                    Text(
                                      ((node['cosine_similarity'] ?? node['similarity'] ?? node['score']) is num)
                                          ? (((node['cosine_similarity'] ?? node['similarity'] ?? node['score']) as num).toStringAsFixed(3))
                                          : '',
                                      style: TextStyle(fontSize: 12.sp, color: Colors.blue[700], fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            // 优先级评分信息
                            if (node['priority_score'] != null && node['final_score'] != null)
                              Padding(
                                padding: EdgeInsets.only(top: 4.h, bottom: 2.h),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 最终排序分数
                                    Row(
                                      children: [
                                        Icon(Icons.stars, color: Colors.purple[300], size: 15.sp),
                                        SizedBox(width: 4.w),
                                        Text('排序分数', style: TextStyle(fontSize: 12.sp, color: Colors.purple[400], fontWeight: FontWeight.w500)),
                                        SizedBox(width: 8.w),
                                        Text(
                                          (node['final_score'] as num).toStringAsFixed(3),
                                          style: TextStyle(fontSize: 12.sp, color: Colors.purple[700], fontWeight: FontWeight.bold),
                                        ),
                                        SizedBox(width: 8.w),
                                        Text(
                                          '(P=${(node['priority_score'] as num).toStringAsFixed(3)})',
                                          style: TextStyle(fontSize: 11.sp, color: Colors.grey[600]),
                                        ),
                                      ],
                                    ),
                                    // 四大组件得分
                                    if (node['components'] != null)
                                      Padding(
                                        padding: EdgeInsets.only(top: 4.h, left: 19.w),
                                        child: Wrap(
                                          spacing: 8.w,
                                          runSpacing: 4.h,
                                          children: [
                                            _buildComponentChip('时间', node['components']['f_time'], Colors.orange),
                                            _buildComponentChip('激活', node['components']['f_react'], Colors.green),
                                            _buildComponentChip('语义', node['components']['f_sem'], Colors.blue),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            // 多约束得分指示器（如果有的话）
                            if (node['constraint_scores'] != null && (node['constraint_scores'] as Map).isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(top: 4.h),
                                child: Row(
                                  children: [
                                    Icon(Icons.tune, color: Colors.deepPurple[300], size: 13.sp),
                                    SizedBox(width: 4.w),
                                    Text(
                                      '多约束评分: ${(node['constraint_scores'] as Map).length} 项',
                                      style: TextStyle(fontSize: 11.sp, color: Colors.deepPurple[400], fontWeight: FontWeight.w500),
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

  // 构建优先级组件得分标签
  Widget _buildComponentChip(String label, dynamic score, Color color) {
    if (score == null) return SizedBox.shrink();

    final scoreValue = (score is num) ? score.toDouble() : 0.0;
    // 选取一个较深的色阶（如果是 MaterialColor），否则用原色
    final Color textColor = (color is MaterialColor && color[700] != null)
        ? color[700]!
        : (color is MaterialAccentColor && color[700] != null)
        ? color[700]!
        : color;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4.r),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Text(
        '$label:${scoreValue.toStringAsFixed(2)}',
        style: TextStyle(
          fontSize: 10.sp,
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
