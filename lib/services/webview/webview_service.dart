import 'package:webview_flutter/webview_flutter.dart';
import 'package:roulette_clean/core/constants/app_constants.dart';
import 'package:roulette_clean/utils/logger.dart';

class WebViewService {
  late final WebViewController _controller;
  bool _initialized = false;

  WebViewController get controller => _controller;

  WebViewService() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(false);
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
  }

  Future<void> startLoginProcess(
      Function(String jwt, String cookies) onLoginSuccess) async {
    await initialize();
    await _controller.loadRequest(Uri.parse(BASE_URL));

    _controller.setNavigationDelegate(NavigationDelegate(
      onPageFinished: (url) async {
        final jsJwt = await _controller.runJavaScriptReturningResult(
            'localStorage.getItem("$JWT_STORAGE_KEY")');
        final jsCookies =
            await _controller.runJavaScriptReturningResult('document.cookie');

        String jwt = _cleanResult(jsJwt);
        String cookieStr = _cleanResult(jsCookies);

        final hasAuth =
            jwt.isNotEmpty && cookieStr.contains("original_user_id=");
        if (hasAuth) {
          onLoginSuccess(jwt, cookieStr);
        }
      },
    ));
  }

  String _cleanResult(Object? result) {
    if (result == null) return "";
    return result.toString().replaceAll('"', '').trim();
  }

  Future<void> setCookies(String cookieHeader, {required String domain}) async {
    final cookieManager = WebViewCookieManager();
    for (var cookie in cookieHeader.split(';')) {
      final parts = cookie.split('=');
      if (parts.length != 2) continue;
      final name = parts[0].trim(), value = parts[1].trim();
      await cookieManager.setCookie(
          WebViewCookie(name: name, value: value, domain: domain, path: "/"));
    }
  }
}
