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

  Future<void> _connectGame(RouletteGame game) async {
    setState(() {
      _connectingGame = true;
      _activeGameId = game.id;
    });

    final signalsService = getIt<SignalsService>();
    final rouletteService = getIt<RouletteService>();
    final wsService = getIt<WebSocketService>();
    final webViewService = getIt<WebViewService>();

    try {
      final params = await rouletteService.extractWebSocketParams(game);
      final results = await wsService.fetchRecentResults(params);

      if (results != null) {
        Logger.info(
            "Received results for game ${game.id}, kickout: ${results.kickoutReason}");
        if (results.kickoutReason == 'notAuthorised') {
          // Если отключили из-за неавторизации, запускаем процесс логина
          await webViewService.startLoginProcess((jwt, cookies) {
            getIt<SessionManager>()
                .saveSession(jwtToken: jwt, cookieHeader: cookies);
            // После успешного логина пробуем подключиться снова
            _connectGame(game);
          });
        } else {
          Logger.info(
              "Processing results for game ${game.id} with kickout: ${results.kickoutReason}");
          signalsService.processResults(
            game.id,
            results.numbers,
            kickoutReason: results.kickoutReason,
          );
          Logger.info("Results processed for game ${game.id}");
        }
      }
    } catch (e) {
      Logger.error("Error connecting to game ${game.title}", e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Ошибка подключения к ${game.title}")),
        );
      }
    }

    if (mounted) {
      setState(() {
        _connectingGame = false;
        _activeGameId = null;
      });
    }
  }

  Future<void> _toggleAutoAnalysis() async {
    final signalsService = getIt<SignalsService>();
    final rouletteService = getIt<RouletteService>();
    final wsService = getIt<WebSocketService>();

    if (!_autoRunning) {
      final gameIds = _games.map((g) => g.id).toList();
      signalsService.startAutoAnalysis(
        Duration(seconds: 20),
        gameIds,
        (String gameId) async {
          final game = _games.firstWhere((g) => g.id == gameId);
          final params = await rouletteService.extractWebSocketParams(game);
          final recent = await wsService.fetchRecentResults(params);
          return recent?.numbers ?? <int>[];
        },
      );
    } else {
      signalsService.stopAutoAnalysis();
    }
    setState(() {
      _autoRunning = !_autoRunning;
    });
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
