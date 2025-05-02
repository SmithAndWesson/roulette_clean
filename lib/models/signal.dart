enum SignalType { patternDozen9, patternRow9 }

class Signal {
  final SignalType type;
  final String message;
  final List<int> lastNumbers;
  final DateTime timestamp;

  Signal({
    required this.type,
    required this.message,
    required this.lastNumbers,
    required this.timestamp,
  });
}
