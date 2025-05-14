import 'package:roulette_clean/models/signal.dart';

class NumberAnalyzer {
  static const int _numbersToAnalyze = 60;

  List<Signal> detectMissingDozenOrRow(List<int> numbers) {
    if (numbers.length < _numbersToAnalyze) return [];

    final slice = numbers.take(_numbersToAnalyze).toList();
    final result = <Signal>[];

    // Проверяем дюжины (0=1-я дюжина, 1=2-я, 2=3-я)
    for (int dz = 0; dz < 3; dz++) {
      final signal = _detectPattern(
        slice,
        dz,
        _getDozenIndex,
        (index, uniq, nums, pos) => _buildDozenSignal(index, uniq, nums, pos),
      );
      if (signal != null) result.add(signal);
    }

    // Проверяем колонки (0=1-я колонка, 1=2-я, 2=3-я)
    for (int col = 0; col < 3; col++) {
      final signal = _detectPattern(
        slice,
        col,
        _getColumnIndex,
        (index, uniq, nums, pos) => _buildColumnSignal(index, uniq, nums, pos),
      );
      if (signal != null) result.add(signal);
    }

    return result;
  }

  Signal? _detectPattern(
    List<int> numbers,
    int targetIndex,
    int Function(int) getIndex,
    Signal Function(int, Set<int>, List<int>, List<int>) buildSignal,
  ) {
    final uniq = <int>{};
    final pos = <int>[];
    bool lastWasCurrent = false;

    for (int i = 0; i < numbers.length; i++) {
      final n = numbers[i];
      if (n == 0) {
        lastWasCurrent = false;
        continue;
      }

      final isCurrent = getIndex(n) == targetIndex;
      if (isCurrent) {
        if (lastWasCurrent || uniq.contains(n)) {
          uniq.clear();
          pos.clear();
          uniq.add(n);
          pos.add(i);
          continue;
        }
        uniq.add(n);
        pos.add(i);
      }
      lastWasCurrent = isCurrent;

      if (uniq.length >= 9) {
        return buildSignal(targetIndex, uniq, numbers, pos);
      }
    }
    return null;
  }

  int _getDozenIndex(int n) =>
      (n - 1) ~/ 12; // 0 для 1-12, 1 для 13-24, 2 для 25-36
  int _getColumnIndex(int n) =>
      (n - 1) % 3; // 0 для 1-й колонки, 1 для 2-й, 2 для 3-й

  Signal _buildDozenSignal(
      int dozenIndex, Set<int> uniq, List<int> lastNums, List<int> positions) {
    final dozenLabel = "${dozenIndex + 1}-я дюжина";
    return Signal(
      type: SignalType.patternDozen9,
      message: "Шаблон 9 уникальных ($dozenLabel): ${uniq.join(", ")}",
      lastNumbers: List.from(lastNums),
      uniqNumbers: List.from(uniq),
      patternPositions: List.from(positions),
      timestamp: DateTime.now(),
    );
  }

  Signal _buildColumnSignal(
      int colIndex, Set<int> uniq, List<int> lastNums, List<int> positions) {
    final colLabel = "${colIndex + 1}-й ряд";
    return Signal(
      type: SignalType.patternRow9,
      message: "Шаблон 9 уникальных ($colLabel): ${uniq.join(", ")}",
      lastNumbers: List.from(lastNums),
      uniqNumbers: List.from(uniq),
      patternPositions: List.from(positions),
      timestamp: DateTime.now(),
    );
  }
}
