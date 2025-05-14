import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
    // notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
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
          uniqNumbers: [],
          patternPositions: [],
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

      for (Signal signal in signals) {
        Logger.info("Current signals state: ${signal.message}");
        SoundPlayer.i.playPing();
      }

      notifyListeners();
    } else {
      final first3 = recentNumbers.take(3).join(', ');
      _gameSignals[gameId] = [
        Signal(
          type: recentNumbers.isEmpty
              ? SignalType.errorImConnection
              : SignalType.emptyAnalysis,
          message: recentNumbers.isEmpty
              ? "Нет соединения"
              : "Проанализирована ($first3)",
          lastNumbers: recentNumbers.take(60).toList(),
          uniqNumbers: [],
          patternPositions: [],
          timestamp: DateTime.now(),
        )
      ];
      notifyListeners();
    }
  }

  Timer? _autoTimer;
  int _currentGameIndex = 0;

  void startAutoAnalysis(
    Duration interval,
    List<String> gameIds,
    Future<List<int>?> Function(String) fetchResults, // ← nullable
  ) {
    stopAutoAnalysis(); // отменяем прежний, если был
    _currentGameIndex = 0;

    _autoTimer = Timer(
      Duration.zero,
      () async {
        while (_autoTimer != null) {
          final gameId = gameIds[_currentGameIndex];
          Logger.info("Starting analysis for game $gameId");
          _currentAnalyzingGameId = gameId;
          notifyListeners();

          try {
            final numbers = await fetchResults(gameId);

            // ⚠️ обрабатываем только когда пришли числа
            if (numbers != null && numbers.isNotEmpty) {
              processResults(gameId, numbers);
            }
          } catch (e) {
            Logger.error("Error analyzing game $gameId", e);
          }

          _currentGameIndex = (_currentGameIndex + 1) % gameIds.length;
          final nextGameId = gameIds[_currentGameIndex];
          Logger.info("Moving to next game: $nextGameId");

          await Future.delayed(interval); // ждём перед следующим запуском
        }
      },
    );
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
