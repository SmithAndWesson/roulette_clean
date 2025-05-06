import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:roulette_clean/models/signal.dart';
import 'package:roulette_clean/services/roulette/number_analyzer.dart';
import 'package:roulette_clean/utils/sound_player.dart';
import 'package:roulette_clean/utils/logger.dart';

class SignalsService extends ChangeNotifier {
  final NumberAnalyzer _numberAnalyzer = NumberAnalyzer();
  final Map<String, List<Signal>> _gameSignals = {};
  String? _currentAnalyzingGameId;

  String? get currentAnalyzingGameId => _currentAnalyzingGameId;

  List<Signal> getSignalsForGame(String gameId) {
    final signals = _gameSignals[gameId] ?? [];
    // Logger.debug("Getting signals for game $gameId: ${signals.length} signals");
    return signals;
  }

  void clearSignals() {
    Logger.info("Clearing all signals");
    _gameSignals.clear();
    notifyListeners();
  }

  void processResults(String gameId, List<int> recentNumbers,
      {String? kickoutReason}) {
    Logger.info("Processing results for game $gameId, kickout: $kickoutReason");

    if (kickoutReason != null) {
      // Создаем сигнал отключения
      _gameSignals[gameId] = [
        Signal(
          type: SignalType.connectionKickout,
          message: "Отключено: $kickoutReason",
          lastNumbers: [],
          timestamp: DateTime.now(),
        )
      ];
      Logger.info("Created kickout signal for game $gameId: $kickoutReason");
      Logger.info("Current signals state: $_gameSignals");
      notifyListeners();
      return;
    }

    // Очищаем сигналы для этой игры перед новым анализом
    _gameSignals.remove(gameId);
    Logger.info("Cleared signals for game $gameId");

    final signals = _numberAnalyzer.detectMissingDozenOrRow(recentNumbers);

    if (signals.isNotEmpty) {
      _gameSignals[gameId] = signals;
      Logger.info("Created ${signals.length} signals for game $gameId");
      Logger.info("Current signals state: $_gameSignals");

      for (Signal signal in signals) {
        SoundPlayer.i.playPing();
      }

      notifyListeners();
    } else {
      notifyListeners();
    }
  }

  Timer? _autoTimer;
  int _currentGameIndex = 0;

  void startAutoAnalysis(
    Duration interval,
    List<String> gameIds,
    Future<List<int>> Function(String) fetchResults,
  ) {
    _autoTimer?.cancel();
    _currentGameIndex = 0;

    Future<void> analyzeNextGame() async {
      if (_currentGameIndex >= gameIds.length) {
        _currentGameIndex = 0;
      }

      final gameId = gameIds[_currentGameIndex];
      Logger.info("Starting analysis for game $gameId");
      _currentAnalyzingGameId = gameId;
      notifyListeners();

      try {
        final numbers = await fetchResults(gameId);
        processResults(gameId, numbers);
      } catch (e) {
        Logger.error("Error analyzing game $gameId", e);
      }

      // Сначала уведомляем об изменениях для текущей игры
      notifyListeners();

      // Затем обновляем индекс и ID следующей игры
      _currentGameIndex++;
      if (_currentGameIndex >= gameIds.length) {
        _currentGameIndex = 0;
      }
      final nextGameId = gameIds[_currentGameIndex];
      Logger.info("Moving to next game: $nextGameId");
      _currentAnalyzingGameId = nextGameId;
      notifyListeners();
    }

    // Сначала анализируем первую игру
    analyzeNextGame();

    // Затем запускаем таймер для последующих игр
    _autoTimer = Timer.periodic(interval, (_) {
      analyzeNextGame();
    });
  }

  void stopAutoAnalysis() {
    _autoTimer?.cancel();
    _autoTimer = null;
    _currentGameIndex = 0;
    _currentAnalyzingGameId = null;
    SoundPlayer.i.dispose();
    notifyListeners();
  }
}
