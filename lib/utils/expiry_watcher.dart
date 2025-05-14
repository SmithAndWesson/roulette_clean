class ExpiryWatcher {
  static final _expiryDate = DateTime.parse('2025-05-20T00:59:00+03:00');

  static bool isExpired() {
    return DateTime.now().isAfter(_expiryDate);
  }
}
