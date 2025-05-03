import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:roulette_clean/models/signal.dart';
import 'package:roulette_clean/services/roulette/number_analyzer.dart';
import 'package:roulette_clean/utils/sound_player.dart';

class SignalsService extends ChangeNotifier {
  final NumberAnalyzer _numberAnalyzer = NumberAnalyzer();
  final Map<String, List<Signal>> _gameSignals = {};
  String? _currentAnalyzingGameId;

  String? get currentAnalyzingGameId => _currentAnalyzingGameId;

  List<Signal> getSignalsForGame(String gameId) {
    return _gameSignals[gameId] ?? [];
  }

  void processResults(String gameId, List<int> recentNumbers) {
    final signals = _numberAnalyzer.detectMissingDozenOrRow(recentNumbers);

    if (signals.isNotEmpty) {
      _gameSignals[gameId] = signals;

      for (Signal signal in signals) {
        SoundPlayer.i.playPing();
      }

      notifyListeners();
    } else {
      _gameSignals.remove(gameId);
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
      _currentAnalyzingGameId = gameId;
      notifyListeners();

      try {
        final numbers = await fetchResults(gameId);
        processResults(gameId, numbers);
      } catch (_) {
        // ignore fetch errors in auto mode
      }

      _currentGameIndex++;
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
