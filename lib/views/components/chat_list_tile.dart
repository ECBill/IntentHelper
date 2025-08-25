import 'package:app/controllers/style_controller.dart';
import 'package:app/utils/assets_util.dart';
import 'package:app/views/components/chat_container.dart';
import 'package:app/views/ui/bud_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

class ChatListTile extends StatelessWidget {
  final String role;
  final String text;
  final TextStyle? style;
  final EdgeInsetsGeometry? padding;
  final GestureLongPressCallback? onLongPress;
  final bool isIntelligentReminder; // 🔥 新增：是否为智能提醒消息

  const ChatListTile({
    super.key,
    required this.role,
    required this.text,
    this.style,
    this.padding,
    this.onLongPress,
    this.isIntelligentReminder = false, // 🔥 新增：默认为false
  });

  static final double _iconSize = 24.sp;
  static final double _iconRight = 8.sp;
  static final double _containMarginHorizontal = 16.sp;
  static final double textWidthSpace = _iconSize + _iconRight + _containMarginHorizontal;

  static EdgeInsets _getChatContainerMargin(String role) {
    bool isUser = role == 'user';
    EdgeInsets margin = EdgeInsets.only(
      left: isUser ? (_iconSize + _iconRight + _containMarginHorizontal) : 0,
      right: isUser ? 0 : _containMarginHorizontal,
    );
    return margin;
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    bool isLightMode = themeNotifier.mode == Mode.light;
    bool isUser = role == 'user';
    bool isAssistant = role == 'assistant';
    bool isOthers = role == 'others';

    TextStyle textStyle = style ??
        const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
        );

    // 🔥 新增：为智能提醒消息应用特殊样式
    if (isIntelligentReminder) {
      textStyle = textStyle.copyWith(
        fontStyle: FontStyle.italic, // 斜体
        color: isLightMode
            ? const Color(0xFF4A90E2) // 浅色模式下使用蓝色
            : const Color(0xFF87CEEB), // 深色模式下使用天蓝色
      );
    }

    // 根据角色选择头像图标
    String getAvatarIcon() {
      if (isUser) {
        return AssetsUtil.icon_user; // 用户头像
      } else if (isAssistant) {
        // 🔥 新增：智能提醒使用特殊图标
        if (isIntelligentReminder) {
          return AssetsUtil.icon_chat_logo; // 可以考虑使用特殊的提醒图标
        }
        return AssetsUtil.icon_chat_logo; // AI助手头像
      } else {
        return AssetsUtil.icon_chat_meeting; // 其他人头像
      }
    }

    // 🔥 新增：智能提醒消息的容器装饰
    Widget messageContainer = ChatContainer(
      role: role,
      margin: _getChatContainerMargin(role),
      padding: padding ?? EdgeInsets.symmetric(horizontal: 18.sp, vertical: 12.sp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔥 新增：智能提醒标识
          if (isIntelligentReminder) ...[
            Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 14.sp,
                  color: isLightMode
                      ? const Color(0xFF4A90E2)
                      : const Color(0xFF87CEEB),
                ),
                SizedBox(width: 4.sp),
                Text(
                  '智能提醒',
                  style: TextStyle(
                    fontSize: 10.sp,
                    color: isLightMode
                        ? const Color(0xFF4A90E2)
                        : const Color(0xFF87CEEB),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            SizedBox(height: 6.sp),
          ],
          // 消息文本
          Text(
            text,
            style: textStyle.copyWith(
              color: isIntelligentReminder
                  ? (isLightMode
                      ? const Color(0xFF4A90E2)
                      : const Color(0xFF87CEEB))
                  : (isLightMode
                      ? const Color(0xFF383838)
                      : isUser
                      ? const Color(0xE6FFFFFF)
                      : const Color(0xB3FFFFFF)),
            ),
          ),
        ],
      ),
    );

    return Row(
      mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 非用户消息显示左侧头像
        if (!isUser)
          Padding(
            padding: EdgeInsets.only(right: _iconRight),
            child: Stack(
              children: [
                BudIcon(
                  icon: getAvatarIcon(),
                  size: _iconSize,
                ),
                // 🔥 新增：智能提醒消息的头像标识
                if (isIntelligentReminder)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8.sp,
                      height: 8.sp,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A90E2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Flexible(
          child: GestureDetector(
            onLongPress: onLongPress,
            child: messageContainer,
          ),
        ),
        // 用户消息显示右侧头像
        if (isUser)
          Padding(
            padding: EdgeInsets.only(left: _iconRight),
            child: BudIcon(
              icon: getAvatarIcon(),
              size: _iconSize,
            ),
          ),
      ],
    );
  }
}
