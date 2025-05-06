class RecentResults {
  final List<int> numbers;
  final DateTime timestamp;
  final String? kickoutReason;

  RecentResults({
    required this.numbers,
    required this.timestamp,
    this.kickoutReason,
  });

  factory RecentResults.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('args')) {
      throw FormatException("Invalid recentResults format");
    }

    final args = json['args'] as Map<String, dynamic>;
    final rawList = args['recentResults'] as List? ?? [];

    final numbers = rawList
        .whereType<List>()
        .map((item) {
          if (item.isNotEmpty) {
            String entry = item.first.toString();
            if (entry.contains('x')) {
              return int.parse(entry.split('x').first);
            }
            return int.tryParse(entry) ?? -1;
          }
          return -1;
        })
        .where((n) => n >= 0)
        .toList();

    return RecentResults(
      numbers: numbers,
      timestamp: DateTime.now(),
      kickoutReason: json['args']?['reason'] as String?,
    );
  }
}
