import 'package:app/controllers/record_controller.dart';
import 'package:app/views/about/about_screen.dart';
import 'package:app/views/home/home_chat_screen.dart';
import 'package:app/views/journal/daily_list_screen.dart';
import 'package:app/views/journal_screen.dart';
import 'package:app/views/login/login_page.dart';
import 'package:app/views/meeting/meeting_detail_screen.dart';
import 'package:app/views/meeting/meeting_list_screen.dart';
import 'package:app/views/setting_screen.dart';
import 'package:app/views/todo/todo_list_screen.dart';
import 'package:app/views/todo_screen.dart';
import 'package:app/models/todo_entity.dart'; // 添加Status枚举的导入
import 'package:app/views/user_screen.dart';
import 'package:app/views/entry/welcome_screen.dart';
import 'package:app/views/knowledge_graph_page.dart';
import 'package:app/views/kg_test_page.dart';
import 'package:app/views/cache_debug_page.dart';
import 'package:app/views/summary_list_screen.dart';
import 'package:app/views/log_evaluation_screen.dart'; // 使用新的标签页版本
import 'package:go_router/go_router.dart';
import '../views/entry/loading_screen.dart';
import 'package:app/views/help_feedback/help_feedback_screen.dart';
import 'package:app/views/meeting/model/meeting_model.dart';
import '../views/voiceprint_screen.dart';
import 'package:flutter/material.dart';

class BudNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route route, Route? previousRoute) {
    if (previousRoute != null) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    super.didPush(route, previousRoute);
  }
}

class RouteUtils {
  static GoRouter goRoute = GoRouter(
    routes: routes,
    initialLocation: RouteName.loading,
    observers: [BudNavigatorObserver()],
  );

  static List<GoRoute> routes = [
    GoRoute(
      path: RouteName.welcome,
      name: RouteName.welcome,
      builder: (_, state) =>
          WelcomeScreen(controller: state.extra as RecordScreenController?),
    ),
    GoRoute(
      path: RouteName.home_chat,
      name: RouteName.home_chat,
      builder: (_, state) =>
          HomeChatScreen(controller: state.extra as RecordScreenController?),
    ),
    GoRoute(
      path: RouteName.setting,
      name: RouteName.setting,
      builder: (_, state) => const SettingScreen(),
    ),
    GoRoute(
      path: RouteName.user,
      name: RouteName.user,
      builder: (_, state) => const UserScreen(),
    ),
    GoRoute(
      path: RouteName.voice_print,
      name: RouteName.voice_print,
      builder: (_, state) => const WelcomeRecordScreen(),
    ),
    GoRoute(
      path: RouteName.about,
      name: RouteName.about,
      builder: (_, state) => const AboutScreen(),
    ),
    GoRoute(
      path: RouteName.journal,
      name: RouteName.journal,
      builder: (_, state) => const JournalScreen(),
    ),
    GoRoute(
      path: RouteName.meeting_list,
      name: RouteName.meeting_list,
      builder: (_, state) => const MeetingListScreen(),
    ),
    GoRoute(
      path: RouteName.daily_list,
      name: RouteName.daily_list,
      builder: (_, state) => const DailyListScreen(),
    ),
    GoRoute(
      path: RouteName.meeting_detail,
      name: RouteName.meeting_detail,
      builder: (_, state) =>
          MeetingDetailScreen(model: state.extra as MeetingModel),
    ),
    GoRoute(
      path: RouteName.todo_list,
      name: RouteName.todo_list,
      builder: (_, state) => const TodoListScreen(),
    ),
    GoRoute(
      path: RouteName.loading,
      name: RouteName.loading,
      builder: (_, state) => const LoadingScreen()
    ),
    GoRoute(
        path: RouteName.help_feedback,
        name: RouteName.help_feedback,
        builder: (_, state) => const HelpFeedbackScreen()
    ),
    GoRoute(
        path: RouteName.login,
        name: RouteName.login,
        builder: (_, state) => const LoginPage()
    ),
    GoRoute(
      path: RouteName.knowledge_graph,
      name: RouteName.knowledge_graph,
      builder: (_, state) => KnowledgeGraphPage(),
    ),
    GoRoute(
      path: RouteName.kg_test,
      name: RouteName.kg_test,
      builder: (_, state) => KGTestPage(),
    ),
    GoRoute(
      path: RouteName.cache_debug,
      name: RouteName.cache_debug,
      builder: (_, state) => const CacheDebugPage(),
    ),
    GoRoute(
      path: RouteName.summary_list,
      name: RouteName.summary_list,
      builder: (_, state) => const SummaryListScreen(),
    ),
    GoRoute(
      path: RouteName.todo,
      name: RouteName.todo,
      builder: (_, state) => const TodoScreen(status: Status.all),
    ),
    GoRoute(
      path: RouteName.log_evaluation,
      name: RouteName.log_evaluation,
      builder: (_, state) => const LogEvaluationTabbedScreen(),
    ),
  ];
}

class RouteName {
  static const String welcome = '/welcome';
  static const String setup = '/setup';
  static const String login = '/login';

  static const String home_chat = '/home_chat';

  /// home
  static const String setting = '/setting';
  static const String user = '/user';
  static const String voice_print = '/voice_print';
  static const String help_feedback = '/help_feedback';
  static const String about = '/about';
  static const String loading = '/loading';

  /// journal
  static const String journal = '/journal';
  static const String meeting_list = '/meeting_list';
  static const String daily_list = '/daily_list';
  static const String meeting_detail = '/meeting_detail';
  static const String todo_list = '/todo_list';

  /// knowledge graph
  static const String knowledge_graph = '/knowledge_graph';
  static const String kg_test = '/kg_test';

  /// cache debug
  static const String cache_debug = '/cache_debug';

  /// summary
  static const String summary_list = '/summary_list';

  /// todo
  static const String todo = '/todo';

  /// log evaluation
  static const String log_evaluation = '/log_evaluation';
}
