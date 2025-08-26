/// 🔥 废弃：此文件已被废弃，提醒管理功能已集成到todo_screen.dart中
/// 保留此文件仅为兼容性考虑

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../views/todo_screen.dart';
import '../models/todo_entity.dart';

/// 🔥 废弃的提醒管理界面 - 现在重定向到统一的任务管理界面
class ReminderManagementScreen extends StatelessWidget {
  const ReminderManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return TodoScreen(status: Status.all);
  }
}
