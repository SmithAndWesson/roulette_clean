class RouletteGame {
  final String id;
  final String title;
  final String provider;
  final String identifier;
  final String playUrl;
  final String slug;
  final List<String> collections;
  bool isAnalyzing;

  RouletteGame({
    required this.id,
    required this.title,
    required this.provider,
    required this.identifier,
    required this.playUrl,
    required this.slug,
    required this.collections,
    this.isAnalyzing = false,
  });

  factory RouletteGame.fromJson(Map<String, dynamic> json) {
    return RouletteGame(
      id: json['id'].toString(),
      title: json['title'] as String,
      provider: json['provider'] as String,
      identifier: json['identifier'] as String,
      playUrl: json['play_url']?['UAH'] ?? '',
      slug: json['slug'] as String,
      collections: List<String>.from(json['collections'] ?? []),
    );
  }
}
