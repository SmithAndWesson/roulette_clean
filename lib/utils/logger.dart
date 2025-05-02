class Logger {
  static void debug(String message) {
    // print("[DEBUG] $message");
  }

  static void info(String message) {
    print("[INFO] $message");
  }

  static void warning(String message) {
    print("[WARN] $message");
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    print("[ERROR] $message");
    if (error != null) print("   Error: $error");
    if (stackTrace != null) print("   Stack: $stackTrace");
  }
}
