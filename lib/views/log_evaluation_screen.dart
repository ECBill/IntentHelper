/// 日志评估页面 - 完全重构版本
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

  List<ConversationLogEntry> _logs = [];
  EvaluationMetrics? _metrics;
  bool _isLoading = false;

  // 时间范围选择
  DateTimeRange _selectedDateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );

  @override
  void initState() {
    super.initState();
    _initializeAndLoadData();
  }

  Future<void> _initializeAndLoadData() async {
    setState(() => _isLoading = true);

    try {
      await _logService.initialize();
      await _loadLogs();
    } catch (e) {
      _showError('初始化失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);

    try {
      final logs = await _logService.getConversationLogs(
        dateRange: _selectedDateRange,
      );

      final metrics = await _logService.calculateMetrics(
        dateRange: _selectedDateRange,
        logs: logs,
      );

      setState(() {
        _logs = logs;
        _metrics = metrics;
      });
    } catch (e) {
      _showError('加载日志失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

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
      setState(() {
        _selectedDateRange = picked;
      });
      await _loadLogs();
    }
  }

  Future<void> _exportData() async {
    if (_logs.isEmpty || _metrics == null) {
      _showError('没有数据可导出');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final format = await _showFormatDialog();
      if (format == null) return;

      final filePath = await _logService.exportData(
        logs: _logs,
        metrics: _metrics!,
        format: format,
      );

      _showSuccess('数据已导出到: $filePath');
    } catch (e) {
      _showError('导出失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<String?> _showFormatDialog() async {
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
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
                Expanded(
                  child: _logs.isEmpty
                      ? _buildEmptyState(isLightMode)
                      : Column(
                          children: [
                            Expanded(
                              child: _buildConversationTimeline(isLightMode),
                            ),
                            if (_metrics != null)
                              _buildMetricsPanel(isLightMode),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildControlBar(bool isLightMode) {
    return Container(
      padding: EdgeInsets.all(16.sp),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _selectDateRange,
              child: BudCard(
                color: isLightMode ? Colors.grey[100] : Colors.grey[800],
                padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
                child: Row(
                  children: [
                    Icon(
                      Icons.date_range,
                      size: 20.sp,
                      color: isLightMode ? Colors.black87 : Colors.white70,
                    ),
                    SizedBox(width: 8.sp),
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
          SizedBox(width: 12.sp),
          GestureDetector(
            onTap: _loadLogs,
            child: BudCard(
              color: Colors.blue.withOpacity(0.1),
              padding: EdgeInsets.all(8.sp),
              child: Icon(
                Icons.refresh,
                size: 20.sp,
                color: Colors.blue,
              ),
            ),
          ),
          SizedBox(width: 12.sp),
          GestureDetector(
            onTap: _exportData,
            child: BudCard(
              color: Colors.green.withOpacity(0.1),
              padding: EdgeInsets.all(8.sp),
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

  Widget _buildEmptyState(bool isLightMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64.sp,
            color: Colors.grey,
          ),
          SizedBox(height: 16.sp),
          Text(
            '所选时间范围内无对话记录',
            style: TextStyle(
              fontSize: 16.sp,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8.sp),
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

  Widget _buildConversationTimeline(bool isLightMode) {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16.sp),
      itemCount: _logs.length,
      itemBuilder: (context, index) {
        final log = _logs[index];
        return ConversationLogTile(
          log: log,
          isLightMode: isLightMode,
          onEvaluationChanged: (evaluation) async {
            await _logService.saveEvaluation(log.id, evaluation);
            final updatedMetrics = await _logService.calculateMetrics(
              dateRange: _selectedDateRange,
              logs: _logs,
            );
            setState(() => _metrics = updatedMetrics);
          },
        );
      },
    );
  }

  Widget _buildMetricsPanel(bool isLightMode) {
    return Container(
      padding: EdgeInsets.all(16.sp),
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
          SizedBox(height: 12.sp),
          Row(
            children: [
              Expanded(
                child: _buildMetricItem(
                  label: 'Todo准确率',
                  value: '${(_metrics!.todoAccuracy * 100).toStringAsFixed(1)}%',
                  color: Colors.blue,
                  isLightMode: isLightMode,
                ),
              ),
              Expanded(
                child: _buildMetricItem(
                  label: 'FoA平均分',
                  value: _metrics!.averageFoaScore.toStringAsFixed(2),
                  color: Colors.green,
                  isLightMode: isLightMode,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.sp),
          Row(
            children: [
              Expanded(
                child: _buildMetricItem(
                  label: '推荐相关性',
                  value: _metrics!.averageRecommendationRelevance.toStringAsFixed(1),
                  color: Colors.orange,
                  isLightMode: isLightMode,
                ),
              ),
              Expanded(
                child: _buildMetricItem(
                  label: '负载合理性',
                  value: _metrics!.averageCognitiveLoadReasonability.toStringAsFixed(1),
                  color: Colors.purple,
                  isLightMode: isLightMode,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.sp),
          Text(
            '总评估数: ${_metrics!.totalEvaluations}',
            style: TextStyle(
              fontSize: 12.sp,
              color: isLightMode ? Colors.grey[600] : Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem({
    required String label,
    required String value,
    required Color color,
    required bool isLightMode,
  }) {
    return BudCard(
      color: color.withOpacity(0.1),
      padding: EdgeInsets.all(12.sp),
      margin: EdgeInsets.symmetric(horizontal: 4.sp),
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
          SizedBox(height: 4.sp),
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

/// 对话日志条目组件
class ConversationLogTile extends StatefulWidget {
  final ConversationLogEntry log;
  final bool isLightMode;
  final Function(UserEvaluation) onEvaluationChanged;

  const ConversationLogTile({
    super.key,
    required this.log,
    required this.isLightMode,
    required this.onEvaluationChanged,
  });

  @override
  State<ConversationLogTile> createState() => _ConversationLogTileState();
}

class _ConversationLogTileState extends State<ConversationLogTile> {
  bool _isExpanded = false;
  UserEvaluation? _currentEvaluation;

  @override
  void initState() {
    super.initState();
    _currentEvaluation = widget.log.evaluation;
  }

  void _updateEvaluation(UserEvaluation evaluation) {
    setState(() => _currentEvaluation = evaluation);
    widget.onEvaluationChanged(evaluation);
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.log.role == 'user';
    final hasResults = widget.log.functionResults.isNotEmpty;

    return Container(
      margin: EdgeInsets.only(bottom: 16.sp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 8.sp),
            child: Text(
              DateFormat('HH:mm:ss').format(widget.log.timestamp),
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.grey,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!isUser) SizedBox(width: 40.sp),
              Flexible(
                child: BudCard(
                  color: isUser
                      ? Colors.blue.withOpacity(0.1)
                      : (widget.isLightMode ? Colors.grey[100] : Colors.grey[800]),
                  padding: EdgeInsets.all(12.sp),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isUser ? '用户' : '系统',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.bold,
                          color: isUser ? Colors.blue : Colors.grey,
                        ),
                      ),
                      SizedBox(height: 4.sp),
                      Text(
                        widget.log.content,
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: widget.isLightMode ? Colors.black87 : Colors.white,
                        ),
                      ),
                      if (hasResults) ...[
                        SizedBox(height: 8.sp),
                        GestureDetector(
                          onTap: () => setState(() => _isExpanded = !_isExpanded),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isExpanded ? Icons.expand_less : Icons.expand_more,
                                size: 16.sp,
                                color: Colors.blue,
                              ),
                              SizedBox(width: 4.sp),
                              Text(
                                '功能结果 (${widget.log.functionResults.length})',
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (isUser) SizedBox(width: 40.sp),
            ],
          ),
          if (hasResults && _isExpanded) ...[
            SizedBox(height: 8.sp),
            _buildFunctionResults(),
          ],
          // 修改：显示评估区域的条件 - 只要有对话内容就显示
          SizedBox(height: 8.sp),
          _buildEvaluationArea(),
        ],
      ),
    );
  }

  Widget _buildFunctionResults() {
    return BudCard(
      color: widget.isLightMode
          ? Colors.blue.withOpacity(0.05)
          : Colors.blue.withOpacity(0.1),
      padding: EdgeInsets.all(12.sp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '功能触发结果',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.bold,
              color: widget.isLightMode ? Colors.black87 : Colors.white,
            ),
          ),
          SizedBox(height: 8.sp),
          ...widget.log.functionResults.entries.map((entry) {
            return _buildFunctionResultItem(entry.key, entry.value);
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildFunctionResultItem(String key, dynamic value) {
    String title = '';
    String content = '';

    switch (key) {
      case 'foa':
        title = 'FoA识别';
        if (value is List && value.isNotEmpty) {
          final result = value.first as Map<String, dynamic>;
          content = '主题: ${(result['topics'] as List).join(', ')}\n置信度: ${result['confidence']}';
        }
        break;
      case 'todo':
        title = 'Todo生成';
        if (value is List && value.isNotEmpty) {
          final result = value.first as Map<String, dynamic>;
          content = '事件: ${result['event']}\n时间: ${result['reminderTime'] ?? '未指定'}\n置信度: ${result['confidence']}';
        }
        break;
      case 'recommendations':
        title = '主动推荐';
        if (value is List && value.isNotEmpty) {
          final result = value.first as Map<String, dynamic>;
          content = '内容: ${result['content']}\n来源: ${result['source']}';
        }
        break;
      case 'summaries':
        title = '总结';
        if (value is List && value.isNotEmpty) {
          final result = value.first as Map<String, dynamic>;
          content = '主题: ${result['subject']}\n内容: ${result['content']}';
        }
        break;
      case 'cognitiveLoad':
        title = '认知负载';
        if (value is Map) {
          content = '数值: ${value['value']}\n级别: ${value['level']}';
        }
        break;
      case 'kgStatus':
        title = 'KG状态';
        if (value is Map) {
          content = '节点数: ${value['nodeCount']}\n边数: ${value['edgeCount']}';
        }
        break;
    }

    if (title.isEmpty || content.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: EdgeInsets.only(bottom: 8.sp),
      padding: EdgeInsets.all(8.sp),
      decoration: BoxDecoration(
        color: widget.isLightMode ? Colors.white : Colors.grey[850],
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(
          color: widget.isLightMode ? Colors.grey[300]! : Colors.grey[600]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          SizedBox(height: 4.sp),
          Text(
            content,
            style: TextStyle(
              fontSize: 11.sp,
              color: widget.isLightMode ? Colors.black54 : Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEvaluationArea() {
    return BudCard(
      color: widget.isLightMode
          ? Colors.orange.withOpacity(0.05)
          : Colors.orange.withOpacity(0.1),
      padding: EdgeInsets.all(12.sp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '人工评估',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.bold,
              color: widget.isLightMode ? Colors.black87 : Colors.white,
            ),
          ),
          SizedBox(height: 12.sp),
          if (widget.log.functionResults.containsKey('foa'))
            _buildFoAEvaluation(),
          if (widget.log.functionResults.containsKey('todo'))
            _buildTodoEvaluation(),
          if (widget.log.functionResults.containsKey('recommendations'))
            _buildRecommendationEvaluation(),
          if (widget.log.functionResults.containsKey('cognitiveLoad'))
            _buildCognitiveLoadEvaluation(),
          if (widget.log.functionResults.containsKey('summaries'))
            _buildSummaryEvaluation(),
          if (widget.log.functionResults.containsKey('kg') || widget.log.functionResults.containsKey('kgStatus'))
            _buildKGEvaluation(),
        ],
      ),
    );
  }

  Widget _buildFoAEvaluation() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FoA是否正确:',
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
            color: widget.isLightMode ? Colors.black87 : Colors.white,
          ),
        ),
        SizedBox(height: 6.sp),
        Wrap(
          spacing: 8.sp,
          children: [1, 2, 3, 4, 5].map((score) {
            final isSelected = _currentEvaluation?.foaScore == score;
            return GestureDetector(
              onTap: () {
                final newEvaluation = UserEvaluation(
                  foaScore: score,
                  todoCorrect: _currentEvaluation?.todoCorrect,
                  recommendationRelevance: _currentEvaluation?.recommendationRelevance,
                  cognitiveLoadReasonability: _currentEvaluation?.cognitiveLoadReasonability,
                  evaluatedAt: DateTime.now(),
                  notes: _currentEvaluation?.notes,
                );
                _updateEvaluation(newEvaluation);
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 4.sp),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue : Colors.transparent,
                  border: Border.all(color: Colors.blue),
                  borderRadius: BorderRadius.circular(4.r),
                ),
                child: Text(
                  score.toString(),
                  style: TextStyle(
                    fontSize: 10.sp,
                    color: isSelected ? Colors.white : Colors.blue,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        SizedBox(height: 12.sp),
      ],
    );
  }

  Widget _buildTodoEvaluation() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Todo是否正确:',
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
            color: widget.isLightMode ? Colors.black87 : Colors.white,
          ),
        ),
        SizedBox(height: 6.sp),
        Row(
          children: [
            _buildBooleanButton(
              label: '✅ 正确',
              isSelected: _currentEvaluation?.todoCorrect == true,
              color: Colors.green,
              onTap: () => _updateTodoEvaluation(true),
            ),
            SizedBox(width: 8.sp),
            _buildBooleanButton(
              label: '❌ 错误',
              isSelected: _currentEvaluation?.todoCorrect == false,
              color: Colors.red,
              onTap: () => _updateTodoEvaluation(false),
            ),
          ],
        ),
        SizedBox(height: 12.sp),
      ],
    );
  }

  Widget _buildRecommendationEvaluation() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '主动推荐相关性 (1-5分):',
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
            color: widget.isLightMode ? Colors.black87 : Colors.white,
          ),
        ),
        SizedBox(height: 6.sp),
        Wrap(
          spacing: 6.sp,
          children: List.generate(5, (index) {
            final score = index + 1;
            final isSelected = _currentEvaluation?.recommendationRelevance == score;
            return _buildScoreButton(
              score: score,
              isSelected: isSelected,
              color: Colors.orange,
              onTap: () => _updateRecommendationEvaluation(score),
            );
          }),
        ),
        SizedBox(height: 12.sp),
      ],
    );
  }

  Widget _buildCognitiveLoadEvaluation() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '认知负载合理性 (1-5分):',
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
            color: widget.isLightMode ? Colors.black87 : Colors.white,
          ),
        ),
        SizedBox(height: 6.sp),
        Wrap(
          spacing: 6.sp,
          children: List.generate(5, (index) {
            final score = index + 1;
            final isSelected = _currentEvaluation?.cognitiveLoadReasonability == score;
            return _buildScoreButton(
              score: score,
              isSelected: isSelected,
              color: Colors.purple,
              onTap: () => _updateCognitiveLoadEvaluation(score),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildSummaryEvaluation() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '总结内容相关性 (1-5分):',
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
            color: widget.isLightMode ? Colors.black87 : Colors.white,
          ),
        ),
        SizedBox(height: 6.sp),
        Wrap(
          spacing: 6.sp,
          children: List.generate(5, (index) {
            final score = index + 1;
            final isSelected = _currentEvaluation?.summaryRelevance == score;
            return _buildScoreButton(
              score: score,
              isSelected: isSelected,
              color: Colors.teal,
              onTap: () => _updateSummaryEvaluation(score),
            );
          }),
        ),
        SizedBox(height: 12.sp),
      ],
    );
  }

  Widget _buildKGEvaluation() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '知识图谱内容准确性 (1-5分):',
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
            color: widget.isLightMode ? Colors.black87 : Colors.white,
          ),
        ),
        SizedBox(height: 6.sp),
        Wrap(
          spacing: 6.sp,
          children: List.generate(5, (index) {
            final score = index + 1;
            final isSelected = _currentEvaluation?.kgAccuracy == score;
            return _buildScoreButton(
              score: score,
              isSelected: isSelected,
              color: Colors.indigo,
              onTap: () => _updateKGEvaluation(score),
            );
          }),
        ),
        SizedBox(height: 12.sp),
      ],
    );
  }

  Widget _buildScoreButton({
    required int score,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24.sp,
        height: 24.sp,
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

  Widget _buildBooleanButton({
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 6.sp),
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

  void _updateTodoEvaluation(bool isCorrect) {
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

  void _updateRecommendationEvaluation(int score) {
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

  void _updateCognitiveLoadEvaluation(int score) {
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

  void _updateSummaryEvaluation(int score) {
    final newEvaluation = UserEvaluation(
      foaScore: _currentEvaluation?.foaScore,
      todoCorrect: _currentEvaluation?.todoCorrect,
      recommendationRelevance: _currentEvaluation?.recommendationRelevance,
      cognitiveLoadReasonability: _currentEvaluation?.cognitiveLoadReasonability,
      summaryRelevance: score,
      kgAccuracy: _currentEvaluation?.kgAccuracy,
      evaluatedAt: DateTime.now(),
      notes: _currentEvaluation?.notes,
    );
    _updateEvaluation(newEvaluation);
  }

  void _updateKGEvaluation(int score) {
    final newEvaluation = UserEvaluation(
      foaScore: _currentEvaluation?.foaScore,
      todoCorrect: _currentEvaluation?.todoCorrect,
      recommendationRelevance: _currentEvaluation?.recommendationRelevance,
      cognitiveLoadReasonability: _currentEvaluation?.cognitiveLoadReasonability,
      summaryRelevance: _currentEvaluation?.summaryRelevance,
      kgAccuracy: score,
      evaluatedAt: DateTime.now(),
      notes: _currentEvaluation?.notes,
    );
    _updateEvaluation(newEvaluation);
  }
}
