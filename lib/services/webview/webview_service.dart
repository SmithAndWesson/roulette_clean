import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart' as wfa;

import 'package:webview_cookie_manager/webview_cookie_manager.dart'
    as wcm; // ← алиас
import 'package:roulette_clean/core/constants/app_constants.dart';
import 'package:roulette_clean/utils/logger.dart';
import 'dart:convert';
import 'dart:async';

class WebViewService {
  late final WebViewController _controller;
  late final wcm.WebviewCookieManager _cookieManager;
  bool _initialized = false;
  StreamController<String>? _channel;

  WebViewController get controller => _controller;
  wcm.WebviewCookieManager get cookieManager => _cookieManager;

  WebViewService() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(false);
    _cookieManager = wcm.WebviewCookieManager();
    _enable3PCookiesIfAndroid();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
  }

  Future<void> _enable3PCookiesIfAndroid() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    // 1. получаем platform-специфичный контроллер
    final androidCtrl = _controller.platform as wfa.AndroidWebViewController;

    // 2. вытаскиваем уже созданный платформой менеджер куков
    final wfa.AndroidWebViewCookieManager androidCookieMgr =
        WebViewCookieManager().platform as wfa.AndroidWebViewCookieManager;

    // 3. разрешаем third-party cookies для ЭТОГО webview
    await androidCookieMgr.setAcceptThirdPartyCookies(androidCtrl, true);
  }

  // / Запускает процесс авторизации и вызывает [onLoginSuccess], когда в localStorage
  // / появляется JWT и в document.cookie существует original_user_id.
  Future<void> startLoginProcess(
    void Function(String jwt, String cookies) onLoginSuccess,
  ) async {
    await initialize();
    await _controller.loadRequest(Uri.parse(BASE_URL));

    // опрос каждые 0.5 с
    Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      try {
        final jsJwt = await _controller.runJavaScriptReturningResult(
            'localStorage.getItem("$JWT_STORAGE_KEY")');
        final jsCookies =
            await _controller.runJavaScriptReturningResult('document.cookie');

        final jwt = _cleanResult(jsJwt);
        final cookies = _cleanResult(jsCookies);

        if (jwt.isNotEmpty && cookies.contains("original_user_id=")) {
          Logger.debug('[login] jwt="$jwt" cookies="$cookies"');

          timer.cancel();
          onLoginSuccess(jwt, cookies);
        }
      } catch (_) {
        /* страница ещё не готова — игнорируем */
      }
    });
  }

//   Future<void> startLoginProcess(
//       Function(String jwt, String cookies) onLoginSuccess) async {
//     await initialize();

//     _controller.setNavigationDelegate(NavigationDelegate(
//       onPageFinished: (url) async {
//         final jsJwt = await _controller.runJavaScriptReturningResult(
//             'localStorage.getItem("$JWT_STORAGE_KEY")');
//         final jsCookies =
//             await _controller.runJavaScriptReturningResult('document.cookie');

//         String jwt = _cleanResult(jsJwt);
//         String cookieStr = _cleanResult(jsCookies);
//         Logger.debug('[login] jwt="$jwt" cookies="$cookieStr"');
//         final hasAuth =
//             jwt.isNotEmpty && cookieStr.contains("original_user_id=");
//         if (hasAuth) {
//           Logger.debug('[login] jwt="$jwt" cookies="$cookieStr"');
//           // 1️⃣ Меняем делегат на «пустой»
//           _controller.setNavigationDelegate(NavigationDelegate());
//           onLoginSuccess(jwt, cookieStr);
//         }
//       },
//       // onHttpError: (HttpResponseError err) {
//       //   final reqUrl = err.request?.uri.toString();
//       //   final code = err.response?.statusCode ?? -1;

//       //   if (code == 429) {
//       //     // вместо ошибки — ждём 5 сек и повторяем загрузку
//       //     Logger.warning('HTTP 429 on $reqUrl → retrying in 5s');
//       //     Future.delayed(const Duration(seconds: 5), () {});
//       //     return;
//       //   }
//       // },
//     ));
// // глобальный навигатор, чтобы ловить onPageFinished
//     // _controller.setNavigationDelegate(
//     //   NavigationDelegate(onPageFinished: (url) => _dumpCookies(url)),
//     // );
//     await _controller.loadRequest(Uri.parse(BASE_URL));
//     // await Future.delayed(const Duration(seconds: 5));

//     // await _controller.loadRequest(Uri.parse(
//     //     'https://gizbo.casino/online-live-casino/speed-roulette-evolution-online'));
//     // await Future.delayed(const Duration(seconds: 15));
//     // final cookies = await _cookieManager.getCookies('.evo-games.com');
//     // Logger.debug('Cookies: $cookies');
//     // await _controller.loadRequest(Uri.parse('https://royal.evo-games.com'));
//   }

  // WebViewService
  Future<void> logCookies(String url) => _dumpCookies(url);

  /// Печатает куки двумя способами
  Future<void> _dumpCookies(String? finishedUrl) async {
    if (finishedUrl == null) return;

    // 1) всё, что лежит в native cookie-store
    final list = await _cookieManager.getCookies(finishedUrl);
    final native = list.map((c) => '${c.name}=${c.value}').join('; ');
    Logger.debug('🍪 [native][$finishedUrl] $native');

    // 2) то, что «видит» JavaScript  (без HttpOnly)
    try {
      var js =
          await _controller.runJavaScriptReturningResult('document.cookie');
      js = js.toString().replaceAll('"', '');
      Logger.debug('🍪 [JS][$finishedUrl] $js');
    } catch (_) {
      // ignored: может бросить, если страница sandbox / about:blank
    }
  }

  String _cleanResult(Object? result) {
    if (result == null) return '';
    final str = result.toString();
    if (str == 'null') return ''; // ← добавьте
    return str.replaceAll('"', '').trim();
  }

  Future<void> setCookies(String cookieHeader, {required String domain}) async {
    // for (var cookie in cookieHeader.split(';')) {
    //   final parts = cookie.split('=');
    //   if (parts.length != 2) continue;
    //   final name = parts[0].trim(), value = parts[1].trim();
    //   await _cookieManager.setCookie(
    //       WebViewCookie(name: name, value: value, domain: domain, path: "/"));
    // }
  }

  Future<void> clearWebView() async {
    await _controller.clearCache();
    await _cookieManager.clearCookies();
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

  Future<void> closeCurrentWebSocket() async {
    if (_channel != null) {
      final comp = Completer<void>();
      _channel!.sink.close();
      _channel!.stream.listen(
        (_) {},
        onDone: () => comp.complete(),
        onError: (_) => comp.complete(),
        cancelOnError: true,
      );
      // ждём подтверждения закрытия или 1 с максимум
      await comp.future.timeout(const Duration(seconds: 1), onTimeout: () {});
      _channel = null;
    }
  }
}
