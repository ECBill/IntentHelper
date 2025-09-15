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
  int _currentTabIndex = 0; // 添加当前标签索引追踪

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
    // 修复标签切换监听器
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentTabIndex = _tabController.index;
        });
      }
    });
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
        onTap: (index) {
          setState(() {
            _currentTabIndex = index;
          });
        },
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

      // 更新对应模块的entry数据
      _updateEntryEvaluation(entryId, evaluation);

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

  /// 更新entry的evaluation数据
  void _updateEntryEvaluation(String entryId, UserEvaluation evaluation) {
    // 根据entryId前缀判断是哪个模块的数据
    if (entryId.startsWith('foa_')) {
      final index = _foaEntries.indexWhere((e) => e.id == entryId);
      if (index != -1) {
        _foaEntries[index] = _foaEntries[index].copyWith(evaluation: evaluation);
      }
    } else if (entryId.startsWith('todo_')) {
      final index = _todoEntries.indexWhere((e) => e.id == entryId);
      if (index != -1) {
        _todoEntries[index] = _todoEntries[index].copyWith(evaluation: evaluation);
      }
    } else if (entryId.startsWith('rec_')) {
      final index = _recommendationEntries.indexWhere((e) => e.id == entryId);
      if (index != -1) {
        _recommendationEntries[index] = _recommendationEntries[index].copyWith(evaluation: evaluation);
      }
    } else if (entryId.startsWith('summary_')) {
      final index = _summaryEntries.indexWhere((e) => e.id == entryId);
      if (index != -1) {
        _summaryEntries[index] = _summaryEntries[index].copyWith(evaluation: evaluation);
      }
    } else if (entryId.startsWith('kg_')) {
      final index = _kgEntries.indexWhere((e) => e.id == entryId);
      if (index != -1) {
        _kgEntries[index] = _kgEntries[index].copyWith(evaluation: evaluation);
      }
    } else if (entryId.startsWith('load_')) {
      final index = _cognitiveLoadEntries.indexWhere((e) => e.id == entryId);
      if (index != -1) {
        _cognitiveLoadEntries[index] = _cognitiveLoadEntries[index].copyWith(evaluation: evaluation);
      }
    }
  }

  /// 构建统计面板 - 只显示当前标签的统计信息
  Widget _buildStatisticsPanel(bool isLightMode) {
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
      child: _buildCurrentTabStatistics(isLightMode),
    );
  }

  /// 构建当前标签的统计信息
  Widget _buildCurrentTabStatistics(bool isLightMode) {
    switch (_currentTabIndex) {
      case 0: // FoA识别
        return _buildFoAStatistics(isLightMode);
      case 1: // Todo生成
        return _buildTodoStatistics(isLightMode);
      case 2: // 智能推荐
        return _buildRecommendationStatistics(isLightMode);
      case 3: // 总结
        return _buildSummaryStatistics(isLightMode);
      case 4: // 知识图谱
        return _buildKGStatistics(isLightMode);
      case 5: // 认知负载
        return _buildCognitiveLoadStatistics(isLightMode);
      default:
        return const SizedBox.shrink();
    }
  }

  /// FoA识别统计
  Widget _buildFoAStatistics(bool isLightMode) {
    final evaluatedEntries = _foaEntries.where((e) => e.evaluation?.foaScore != null).toList();
    if (evaluatedEntries.isEmpty) {
      return _buildEmptyStatistics('FoA识别', isLightMode);
    }

    // 统计各个分档的数量
    int basicCorrect = 0; // 1.0
    int relativelyCorrect = 0; // 0.75
    int notVeryCorrect = 0; // 0.5
    int basicIncorrect = 0; // 0.0

    for (final entry in evaluatedEntries) {
      final score = entry.evaluation!.foaScore!;
      if (score == 1.0) basicCorrect++;
      else if (score == 0.75) relativelyCorrect++;
      else if (score == 0.5) notVeryCorrect++;
      else if (score == 0.0) basicIncorrect++;
    }

    final avgScore = evaluatedEntries.map((e) => e.evaluation!.foaScore!).reduce((a, b) => a + b) / evaluatedEntries.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FoA识别评估统计',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
            color: isLightMode ? Colors.black : Colors.white,
          ),
        ),
        SizedBox(height: 12.h),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                label: '平均得分',
                value: avgScore.toStringAsFixed(2),
                color: Colors.blue,
                isLightMode: isLightMode,
              ),
            ),
            Expanded(
              child: _buildMetricCard(
                label: '已评估数',
                value: '${evaluatedEntries.length}/${_foaEntries.length}',
                color: Colors.green,
                isLightMode: isLightMode,
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        Text(
          '评分分布：',
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
            color: isLightMode ? Colors.black87 : Colors.white,
          ),
        ),
        SizedBox(height: 8.h),
        _buildScoreDistribution([
          {'label': '基本正确', 'count': basicCorrect, 'color': Colors.green},
          {'label': '比较正确', 'count': relativelyCorrect, 'color': Colors.lightGreen},
          {'label': '不太正确', 'count': notVeryCorrect, 'color': Colors.orange},
          {'label': '基本不正确', 'count': basicIncorrect, 'color': Colors.red},
        ], isLightMode),
      ],
    );
  }

  /// Todo生成统计
  Widget _buildTodoStatistics(bool isLightMode) {
    final evaluatedEntries = _todoEntries.where((e) => e.evaluation?.todoCorrect != null).toList();
    if (evaluatedEntries.isEmpty) {
      return _buildEmptyStatistics('Todo生成', isLightMode);
    }

    final correctCount = evaluatedEntries.where((e) => e.evaluation!.todoCorrect == true).length;
    final incorrectCount = evaluatedEntries.length - correctCount;
    final accuracy = correctCount / evaluatedEntries.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Todo生成评估统计',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
            color: isLightMode ? Colors.black : Colors.white,
          ),
        ),
        SizedBox(height: 12.h),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                label: '准确率',
                value: '${(accuracy * 100).toStringAsFixed(1)}%',
                color: Colors.blue,
                isLightMode: isLightMode,
              ),
            ),
            Expanded(
              child: _buildMetricCard(
                label: '已评估数',
                value: '${evaluatedEntries.length}/${_todoEntries.length}',
                color: Colors.green,
                isLightMode: isLightMode,
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        Text(
          '评估结果分布：',
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
            color: isLightMode ? Colors.black87 : Colors.white,
          ),
        ),
        SizedBox(height: 8.h),
        _buildScoreDistribution([
          {'label': '正确', 'count': correctCount, 'color': Colors.green},
          {'label': '错误', 'count': incorrectCount, 'color': Colors.red},
        ], isLightMode),
      ],
    );
  }

  /// 智能推荐统计
  Widget _buildRecommendationStatistics(bool isLightMode) {
    final evaluatedEntries = _recommendationEntries.where((e) => e.evaluation?.recommendationRelevance != null).toList();
    if (evaluatedEntries.isEmpty) {
      return _buildEmptyStatistics('智能推荐', isLightMode);
    }

    // 统计1-5分的分布
    final scoreCounts = List.filled(5, 0);
    for (final entry in evaluatedEntries) {
      final score = entry.evaluation!.recommendationRelevance!;
      if (score >= 1 && score <= 5) {
        scoreCounts[score - 1]++;
      }
    }

    final avgScore = evaluatedEntries.map((e) => e.evaluation!.recommendationRelevance!).reduce((a, b) => a + b) / evaluatedEntries.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '智能推荐评估统计',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
            color: isLightMode ? Colors.black : Colors.white,
          ),
        ),
        SizedBox(height: 12.h),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                label: '平均相关性',
                value: avgScore.toStringAsFixed(1),
                color: Colors.orange,
                isLightMode: isLightMode,
              ),
            ),
            Expanded(
              child: _buildMetricCard(
                label: '已评估数',
                value: '${evaluatedEntries.length}/${_recommendationEntries.length}',
                color: Colors.green,
                isLightMode: isLightMode,
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        Text(
          '评分分布(1-5分)：',
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
            color: isLightMode ? Colors.black87 : Colors.white,
          ),
        ),
        SizedBox(height: 8.h),
        _buildScoreDistribution([
          for (int i = 0; i < 5; i++)
            {
              'label': '${i + 1}分',
              'count': scoreCounts[i],
              'color': _getScoreColor(i + 1),
            }
        ], isLightMode),
      ],
    );
  }

  /// 总结统计
  Widget _buildSummaryStatistics(bool isLightMode) {
    final evaluatedEntries = _summaryEntries.where((e) => e.evaluation?.summaryRelevance != null).toList();
    if (evaluatedEntries.isEmpty) {
      return _buildEmptyStatistics('总结', isLightMode);
    }

    // 统计1-5分的分布
    final scoreCounts = List.filled(5, 0);
    for (final entry in evaluatedEntries) {
      final score = entry.evaluation!.summaryRelevance!;
      if (score >= 1 && score <= 5) {
        scoreCounts[score - 1]++;
      }
    }

    final avgScore = evaluatedEntries.map((e) => e.evaluation!.summaryRelevance!).reduce((a, b) => a + b) / evaluatedEntries.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '总结质量评估统计',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
            color: isLightMode ? Colors.black : Colors.white,
          ),
        ),
        SizedBox(height: 12.h),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                label: '平均质量分',
                value: avgScore.toStringAsFixed(1),
                color: Colors.teal,
                isLightMode: isLightMode,
              ),
            ),
            Expanded(
              child: _buildMetricCard(
                label: '已评估数',
                value: '${evaluatedEntries.length}/${_summaryEntries.length}',
                color: Colors.green,
                isLightMode: isLightMode,
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        Text(
          '评分分布(1-5分)：',
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
            color: isLightMode ? Colors.black87 : Colors.white,
          ),
        ),
        SizedBox(height: 8.h),
        _buildScoreDistribution([
          for (int i = 0; i < 5; i++)
            {
              'label': '${i + 1}分',
              'count': scoreCounts[i],
              'color': _getScoreColor(i + 1),
            }
        ], isLightMode),
      ],
    );
  }

  /// 知识图谱统计
  Widget _buildKGStatistics(bool isLightMode) {
    final evaluatedEntries = _kgEntries.where((e) => e.evaluation?.kgAccuracy != null).toList();
    if (evaluatedEntries.isEmpty) {
      return _buildEmptyStatistics('知识图谱', isLightMode);
    }

    // 统计1-5分的分布
    final scoreCounts = List.filled(5, 0);
    for (final entry in evaluatedEntries) {
      final score = entry.evaluation!.kgAccuracy!;
      if (score >= 1 && score <= 5) {
        scoreCounts[score - 1]++;
      }
    }

    final avgScore = evaluatedEntries.map((e) => e.evaluation!.kgAccuracy!).reduce((a, b) => a + b) / evaluatedEntries.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '知识图谱评估统计',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
            color: isLightMode ? Colors.black : Colors.white,
          ),
        ),
        SizedBox(height: 12.h),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                label: '平均准确性',
                value: avgScore.toStringAsFixed(1),
                color: Colors.indigo,
                isLightMode: isLightMode,
              ),
            ),
            Expanded(
              child: _buildMetricCard(
                label: '已评估数',
                value: '${evaluatedEntries.length}/${_kgEntries.length}',
                color: Colors.green,
                isLightMode: isLightMode,
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        Text(
          '评分分布(1-5分)：',
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
            color: isLightMode ? Colors.black87 : Colors.white,
          ),
        ),
        SizedBox(height: 8.h),
        _buildScoreDistribution([
          for (int i = 0; i < 5; i++)
            {
              'label': '${i + 1}分',
              'count': scoreCounts[i],
              'color': _getScoreColor(i + 1),
            }
        ], isLightMode),
      ],
    );
  }

  /// 认知负载统计
  Widget _buildCognitiveLoadStatistics(bool isLightMode) {
    final evaluatedEntries = _cognitiveLoadEntries.where((e) => e.evaluation?.cognitiveLoadReasonability != null).toList();
    if (evaluatedEntries.isEmpty) {
      return _buildEmptyStatistics('认知负载', isLightMode);
    }

    // 统计1-5分的分布
    final scoreCounts = List.filled(5, 0);
    for (final entry in evaluatedEntries) {
      final score = entry.evaluation!.cognitiveLoadReasonability!;
      if (score >= 1 && score <= 5) {
        scoreCounts[score - 1]++;
      }
    }

    final avgScore = evaluatedEntries.map((e) => e.evaluation!.cognitiveLoadReasonability!).reduce((a, b) => a + b) / evaluatedEntries.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '认知负载评估统计',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
            color: isLightMode ? Colors.black : Colors.white,
          ),
        ),
        SizedBox(height: 12.h),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                label: '平均合理性',
                value: avgScore.toStringAsFixed(1),
                color: Colors.purple,
                isLightMode: isLightMode,
              ),
            ),
            Expanded(
              child: _buildMetricCard(
                label: '已评估数',
                value: '${evaluatedEntries.length}/${_cognitiveLoadEntries.length}',
                color: Colors.green,
                isLightMode: isLightMode,
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        Text(
          '评分分布(1-5分)：',
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
            color: isLightMode ? Colors.black87 : Colors.white,
          ),
        ),
        SizedBox(height: 8.h),
        _buildScoreDistribution([
          for (int i = 0; i < 5; i++)
            {
              'label': '${i + 1}分',
              'count': scoreCounts[i],
              'color': _getScoreColor(i + 1),
            }
        ], isLightMode),
      ],
    );
  }

  /// 构建空统计信息
  Widget _buildEmptyStatistics(String moduleName, bool isLightMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$moduleName评估统计',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
            color: isLightMode ? Colors.black : Colors.white,
          ),
        ),
        SizedBox(height: 12.h),
        Text(
          '暂无评估数据',
          style: TextStyle(
            fontSize: 14.sp,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  /// 构建评分分布组件
  Widget _buildScoreDistribution(List<Map<String, dynamic>> distribution, bool isLightMode) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 4.h,
      children: distribution.map((item) {
        final label = item['label'] as String;
        final count = item['count'] as int;
        final color = item['color'] as Color;

        return Container(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Text(
            '$label: $count',
            style: TextStyle(
              fontSize: 12.sp,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 根据评分获取颜色
  Color _getScoreColor(int score) {
    switch (score) {
      case 1:
        return Colors.red;
      case 2:
        return Colors.deepOrange;
      case 3:
        return Colors.orange;
      case 4:
        return Colors.lightGreen;
      case 5:
        return Colors.green;
      default:
        return Colors.grey;
    }
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.sp,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            value,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

