import 'package:app/extension/context_extension.dart';
import 'package:app/utils/assets_util.dart';
import 'package:app/views/ui/app_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../ui/bud_icon.dart';

class HelpFeedbackScreen extends StatefulWidget {
  const HelpFeedbackScreen({super.key});

  @override
  State<HelpFeedbackScreen> createState() => _HelpFeedbackScreenState();
}

class _HelpFeedbackScreenState extends State<HelpFeedbackScreen> {
  late final _quickHelp = <_InfoData>[
    _InfoData('Official website', "<body>dsadasdadsadada</body>"),
    _InfoData('Official website', "<body>dsadasdadsadada</body>"),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: DefaultTextStyle(
            style: TextStyle(
              color: context.isLightMode ? Colors.black : Colors.white,
            ),
            child: Column(
              children: [
                _buildAppbar(context),
                SizedBox(height: 17.h),
                Expanded(
                  child: Column(
                    children: [
                      Flexible(
                        child: Padding(
                          padding: EdgeInsets.all(16.r),
                          child: _buildInfoGroup(context, _quickHelp, true),
                        ),
                      )
                    ],
                  ),
                ),
                DefaultTextStyle(
                  style: TextStyle(
                    color: context.isLightMode ? Colors.black : Colors.white,
                    fontSize: 12.sp,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {},
                          child: Column(
                            children: [
                              Icon(
                                Icons.contact_support_outlined,
                                color: context.isLightMode
                                    ? Colors.black
                                    : Colors.white,
                              ),
                              const Text('Contact us')
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {},
                          child: Column(
                            children: [
                              Icon(
                                Icons.feedback_outlined,
                                color: context.isLightMode
                                    ? Colors.black
                                    : Colors.white,
                              ),
                              const Text('Feedback')
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 17.h),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppbar(BuildContext context) {
    return SizedBox(
      height: 40.r,
      child: Stack(
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: GestureDetector(
              onTap: () => context.pop(),
              child: Padding(
                padding: EdgeInsets.all(10.r),
                child: BudIcon(
                  icon: AssetsUtil.icon_arrow_back,
                  size: 20.r,
                ),
              ),
            ),
          ),
          Center(
            child: Text(
              'About Buddie',
              style: TextStyle(
                color: context.isLightMode ? Colors.black : Colors.white,
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: GestureDetector(
              onTap: () {},
              child: Padding(
                padding: EdgeInsets.all(10.r),
                child: Text(
                  'report',
                  style: TextStyle(
                    color: context.isLightMode ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoGroup(
      BuildContext context, List<_InfoData> infoList, bool scrollable) {
    return Container(
      decoration: BoxDecoration(
        color: context.isLightMode ? Colors.white : const Color(0xff394044),
        borderRadius: BorderRadius.circular(8).r,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
        ),
        child: ListView.separated(
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          itemBuilder: (context, index) {
            final info = infoList[index];
            return ExpansionTile(
              title: Text(
                info.title,
                style: TextStyle(
                  color: context.isLightMode ? Colors.black : Colors.white,
                  fontSize: 12.sp,
                ),
              ),
              tilePadding: EdgeInsets.symmetric(horizontal: 7.w),
              collapsedIconColor:
              context.isLightMode ? Colors.black : Colors.white,
              collapsedBackgroundColor: Colors.transparent,
              backgroundColor: Colors.transparent,
              iconColor: context.isLightMode ? Colors.black : Colors.white,
              shape: const Border(),
              collapsedShape: const Border(),
              children: [
                Html(
                  data: info.content,
                  style: {
                    "body": Style(
                      padding: HtmlPaddings.zero,
                      color: context.isLightMode ? Colors.black : Colors.white,
                      fontSize: FontSize(12.sp),
                    ),
                    "p": Style(
                      padding: HtmlPaddings.zero,
                      color: context.isLightMode ? Colors.black : Colors.white,
                      fontSize: FontSize(12.sp),
                    )
                  },
                )
              ],
            );
          },
          separatorBuilder: (context, index) {
            return Divider(
              height: 1,
              indent: 7.w,
              endIndent: 7.w,
              color: context.isLightMode
                  ? Colors.black.withAlpha(10)
                  : Colors.white.withAlpha(10),
            );
          },
          itemCount: infoList.length,
        ),
      ),
    );
  }
}

class _InfoData {
  final String title;
  final String content;

  _InfoData(this.title, this.content);
}