import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:roulette_clean/core/di/service_locator.dart';
import 'package:roulette_clean/services/session/session_manager.dart';
import 'package:roulette_clean/services/signals/signals_service.dart';
import 'package:roulette_clean/presentation/screens/login/login_screen.dart';
import 'package:roulette_clean/presentation/screens/main/main_screen.dart';
import 'package:roulette_clean/presentation/screens/expired/expired_screen.dart';
import 'package:roulette_clean/utils/expiry_watcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setupServiceLocator();

  final sessionManager = getIt<SessionManager>();
  await sessionManager.loadSession();

  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late Widget _startScreen;
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startScreen = _chooseStartScreen(); // первичная проверка
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // слушаем «возврат» приложения
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final newScreen = _chooseStartScreen();
      if (newScreen.runtimeType != _startScreen.runtimeType) {
        _navKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => newScreen),
          (_) => false,
        );
        _startScreen = newScreen;
      }
    }
  }

  Widget _chooseStartScreen() {
    if (ExpiryWatcher.isExpired()) return const ExpiredScreen();
    return const LoginScreen();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => getIt<SignalsService>()),
      ],
      child: MaterialApp(
        navigatorKey: _navKey,
        title: 'Сигналы рулетки',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: _startScreen,
      ),
    );
  }
}
