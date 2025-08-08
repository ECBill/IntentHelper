import 'package:app/utils/assets_util.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/record_controller.dart';
import '../../utils/route_utils.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  final RecordScreenController _audioController = RecordScreenController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.delayed(Duration(milliseconds: 500));
    await _audioController.load();
    await Future.delayed(Duration(seconds: 1));
    final prefs = await SharedPreferences.getInstance();
    final isFirstLaunch = prefs.getBool("isFirstLaunch") ?? true;

    // 直接跳转到主界面或欢迎页面，不再检查登录状态
    if (mounted) {
      context.pushReplacementNamed(
        isFirstLaunch 
        ? RouteName.welcome 
        : RouteName.home_chat, // 直接进入主界面
      extra: _audioController);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Image.asset(
          AssetsUtil.logo_hd,
          width: 200,
          height: 200,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}