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

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => getIt<SignalsService>()),
      ],
      child: MaterialApp(
        title: 'Сигналы рулетки',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: ExpiryWatcher.isExpired()
            ? const ExpiredScreen()
            : getIt<SessionManager>().isLoggedIn
                ? const MainScreen()
                : const LoginScreen(),
        // home: ExpiryWatcher.isExpired()
        //     ? const ExpiredScreen()
        //     : const LoginScreen(),
      ),
    );
  }
}
