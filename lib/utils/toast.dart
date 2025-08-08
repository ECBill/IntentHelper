import 'package:flutter/material.dart';

void showMessage(String message, {BuildContext? context}) {
  if (context != null) {
    // 使用SnackBar替代fluttertoast
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.black87,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  } else {
    // 如果没有context，打印到控制台作为备选
    print('Toast: $message');
  }
}

// 为了保持向后兼容，也提供一个不需要context的版本
void showToast(String message) {
  print('Toast: $message');
}