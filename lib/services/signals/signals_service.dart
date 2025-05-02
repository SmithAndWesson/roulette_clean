import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:roulette_clean/models/signal.dart';
import 'package:roulette_clean/services/roulette/number_analyzer.dart';
import 'package:roulette_clean/utils/sound_player.dart';

class SignalsService extends ChangeNotifier {
  final NumberAnalyzer _numberAnalyzer = NumberAnalyzer();
  final Map<String, List<Signal>> _gameSignals = {};

  List<Signal> getSignalsForGame(String gameId) {
    return _gameSignals[gameId] ?? [];
  }

  void processResults(String gameId, List<int> recentNumbers) {
    final signals = _numberAnalyzer.detectMissingDozenOrRow(recentNumbers);

    if (signals.isNotEmpty) {
      _gameSignals[gameId] = signals;

      for (Signal signal in signals) {
        SoundPlayer.play("alert.wav");
      }

      notifyListeners();
    } else {
      _gameSignals.remove(gameId);
      notifyListeners();
    }
  }

  Timer? _autoTimer;

  void startAutoAnalysis(
    Duration interval,
    List<String> gameIds,
    Future<List<int>> Function(String) fetchResults,
  ) {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(interval, (_) async {
      for (String id in gameIds) {
        try {
          final numbers = await fetchResults(id);
          processResults(id, numbers);
        } catch (_) {
          // ignore fetch errors in auto mode
        }
      }
    });
  }

  void stopAutoAnalysis() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }
}
