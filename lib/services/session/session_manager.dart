import 'package:shared_preferences/shared_preferences.dart';
import 'package:roulette_clean/core/constants/app_constants.dart';

class SessionManager {
  String? _jwtToken;
  String? _cookieHeader;

  String? get jwtToken => _jwtToken;
  String? get cookieHeader => _cookieHeader;

  void saveSession({required String jwtToken, required String cookieHeader}) {
    _jwtToken = jwtToken;
    _cookieHeader = cookieHeader;

    // Сохраняем в SharedPreferences
    final prefs = SharedPreferences.getInstance();
    prefs.then((instance) {
      instance.setString(JWT_STORAGE_KEY, jwtToken);
      instance.setString('COOKIE_HEADER', cookieHeader);
    });
  }

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _jwtToken = prefs.getString(JWT_STORAGE_KEY);
    _cookieHeader = prefs.getString('COOKIE_HEADER');
  }

  bool get isLoggedIn {
    if (_jwtToken == null) return false;
    // TODO: Проверка срока действия JWT
    return true;
  }

  void clearSession() {
    _jwtToken = null;
    _cookieHeader = null;

    final prefs = SharedPreferences.getInstance();
    prefs.then((instance) {
      instance.remove(JWT_STORAGE_KEY);
      instance.remove('COOKIE_HEADER');
    });
  }
}
