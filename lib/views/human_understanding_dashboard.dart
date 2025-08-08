/// 人类理解系统可视化界面
/// 提供系统状态、分析结果和统计信息的可视化展示

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:app/models/human_understanding_models.dart' as hum;
import 'package:app/services/human_understanding_system.dart';
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
    _tabController = TabController(length: 5, vsync: this);
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
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadSystemData,
          ),
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              PopupMenuItem(value: 'export', child: Text('导出数据')),
              PopupMenuItem(value: 'reset', child: Text('重置系统')),
              PopupMenuItem(value: 'test', child: Text('测试分析')),
              PopupMenuItem(value: 'trigger_check', child: Text('手动检查对话')), // 🔥 新增
              PopupMenuItem(value: 'reset_monitoring', child: Text('重置监听状态')), // 🔥 新增
              PopupMenuItem(value: 'debug_info', child: Text('调试信息')), // 🔥 新增
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
                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
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
                    style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    '监听中: ${monitoringStatus['is_monitoring'] ?? false ? "是" : "否"}',
                    style: TextStyle(fontSize: 11.sp),
                  ),
                  Text(
                    '已处理记录: ${monitoringStatus['processed_record_count'] ?? 0}',
                    style: TextStyle(fontSize: 11.sp),
                  ),
                  Text(
                    '检查间隔: ${monitoringStatus['monitor_interval_seconds'] ?? 0}秒',
                    style: TextStyle(fontSize: 11.sp),
                  ),
                ],
              ),
            ),

            if (_currentState != null) ...[
              SizedBox(height: 8.h),
              Text(
                '认知负载: ${_getCognitiveLoadText(_currentState!.currentCognitiveLoad.level)}',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: _getCognitiveLoadColor(_currentState!.currentCognitiveLoad.level),
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

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
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
    final suggestions = _intelligentSuggestions?['suggestions'] as Map<String, dynamic>? ?? {};
    final priorityActions = _intelligentSuggestions?['priority_actions'] as List? ?? [];

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
                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            if (priorityActions.isNotEmpty) ...[
              Text(
                '优先行动:',
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
              ),
              ...priorityActions.map((action) => Padding(
                    padding: EdgeInsets.symmetric(vertical: 2.h),
                    child: Row(
                      children: [
                        Icon(Icons.arrow_right, size: 16.sp, color: Colors.orange),
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
              ...suggestions.entries.map((entry) => Padding(
                    padding: EdgeInsets.symmetric(vertical: 2.h),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lightbulb_outline, size: 16.sp, color: Colors.amber),
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
              ..._currentState!.recentTriples.take(3).map((triple) => Padding(
                    padding: EdgeInsets.symmetric(vertical: 2.h),
                    child: Text(
                      '${triple.subject} → ${triple.predicate} → ${triple.object}',
                      style: TextStyle(fontSize: 12.sp, color: Colors.grey[700]),
                    ),
                  )),
            ],
            if (_currentState!.recentCausalChains.isNotEmpty) ...[
              SizedBox(height: 8.h),
              Text(
                '最新因果关系:',
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
              ),
              ..._currentState!.recentCausalChains.take(2).map((causal) => Padding(
                    padding: EdgeInsets.symmetric(vertical: 2.h),
                    child: Text(
                      '${causal.cause} → ${causal.effect}',
                      style: TextStyle(fontSize: 12.sp, color: Colors.grey[700]),
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
      final state = intent.state.toString().split('.').last;
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
              children: stateGroups.entries.map((entry) => Chip(
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
                    style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: _getIntentStateColor(intent.state.toString().split('.').last),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Text(
                    intent.state.toString().split('.').last,
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
      child: topics.isEmpty
          ? Center(child: Text('暂无活跃主题'))
          : ListView.builder(
              itemCount: topics.length,
              itemBuilder: (context, index) => _buildTopicCard(topics[index]),
            ),
    );
  }

  Widget _buildTopicCard(hum.ConversationTopic topic) {
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
                    style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(topic.relevanceScore),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Text(
                    '${(topic.relevanceScore * 100).toInt()}%',
                    style: TextStyle(fontSize: 10.sp, color: Colors.white),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            Text(
              '类别: ${topic.category}',
              style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
            ),
            if (topic.keywords.isNotEmpty) ...[
              SizedBox(height: 4.h),
              Wrap(
                spacing: 4.w,
                children: topic.keywords.take(5).map((keyword) => Chip(
                  label: Text(keyword, style: TextStyle(fontSize: 10.sp)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                )).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCausalTab() {
    if (_currentState == null) return Container();

    final causals = _currentState!.recentCausalChains;

    return Padding(
      padding: EdgeInsets.all(16.w),
      child: causals.isEmpty
          ? Center(child: Text('暂无因果关系'))
          : ListView.builder(
              itemCount: causals.length,
              itemBuilder: (context, index) => _buildCausalCard(causals[index]),
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
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 14.sp, color: Colors.black),
                      children: [
                        TextSpan(
                          text: causal.cause,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: ' → '),
                        TextSpan(
                          text: causal.effect,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: _getCausalTypeColor(causal.type),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Text(
                    causal.type.toString().split('.').last,
                    style: TextStyle(fontSize: 10.sp, color: Colors.white),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            Text(
              '置信度: ${(causal.confidence * 100).toInt()}%',
              style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCognitiveLoadTab() {
    if (_currentState == null) return Container();

    final load = _currentState!.currentCognitiveLoad;

    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(
        children: [
          _buildLoadLevelCard(load),
          SizedBox(height: 16.h),
          _buildLoadFactorsCard(load),
          SizedBox(height: 16.h),
          _buildLoadRecommendationCard(load),
        ],
      ),
    );
  }

  Widget _buildLoadLevelCard(hum.CognitiveLoadAssessment load) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          children: [
            Text(
              '当前认知负载',
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16.h),
            CircularProgressIndicator(
              value: load.score,
              strokeWidth: 8.w,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation(_getCognitiveLoadColor(load.level)),
            ),
            SizedBox(height: 16.h),
            Text(
              '${(load.score * 100).toInt()}%',
              style: TextStyle(
                fontSize: 24.sp,
                fontWeight: FontWeight.bold,
                color: _getCognitiveLoadColor(load.level),
              ),
            ),
            Text(
              _getCognitiveLoadText(load.level),
              style: TextStyle(fontSize: 16.sp),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadFactorsCard(hum.CognitiveLoadAssessment load) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '负载因子分析',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12.h),
            ...load.factors.entries.map((entry) => Padding(
                  padding: EdgeInsets.symmetric(vertical: 4.h),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          _getFactorDisplayName(entry.key),
                          style: TextStyle(fontSize: 14.sp),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: LinearProgressIndicator(
                          value: entry.value,
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation(_getFactorColor(entry.value)),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Text(
                        '${(entry.value * 100).toInt()}%',
                        style: TextStyle(fontSize: 12.sp),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadRecommendationCard(hum.CognitiveLoadAssessment load) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb, color: Colors.amber, size: 20.sp),
                SizedBox(width: 8.w),
                Text(
                  '系统建议',
                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            Text(
              load.recommendation.isNotEmpty ? load.recommendation : '暂无特别建议',
              style: TextStyle(fontSize: 14.sp),
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
      builder: (context) => AlertDialog(
        title: Text('确认重置'),
        content: Text('这将清空所有理解系统数据，确定要继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取��'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('���定'),
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
      builder: (context) => AlertDialog(
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
      case hum.CognitiveLoadLevel.low: return '负载较低';
      case hum.CognitiveLoadLevel.moderate: return '负载适中';
      case hum.CognitiveLoadLevel.high: return '负载较高';
      case hum.CognitiveLoadLevel.overload: return '负载过重';
    }
  }

  Color _getCognitiveLoadColor(hum.CognitiveLoadLevel level) {
    switch (level) {
      case hum.CognitiveLoadLevel.low: return Colors.green;
      case hum.CognitiveLoadLevel.moderate: return Colors.blue;
      case hum.CognitiveLoadLevel.high: return Colors.orange;
      case hum.CognitiveLoadLevel.overload: return Colors.red;
    }
  }

  Color _getIntentStateColor(String state) {
    switch (state) {
      case 'forming': return Colors.grey;
      case 'clarifying': return Colors.orange;
      case 'executing': return Colors.blue;
      case 'paused': return Colors.yellow;
      case 'completed': return Colors.green;
      case 'abandoned': return Colors.red;
      default: return Colors.grey;
    }
  }

  Color _getCausalTypeColor(hum.CausalRelationType type) {
    switch (type) {
      case hum.CausalRelationType.directCause: return Colors.red;
      case hum.CausalRelationType.indirectCause: return Colors.orange;
      case hum.CausalRelationType.enabler: return Colors.green;
      case hum.CausalRelationType.inhibitor: return Colors.blue;
      case hum.CausalRelationType.correlation: return Colors.purple;
    }
  }

  String _getFactorDisplayName(String factor) {
    switch (factor) {
      case 'intent_count': return '意图数量';
      case 'topic_count': return '主题数量';
      case 'emotional_intensity': return '情绪强度';
      case 'topic_switch_rate': return '话题切换频率';
      case 'complexity_score': return '语言复杂度';
      case 'temporal_pressure': return '时间压力';
      default: return factor;
    }
  }

  Color _getFactorColor(double value) {
    if (value < 0.3) return Colors.green;
    if (value < 0.6) return Colors.orange;
    return Colors.red;
  }
}
