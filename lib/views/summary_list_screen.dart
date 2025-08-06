import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../controllers/style_controller.dart';
import '../models/summary_entity.dart';
import '../services/objectbox_service.dart';
import '../utils/assets_util.dart';
import 'ui/bud_card.dart';
import 'ui/bud_icon.dart';
import 'ui/layout/bud_scaffold.dart';

class SummaryListScreen extends StatefulWidget {
  const SummaryListScreen({super.key});

  @override
  State<SummaryListScreen> createState() => _SummaryListScreenState();
}

class _SummaryListScreenState extends State<SummaryListScreen> {
  List<SummaryEntity> _summaries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSummaries();
  }

  Future<void> _loadSummaries() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final summaries = ObjectBoxService().getSummaries() ?? [];
      // 按创建时间倒序排列，最新的在前面
      summaries.sort((a, b) => (b.createdAt ?? 0).compareTo(a.createdAt ?? 0));

      setState(() {
        _summaries = summaries;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading summaries: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteSummary(SummaryEntity summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除摘要'),
        content: const Text('确定要删除这条摘要吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ObjectBoxService().deleteSummary(summary.id);
      _loadSummaries(); // 重新加载列表
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    bool isLightMode = themeNotifier.mode == Mode.light;

    return BudScaffold(
      title: '📋 对话摘要',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _summaries.isEmpty
              ? _buildEmptyState(isLightMode)
              : _buildSummaryList(isLightMode),
    );
  }

  Widget _buildEmptyState(bool isLightMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BudIcon(
            icon: AssetsUtil.icon_about,
            size: 64.sp,
          ),
          SizedBox(height: 16.sp),
          Text(
            '暂无对话摘要',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w500,
              color: isLightMode ? Colors.black54 : Colors.white54,
            ),
          ),
          SizedBox(height: 8.sp),
          Text(
            '当您与Buddie的对话达到一定长度时\n系统会自动生成摘要',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.sp,
              color: isLightMode ? Colors.black38 : Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryList(bool isLightMode) {
    return RefreshIndicator(
      onRefresh: _loadSummaries,
      child: ListView.builder(
        padding: EdgeInsets.all(16.sp),
        itemCount: _summaries.length,
        itemBuilder: (context, index) {
          final summary = _summaries[index];
          return _buildSummaryCard(summary, isLightMode);
        },
      ),
    );
  }

  Widget _buildSummaryCard(SummaryEntity summary, bool isLightMode) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.sp),
      child: BudCard(
        radius: 12.sp,
        color: isLightMode ? Colors.white : const Color(0xFF2A2A2A),
        padding: EdgeInsets.all(16.sp),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题和时间
            Row(
              children: [
                Expanded(
                  child: Text(
                    summary.subject ?? '无标题',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: isLightMode ? Colors.black87 : Colors.white,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'delete') {
                      _deleteSummary(summary);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 16),
                          SizedBox(width: 8),
                          Text('删除'),
                        ],
                      ),
                    ),
                  ],
                  child: Icon(
                    Icons.more_vert,
                    size: 20.sp,
                    color: isLightMode ? Colors.black54 : Colors.white54,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8.sp),

            // 时间范围
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 14.sp,
                  color: isLightMode ? Colors.black54 : Colors.white54,
                ),
                SizedBox(width: 4.sp),
                Text(
                  _formatTimeRange(summary.startTime, summary.endTime),
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: isLightMode ? Colors.black54 : Colors.white54,
                  ),
                ),
                SizedBox(width: 16.sp),
                Icon(
                  Icons.calendar_today,
                  size: 14.sp,
                  color: isLightMode ? Colors.black54 : Colors.white54,
                ),
                SizedBox(width: 4.sp),
                Text(
                  _formatCreatedDate(summary.createdAt ?? 0),
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: isLightMode ? Colors.black54 : Colors.white54,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.sp),

            // 摘要内容
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12.sp),
              decoration: BoxDecoration(
                color: isLightMode
                    ? const Color(0xFFF8F9FA)
                    : const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8.sp),
              ),
              child: Text(
                summary.content ?? '暂无内容',
                style: TextStyle(
                  fontSize: 14.sp,
                  height: 1.5,
                  color: isLightMode ? Colors.black87 : Colors.white70,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeRange(int startTime, int endTime) {
    final start = DateTime.fromMillisecondsSinceEpoch(startTime);
    final end = DateTime.fromMillisecondsSinceEpoch(endTime);
    final startStr = DateFormat('HH:mm').format(start);
    final endStr = DateFormat('HH:mm').format(end);
    return '$startStr - $endStr';
  }

  String _formatCreatedDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return '今天';
    } else if (difference.inDays == 1) {
      return '昨天';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else {
      return DateFormat('MM月dd日').format(date);
    }
  }
}
