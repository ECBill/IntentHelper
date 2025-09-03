import 'dart:developer' as dev;

import 'package:app/controllers/auth_controller.dart';
import 'package:app/utils/assets_util.dart';
import 'package:app/utils/route_utils.dart';
import 'package:app/utils/sp_util.dart';
import 'package:app/views/components/member_progress_indicator.dart';
import 'package:app/views/members/members_dialog.dart';
import 'package:app/views/ui/bud_card.dart';
import 'package:app/views/ui/bud_icon.dart';
import 'package:app/views/ui/bud_switch.dart';
import 'package:app/views/ui/layout/bud_scaffold.dart';
import 'package:app/views/human_understanding_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../controllers/export_controller.dart';
import '../controllers/style_controller.dart';
import '../controllers/setting_controller.dart';
import 'ble_screen.dart';

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});

  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  final SettingScreenController _controller = SettingScreenController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
  }

  void _onClickUser() {
    context.pushNamed(RouteName.user);
  }

  void _onClickResetVoicePrint() async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Reset'),
          content: const Text('Do you want to reset your voiceprint sample?'),
          actions: [
            TextButton(
              onPressed: () {
                context.pop(false);
              },
              child: const Text('NO'),
            ),
            TextButton(
              onPressed: () {
                context.pop(true);
              },
              child: const Text('YES'),
            ),
          ],
        );
      },
    );

    if (shouldReset == true) {
      _controller.resetVoiceprint();
      context.pushNamed(RouteName.voice_print);
      return;
    }
  }

  /// Navigate to privacy settings or show a dialog
  void _onClickPrivacy() {}

  void _onClickExportData() {
    showDialog(
      context: context,
      builder: (context) {
        return ExportDataDialog();
      },
    );
  }

  void _onClickAbout() {
    context.pushNamed(RouteName.about);
  }

  void _onClickConnectDevice() {
    showDialog(
        context: context,
        builder: (context) {
          return BLEScreen();
        });
  }

  void _onClickHeadphoneUpgrade() {}

  void _onClickHelpAndFeedback() {
    context.pushNamed(RouteName.help_feedback);
  }

  void _onClickPrivacyAndProtocol() {}

  void _onClickKnowledgeGraph() {
    context.pushNamed(RouteName.knowledge_graph);
  }

  void _onClickKGTest() {
    context.pushNamed(RouteName.kg_test);
  }

  void _onClickCacheDebug() {
    context.pushNamed(RouteName.cache_debug);
  }

  void _onClickSummaryList() {
    context.pushNamed(RouteName.summary_list);
  }

  void _onClickTodo() {
    context.pushNamed(RouteName.todo);
  }

  /// 点击人类理解系统入口
  void _onClickHumanUnderstanding() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const HumanUnderstandingDashboard(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);

    return BudScaffold(
      title: 'Settings',
      actions: [
        InkWell(
          onTap: _onClickUser,
          child: Image.asset(
            AssetsUtil.getIconPath(
              mode: themeNotifier.mode,
              icon: AssetsUtil.icon_user,
            ),
            width: 24.sp,
            height: 24.sp,
          ),
        ),
        SizedBox(width: 16.sp),
      ],
      body: ListView(
        padding: EdgeInsets.all(16.sp),
        children: [
          SectionListView(
            children: [
              SettingListTile(
                leading: AssetsUtil.icon_dark_mode,
                title: 'Dark Mode',
                trailing: BudSwitch(
                  value: themeNotifier.mode == Mode.dark,
                  onChanged: (value) {
                    themeNotifier.toggleTheme();
                  },
                ),
              ),
              SettingListTile(
                onTap: _onClickResetVoicePrint,
                leading: AssetsUtil.icon_voice_print,
                title: 'Reset Voiceprint',
                subtitle: 'Reset your voiceprint sample',
              ),
              SettingListTile(
                leading: AssetsUtil.icon_export_data,
                title: 'Export Data',
                subtitle: 'Export transcription results',
                onTap: _onClickExportData,
              ),
              SettingListTile(
                leading: AssetsUtil.icon_about, // 临时使用现有图标
                title: 'Knowledge Graph',
                subtitle: 'View extracted events and relationships',
                onTap: _onClickKnowledgeGraph,
              ),
              SettingListTile(
                leading: AssetsUtil.icon_feedback, // 临时使用现有图标
                title: 'KG Test',
                subtitle: 'Test buildInputWithKG function',
                onTap: _onClickKGTest,
              ),
              SettingListTile(
                leading: AssetsUtil.icon_connection,
                title: 'Connect',
                subtitle: 'Scan and connect to Buddie',
                onTap: _onClickConnectDevice,
              ),
              SettingListTile(
                leading: AssetsUtil.icon_set_up,
                title: 'Headphone upgrade',
                subtitle: 'Update your headphone version',
                onTap: _onClickHeadphoneUpgrade,
              ),
              SettingListTile(
                leading: AssetsUtil.icon_feedback, // 临时使用现有图标
                title: 'Cache Debug',
                subtitle: 'Debugging tools for cache',
                onTap: _onClickCacheDebug,
              ),
              SettingListTile(
                leading: AssetsUtil.icon_feedback, // 临时使用现有图标
                title: 'Summary List',
                subtitle: 'View and manage your summaries',
                onTap: _onClickSummaryList,
              ),
              SettingListTile(
                leading: AssetsUtil.icon_set_up, // 临时使用现有图标
                title: 'Todo List',
                subtitle: 'View and manage your tasks',
                onTap: _onClickTodo,
              ),
              SettingListTile(
                leading: AssetsUtil.icon_about, // 临时使用现有图标
                title: 'Human Understanding',
                subtitle: 'Advanced AI understanding system',
                onTap: _onClickHumanUnderstanding,
              ),
            ],
          ),
          SizedBox(height: 12.sp),
          SectionListView(children: [
            SettingListTile(
              leading: AssetsUtil.icon_about,
              title: 'About',
              subtitle: 'Learn more about Buddie',
              onTap: _onClickAbout,
            ),
            SettingListTile(
              leading: AssetsUtil.icon_feedback,
              title: 'Help and Feedback',
              onTap: _onClickHelpAndFeedback,
            ),
          ]),
          // 添加底部安全区域
          SizedBox(height: MediaQuery.of(context).padding.bottom + 20.h),
        ],
      ),
    );
  }
}

class SectionListView extends StatelessWidget {
  final List<Widget> children;

  const SectionListView({
    super.key,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    bool isLightMode = themeNotifier.mode == Mode.light;
    return BudCard(
      color: isLightMode ? const Color(0xFFFAFAFA) : const Color(0x33FFFFFF),
      radius: 8.sp,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: 32.sp),
        itemCount: children.length,
        separatorBuilder: (_, index) => const Divider(
          height: 1,
          color: Color.fromRGBO(0, 0, 0, 0.1),
        ),
        itemBuilder: (_, index) => children[index],
      ),
    );
  }
}

class SettingListTile extends StatelessWidget {
  final String leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final GestureTapCallback? onTap;

  const SettingListTile({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    bool isLightMode = themeNotifier.mode == Mode.light;
    return InkWell(
      onTap: onTap,
      child: Container(
        // 移除固定高度，使用动态高度
        constraints: BoxConstraints(minHeight: 70.sp),
        padding: EdgeInsets.symmetric(vertical: 14.sp),
        child: Row(
          children: [
            BudCard(
              color: isLightMode
                  ? const Color(0xFFEEEEEE)
                  : const Color(0x1AEEEEEE),
              radius: 5.sp,
              padding: EdgeInsets.all(5.sp),
              child: BudIcon(
                icon: leading,
                size: 14.sp,
              ),
            ),
            SizedBox(width: 16.sp),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isLightMode ? Colors.black : Colors.white,
                    ),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: 4.h),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isLightMode
                            ? const Color(0xFF999999)
                            : const Color(0x99FFFFFF),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ]
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
