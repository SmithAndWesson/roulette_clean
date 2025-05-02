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

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  List<RouletteGame> _games = [];
  bool _loadingGames = false;
  bool _connectingGame = false;
  String? _activeGameId;

  @override
  void initState() {
    super.initState();
    _loadGames();
  }

  Future<void> _loadGames() async {
    setState(() => _loadingGames = true);
    try {
      _games = await getIt<RouletteService>().fetchLiveRouletteGames();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ошибка загрузки игр")),
        );
      }
    }
    if (mounted) {
      setState(() => _loadingGames = false);
    }
  }

  Future<void> _connectGame(RouletteGame game) async {
    setState(() {
      _connectingGame = true;
      _activeGameId = game.id;
    });

    final rouletteService = getIt<RouletteService>();
    final wsService = getIt<WebSocketService>();
    final signalsService = getIt<SignalsService>();

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
        ],
      ),
      body: _loadingGames
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadGames,
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.8,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _games.length,
                itemBuilder: (context, index) {
                  final game = _games[index];
                  final signals = signalsService.getSignalsForGame(game.id);
                  return RouletteCard(
                    game: game,
                    signals: signals,
                    isConnecting: _connectingGame && _activeGameId == game.id,
                    onConnect: () => _connectGame(game),
                  );
                },
              ),
            ),
    );
  }
}
