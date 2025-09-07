/// 日志评估页面 - 重构版本
/// 提供对话日志的时间轴展示、功能结果显示、人工标注和统计分析功能

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:app/models/log_evaluation_models.dart';
import 'package:app/services/log_evaluation_service.dart';
import 'package:app/controllers/style_controller.dart';
import 'package:app/views/ui/bud_card.dart';
import 'package:app/views/ui/layout/bud_scaffold.dart';

class LogEvaluationScreen extends StatefulWidget {
  const LogEvaluationScreen({super.key});

  @override
  State<LogEvaluationScreen> createState() => _LogEvaluationScreenState();
}

class _LogEvaluationScreenState extends State<LogEvaluationScreen> {
  final LogEvaluationService _logService = LogEvaluationService();

  // 状态管理
  List<ConversationLogEntry> _conversationLogs = [];
  EvaluationMetrics? _evaluationMetrics;
  bool _isLoading = false;
  String? _errorMessage;

  // 时间范围选择
  DateTimeRange _selectedTimeRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  /// 初始化页面
  Future<void> _initializeScreen() async {
    await _setLoadingState(true);

    try {
      await _logService.initialize();
      await _refreshLogData();
    } catch (error) {
      _setErrorState('初始化失败: $error');
    } finally {
      await _setLoadingState(false);
    }
  }

  /// 刷新日志数据
  Future<void> _refreshLogData() async {
    await _setLoadingState(true);

    try {
      final logs = await _logService.getConversationLogs(
        dateRange: _selectedTimeRange,
      );

      final metrics = await _logService.calculateMetrics(
        dateRange: _selectedTimeRange,
        logs: logs,
      );

      setState(() {
        _conversationLogs = logs;
        _evaluationMetrics = metrics;
        _errorMessage = null;
      });

    } catch (error) {
      _setErrorState('加载日志失败: $error');
    } finally {
      await _setLoadingState(false);
    }
  }

  /// 设置加载状态
  Future<void> _setLoadingState(bool loading) async {
    if (mounted) {
      setState(() => _isLoading = loading);
    }
  }

  /// 设置错误状态
  void _setErrorState(String message) {
    if (mounted) {
      setState(() => _errorMessage = message);
      _showNotification(message, isError: true);
    }
  }

  /// 选择时间范围
  Future<void> _selectTimeRange() async {
    final DateTimeRange? selectedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: _selectedTimeRange,
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

    if (selectedRange != null && selectedRange != _selectedTimeRange) {
      setState(() => _selectedTimeRange = selectedRange);
      await _refreshLogData();
    }
  }

  /// 导出数据
  Future<void> _exportLogData() async {
    if (_conversationLogs.isEmpty || _evaluationMetrics == null) {
      _showNotification('没有数据可导出', isError: true);
      return;
    }

    await _setLoadingState(true);

    try {
      final format = await _showExportFormatDialog();
      if (format == null) return;

      final filePath = await _logService.exportData(
        logs: _conversationLogs,
        metrics: _evaluationMetrics!,
        format: format,
      );

      _showNotification('数据已导出到: $filePath');
    } catch (error) {
      _setErrorState('导出失败: $error');
    } finally {
      await _setLoadingState(false);
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
    final isLightTheme = themeNotifier.mode == Mode.light;

    return BudScaffold(
      title: '日志评估',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildControlPanel(isLightTheme),
                Expanded(
                  child: _conversationLogs.isEmpty
                      ? _buildEmptyDataView(isLightTheme)
                      : Column(
                          children: [
                            Expanded(
                              child: _buildConversationTimelineView(isLightTheme),
                            ),
                            if (_evaluationMetrics != null)
                              _buildStatisticsPanel(isLightTheme),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  /// 构建控制面板
  Widget _buildControlPanel(bool isLightTheme) {
    return Container(
      padding: EdgeInsets.all(16.w),
      child: Row(
        children: [
          Expanded(
            child: _buildTimeRangeSelector(isLightTheme),
          ),
          SizedBox(width: 12.w),
          _buildActionButton(
            icon: Icons.refresh,
            color: Colors.blue,
            onTap: _refreshLogData,
          ),
          SizedBox(width: 12.w),
          _buildActionButton(
            icon: Icons.download,
            color: Colors.green,
            onTap: _exportLogData,
          ),
        ],
      ),
    );
  }

  /// 构建时间范围选择器
  Widget _buildTimeRangeSelector(bool isLightTheme) {
    return GestureDetector(
      onTap: _selectTimeRange,
      child: BudCard(
        color: isLightTheme ? Colors.grey[100] : Colors.grey[800],
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        child: Row(
          children: [
            Icon(
              Icons.date_range,
              size: 20.sp,
              color: isLightTheme ? Colors.black87 : Colors.white70,
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                '${DateFormat('MM/dd').format(_selectedTimeRange.start)} - ${DateFormat('MM/dd').format(_selectedTimeRange.end)}',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: isLightTheme ? Colors.black87 : Colors.white70,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建操作按钮
  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: BudCard(
        color: color.withOpacity(0.1),
        padding: EdgeInsets.all(8.w),
        child: Icon(
          icon,
          size: 20.sp,
          color: color,
        ),
      ),
    );
  }

  /// 构建空数据视图
  Widget _buildEmptyDataView(bool isLightTheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64.sp,
            color: Colors.grey,
          ),
          SizedBox(height: 16.h),
          Text(
            '所选时间范围内无对话记录',
            style: TextStyle(
              fontSize: 16.sp,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            '请选择其他时间范围或开始新的对话',
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建对话时间轴视图
  Widget _buildConversationTimelineView(bool isLightTheme) {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      itemCount: _conversationLogs.length,
      itemBuilder: (context, index) {
        final logEntry = _conversationLogs[index];
        return ConversationLogTile(
          logEntry: logEntry,
          isLightTheme: isLightTheme,
          onEvaluationUpdated: (evaluation) async {
            await _handleEvaluationUpdate(logEntry.id, evaluation);
          },
        );
      },
    );
  }

  /// 处理评估更新
  Future<void> _handleEvaluationUpdate(String logId, UserEvaluation evaluation) async {
    try {
      await _logService.saveEvaluation(logId, evaluation);

      // 重新计算指标
      final updatedMetrics = await _logService.calculateMetrics(
        dateRange: _selectedTimeRange,
        logs: _conversationLogs,
      );

      setState(() => _evaluationMetrics = updatedMetrics);
    } catch (error) {
      _setErrorState('保存评估失败: $error');
    }
  }

  /// 构建统计面板
  Widget _buildStatisticsPanel(bool isLightTheme) {
    final metrics = _evaluationMetrics!;

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: isLightTheme ? Colors.grey[50] : Colors.grey[900],
        border: Border(
          top: BorderSide(
            color: isLightTheme ? Colors.grey[300]! : Colors.grey[700]!,
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
              color: isLightTheme ? Colors.black : Colors.white,
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  label: 'Todo准确率',
                  value: '${(metrics.todoAccuracy * 100).toStringAsFixed(1)}%',
                  color: Colors.blue,
                  isLightTheme: isLightTheme,
                ),
              ),
              Expanded(
                child: _buildMetricCard(
                  label: 'FoA平均分',
                  value: metrics.averageFoaScore.toStringAsFixed(2),
                  color: Colors.green,
                  isLightTheme: isLightTheme,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  label: '推荐相关性',
                  value: metrics.averageRecommendationRelevance.toStringAsFixed(1),
                  color: Colors.orange,
                  isLightTheme: isLightTheme,
                ),
              ),
              Expanded(
                child: _buildMetricCard(
                  label: '负载合理性',
                  value: metrics.averageCognitiveLoadReasonability.toStringAsFixed(1),
                  color: Colors.purple,
                  isLightTheme: isLightTheme,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            '总评估数: ${metrics.totalEvaluations}',
            style: TextStyle(
              fontSize: 12.sp,
              color: isLightTheme ? Colors.grey[600] : Colors.grey[400],
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
    required bool isLightTheme,
  }) {
    return BudCard(
      color: color.withOpacity(0.1),
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
              color: isLightTheme ? Colors.grey[600] : Colors.grey[400],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// 对话日志条目组件
class ConversationLogTile extends StatefulWidget {
  final ConversationLogEntry logEntry;
  final bool isLightTheme;
  final Function(UserEvaluation) onEvaluationUpdated;

  const ConversationLogTile({
    super.key,
    required this.logEntry,
    required this.isLightTheme,
    required this.onEvaluationUpdated,
  });

  @override
  State<ConversationLogTile> createState() => _ConversationLogTileState();
}

class _ConversationLogTileState extends State<ConversationLogTile> {
  bool _isResultsExpanded = false;
  UserEvaluation? _currentEvaluation;

  @override
  void initState() {
    super.initState();
    _currentEvaluation = widget.logEntry.evaluation;
  }

  void _updateEvaluation(UserEvaluation evaluation) {
    setState(() => _currentEvaluation = evaluation);
    widget.onEvaluationUpdated(evaluation);
  }

  @override
  Widget build(BuildContext context) {
    final isUserMessage = widget.logEntry.role == 'user';
    final hasFunctionResults = widget.logEntry.functionResults.isNotEmpty;

    return Container(
      margin: EdgeInsets.only(bottom: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTimestamp(),
          _buildMessageBubble(isUserMessage),
          if (hasFunctionResults) ...[
            if (_isResultsExpanded) _buildFunctionResultsPanel(),
            if (hasFunctionResults) _buildEvaluationPanel(),
          ],
        ],
      ),
    );
  }

  /// 构建时间戳
  Widget _buildTimestamp() {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Text(
        DateFormat('HH:mm:ss').format(widget.logEntry.timestamp),
        style: TextStyle(
          fontSize: 12.sp,
          color: Colors.grey,
        ),
      ),
    );
  }

  /// 构建消息气泡
  Widget _buildMessageBubble(bool isUserMessage) {
    return Row(
      mainAxisAlignment: isUserMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (!isUserMessage) SizedBox(width: 40.w),
        Flexible(
          child: BudCard(
            color: isUserMessage
                ? Colors.blue.withOpacity(0.1)
                : (widget.isLightTheme ? Colors.grey[100] : Colors.grey[800]),
            padding: EdgeInsets.all(12.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRoleLabel(isUserMessage),
                SizedBox(height: 4.h),
                _buildMessageContent(),
                if (widget.logEntry.functionResults.isNotEmpty)
                  _buildExpandToggle(),
              ],
            ),
          ),
        ),
        if (isUserMessage) SizedBox(width: 40.w),
      ],
    );
  }

  /// 构建角色标签
  Widget _buildRoleLabel(bool isUserMessage) {
    return Text(
      isUserMessage ? '用户' : '系统',
      style: TextStyle(
        fontSize: 12.sp,
        fontWeight: FontWeight.bold,
        color: isUserMessage ? Colors.blue : Colors.grey,
      ),
    );
  }

  /// 构建消息内容
  Widget _buildMessageContent() {
    return Text(
      widget.logEntry.content,
      style: TextStyle(
        fontSize: 14.sp,
        color: widget.isLightTheme ? Colors.black87 : Colors.white,
      ),
    );
  }

  /// 构建展开切换按钮
  Widget _buildExpandToggle() {
    return Padding(
      padding: EdgeInsets.only(top: 8.h),
      child: GestureDetector(
        onTap: () => setState(() => _isResultsExpanded = !_isResultsExpanded),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isResultsExpanded ? Icons.expand_less : Icons.expand_more,
              size: 16.sp,
              color: Colors.blue,
            ),
            SizedBox(width: 4.w),
            Text(
              '功能结果 (${widget.logEntry.functionResults.length})',
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建功能结果面板
  Widget _buildFunctionResultsPanel() {
    return Padding(
      padding: EdgeInsets.only(top: 8.h),
      child: BudCard(
        color: widget.isLightTheme
            ? Colors.blue.withOpacity(0.05)
            : Colors.blue.withOpacity(0.1),
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '功能触发结果',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.bold,
                color: widget.isLightTheme ? Colors.black87 : Colors.white,
              ),
            ),
            SizedBox(height: 8.h),
            ...widget.logEntry.functionResults.entries
                .map((entry) => _buildFunctionResultItem(entry.key, entry.value))
                .toList(),
          ],
        ),
      ),
    );
  }

  /// 构建功能结果项目
  Widget _buildFunctionResultItem(String functionType, dynamic result) {
    final resultInfo = _parseFunctionResult(functionType, result);

    if (resultInfo == null) return const SizedBox.shrink();

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.all(8.w),
      decoration: BoxDecoration(
        color: widget.isLightTheme ? Colors.white : Colors.grey[850],
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(
          color: widget.isLightTheme ? Colors.grey[300]! : Colors.grey[600]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            resultInfo['title']!,
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            resultInfo['content']!,
            style: TextStyle(
              fontSize: 11.sp,
              color: widget.isLightTheme ? Colors.black54 : Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  /// 解析功能结果
  Map<String, String>? _parseFunctionResult(String functionType, dynamic result) {
    switch (functionType) {
      case 'foa':
        if (result is List && result.isNotEmpty) {
          final data = result.first as Map<String, dynamic>;
          return {
            'title': 'FoA识别',
            'content': '主题: ${(data['topics'] as List).join(', ')}\n置信度: ${data['confidence']}'
          };
        }
        break;
      case 'todo':
        if (result is List && result.isNotEmpty) {
          final data = result.first as Map<String, dynamic>;
          return {
            'title': 'Todo生成',
            'content': '事件: ${data['event']}\n时间: ${data['reminderTime'] ?? '未指定'}\n置信度: ${data['confidence']}'
          };
        }
        break;
      case 'recommendations':
        if (result is List && result.isNotEmpty) {
          final data = result.first as Map<String, dynamic>;
          return {
            'title': '主动推荐',
            'content': '内容: ${data['content']}\n来源: ${data['source']}'
          };
        }
        break;
      case 'summaries':
        if (result is List && result.isNotEmpty) {
          final data = result.first as Map<String, dynamic>;
          return {
            'title': '总结',
            'content': '主题: ${data['subject']}\n内容: ${data['content']}'
          };
        }
        break;
      case 'cognitiveLoad':
        if (result is Map) {
          return {
            'title': '认知负载',
            'content': '数值: ${result['value']}\n级别: ${result['level']}'
          };
        }
        break;
      case 'kgStatus':
        if (result is Map) {
          return {
            'title': 'KG状态',
            'content': '节点数: ${result['nodeCount']}\n边数: ${result['edgeCount']}'
          };
        }
        break;
    }
    return null;
  }

  /// 构建评估面板
  Widget _buildEvaluationPanel() {
    return Padding(
      padding: EdgeInsets.only(top: 8.h),
      child: BudCard(
        color: widget.isLightTheme
            ? Colors.orange.withOpacity(0.05)
            : Colors.orange.withOpacity(0.1),
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '人工评估',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.bold,
                color: widget.isLightTheme ? Colors.black87 : Colors.white,
              ),
            ),
            SizedBox(height: 12.h),
            if (widget.logEntry.functionResults.containsKey('foa'))
              _buildFoAEvaluationSection(),
            if (widget.logEntry.functionResults.containsKey('todo'))
              _buildTodoEvaluationSection(),
            if (widget.logEntry.functionResults.containsKey('recommendations'))
              _buildRecommendationEvaluationSection(),
            if (widget.logEntry.functionResults.containsKey('cognitiveLoad'))
              _buildCognitiveLoadEvaluationSection(),
          ],
        ),
      ),
    );
  }

  /// 构建FoA评估区域
  Widget _buildFoAEvaluationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FoA是否正确:',
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
            color: widget.isLightTheme ? Colors.black87 : Colors.white,
          ),
        ),
        SizedBox(height: 6.h),
        Wrap(
          spacing: 8.w,
          children: List.generate(5, (index) {
            final score = index + 1;
            final isSelected = _currentEvaluation?.foaScore == score;
            return _buildScoreButton(
              score: score,
              isSelected: isSelected,
              color: Colors.blue,
              onTap: () => _updateFoAScore(score),
            );
          }),
        ),
        SizedBox(height: 12.h),
      ],
    );
  }

  /// 构建Todo评估区域
  Widget _buildTodoEvaluationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Todo是否正确:',
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
            color: widget.isLightTheme ? Colors.black87 : Colors.white,
          ),
        ),
        SizedBox(height: 6.h),
        Row(
          children: [
            _buildBooleanButton(
              label: '✅ 正确',
              isSelected: _currentEvaluation?.todoCorrect == true,
              color: Colors.green,
              onTap: () => _updateTodoCorrectness(true),
            ),
            SizedBox(width: 8.w),
            _buildBooleanButton(
              label: '❌ 错误',
              isSelected: _currentEvaluation?.todoCorrect == false,
              color: Colors.red,
              onTap: () => _updateTodoCorrectness(false),
            ),
          ],
        ),
        SizedBox(height: 12.h),
      ],
    );
  }

  /// 构建推荐评估区域
  Widget _buildRecommendationEvaluationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '主动推荐相关性 (1-5分):',
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
            color: widget.isLightTheme ? Colors.black87 : Colors.white,
          ),
        ),
        SizedBox(height: 6.h),
        Wrap(
          spacing: 6.w,
          children: List.generate(5, (index) {
            final score = index + 1;
            final isSelected = _currentEvaluation?.recommendationRelevance == score;
            return _buildScoreButton(
              score: score,
              isSelected: isSelected,
              color: Colors.orange,
              onTap: () => _updateRecommendationRelevance(score),
            );
          }),
        ),
        SizedBox(height: 12.h),
      ],
    );
  }

  /// 构建认知负载评估区域
  Widget _buildCognitiveLoadEvaluationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '认知负载合理性 (1-5分):',
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
            color: widget.isLightTheme ? Colors.black87 : Colors.white,
          ),
        ),
        SizedBox(height: 6.h),
        Wrap(
          spacing: 6.w,
          children: List.generate(5, (index) {
            final score = index + 1;
            final isSelected = _currentEvaluation?.cognitiveLoadReasonability == score;
            return _buildScoreButton(
              score: score,
              isSelected: isSelected,
              color: Colors.purple,
              onTap: () => _updateCognitiveLoadReasonability(score),
            );
          }),
        ),
      ],
    );
  }

  /// 构建评分按钮
  Widget _buildScoreButton({
    required int score,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24.w,
        height: 24.h,
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(4.r),
        ),
        child: Center(
          child: Text(
            score.toString(),
            style: TextStyle(
              fontSize: 11.sp,
              color: isSelected ? Colors.white : color,
            ),
          ),
        ),
      ),
    );
  }

  /// 构建布尔按钮
  Widget _buildBooleanButton({
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(4.r),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
            color: isSelected ? Colors.white : color,
          ),
        ),
      ),
    );
  }

  /// 更新FoA评分
  void _updateFoAScore(int score) {
    final newEvaluation = UserEvaluation(
      foaScore: score,
      todoCorrect: _currentEvaluation?.todoCorrect,
      recommendationRelevance: _currentEvaluation?.recommendationRelevance,
      cognitiveLoadReasonability: _currentEvaluation?.cognitiveLoadReasonability,
      evaluatedAt: DateTime.now(),
      notes: _currentEvaluation?.notes,
    );
    _updateEvaluation(newEvaluation);
  }

  /// 更新Todo正确性
  void _updateTodoCorrectness(bool isCorrect) {
    final newEvaluation = UserEvaluation(
      foaScore: _currentEvaluation?.foaScore,
      todoCorrect: isCorrect,
      recommendationRelevance: _currentEvaluation?.recommendationRelevance,
      cognitiveLoadReasonability: _currentEvaluation?.cognitiveLoadReasonability,
      evaluatedAt: DateTime.now(),
      notes: _currentEvaluation?.notes,
    );
    _updateEvaluation(newEvaluation);
  }

  /// 更新推荐相关性
  void _updateRecommendationRelevance(int score) {
    final newEvaluation = UserEvaluation(
      foaScore: _currentEvaluation?.foaScore,
      todoCorrect: _currentEvaluation?.todoCorrect,
      recommendationRelevance: score,
      cognitiveLoadReasonability: _currentEvaluation?.cognitiveLoadReasonability,
      evaluatedAt: DateTime.now(),
      notes: _currentEvaluation?.notes,
    );
    _updateEvaluation(newEvaluation);
  }

  /// 更新认知负载合理性
  void _updateCognitiveLoadReasonability(int score) {
    final newEvaluation = UserEvaluation(
      foaScore: _currentEvaluation?.foaScore,
      todoCorrect: _currentEvaluation?.todoCorrect,
      recommendationRelevance: _currentEvaluation?.recommendationRelevance,
      cognitiveLoadReasonability: score,
      evaluatedAt: DateTime.now(),
      notes: _currentEvaluation?.notes,
    );
    _updateEvaluation(newEvaluation);
  }
}
