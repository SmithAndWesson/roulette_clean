import 'package:roulette_clean/models/signal.dart';

class NumberAnalyzer {
  static const int _numbersToAnalyze = 60;

  List<Signal> detectMissingDozenOrRow(List<int> numbers) {
    if (numbers.length < _numbersToAnalyze) return [];

    final slice = numbers.take(_numbersToAnalyze).toList();
    final result = <Signal>[];

    // Проверяем дюжины (0=1-я дюжина, 1=2-я, 2=3-я)
    for (int dz = 0; dz < 3; dz++) {
      final uniq = <int>{};
      bool lastWasCurrent = false;

      for (int n in slice) {
        bool isCurrentDozen = _getDozenIndex(n) == dz;
        if (isCurrentDozen) {
          if (lastWasCurrent) {
            uniq.clear();
            lastWasCurrent = false;
            continue;
          }
          uniq.add(n);
        }
        lastWasCurrent = isCurrentDozen;

        if (uniq.length >= 9) {
          result.add(_buildDozenSignal(dz, uniq, slice));
          break;
        }
      }
    }

    // Проверяем колонки (0=1-я колонка, 1=2-я, 2=3-я)
    for (int col = 0; col < 3; col++) {
      final uniq = <int>{};
      bool lastWasCurrent = false;

      for (int n in slice) {
        bool isCurrentCol = _getColumnIndex(n) == col;
        if (isCurrentCol) {
          if (lastWasCurrent) {
            uniq.clear();
            lastWasCurrent = false;
            continue;
          }
          uniq.add(n);
        }
        lastWasCurrent = isCurrentCol;
      }

      if (uniq.length >= 9) {
        result.add(_buildColumnSignal(col, uniq, slice));
        break;
      }
    }

    return result;
  }

  int _getDozenIndex(int n) =>
      (n - 1) ~/ 12; // 0 для 1-12, 1 для 13-24, 2 для 25-36
  int _getColumnIndex(int n) =>
      (n - 1) % 3; // 0 для 1-й колонки, 1 для 2-й, 2 для 3-й

  Signal _buildDozenSignal(int dozenIndex, Set<int> uniq, List<int> lastNums) {
    final dozenLabel = "${dozenIndex + 1}-я дюжина";
    return Signal(
      type: SignalType.patternDozen9,
      message: "Шаблон 9 уникальных ($dozenLabel): ${uniq.join(", ")}",
      lastNumbers: List.from(lastNums),
      timestamp: DateTime.now(),
    );
  }

  Signal _buildColumnSignal(int colIndex, Set<int> uniq, List<int> lastNums) {
    final colLabel = "${colIndex + 1}-й ряд";
    return Signal(
      type: SignalType.patternRow9,
      message: "Шаблон 9 уникальных ($colLabel): ${uniq.join(", ")}",
      lastNumbers: List.from(lastNums),
      timestamp: DateTime.now(),
    );
  }
}
