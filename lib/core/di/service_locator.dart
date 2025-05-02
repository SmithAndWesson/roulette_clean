import 'package:get_it/get_it.dart';
import 'package:roulette_clean/services/session/session_manager.dart';
import 'package:roulette_clean/services/webview/webview_service.dart';
import 'package:roulette_clean/services/websocket/websocket_service.dart';
import 'package:roulette_clean/services/roulette/roulette_service.dart';
import 'package:roulette_clean/services/signals/signals_service.dart';

final getIt = GetIt.instance;

void setupServiceLocator() {
  // Core singletons
  getIt.registerLazySingleton<SessionManager>(() => SessionManager());
  getIt.registerLazySingleton<WebViewService>(() => WebViewService());
  getIt.registerLazySingleton<WebSocketService>(() => WebSocketService());

  // Register RouletteService with dependencies
  getIt.registerLazySingleton<RouletteService>(() => RouletteService(
        sessionManager: getIt<SessionManager>(),
        webViewService: getIt<WebViewService>(),
      ));

  getIt.registerLazySingleton<SignalsService>(() => SignalsService());
}
