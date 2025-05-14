enum SignalType {
  patternDozen9,
  patternRow9,
  connectionKickout,
  emptyAnalysis,
  errorImConnection
}

class Signal {
  final SignalType type;
  final String message;
  final List<int> lastNumbers;
  final List<int> uniqNumbers;
  final List<int> patternPositions;
  final DateTime timestamp;

  Signal({
    required this.type,
    required this.message,
    required this.lastNumbers,
    required this.uniqNumbers,
    required this.patternPositions,
    required this.timestamp,
  });
}
