import 'package:app/controllers/style_controller.dart';
import 'package:app/extension/media_query_data_extension.dart';
import 'package:app/utils/route_utils.dart';
import 'package:app/views/components/chat_list_tile.dart';
import 'package:app/views/components/home_app_bar.dart';
import 'package:app/views/components/home_bottom_bar.dart';
import 'package:app/views/ui/app_background.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:keyboard_dismisser/keyboard_dismisser.dart';
import 'package:provider/provider.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../../constants/prompt_constants.dart';
import '../../controllers/chat_controller.dart';
import '../../controllers/record_controller.dart';
import '../../utils/assets_util.dart';
import '../ble_screen.dart';

class HomeChatScreen extends StatefulWidget {
  final RecordScreenController? controller;

  const HomeChatScreen({super.key, this.controller});

  @override
  State<HomeChatScreen> createState() => _HomeChatScreenState();
}

class _HomeChatScreenState extends State<HomeChatScreen> {
  late ChatController _chatController;
  final FocusNode _focusNode = FocusNode();
  late RecordScreenController _audioController;

  final _listenable = IndicatorStateListenable();
  bool _shrinkWrap = false;
  double? _viewportDimension;
  bool _bluetoothConnected = false;

  final TextStyle textTextStyle = const TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 14,
  );

  final EdgeInsets chatPadding =
  EdgeInsets.symmetric(horizontal: 18.sp, vertical: 12.sp);

  final double lineSpace = 16.sp;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _chatController.dispose();
    _listenable.removeListener(_onHeaderChange);
    super.dispose();
  }

  void _init() {
    if (widget.controller == null) {
      _audioController = RecordScreenController();
      _audioController.load();
    } else {
      _audioController = widget.controller!;
    }
    _audioController.attach(this);
    _listenable.addListener(_onHeaderChange);
    _chatController = ChatController(
      onNewMessage: onNewMessage,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_chatController.checkAndNavigateToWelcomeRecordScreen()) {
        await context.pushNamed(RouteName.voice_print);
      }
      // if (!_bluetoothConnected) {
      //   _showEarphoneConnectDialog();
      // }
    });
  }

  void _showEarphoneConnectDialog() async {
    bool? connect = await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const EarphoneDialog(),
          actions: [
            TextButton(
              onPressed: () => context.pop(false),
              child: const Text('cancel'),
            ),
            TextButton(
              onPressed: () => context.pop(true),
              child: const Text('connect'),
            ),
          ],
        );
      },
    );
    if (connect == true) {
      showDialog(
        context: context,
        builder: (context) {
          return BLEScreen();
        },
      );
    }
  }

  void _onHeaderChange() {
    final state = _listenable.value;
    if (state != null) {
      final position = state.notifier.position;
      _viewportDimension ??= position.viewportDimension;
      final shrinkWrap = state.notifier.position.maxScrollExtent == 0;
      if (_shrinkWrap != shrinkWrap &&
          _viewportDimension == position.viewportDimension) {
        setState(() {
          _shrinkWrap = shrinkWrap;
        });
      }
    }
  }

  void onNewMessage() {
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildMsg(Map<String, dynamic> message) {
    final dynamic rawText = message['text'];

    // ✅ 确保 text 是 String 类型且不为空
    if (rawText == null || rawText is! String || rawText.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final String text = rawText;
    final dynamic rawRole = message['isUser'];
    final dynamic rawId = message['id'];

    // ✅ 统一角色处理逻辑 - 同时处理历史消息和新消息
    String role;
    if (rawRole is String) {
      // 直接使用字符串角色
      if (rawRole == 'user' || rawRole == 'assistant' || rawRole == 'others' || rawRole == 'system') {
        role = rawRole;
      } else {
        // 对于其他字符串值（如speaker名称），统一归类为 'others'
        role = 'others';
      }
    } else if (rawRole is bool) {
      // 布尔值（向后兼容）
      role = rawRole ? 'user' : 'assistant';
    } else {
      // null 或其他类型，默认为 'others'
      role = 'others';
    }

    final String id = rawId?.toString() ?? '';

    // 🔥 新增：检查是否为智能提醒消息
    final messageType = message['type']?.toString();
    final isIntelligentReminder = messageType == 'intelligent_reminder';

    // 添加调试信息来查看角色识别结果
    if (isIntelligentReminder) {
      print('DEBUG: 智能提醒消息 - rawRole: $rawRole (${rawRole.runtimeType}) -> role: $role, text: ${text.substring(0, text.length > 20 ? 20 : text.length)}...');
    } else {
      print('DEBUG: _buildMsg - rawRole: $rawRole (${rawRole.runtimeType}) -> role: $role, text: ${text.substring(0, text.length > 20 ? 20 : text.length)}...');
    }

    // ✅ 如果 id 为空，直接返回基本的消息组件，不使用 VisibilityDetector
    if (id.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(bottom: lineSpace),
        child: ChatListTile(
          onLongPress: () => _chatController.copyToClipboard(context, text),
          role: role,
          text: text,
          style: textTextStyle,
          padding: chatPadding,
          // 🔥 新增：为智能提醒消息添加特殊样式标识
          isIntelligentReminder: isIntelligentReminder,
        ),
      );
    }

    Widget body = Padding(
      padding: EdgeInsets.only(bottom: lineSpace),
      child: ChatListTile(
        onLongPress: () => _chatController.copyToClipboard(context, text),
        role: role,
        text: text,
        style: textTextStyle,
        padding: chatPadding,
        // 🔥 新增：为智能提醒消息添加特殊样式标识
        isIntelligentReminder: isIntelligentReminder,
      ),
    );

    if (_chatController.unReadMessageId.value.contains(id)) {
      body = VisibilityDetector(
        key: UniqueKey(),
        onVisibilityChanged: (info) {
          if (info.visibleFraction == 1) {
            _chatController.unReadMessageId.value.remove(id);
            _chatController.unReadMessageId.value = Set.from(_chatController.unReadMessageId.value);
          }
        },
        child: body,
      );
    }

    return body;
  }


  void _onClickKeyboard() {
    if (_focusNode.hasFocus) {
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
    }
  }

  void _onClickBluetooth() {
    setState(() {
      _bluetoothConnected = !_bluetoothConnected;
    });
  }

  void _onClickRecord() {
    setState(() {
      _audioController.toggleRecording();
    });
  }

  void _onClickSendMessage() {
    _chatController.sendMessage();
  }

  void _onClickHelp() {
    _chatController.sendMessage(initialText: systemPromptOfHelp);
  }

  void _onClickBottomRight() {
    _focusNode.unfocus();
    context.pushNamed(RouteName.meeting_list);
    // context.pushNamed(RouteName.journal);
  }

  var centerKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final slivers = <Widget>[];

    // 显示历史消息
    final history = _chatController.historyMessages.reversed.toList();
    print('DEBUG: history messages count: ${history.length}');
    if (history.isNotEmpty) {
      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
              (BuildContext context, int i) {
            if (i >= history.length) {
              return const SizedBox();
            }
            return _buildMsg(history[i]);
          },
          childCount: history.length,
        ),
      ));
    }

    // 添加中心分隔符
    slivers.add(SliverPadding(
      padding: EdgeInsets.zero,
      key: centerKey,
    ));

    // 显示新消息
    final newMessage = _chatController.newMessages.reversed.toList();
    print('DEBUG: newMessages count: ${newMessage.length}');
    print('DEBUG: newMessages content: ${newMessage.map((msg) {
      final text = msg['text']?.toString() ?? '';
      final shortText = text.length > 20 ? text.substring(0, 20) : text;
      return '${msg['id']}: $shortText...';
    }).toList()}');

    if (newMessage.isNotEmpty) {
      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
              (BuildContext context, int i) {
            if (i >= newMessage.length) {
              return const SizedBox();
            }
            return _buildMsg(newMessage[i]);
          },
          childCount: newMessage.length,
        ),
      ));
    }

    return KeyboardDismisser(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: AppBackground(
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top,
              left: 10.sp,
              right: 10.sp,
              bottom: MediaQuery.of(context).fixedBottom,
            ),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.sp),
                  child: HomeAppBar(
                    bluetoothConnected: _audioController.connectionState,
                    onTapBluetooth: _onClickBluetooth,
                  ),
                ),
                SizedBox(height: 18.sp),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: 8.sp,
                    ),
                    child: Stack(
                      children: [
                        EasyRefresh.builder(
                          header: const MaterialHeader(triggerOffset: 30.0),
                          footer: const MaterialFooter(triggerOffset: 30.0),
                          clipBehavior: Clip.none,
                          onRefresh: () {
                            return _chatController.loadMoreMessages();
                          },
                          childBuilder: (
                              BuildContext context,
                              ScrollPhysics physics,
                              ) {
                            return ClipRect(
                              child: CustomScrollView(
                                physics: physics,
                                controller: _chatController.scrollController,
                                clipBehavior: Clip.none,
                                center: centerKey,
                                cacheExtent: 0,
                                slivers: slivers,
                              ),
                            );
                          },
                        ),
                        Align(
                          alignment: AlignmentDirectional.bottomEnd,
                          child: ValueListenableBuilder(
                              valueListenable: _chatController.unReadMessageId,
                              builder: (context, ids, _) {
                                if (ids.isEmpty) return const SizedBox();
                                return GestureDetector(
                                  onTap: () {
                                    _chatController.unReadMessageId.value = {};
                                    _chatController.firstScrollToBottom();
                                  },
                                  child: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(30),
                                        color: Colors.blue),
                                    child: Center(
                                      child: Text(
                                        ids.length.toString(),
                                        style: const TextStyle(color: Colors.white),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                        )
                      ],
                    ),
                  ),
                ),
                HomeBottomBar(
                  controller: _chatController.textController,
                  onTapKeyboard: _onClickKeyboard,
                  onSubmitted: (_) {},
                  onTapSend: _onClickSendMessage,
                  onTapLeft: _onClickRecord,
                  onTapHelp: _onClickHelp,
                  onTapRight: _onClickBottomRight,
                  isRecording: _audioController.isRecording,
                  isSpeakValueNotifier: _chatController.isSpeakValueNotifier,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EarphoneDialog extends StatelessWidget {
  final GestureTapCallback? onClickConnect;

  const EarphoneDialog({
    super.key,
    this.onClickConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          AssetsUtil.logo,
          width: 116.sp,
          height: 116.sp,
        ),
      ],
    );
  }
}