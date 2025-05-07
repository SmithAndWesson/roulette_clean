import 'package:webview_flutter/webview_flutter.dart';
import 'package:roulette_clean/core/constants/app_constants.dart';
import 'package:roulette_clean/utils/logger.dart';
import 'dart:convert';
import 'dart:async';

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

  /// Запускает процесс авторизации и вызывает [onLoginSuccess], когда в localStorage
  /// появляется JWT и в document.cookie существует original_user_id.
  // Future<void> startLoginProcess(
  //   void Function(String jwt, String cookies) onLoginSuccess,
  // ) async {
  //   await initialize();
  //   await _controller.loadRequest(Uri.parse(BASE_URL));

  //   // опрос каждые 0.5 с
  //   Timer.periodic(const Duration(milliseconds: 500), (timer) async {
  //     try {
  //       final jsJwt = await _controller.runJavaScriptReturningResult(
  //           'localStorage.getItem("$JWT_STORAGE_KEY")');
  //       final jsCookies =
  //           await _controller.runJavaScriptReturningResult('document.cookie');

  //       final jwt = _cleanResult(jsJwt);
  //       final cookies = _cleanResult(jsCookies);

  //       if (jwt.isNotEmpty && cookies.contains("original_user_id=")) {
  //         Logger.debug('[login] jwt="$jwt" cookies="$cookies"');

  //         timer.cancel();
  //         onLoginSuccess(jwt, cookies);
  //       }
  //     } catch (_) {
  //       /* страница ещё не готова — игнорируем */
  //     }
  //   });
  // }

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
    if (result == null) return '';
    final str = result.toString();
    if (str == 'null') return ''; // ← добавьте
    return str.replaceAll('"', '').trim();
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

  Future<void> clearWebView() async {
    await _controller.clearCache();
    await WebViewCookieManager().clearCookies();
    await _controller.clearLocalStorage();
  }

  Future<void> resetDomWithoutLogout() async {
    try {
      await _controller.runJavaScript('document.body.innerHTML = ""');
      await _controller.runJavaScript('''
      const iframe = document.querySelector('iframe');
      if (iframe) iframe.src = 'about:blank';
    ''');
      await _controller.loadRequest(Uri.parse('about:blank'));
    } catch (e) {
      Logger.warning("Failed to reset DOM: $e");
    }
  }
}
