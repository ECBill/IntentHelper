import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

void showMessage(String message) {
  Fluttertoast.showToast(
    msg: message,
    toastLength: Toast.LENGTH_LONG, // 显示时间: SHORT 或 LONG
    gravity: ToastGravity.CENTER, // 位置: TOP, CENTER, BOTTOM
    backgroundColor: Colors.black54,
    textColor: Colors.white,
    fontSize: 16.0,
  );
}