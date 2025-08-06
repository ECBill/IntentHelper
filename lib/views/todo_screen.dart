import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controllers/todo_controller.dart';
import '../models/todo_entity.dart';
import '../services/objectbox_service.dart';

class TodoScreen extends StatefulWidget {
  final Status status;

  const TodoScreen({super.key, required this.status});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  List<TodoEntity> _allTodos = [];
  List<TodoEntity> _pendingTodos = [];
  List<TodoEntity> _completedTodos = [];
  List<TodoEntity> _expiredTodos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadTodos();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTodos() async {
    setState(() => _isLoading = true);

    try {
      final allTodos = ObjectBoxService().getAllTodos() ?? [];
      final now = DateTime.now().millisecondsSinceEpoch;

      setState(() {
        _allTodos = allTodos;
        _pendingTodos = allTodos.where((todo) =>
          todo.status == Status.pending &&
          (todo.deadline == null || todo.deadline! > now)
        ).toList();
        _completedTodos = allTodos.where((todo) => todo.status == Status.completed).toList();
        _expiredTodos = allTodos.where((todo) =>
          todo.status == Status.pending &&
          todo.deadline != null &&
          todo.deadline! <= now
        ).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorDialog('加载任务失败: $e');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('错误'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showAddTodoDialog() {
    final taskController = TextEditingController();
    final detailController = TextEditingController();
    DateTime? selectedDeadline;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加新任务'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: taskController,
                  decoration: const InputDecoration(
                    labelText: '任务标题',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: detailController,
                  decoration: const InputDecoration(
                    labelText: '任务详情',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        selectedDeadline == null
                          ? '未设置截止时间'
                          : '截止时间: ${DateFormat('yyyy-MM-dd HH:mm').format(selectedDeadline!)}',
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (date != null) {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.now(),
                          );
                          if (time != null) {
                            setDialogState(() {
                              selectedDeadline = DateTime(
                                date.year, date.month, date.day,
                                time.hour, time.minute,
                              );
                            });
                          }
                        }
                      },
                      child: const Text('设置时间'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                if (taskController.text.trim().isNotEmpty) {
                  _addTodo(
                    taskController.text.trim(),
                    detailController.text.trim(),
                    selectedDeadline,
                  );
                  Navigator.of(context).pop();
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  void _addTodo(String task, String detail, DateTime? deadline) {
    try {
      final todo = TodoEntity(
        task: task,
        detail: detail.isEmpty ? null : detail,
        deadline: deadline?.millisecondsSinceEpoch,
        status: Status.pending,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      ObjectBoxService().createTodos([todo]);
      _loadTodos();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('任务添加成功')),
      );
    } catch (e) {
      _showErrorDialog('添加任务失败: $e');
    }
  }

  void _updateTodoStatus(TodoEntity todo, Status newStatus) {
    try {
      todo.status = newStatus;
      ObjectBoxService().updateTodo(todo);
      _loadTodos();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('任务状态已更新为: ${_getStatusText(newStatus)}')),
      );
    } catch (e) {
      _showErrorDialog('更新任务状态失败: $e');
    }
  }

  void _deleteTodo(TodoEntity todo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除任务 "${todo.task}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              try {
                ObjectBoxService().deleteTodo(todo.id);
                _loadTodos();
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('任务删除成功')),
                );
              } catch (e) {
                Navigator.of(context).pop();
                _showErrorDialog('删除任务失败: $e');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _editTodo(TodoEntity todo) {
    final taskController = TextEditingController(text: todo.task);
    final detailController = TextEditingController(text: todo.detail ?? '');
    DateTime? selectedDeadline = todo.deadline != null
      ? DateTime.fromMillisecondsSinceEpoch(todo.deadline!)
      : null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('编辑任务'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: taskController,
                  decoration: const InputDecoration(
                    labelText: '任务标题',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: detailController,
                  decoration: const InputDecoration(
                    labelText: '任务详情',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        selectedDeadline == null
                          ? '未设置截止时间'
                          : '截止时间: ${DateFormat('yyyy-MM-dd HH:mm').format(selectedDeadline!)}',
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDeadline ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (date != null) {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: selectedDeadline != null
                              ? TimeOfDay.fromDateTime(selectedDeadline!)
                              : TimeOfDay.now(),
                          );
                          if (time != null) {
                            setDialogState(() {
                              selectedDeadline = DateTime(
                                date.year, date.month, date.day,
                                time.hour, time.minute,
                              );
                            });
                          }
                        }
                      },
                      child: const Text('修改时间'),
                    ),
                    if (selectedDeadline != null)
                      TextButton(
                        onPressed: () => setDialogState(() => selectedDeadline = null),
                        child: const Text('清除'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                if (taskController.text.trim().isNotEmpty) {
                  _updateTodo(
                    todo,
                    taskController.text.trim(),
                    detailController.text.trim(),
                    selectedDeadline,
                  );
                  Navigator.of(context).pop();
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _updateTodo(TodoEntity todo, String task, String detail, DateTime? deadline) {
    try {
      todo.task = task;
      todo.detail = detail.isEmpty ? null : detail;
      todo.deadline = deadline?.millisecondsSinceEpoch;

      ObjectBoxService().updateTodo(todo);
      _loadTodos();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('任务更新成功')),
      );
    } catch (e) {
      _showErrorDialog('更新任务失败: $e');
    }
  }

  String _getStatusText(Status status) {
    switch (status) {
      case Status.pending:
        return '待完成';
      case Status.completed:
        return '已完成';
      case Status.expired:
        return '已过期';
      case Status.all:
        return '全部';
    }
  }

  Color _getStatusColor(Status status) {
    switch (status) {
      case Status.pending:
        return Colors.orange;
      case Status.completed:
        return Colors.green;
      case Status.expired:
        return Colors.red;
      case Status.all:
        return Colors.blue;
    }
  }

  IconData _getStatusIcon(Status status) {
    switch (status) {
      case Status.pending:
        return Icons.schedule;
      case Status.completed:
        return Icons.check_circle;
      case Status.expired:
        return Icons.error;
      case Status.all:
        return Icons.list;
    }
  }

  Widget _buildTodoCard(TodoEntity todo) {
    final isExpired = todo.deadline != null &&
                     todo.deadline! <= DateTime.now().millisecondsSinceEpoch &&
                     todo.status == Status.pending;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    todo.task ?? '无标题',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      decoration: todo.status == Status.completed
                        ? TextDecoration.lineThrough
                        : null,
                      color: isExpired ? Colors.red : null,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        _editTodo(todo);
                        break;
                      case 'complete':
                        _updateTodoStatus(todo, Status.completed);
                        break;
                      case 'pending':
                        _updateTodoStatus(todo, Status.pending);
                        break;
                      case 'delete':
                        _deleteTodo(todo);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Text('编辑')),
                    if (todo.status != Status.completed)
                      const PopupMenuItem(value: 'complete', child: Text('标记完成')),
                    if (todo.status == Status.completed)
                      const PopupMenuItem(value: 'pending', child: Text('标记待完成')),
                    const PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
            if (todo.detail != null && todo.detail!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                todo.detail!,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(todo.status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _getStatusColor(todo.status)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getStatusIcon(todo.status),
                        size: 16,
                        color: _getStatusColor(todo.status),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _getStatusText(todo.status),
                        style: TextStyle(
                          fontSize: 12,
                          color: _getStatusColor(todo.status),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (todo.deadline != null) ...[
                  Icon(
                    Icons.access_time,
                    size: 16,
                    color: isExpired ? Colors.red : Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('MM-dd HH:mm').format(
                      DateTime.fromMillisecondsSinceEpoch(todo.deadline!),
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: isExpired ? Colors.red : Colors.grey[600],
                      fontWeight: isExpired ? FontWeight.bold : null,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodoList(List<TodoEntity> todos) {
    if (todos.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.task_alt, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('暂无任务', style: TextStyle(fontSize: 18, color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTodos,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: todos.length,
        itemBuilder: (context, index) => _buildTodoCard(todos[index]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('任务管理'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.list),
              text: '全部 (${_allTodos.length})',
            ),
            Tab(
              icon: const Icon(Icons.schedule),
              text: '待完成 (${_pendingTodos.length})',
            ),
            Tab(
              icon: const Icon(Icons.check_circle),
              text: '已完成 (${_completedTodos.length})',
            ),
            Tab(
              icon: const Icon(Icons.error),
              text: '已过期 (${_expiredTodos.length})',
            ),
          ],
        ),
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : TabBarView(
            controller: _tabController,
            children: [
              _buildTodoList(_allTodos),
              _buildTodoList(_pendingTodos),
              _buildTodoList(_completedTodos),
              _buildTodoList(_expiredTodos),
            ],
          ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTodoDialog,
        icon: const Icon(Icons.add),
        label: const Text('添加任务'),
      ),
    );
  }
}
