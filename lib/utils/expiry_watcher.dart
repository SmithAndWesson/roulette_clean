class ExpiryWatcher {
  static final _expiryDate = DateTime(2025, 5, 10);

  static bool isExpired() {
    return DateTime.now().isAfter(_expiryDate);
  }
}
