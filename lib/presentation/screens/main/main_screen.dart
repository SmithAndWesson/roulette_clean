import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:roulette_clean/core/di/service_locator.dart';
import 'package:roulette_clean/models/roulette/roulette_game.dart';
import 'package:roulette_clean/models/signal.dart';
import 'package:roulette_clean/presentation/screens/login/login_screen.dart';
import 'package:roulette_clean/services/roulette/roulette_service.dart';
import 'package:roulette_clean/services/signals/signals_service.dart';
import 'package:roulette_clean/services/websocket/websocket_service.dart';
import 'package:roulette_clean/presentation/widgets/roulette_card.dart';
import 'package:roulette_clean/utils/logger.dart';
import 'package:roulette_clean/services/session/session_manager.dart';
import 'package:roulette_clean/utils/sound_player.dart';
import 'package:roulette_clean/services/webview/webview_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  List<RouletteGame> _games = [];
  Map<String, RouletteGame> _gamesById = {};
  bool _loadingGames = false;
  bool _connectingGame = false;
  String? _activeGameId;
  bool _autoRunning = false;

  @override
  void initState() {
    super.initState();
    _loadGames();
  }

  Future<void> _loadGames() async {
    setState(() => _loadingGames = true);
    try {
      getIt<SignalsService>().clearSignals();
      _games = await getIt<RouletteService>().fetchLiveRouletteGames();
      _gamesById = {for (var g in _games) g.id: g};
    } finally {
      if (mounted) {
        setState(() => _loadingGames = false);
      }
    }
  }

  Future<void> _cleanupWebView(WebViewService web) async {
    try {
      await web.controller.runJavaScript('''
        (function(){
          (window.__audioCtxs||[]).forEach(c=>c.close && c.close());
          document.querySelectorAll('audio,iframe').forEach(el=>el.remove());
        })();
      ''');
    } catch (_) {}
    await web.resetDomWithoutLogout();
  }

  Future<void> _handleResults(
    RouletteGame game,
    SignalsService signals,
    WebViewService webView,
    List<int> numbers, {
    String? kickout,
  }) async {
    Logger.info("Processing results for game ${game.id}, kickout: $kickout");

    // Если выкинули из‑за отсутствия авторизации – залогинимся и повторим анализ
    if (kickout == 'notAuthorised') {
      await webView.startLoginProcess((jwt, cookies) {
        getIt<SessionManager>().saveSession(
          jwtToken: jwt,
          cookieHeader: cookies,
        );
        // запускаем повторный анализ ТОЛЬКО для текущей игры
        _connectGame(game);
      });
      return; // ждём логина, дальше не обрабатываем
    }

    // обычная обработка чисел
    signals.processResults(
      game.id,
      numbers,
      kickoutReason: kickout,
    );
    Logger.info("Results processed for game ${game.id}");

    // очищаем WebView после обработки
    await _cleanupWebView(webView);
  }

  Future<void> _connectGame(RouletteGame game) async {
    final roulette = getIt<RouletteService>();
    final wsService = getIt<WebSocketService>();
    final signals = context.read<SignalsService>();
    final webView = getIt<WebViewService>();

    setState(() {
      _connectingGame = true;
      _activeGameId = game.id;
    });

    try {
      final params = await roulette.extractWebSocketParams(game);
      final results = await wsService.fetchRecentResults(params);

      if (results != null) {
        await _handleResults(
          game,
          signals,
          webView,
          results.numbers,
          kickout: results.kickoutReason,
        );
      }
    } catch (e, st) {
      Logger.error("Error connecting to game ${game.title}", e, st);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка подключения: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _connectingGame = false;
          _activeGameId = null;
        });
      }
    }
  }

  Future<void> _toggleAutoAnalysis() async {
    final signals = getIt<SignalsService>();
    final roulette = getIt<RouletteService>();
    final wsService = getIt<WebSocketService>();
    final webView = getIt<WebViewService>();

    if (!_autoRunning) {
      final gameIds = _games.map((g) => g.id).toList();

      signals.startAutoAnalysis(
        const Duration(seconds: 5), // интервал между анализами
        gameIds,
        (String gameId) async {
          final game = _gamesById[gameId]!;

          try {
            final params = await roulette.extractWebSocketParams(game);
            final res = await wsService.fetchRecentResults(params);
            if (res == null) return null; // пропускаем

            await _handleResults(
              game,
              signals,
              webView,
              res.numbers,
              kickout: res.kickoutReason,
            );

            // если кикнуло за notAuthorised – числа уже не нужны
            return res.kickoutReason == 'notAuthorised' ? null : res.numbers;
          } catch (e, st) {
            Logger.error('Auto‑analysis error for ${game.id}', e, st);
            return null; // не останавливаем цикл
          }
        },
      );
    } else {
      signals.stopAutoAnalysis();
    }

    if (mounted) {
      setState(() => _autoRunning = !_autoRunning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final signalsService = context.watch<SignalsService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Рулетка Сигналы"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: _loadingGames
                ? Container(
                    width: 24,
                    height: 24,
                    padding: const EdgeInsets.all(2),
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.refresh),
            tooltip: _loadingGames ? 'Обновление...' : 'Обновить игры',
            onPressed: _loadingGames
                ? null
                : () async {
                    setState(() => _loadingGames = true);
                    try {
                      await _loadGames();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Список игр обновлен'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _loadingGames = false);
                      }
                    }
                  },
          ),
          // IconButton(
          //   icon: const Icon(Icons.volume_up),
          //   tooltip: 'Тест звука',
          //   onPressed: () {
          //     SoundPlayer.i.playPing();
          //   },
          // ),
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            tooltip: 'Выйти',
            onPressed: () async {
              await getIt<WebViewService>().clearWebView();
              getIt<SessionManager>().clearSession();
              signalsService.stopAutoAnalysis();
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_autoRunning && signalsService.currentAnalyzingGameId != null)
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Анализируем: ${_gamesById[signalsService.currentAnalyzingGameId]?.title ?? ''}",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loadingGames
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          'Загрузка игр...',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadGames,
                    child: GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.8,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _games.length,
                      itemBuilder: (context, index) {
                        final game = _games[index];
                        final signals =
                            signalsService.getSignalsForGame(game.id);
                        final isAnalyzing =
                            signalsService.currentAnalyzingGameId == game.id;
                        return RouletteCard(
                          game: game,
                          signals: signals,
                          isConnecting:
                              _connectingGame && _activeGameId == game.id,
                          isAnalyzing: isAnalyzing,
                          onConnect: () => _connectGame(game),
                          connectEnabled: !_autoRunning,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleAutoAnalysis,
        child: Icon(_autoRunning ? Icons.stop : Icons.play_arrow),
        tooltip: _autoRunning ? 'Остановить анализ' : 'Начать анализ',
      ),
    );
  }
}
