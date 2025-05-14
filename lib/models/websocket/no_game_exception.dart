class NoGameException implements Exception {
  final String url;
  NoGameException(this.url);

  @override
  String toString() => 'NoGameException: $url';
}
