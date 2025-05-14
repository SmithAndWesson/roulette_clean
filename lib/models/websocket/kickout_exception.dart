class KickoutException implements Exception {
  final String reason;
  KickoutException(this.reason);
  @override
  String toString() => 'KickoutException: $reason';
}
