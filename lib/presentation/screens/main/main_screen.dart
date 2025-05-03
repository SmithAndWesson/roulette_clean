import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:roulette_clean/core/di/service_locator.dart';
import 'package:roulette_clean/models/roulette/roulette_game.dart';
import 'package:roulette_clean/models/signal.dart';
import 'package:roulette_clean/services/roulette/roulette_service.dart';
import 'package:roulette_clean/services/signals/signals_service.dart';
import 'package:roulette_clean/services/websocket/websocket_service.dart';
import 'package:roulette_clean/presentation/widgets/roulette_card.dart';
import 'package:roulette_clean/utils/logger.dart';
import 'package:roulette_clean/services/session/session_manager.dart';
import 'package:roulette_clean/utils/sound_player.dart';

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

    try {
      final params = await rouletteService.extractWebSocketParams(game);
      final results = await wsService.fetchRecentResults(params);

      if (results != null) {
        signalsService.processResults(game.id, results.numbers);
      }
    } catch (e) {
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
        Duration(seconds: 5),
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
            icon: const Icon(Icons.refresh),
            onPressed: _loadGames,
          ),
          IconButton(
            icon: const Icon(Icons.volume_up),
            tooltip: 'Тест звука',
            onPressed: () {
              SoundPlayer.i.playPing();
            },
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            tooltip: 'Выйти',
            onPressed: () {
              getIt<SessionManager>().clearSession();
              signalsService.stopAutoAnalysis();
              Navigator.pushNamedAndRemoveUntil(
                  context, '/login', (route) => false);
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
                ? const Center(child: CircularProgressIndicator())
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
