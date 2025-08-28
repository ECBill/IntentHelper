import 'package:app/controllers/style_controller.dart';
import 'package:app/services/llm.dart';
import 'package:app/services/objectbox_service.dart';
import 'package:app/utils/route_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';


final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

Future<void> main() async {
  // Initialize port for communication between TaskHandler and UI.
  WidgetsFlutterBinding.ensureInitialized();

  // 加载 .env 文件
  await dotenv.load(fileName: ".env");

  // 🔥 新增：在应用启动时缓存API key，解决后台任务访问环境变量的问题
  final apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
  if (apiKey.isNotEmpty) {
    LLM.cacheApiKey(apiKey);
    print('[Main] API key已缓存，自动总结功能可正常使用');
  } else {
    print('[Main] 警告：未找到API key，自动总结功能可能无法使用');
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  final DarwinInitializationSettings initializationSettingsIOS =
  DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
  );

  FlutterForegroundTask.initCommunicationPort();

  await Firebase.initializeApp();
  await ObjectBoxService.initialize();

  FlutterBluePlus.setLogLevel(LogLevel.error);
  FlutterBluePlus.setOptions(restoreState: true);

  final prefs = await SharedPreferences.getInstance();
  final isFirstLaunch = prefs.getBool("isFirstLaunch") ?? true;

  // 直接设置为已登录状态，跳过登录流程
  await prefs.setBool('isLogin', true);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://476fe26ce43858184b0f5309106671d6@o4507015727874048.ingest.us.sentry.io/4508811095375872';
      options.tracesSampleRate = 1.0;
      options.profilesSampleRate = 1.0;
      options.diagnosticLevel = SentryLevel.warning;
    },
    appRunner: () => runApp(
      SentryWidget(
        child: ChangeNotifierProvider(
          create: (_) => ThemeNotifier(),
          child: MyApp(isFirstLaunch: isFirstLaunch),
        ),
      ),
    ),
  );


  // 你可以将 whisper 作为全局变量传递或通过 Provider 等方式管理
}

class MyApp extends StatelessWidget {
  final bool isFirstLaunch;

  const MyApp({required this.isFirstLaunch, super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
      builder: (context, themeNotifier, child) {
        return ScreenUtilInit(
          designSize: const Size(375, 812),
          child: MaterialApp.router(
            title: 'Bud',
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF229954),
                brightness: Brightness.light,
              ),
              useMaterial3: true,
              textTheme: const TextTheme(
                displayLarge: TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
                displayMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w300),
                displaySmall: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF229954),
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
              textTheme: const TextTheme(
                displayLarge: TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
                displayMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w300),
                displaySmall: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            themeMode: themeNotifier.mode == Mode.dark ? ThemeMode.dark : ThemeMode.light,
            debugShowCheckedModeBanner: false,
            routerConfig: RouteUtils.goRoute,
          ),
        );
      },
    );
  }
}