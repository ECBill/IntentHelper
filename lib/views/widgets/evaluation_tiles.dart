/// 评分组件 - 包含各个模块的评分界面
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:app/models/log_evaluation_models.dart';
import 'package:app/views/ui/bud_card.dart';

/// FoA条目组件 - 包含4档评分系统
class FoAEntryTile extends StatefulWidget {
  final FoAEntry entry;
  final bool isLightMode;
  final Function(UserEvaluation) onEvaluationChanged;

  const FoAEntryTile({
    super.key,
    required this.entry,
    required this.isLightMode,
    required this.onEvaluationChanged,
  });

  @override
  State<FoAEntryTile> createState() => _FoAEntryTileState();
}

class _FoAEntryTileState extends State<FoAEntryTile> {
  UserEvaluation? _currentEvaluation;

  @override
  void initState() {
    super.initState();
    _currentEvaluation = widget.entry.evaluation;
  }

  void _updateEvaluation(UserEvaluation evaluation) {
    setState(() => _currentEvaluation = evaluation);
    widget.onEvaluationChanged(evaluation);
  }

  @override
  Widget build(BuildContext context) {
    return BudCard(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(16.w),
      color: widget.isLightMode ? Colors.white : Colors.grey[800],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '主题: ${widget.entry.topics.join(', ')}',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                    color: widget.isLightMode ? Colors.black : Colors.white,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  '置信度: ${(widget.entry.confidence * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            DateFormat('yyyy-MM-dd HH:mm:ss').format(widget.entry.timestamp),
            style: TextStyle(
              fontSize: 12.sp,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            '相关内容: ${widget.entry.relatedContent}',
            style: TextStyle(
              fontSize: 14.sp,
              color: widget.isLightMode ? Colors.black87 : Colors.white70,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 16.h),
          Text(
            'FoA识别是否正确:',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: widget.isLightMode ? Colors.black87 : Colors.white,
            ),
          ),
          SizedBox(height: 8.h),
          _buildFoAScoreButtons(),
        ],
      ),
    );
  }

  Widget _buildFoAScoreButtons() {
    final scores = [
      {'label': '基本正确', 'value': 1.0, 'color': Colors.green},
      {'label': '比较正确', 'value': 0.75, 'color': Colors.lightGreen},
      {'label': '不太正确', 'value': 0.5, 'color': Colors.orange},
      {'label': '基本不正确', 'value': 0.0, 'color': Colors.red},
    ];

    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: scores.map((score) {
        final isSelected = _currentEvaluation?.foaScore == score['value'];
        final color = score['color'] as Color;

        return GestureDetector(
          onTap: () => _updateFoAScore(score['value'] as double),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: isSelected ? color : Colors.transparent,
              border: Border.all(color: color),
              borderRadius: BorderRadius.circular(6.r),
            ),
            child: Text(
              score['label'] as String,
              style: TextStyle(
                fontSize: 12.sp,
                color: isSelected ? Colors.white : color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _updateFoAScore(double score) {
    final newEvaluation = UserEvaluation(
      foaScore: score, // 改为 score（保持double类型）
      todoCorrect: _currentEvaluation?.todoCorrect,
      recommendationRelevance: _currentEvaluation?.recommendationRelevance,
      cognitiveLoadReasonability: _currentEvaluation?.cognitiveLoadReasonability,
      summaryRelevance: _currentEvaluation?.summaryRelevance,
      kgAccuracy: _currentEvaluation?.kgAccuracy,
      evaluatedAt: DateTime.now(),
      notes: _currentEvaluation?.notes,
    );
    _updateEvaluation(newEvaluation);
  }
}

/// Todo条目组件 - 包含正确/错误评分
class TodoEntryTile extends StatefulWidget {
  final TodoEntry entry;
  final bool isLightMode;
  final Function(UserEvaluation) onEvaluationChanged;

  const TodoEntryTile({
    super.key,
    required this.entry,
    required this.isLightMode,
    required this.onEvaluationChanged,
  });

  @override
  State<TodoEntryTile> createState() => _TodoEntryTileState();
}

class _TodoEntryTileState extends State<TodoEntryTile> {
  UserEvaluation? _currentEvaluation;

  @override
  void initState() {
    super.initState();
    _currentEvaluation = widget.entry.evaluation;
  }

  void _updateEvaluation(UserEvaluation evaluation) {
    setState(() => _currentEvaluation = evaluation);
    widget.onEvaluationChanged(evaluation);
  }

  @override
  Widget build(BuildContext context) {
    return BudCard(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(16.w),
      color: widget.isLightMode ? Colors.white : Colors.grey[800],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Todo: ${widget.entry.task}',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                    color: widget.isLightMode ? Colors.black : Colors.white,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  '置信度: ${(widget.entry.confidence * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            DateFormat('yyyy-MM-dd HH:mm:ss').format(widget.entry.timestamp),
            style: TextStyle(
              fontSize: 12.sp,
              color: Colors.grey,
            ),
          ),
          if (widget.entry.deadline != null) ...[
            SizedBox(height: 4.h),
            Text(
              '截止时间: ${DateFormat('yyyy-MM-dd HH:mm').format(widget.entry.deadline!)}',
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.orange,
              ),
            ),
          ],
          SizedBox(height: 8.h),
          Text(
            '相关内容: ${widget.entry.relatedContent}',
            style: TextStyle(
              fontSize: 14.sp,
              color: widget.isLightMode ? Colors.black87 : Colors.white70,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 16.h),
          Text(
            'Todo是否正确:',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: widget.isLightMode ? Colors.black87 : Colors.white,
            ),
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              _buildBooleanButton(
                label: '✅ 正确',
                isSelected: _currentEvaluation?.todoCorrect == true,
                color: Colors.green,
                onTap: () => _updateTodoCorrectness(true),
              ),
              SizedBox(width: 12.w),
              _buildBooleanButton(
                label: '❌ 错误',
                isSelected: _currentEvaluation?.todoCorrect == false,
                color: Colors.red,
                onTap: () => _updateTodoCorrectness(false),
              ),
            ],
          ),
        ],
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
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(6.r),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14.sp,
            color: isSelected ? Colors.white : color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _updateTodoCorrectness(bool isCorrect) {
    final newEvaluation = UserEvaluation(
      foaScore: _currentEvaluation?.foaScore,
      todoCorrect: isCorrect,
      recommendationRelevance: _currentEvaluation?.recommendationRelevance,
      cognitiveLoadReasonability: _currentEvaluation?.cognitiveLoadReasonability,
      summaryRelevance: _currentEvaluation?.summaryRelevance,
      kgAccuracy: _currentEvaluation?.kgAccuracy,
      evaluatedAt: DateTime.now(),
      notes: _currentEvaluation?.notes,
    );
    _updateEvaluation(newEvaluation);
  }
}

/// 智能推荐条目组件 - 包含1-5分评分
class RecommendationEntryTile extends StatefulWidget {
  final RecommendationEntry entry;
  final bool isLightMode;
  final Function(UserEvaluation) onEvaluationChanged;

  const RecommendationEntryTile({
    super.key,
    required this.entry,
    required this.isLightMode,
    required this.onEvaluationChanged,
  });

  @override
  State<RecommendationEntryTile> createState() => _RecommendationEntryTileState();
}

class _RecommendationEntryTileState extends State<RecommendationEntryTile> {
  UserEvaluation? _currentEvaluation;

  @override
  void initState() {
    super.initState();
    _currentEvaluation = widget.entry.evaluation;
  }

  void _updateEvaluation(UserEvaluation evaluation) {
    setState(() => _currentEvaluation = evaluation);
    widget.onEvaluationChanged(evaluation);
  }

  @override
  Widget build(BuildContext context) {
    return BudCard(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(16.w),
      color: widget.isLightMode ? Colors.white : Colors.grey[800],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '智能推荐',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                    color: widget.isLightMode ? Colors.black : Colors.white,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  '来源: ${widget.entry.source}',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.orange,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            DateFormat('yyyy-MM-dd HH:mm:ss').format(widget.entry.timestamp),
            style: TextStyle(
              fontSize: 12.sp,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            '推荐内容: ${widget.entry.content}',
            style: TextStyle(
              fontSize: 14.sp,
              color: widget.isLightMode ? Colors.black87 : Colors.white70,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 16.h),
          Text(
            '推荐相关性评分 (1-5分):',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: widget.isLightMode ? Colors.black87 : Colors.white,
            ),
          ),
          SizedBox(height: 8.h),
          _buildScoreButtons(
            currentScore: _currentEvaluation?.recommendationRelevance,
            color: Colors.orange,
            onScoreChanged: _updateRecommendationRelevance,
          ),
        ],
      ),
    );
  }

  Widget _buildScoreButtons({
    required int? currentScore,
    required Color color,
    required Function(int) onScoreChanged,
  }) {
    return Wrap(
      spacing: 8.w,
      children: List.generate(5, (index) {
        final score = index + 1;
        final isSelected = currentScore == score;
        return GestureDetector(
          onTap: () => onScoreChanged(score),
          child: Container(
            width: 32.w,
            height: 32.h,
            decoration: BoxDecoration(
              color: isSelected ? color : Colors.transparent,
              border: Border.all(color: color),
              borderRadius: BorderRadius.circular(6.r),
            ),
            child: Center(
              child: Text(
                score.toString(),
                style: TextStyle(
                  fontSize: 14.sp,
                  color: isSelected ? Colors.white : color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  void _updateRecommendationRelevance(int score) {
    final newEvaluation = UserEvaluation(
      foaScore: _currentEvaluation?.foaScore,
      todoCorrect: _currentEvaluation?.todoCorrect,
      recommendationRelevance: score,
      cognitiveLoadReasonability: _currentEvaluation?.cognitiveLoadReasonability,
      summaryRelevance: _currentEvaluation?.summaryRelevance,
      kgAccuracy: _currentEvaluation?.kgAccuracy,
      evaluatedAt: DateTime.now(),
      notes: _currentEvaluation?.notes,
    );
    _updateEvaluation(newEvaluation);
  }
}

/// 总结条目组件
class SummaryEntryTile extends StatefulWidget {
  final SummaryEntry entry;
  final bool isLightMode;
  final Function(UserEvaluation) onEvaluationChanged;

  const SummaryEntryTile({
    super.key,
    required this.entry,
    required this.isLightMode,
    required this.onEvaluationChanged,
  });

  @override
  State<SummaryEntryTile> createState() => _SummaryEntryTileState();
}

class _SummaryEntryTileState extends State<SummaryEntryTile> {
  UserEvaluation? _currentEvaluation;

  @override
  void initState() {
    super.initState();
    _currentEvaluation = widget.entry.evaluation;
  }

  void _updateEvaluation(UserEvaluation evaluation) {
    setState(() => _currentEvaluation = evaluation);
    widget.onEvaluationChanged(evaluation);
  }

  @override
  Widget build(BuildContext context) {
    return BudCard(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(16.w),
      color: widget.isLightMode ? Colors.white : Colors.grey[800],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '总结: ${widget.entry.subject}',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: widget.isLightMode ? Colors.black : Colors.white,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            DateFormat('yyyy-MM-dd HH:mm:ss').format(widget.entry.timestamp),
            style: TextStyle(
              fontSize: 12.sp,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            '总结内容: ${widget.entry.content}',
            style: TextStyle(
              fontSize: 14.sp,
              color: widget.isLightMode ? Colors.black87 : Colors.white70,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 16.h),
          Text(
            '总结质量评分 (1-5分):',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: widget.isLightMode ? Colors.black87 : Colors.white,
            ),
          ),
          SizedBox(height: 8.h),
          _buildScoreButtons(
            currentScore: _currentEvaluation?.summaryRelevance,
            color: Colors.teal,
            onScoreChanged: _updateSummaryRelevance,
          ),
        ],
      ),
    );
  }

  Widget _buildScoreButtons({
    required int? currentScore,
    required Color color,
    required Function(int) onScoreChanged,
  }) {
    return Wrap(
      spacing: 8.w,
      children: List.generate(5, (index) {
        final score = index + 1;
        final isSelected = currentScore == score;
        return GestureDetector(
          onTap: () => onScoreChanged(score),
          child: Container(
            width: 32.w,
            height: 32.h,
            decoration: BoxDecoration(
              color: isSelected ? color : Colors.transparent,
              border: Border.all(color: color),
              borderRadius: BorderRadius.circular(6.r),
            ),
            child: Center(
              child: Text(
                score.toString(),
                style: TextStyle(
                  fontSize: 14.sp,
                  color: isSelected ? Colors.white : color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  void _updateSummaryRelevance(int score) {
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
}

/// 知识图谱条目组件
class KGEntryTile extends StatefulWidget {
  final KGEntry entry;
  final bool isLightMode;
  final Function(UserEvaluation) onEvaluationChanged;

  const KGEntryTile({
    super.key,
    required this.entry,
    required this.isLightMode,
    required this.onEvaluationChanged,
  });

  @override
  State<KGEntryTile> createState() => _KGEntryTileState();
}

class _KGEntryTileState extends State<KGEntryTile> {
  UserEvaluation? _currentEvaluation;

  @override
  void initState() {
    super.initState();
    _currentEvaluation = widget.entry.evaluation;
  }

  void _updateEvaluation(UserEvaluation evaluation) {
    setState(() => _currentEvaluation = evaluation);
    widget.onEvaluationChanged(evaluation);
  }

  @override
  Widget build(BuildContext context) {
    return BudCard(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(16.w),
      color: widget.isLightMode ? Colors.white : Colors.grey[800],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '知识图谱: ${widget.entry.nodeType}',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                    color: widget.isLightMode ? Colors.black : Colors.white,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  '类型: ${widget.entry.nodeType}',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.indigo,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            DateFormat('yyyy-MM-dd HH:mm:ss').format(widget.entry.timestamp),
            style: TextStyle(
              fontSize: 12.sp,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            '内容: ${widget.entry.content}',
            style: TextStyle(
              fontSize: 14.sp,
              color: widget.isLightMode ? Colors.black87 : Colors.white70,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 16.h),
          Text(
            'KG准确性评分 (1-5分):',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: widget.isLightMode ? Colors.black87 : Colors.white,
            ),
          ),
          SizedBox(height: 8.h),
          _buildScoreButtons(
            currentScore: _currentEvaluation?.kgAccuracy,
            color: Colors.indigo,
            onScoreChanged: _updateKGAccuracy,
          ),
        ],
      ),
    );
  }

  Widget _buildScoreButtons({
    required int? currentScore,
    required Color color,
    required Function(int) onScoreChanged,
  }) {
    return Wrap(
      spacing: 8.w,
      children: List.generate(5, (index) {
        final score = index + 1;
        final isSelected = currentScore == score;
        return GestureDetector(
          onTap: () => onScoreChanged(score),
          child: Container(
            width: 32.w,
            height: 32.h,
            decoration: BoxDecoration(
              color: isSelected ? color : Colors.transparent,
              border: Border.all(color: color),
              borderRadius: BorderRadius.circular(6.r),
            ),
            child: Center(
              child: Text(
                score.toString(),
                style: TextStyle(
                  fontSize: 14.sp,
                  color: isSelected ? Colors.white : color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  void _updateKGAccuracy(int score) {
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

/// 认知负载条目组件 - 包含1-5分合理性评分
class CognitiveLoadEntryTile extends StatefulWidget {
  final CognitiveLoadEntry entry;
  final bool isLightMode;
  final Function(UserEvaluation) onEvaluationChanged;

  const CognitiveLoadEntryTile({
    super.key,
    required this.entry,
    required this.isLightMode,
    required this.onEvaluationChanged,
  });

  @override
  State<CognitiveLoadEntryTile> createState() => _CognitiveLoadEntryTileState();
}

class _CognitiveLoadEntryTileState extends State<CognitiveLoadEntryTile> {
  UserEvaluation? _currentEvaluation;

  @override
  void initState() {
    super.initState();
    _currentEvaluation = widget.entry.evaluation;
  }

  void _updateEvaluation(UserEvaluation evaluation) {
    setState(() => _currentEvaluation = evaluation);
    widget.onEvaluationChanged(evaluation);
  }

  @override
  Widget build(BuildContext context) {
    return BudCard(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(16.w),
      color: widget.isLightMode ? Colors.white : Colors.grey[800],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '认知负载分析',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                    color: widget.isLightMode ? Colors.black : Colors.white,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: _getLoadLevelColor().withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  '${widget.entry.level} (${(widget.entry.value * 100).toInt()}%)',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: _getLoadLevelColor(),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            DateFormat('yyyy-MM-dd HH:mm:ss').format(widget.entry.timestamp),
            style: TextStyle(
              fontSize: 12.sp,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            '相关内容: ${widget.entry.relatedContent}',
            style: TextStyle(
              fontSize: 14.sp,
              color: widget.isLightMode ? Colors.black87 : Colors.white70,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 16.h),
          Text(
            '负载合理性评分 (1-5分):',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: widget.isLightMode ? Colors.black87 : Colors.white,
            ),
          ),
          SizedBox(height: 8.h),
          _buildScoreButtons(
            currentScore: _currentEvaluation?.cognitiveLoadReasonability,
            color: Colors.purple,
            onScoreChanged: _updateCognitiveLoadReasonability,
          ),
        ],
      ),
    );
  }

  Widget _buildScoreButtons({
    required int? currentScore,
    required Color color,
    required Function(int) onScoreChanged,
  }) {
    return Wrap(
      spacing: 8.w,
      children: List.generate(5, (index) {
        final score = index + 1;
        final isSelected = currentScore == score;
        return GestureDetector(
          onTap: () => onScoreChanged(score),
          child: Container(
            width: 32.w,
            height: 32.h,
            decoration: BoxDecoration(
              color: isSelected ? color : Colors.transparent,
              border: Border.all(color: color),
              borderRadius: BorderRadius.circular(6.r),
            ),
            child: Center(
              child: Text(
                score.toString(),
                style: TextStyle(
                  fontSize: 14.sp,
                  color: isSelected ? Colors.white : color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Color _getLoadLevelColor() {
    switch (widget.entry.level) {
      case '高':
        return Colors.red;
      case '中等':
        return Colors.orange;
      case '低':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  void _updateCognitiveLoadReasonability(int score) {
    final newEvaluation = UserEvaluation(
      foaScore: _currentEvaluation?.foaScore,
      todoCorrect: _currentEvaluation?.todoCorrect,
      recommendationRelevance: _currentEvaluation?.recommendationRelevance,
      cognitiveLoadReasonability: score,
      summaryRelevance: _currentEvaluation?.summaryRelevance,
      kgAccuracy: _currentEvaluation?.kgAccuracy,
      evaluatedAt: DateTime.now(),
      notes: _currentEvaluation?.notes,
    );
    _updateEvaluation(newEvaluation);
  }
}
