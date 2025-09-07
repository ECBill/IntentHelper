/// 日志评估页面 - 分功能模块标签页版本
/// 提供按功能模块分类的评估界面，包括时间选择、标签页切换、评估打分和统计汇总

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:app/models/log_evaluation_models.dart';
import 'package:app/services/log_evaluation_service.dart';
import 'package:app/controllers/style_controller.dart';
import 'package:app/views/ui/bud_card.dart';
import 'package:app/views/ui/layout/bud_scaffold.dart';
import 'package:app/views/widgets/evaluation_tiles.dart';

class LogEvaluationTabbedScreen extends StatefulWidget {
  const LogEvaluationTabbedScreen({super.key});

  @override
  State<LogEvaluationTabbedScreen> createState() => _LogEvaluationTabbedScreenState();
}

class _LogEvaluationTabbedScreenState extends State<LogEvaluationTabbedScreen>
    with TickerProviderStateMixin {
  final LogEvaluationService _logService = LogEvaluationService();
  late TabController _tabController;

  // 数据状态
  bool _isLoading = false;

  // 各模块数据
  List<FoAEntry> _foaEntries = [];
  List<TodoEntry> _todoEntries = [];
  List<RecommendationEntry> _recommendationEntries = [];
  List<SummaryEntry> _summaryEntries = [];
  List<KGEntry> _kgEntries = [];
  List<CognitiveLoadEntry> _cognitiveLoadEntries = [];

  // 统计数据
  EvaluationMetrics? _metrics;

  // 时间范围选择
  DateTimeRange _selectedDateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _initializeScreen();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 初始化页面
  Future<void> _initializeScreen() async {
    setState(() => _isLoading = true);

    try {
      await _logService.initialize();
      await _loadAllData();
    } catch (error) {
      _setErrorState('初始化失败: $error');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 加载所有模块数据
  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);

    try {
      final futures = await Future.wait([
        _logService.getFoAEntries(dateRange: _selectedDateRange),
        _logService.getTodoEntries(dateRange: _selectedDateRange),
        _logService.getRecommendationEntries(dateRange: _selectedDateRange),
        _logService.getSummaryEntries(dateRange: _selectedDateRange),
        _logService.getKGEntries(dateRange: _selectedDateRange),
        _logService.getCognitiveLoadEntries(dateRange: _selectedDateRange),
      ]);

      _foaEntries = futures[0] as List<FoAEntry>;
      _todoEntries = futures[1] as List<TodoEntry>;
      _recommendationEntries = futures[2] as List<RecommendationEntry>;
      _summaryEntries = futures[3] as List<SummaryEntry>;
      _kgEntries = futures[4] as List<KGEntry>;
      _cognitiveLoadEntries = futures[5] as List<CognitiveLoadEntry>;

      // 计算统计指标
      final logs = await _logService.getConversationLogs(dateRange: _selectedDateRange);
      _metrics = await _logService.calculateMetrics(
        dateRange: _selectedDateRange,
        logs: logs,
      );

      setState(() {});
    } catch (error) {
      _setErrorState('加载数据失败: $error');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 设置错误状态
  void _setErrorState(String message) {
    _showNotification(message, isError: true);
  }

  /// 选择时间范围
  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Colors.blue,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDateRange) {
      setState(() => _selectedDateRange = picked);
      await _loadAllData();
    }
  }

  /// 导出数据
  Future<void> _exportData() async {
    if (_metrics == null) {
      _showNotification('没有数据可导出', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final format = await _showExportFormatDialog();
      if (format == null) return;

      final logs = await _logService.getConversationLogs(dateRange: _selectedDateRange);
      final filePath = await _logService.exportData(
        logs: logs,
        metrics: _metrics!,
        format: format,
      );

      _showNotification('数据已导出到: $filePath');
    } catch (error) {
      _setErrorState('导出失败: $error');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 显示导出格式选择对话框
  Future<String?> _showExportFormatDialog() async {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择导出格式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('JSON'),
              subtitle: const Text('完整数据结构，适合程序处理'),
              onTap: () => Navigator.pop(context, 'json'),
            ),
            ListTile(
              title: const Text('CSV'),
              subtitle: const Text('表格格式，适合Excel分析'),
              onTap: () => Navigator.pop(context, 'csv'),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示通知
  void _showNotification(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    final isLightMode = themeNotifier.mode == Mode.light;

    return BudScaffold(
      title: '日志评估',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildControlBar(isLightMode),
                _buildTabBar(isLightMode),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildFoATab(isLightMode),
                      _buildTodoTab(isLightMode),
                      _buildRecommendationTab(isLightMode),
                      _buildSummaryTab(isLightMode),
                      _buildKGTab(isLightMode),
                      _buildCognitiveLoadTab(isLightMode),
                    ],
                  ),
                ),
                if (_metrics != null) _buildStatisticsPanel(isLightMode),
              ],
            ),
    );
  }

  /// 构建控制栏
  Widget _buildControlBar(bool isLightMode) {
    return Container(
      padding: EdgeInsets.all(16.w),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _selectDateRange,
              child: BudCard(
                color: isLightMode ? Colors.grey[100] : Colors.grey[800],
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                child: Row(
                  children: [
                    Icon(
                      Icons.date_range,
                      size: 20.sp,
                      color: isLightMode ? Colors.black87 : Colors.white70,
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Text(
                        '${DateFormat('MM/dd').format(_selectedDateRange.start)} - ${DateFormat('MM/dd').format(_selectedDateRange.end)}',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: isLightMode ? Colors.black87 : Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: 12.w),
          GestureDetector(
            onTap: _loadAllData,
            child: BudCard(
              color: Colors.blue.withValues(alpha: 0.1),
              padding: EdgeInsets.all(8.w),
              child: Icon(
                Icons.refresh,
                size: 20.sp,
                color: Colors.blue,
              ),
            ),
          ),
          SizedBox(width: 12.w),
          GestureDetector(
            onTap: _exportData,
            child: BudCard(
              color: Colors.green.withValues(alpha: 0.1),
              padding: EdgeInsets.all(8.w),
              child: Icon(
                Icons.download,
                size: 20.sp,
                color: Colors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建标签栏
  Widget _buildTabBar(bool isLightMode) {
    return Container(
      color: isLightMode ? Colors.white : Colors.grey[900],
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        labelColor: Colors.blue,
        unselectedLabelColor: isLightMode ? Colors.grey[600] : Colors.grey[400],
        indicatorColor: Colors.blue,
        labelStyle: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500),
        unselectedLabelStyle: TextStyle(fontSize: 14.sp),
        tabs: [
          Tab(text: 'FoA识别 (${_foaEntries.length})'),
          Tab(text: 'Todo生成 (${_todoEntries.length})'),
          Tab(text: '智能推荐 (${_recommendationEntries.length})'),
          Tab(text: '总结 (${_summaryEntries.length})'),
          Tab(text: '知识图谱 (${_kgEntries.length})'),
          Tab(text: '认知负载 (${_cognitiveLoadEntries.length})'),
        ],
      ),
    );
  }

  /// 构建模块标签页内容的通用方法
  Widget _buildModuleTabContent<T>({
    required List<T> entries,
    required bool isLightMode,
    required String emptyMessage,
    required Widget Function(T) itemBuilder,
  }) {
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64.sp,
              color: Colors.grey,
            ),
            SizedBox(height: 16.h),
            Text(
              emptyMessage,
              style: TextStyle(
                fontSize: 16.sp,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: entries.length,
      itemBuilder: (context, index) => itemBuilder(entries[index]),
    );
  }

  /// 构建各个标签页
  Widget _buildFoATab(bool isLightMode) {
    return _buildModuleTabContent<FoAEntry>(
      entries: _foaEntries,
      isLightMode: isLightMode,
      emptyMessage: '所选时间范围内无FoA识别记录',
      itemBuilder: (entry) => FoAEntryTile(
        entry: entry,
        isLightMode: isLightMode,
        onEvaluationChanged: (evaluation) => _handleEvaluationUpdate(entry.id, evaluation),
      ),
    );
  }

  Widget _buildTodoTab(bool isLightMode) {
    return _buildModuleTabContent<TodoEntry>(
      entries: _todoEntries,
      isLightMode: isLightMode,
      emptyMessage: '所选时间范围内无Todo生成记录',
      itemBuilder: (entry) => TodoEntryTile(
        entry: entry,
        isLightMode: isLightMode,
        onEvaluationChanged: (evaluation) => _handleEvaluationUpdate(entry.id, evaluation),
      ),
    );
  }

  Widget _buildRecommendationTab(bool isLightMode) {
    return _buildModuleTabContent<RecommendationEntry>(
      entries: _recommendationEntries,
      isLightMode: isLightMode,
      emptyMessage: '所选时间范围内无智能推荐记录',
      itemBuilder: (entry) => RecommendationEntryTile(
        entry: entry,
        isLightMode: isLightMode,
        onEvaluationChanged: (evaluation) => _handleEvaluationUpdate(entry.id, evaluation),
      ),
    );
  }

  Widget _buildSummaryTab(bool isLightMode) {
    return _buildModuleTabContent<SummaryEntry>(
      entries: _summaryEntries,
      isLightMode: isLightMode,
      emptyMessage: '所选时间范围内无总结记录',
      itemBuilder: (entry) => SummaryEntryTile(
        entry: entry,
        isLightMode: isLightMode,
        onEvaluationChanged: (evaluation) => _handleEvaluationUpdate(entry.id, evaluation),
      ),
    );
  }

  Widget _buildKGTab(bool isLightMode) {
    return _buildModuleTabContent<KGEntry>(
      entries: _kgEntries,
      isLightMode: isLightMode,
      emptyMessage: '所选时间范围内无知识图谱记录',
      itemBuilder: (entry) => KGEntryTile(
        entry: entry,
        isLightMode: isLightMode,
        onEvaluationChanged: (evaluation) => _handleEvaluationUpdate(entry.id, evaluation),
      ),
    );
  }

  Widget _buildCognitiveLoadTab(bool isLightMode) {
    return _buildModuleTabContent<CognitiveLoadEntry>(
      entries: _cognitiveLoadEntries,
      isLightMode: isLightMode,
      emptyMessage: '所选时间范围内无认知负载记录',
      itemBuilder: (entry) => CognitiveLoadEntryTile(
        entry: entry,
        isLightMode: isLightMode,
        onEvaluationChanged: (evaluation) => _handleEvaluationUpdate(entry.id, evaluation),
      ),
    );
  }

  /// 处理评估更新
  Future<void> _handleEvaluationUpdate(String entryId, UserEvaluation evaluation) async {
    try {
      await _logService.saveEvaluation(entryId, evaluation);

      // 重新计算指标
      final logs = await _logService.getConversationLogs(dateRange: _selectedDateRange);
      final updatedMetrics = await _logService.calculateMetrics(
        dateRange: _selectedDateRange,
        logs: logs,
      );

      setState(() => _metrics = updatedMetrics);
    } catch (error) {
      _setErrorState('保存评估失败: $error');
    }
  }

  /// 构建统计面板
  Widget _buildStatisticsPanel(bool isLightMode) {
    final metrics = _metrics!;

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: isLightMode ? Colors.grey[50] : Colors.grey[900],
        border: Border(
          top: BorderSide(
            color: isLightMode ? Colors.grey[300]! : Colors.grey[700]!,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '评估统计',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              color: isLightMode ? Colors.black : Colors.white,
            ),
          ),
          SizedBox(height: 12.h),
          // 第一行：Todo准确率 + FoA平均分
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  label: 'Todo准确率',
                  value: '${(metrics.todoAccuracy * 100).toStringAsFixed(1)}%',
                  color: Colors.blue,
                  isLightMode: isLightMode,
                ),
              ),
              Expanded(
                child: _buildMetricCard(
                  label: 'FoA平均分',
                  value: metrics.averageFoaScore.toStringAsFixed(2),
                  color: Colors.green,
                  isLightMode: isLightMode,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          // 第二行：推荐相关性 + 负载合理性
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  label: '推荐相关性',
                  value: metrics.averageRecommendationRelevance.toStringAsFixed(1),
                  color: Colors.orange,
                  isLightMode: isLightMode,
                ),
              ),
              Expanded(
                child: _buildMetricCard(
                  label: '负载合理性',
                  value: metrics.averageCognitiveLoadReasonability.toStringAsFixed(1),
                  color: Colors.purple,
                  isLightMode: isLightMode,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          // 第三行：总结质量 + KG准确性
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  label: '总结质量',
                  value: metrics.averageSummaryRelevance.toStringAsFixed(1),
                  color: Colors.teal,
                  isLightMode: isLightMode,
                ),
              ),
              Expanded(
                child: _buildMetricCard(
                  label: 'KG准确性',
                  value: metrics.averageKgAccuracy.toStringAsFixed(1),
                  color: Colors.indigo,
                  isLightMode: isLightMode,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            '总评估数: ${metrics.totalEvaluations}',
            style: TextStyle(
              fontSize: 12.sp,
              color: isLightMode ? Colors.grey[600] : Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建指标卡片
  Widget _buildMetricCard({
    required String label,
    required String value,
    required Color color,
    required bool isLightMode,
  }) {
    return BudCard(
      color: color.withValues(alpha: 0.1),
      padding: EdgeInsets.all(12.w),
      margin: EdgeInsets.symmetric(horizontal: 4.w),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.sp,
              color: isLightMode ? Colors.grey[600] : Colors.grey[400],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
