/// 智能提醒管理界面
/// 显示所有自然语言提醒，支持查看、编辑、删除和手动创建

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:app/services/natural_language_reminder_service.dart';
import 'package:app/services/intelligent_reminder_manager.dart';
import 'dart:async';

// 提醒项目数据模型
class ReminderItem {
  final String id;
  final String title;
  final String description;
  final DateTime reminderTime;
  final bool isCompleted;
  final String originalText;
  final DateTime createdAt;

  ReminderItem({
    required this.id,
    required this.title,
    required this.description,
    required this.reminderTime,
    this.isCompleted = false,
    this.originalText = '',
    required this.createdAt,
  });

  ReminderItem copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? reminderTime,
    bool? isCompleted,
    String? originalText,
    DateTime? createdAt,
  }) {
    return ReminderItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      reminderTime: reminderTime ?? this.reminderTime,
      isCompleted: isCompleted ?? this.isCompleted,
      originalText: originalText ?? this.originalText,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'reminderTime': reminderTime.toIso8601String(),
      'isCompleted': isCompleted,
      'originalText': originalText,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ReminderItem.fromJson(Map<String, dynamic> json) {
    return ReminderItem(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      reminderTime: DateTime.parse(json['reminderTime']),
      isCompleted: json['isCompleted'] ?? false,
      originalText: json['originalText'] ?? '',
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

class ReminderManagementScreen extends StatefulWidget {
  const ReminderManagementScreen({super.key});

  @override
  State<ReminderManagementScreen> createState() => _ReminderManagementScreenState();
}

class _ReminderManagementScreenState extends State<ReminderManagementScreen>
    with TickerProviderStateMixin {

  final IntelligentReminderManager _reminderManager = IntelligentReminderManager();
  late NaturalLanguageReminderService _nlReminderService;

  late TabController _tabController;
  StreamSubscription? _reminderSubscription;

  List<ReminderItem> _allReminders = [];
  List<ReminderItem> _activeReminders = [];
  List<ReminderItem> _completedReminders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _nlReminderService = _reminderManager.naturalLanguageReminderService;
    _initializeData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _reminderSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeData() async {
    try {
      // 监听提醒更新
      _reminderSubscription = _nlReminderService.remindersStream.listen((reminders) {
        if (mounted) {
          setState(() {
            _updateReminderLists(reminders);
            _isLoading = false;
          });
        }
      });

      // 加载现有提醒
      await _loadReminders();
    } catch (e) {
      print('[ReminderScreen] 初始化失败: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadReminders() async {
    try {
      // 这里应该从存储中加载提醒，暂时使用示例数据
      final sampleReminders = [
        ReminderItem(
          id: '1',
          title: '面试准备',
          description: '明天晚上八点半约了面试',
          reminderTime: DateTime.now().add(Duration(days: 1)).copyWith(hour: 20, minute: 30),
          originalText: '明天晚上八点半约了面试',
          createdAt: DateTime.now(),
        ),
        ReminderItem(
          id: '2',
          title: '检查老板状态',
          description: '一分钟后去看一下老板还在不在',
          reminderTime: DateTime.now().add(Duration(minutes: 1)),
          originalText: '一分钟后去看一下老板还在不在',
          createdAt: DateTime.now(),
        ),
      ];

      setState(() {
        _updateReminderLists(sampleReminders);
        _isLoading = false;
      });
    } catch (e) {
      print('[ReminderScreen] 加载提醒失败: $e');
    }
  }

  void _updateReminderLists(List<ReminderItem> reminders) {
    _allReminders = reminders;
    _activeReminders = reminders.where((r) => !r.isCompleted).toList();
    _completedReminders = reminders.where((r) => r.isCompleted).toList();

    // 按时间排序
    _activeReminders.sort((a, b) => a.reminderTime.compareTo(b.reminderTime));
    _completedReminders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: Column(
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAllRemindersTab(),
                _buildActiveRemindersTab(),
                _buildCompletedRemindersTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddReminderDialog,
        child: Icon(Icons.add),
        tooltip: '手动添加提醒',
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.all(16.w),
      child: Row(
        children: [
          Icon(Icons.notifications, size: 24.sp, color: Colors.blue),
          SizedBox(width: 8.w),
          Text(
            '智能提醒管理',
            style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
          ),
          Spacer(),
          _buildStatsChip(),
        ],
      ),
    );
  }

  Widget _buildStatsChip() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 16.sp, color: Colors.green),
          SizedBox(width: 4.w),
          Text(
            '${_activeReminders.length}活跃',
            style: TextStyle(fontSize: 12.sp, color: Colors.green),
          ),
          SizedBox(width: 8.w),
          Icon(Icons.done_all, size: 16.sp, color: Colors.grey),
          SizedBox(width: 4.w),
          Text(
            '${_completedReminders.length}完成',
            style: TextStyle(fontSize: 12.sp, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.grey[100],
      child: TabBar(
        controller: _tabController,
        labelColor: Colors.blue,
        unselectedLabelColor: Colors.grey,
        indicatorColor: Colors.blue,
        tabs: [
          Tab(text: '全部 (${_allReminders.length})'),
          Tab(text: '活跃 (${_activeReminders.length})'),
          Tab(text: '已完成 (${_completedReminders.length})'),
        ],
      ),
    );
  }

  Widget _buildAllRemindersTab() {
    return _buildReminderList(_allReminders);
  }

  Widget _buildActiveRemindersTab() {
    return _buildReminderList(_activeReminders);
  }

  Widget _buildCompletedRemindersTab() {
    return _buildReminderList(_completedReminders);
  }

  Widget _buildReminderList(List<ReminderItem> reminders) {
    if (reminders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 64.sp, color: Colors.grey),
            SizedBox(height: 16.h),
            Text(
              '暂无提醒',
              style: TextStyle(fontSize: 16.sp, color: Colors.grey),
            ),
            SizedBox(height: 8.h),
            Text(
              '试试说"明天上午10点开会"来创建提醒',
              style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: reminders.length,
      itemBuilder: (context, index) => _buildReminderCard(reminders[index]),
    );
  }

  Widget _buildReminderCard(ReminderItem reminder) {
    final isOverdue = !reminder.isCompleted && reminder.reminderTime.isBefore(DateTime.now());
    final isUpcoming = !reminder.isCompleted &&
        reminder.reminderTime.isAfter(DateTime.now()) &&
        reminder.reminderTime.isBefore(DateTime.now().add(Duration(hours: 2)));

    return Card(
      margin: EdgeInsets.only(bottom: 12.h),
      elevation: reminder.isCompleted ? 1 : 3,
      child: InkWell(
        onTap: () => _showReminderDetails(reminder),
        borderRadius: BorderRadius.circular(8.r),
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  Expanded(
                    child: Text(
                      reminder.title,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        decoration: reminder.isCompleted ? TextDecoration.lineThrough : null,
                        color: reminder.isCompleted ? Colors.grey : null,
                      ),
                    ),
                  ),
                  if (isOverdue)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Text(
                        '已过期',
                        style: TextStyle(fontSize: 10.sp, color: Colors.white),
                      ),
                    ),
                  if (isUpcoming)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Text(
                        '即将到期',
                        style: TextStyle(fontSize: 10.sp, color: Colors.white),
                      ),
                    ),
                  PopupMenuButton<String>(
                    onSelected: (value) => _handleReminderAction(value, reminder),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 16.sp),
                            SizedBox(width: 8.w),
                            Text('编辑'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: reminder.isCompleted ? 'uncomplete' : 'complete',
                        child: Row(
                          children: [
                            Icon(
                              reminder.isCompleted ? Icons.undo : Icons.check,
                              size: 16.sp,
                            ),
                            SizedBox(width: 8.w),
                            Text(reminder.isCompleted ? '标记未完成' : '标记完成'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 16.sp, color: Colors.red),
                            SizedBox(width: 8.w),
                            Text('删除', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // 描述
              if (reminder.description.isNotEmpty) ...[
                SizedBox(height: 8.h),
                Text(
                  reminder.description,
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: Colors.grey[600],
                    decoration: reminder.isCompleted ? TextDecoration.lineThrough : null,
                  ),
                ),
              ],

              SizedBox(height: 12.h),

              // 时间和状态信息
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 16.sp,
                    color: isOverdue ? Colors.red : Colors.grey[600],
                  ),
                  SizedBox(width: 4.w),
                  Text(
                    _formatReminderTime(reminder.reminderTime),
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: isOverdue ? Colors.red : Colors.grey[600],
                      fontWeight: isOverdue ? FontWeight.w600 : null,
                    ),
                  ),
                  Spacer(),
                  if (reminder.originalText.isNotEmpty)
                    Icon(Icons.record_voice_over, size: 16.sp, color: Colors.blue),
                ],
              ),

              // 原始文本（如果是自然语言创建的）
              if (reminder.originalText.isNotEmpty) ...[
                SizedBox(height: 8.h),
                Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6.r),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.format_quote, size: 14.sp, color: Colors.blue),
                      SizedBox(width: 4.w),
                      Expanded(
                        child: Text(
                          '"${reminder.originalText}"',
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: Colors.blue[700],
                            fontStyle: FontStyle.italic,
                          ),
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
    );
  }

  String _formatReminderTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = dateTime.difference(now);

    if (difference.isNegative) {
      // 已过期
      final absDifference = difference.abs();
      if (absDifference.inDays > 0) {
        return '${absDifference.inDays}天前过期';
      } else if (absDifference.inHours > 0) {
        return '${absDifference.inHours}小时前过期';
      } else {
        return '${absDifference.inMinutes}分钟前过期';
      }
    } else {
      // 未来时间
      if (difference.inDays > 0) {
        return '${difference.inDays}天后 ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}小时后';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}分钟后';
      } else {
        return '即将到期';
      }
    }
  }

  void _handleReminderAction(String action, ReminderItem reminder) {
    switch (action) {
      case 'edit':
        _showEditReminderDialog(reminder);
        break;
      case 'complete':
        _toggleReminderComplete(reminder, true);
        break;
      case 'uncomplete':
        _toggleReminderComplete(reminder, false);
        break;
      case 'delete':
        _deleteReminder(reminder);
        break;
    }
  }

  void _showReminderDetails(ReminderItem reminder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(reminder.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reminder.description.isNotEmpty) ...[
              Text('描述:', style: TextStyle(fontWeight: FontWeight.w600)),
              Text(reminder.description),
              SizedBox(height: 12.h),
            ],
            Text('提醒时间:', style: TextStyle(fontWeight: FontWeight.w600)),
            Text(_formatReminderTime(reminder.reminderTime)),
            SizedBox(height: 12.h),
            Text('创建时间:', style: TextStyle(fontWeight: FontWeight.w600)),
            Text('${reminder.createdAt.year}-${reminder.createdAt.month.toString().padLeft(2, '0')}-${reminder.createdAt.day.toString().padLeft(2, '0')} ${reminder.createdAt.hour.toString().padLeft(2, '0')}:${reminder.createdAt.minute.toString().padLeft(2, '0')}'),
            if (reminder.originalText.isNotEmpty) ...[
              SizedBox(height: 12.h),
              Text('原始语音:', style: TextStyle(fontWeight: FontWeight.w600)),
              Text('"${reminder.originalText}"', style: TextStyle(fontStyle: FontStyle.italic)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('关闭'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showEditReminderDialog(reminder);
            },
            child: Text('编辑'),
          ),
        ],
      ),
    );
  }

  void _showAddReminderDialog() {
    String title = '';
    String description = '';
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('手动添加提醒'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: InputDecoration(
                    labelText: '标题 *',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => title = value,
                ),
                SizedBox(height: 12.h),
                TextField(
                  decoration: InputDecoration(
                    labelText: '描述',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  onChanged: (value) => description = value,
                ),
                SizedBox(height: 16.h),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() => selectedDate = picked);
                          }
                        },
                        icon: Icon(Icons.calendar_today),
                        label: Text('${selectedDate.month}/${selectedDate.day}'),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: selectedTime,
                          );
                          if (picked != null) {
                            setState(() => selectedTime = picked);
                          }
                        },
                        icon: Icon(Icons.access_time),
                        label: Text(selectedTime.format(context)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('取消'),
            ),
            ElevatedButton(
              onPressed: title.isNotEmpty ? () {
                _addReminder(ReminderItem(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  title: title,
                  description: description,
                  reminderTime: DateTime(
                    selectedDate.year,
                    selectedDate.month,
                    selectedDate.day,
                    selectedTime.hour,
                    selectedTime.minute,
                  ),
                  createdAt: DateTime.now(),
                ));
                Navigator.pop(context);
              } : null,
              child: Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditReminderDialog(ReminderItem reminder) {
    String title = reminder.title;
    String description = reminder.description;
    DateTime selectedDate = reminder.reminderTime;
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(reminder.reminderTime);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('编辑提醒'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: InputDecoration(
                    labelText: '标题 *',
                    border: OutlineInputBorder(),
                  ),
                  controller: TextEditingController(text: title),
                  onChanged: (value) => title = value,
                ),
                SizedBox(height: 12.h),
                TextField(
                  decoration: InputDecoration(
                    labelText: '描述',
                    border: OutlineInputBorder(),
                  ),
                  controller: TextEditingController(text: description),
                  maxLines: 3,
                  onChanged: (value) => description = value,
                ),
                SizedBox(height: 16.h),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() => selectedDate = picked);
                          }
                        },
                        icon: Icon(Icons.calendar_today),
                        label: Text('${selectedDate.month}/${selectedDate.day}'),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: selectedTime,
                          );
                          if (picked != null) {
                            setState(() => selectedTime = picked);
                          }
                        },
                        icon: Icon(Icons.access_time),
                        label: Text(selectedTime.format(context)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                _updateReminder(reminder.copyWith(
                  title: title,
                  description: description,
                  reminderTime: DateTime(
                    selectedDate.year,
                    selectedDate.month,
                    selectedDate.day,
                    selectedTime.hour,
                    selectedTime.minute,
                  ),
                ));
                Navigator.pop(context);
              },
              child: Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _addReminder(ReminderItem reminder) {
    setState(() {
      _allReminders.add(reminder);
      _updateReminderLists(_allReminders);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('提醒已添加')),
    );
  }

  void _updateReminder(ReminderItem updatedReminder) {
    setState(() {
      final index = _allReminders.indexWhere((r) => r.id == updatedReminder.id);
      if (index != -1) {
        _allReminders[index] = updatedReminder;
        _updateReminderLists(_allReminders);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('提醒已更新')),
    );
  }

  void _toggleReminderComplete(ReminderItem reminder, bool isCompleted) {
    setState(() {
      final index = _allReminders.indexWhere((r) => r.id == reminder.id);
      if (index != -1) {
        _allReminders[index] = reminder.copyWith(isCompleted: isCompleted);
        _updateReminderLists(_allReminders);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(isCompleted ? '提醒已完成' : '提醒已标记为未完成')),
    );
  }

  void _deleteReminder(ReminderItem reminder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除'),
        content: Text('确定要删除提醒"${reminder.title}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _allReminders.removeWhere((r) => r.id == reminder.id);
                _updateReminderLists(_allReminders);
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('提醒已删除')),
              );
            },
            child: Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
