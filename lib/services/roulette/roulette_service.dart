import 'dart:convert';
import 'package:get_it/get_it.dart';

import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:roulette_clean/core/constants/app_constants.dart';
import 'package:roulette_clean/models/roulette/roulette_game.dart';
import 'package:roulette_clean/models/websocket/websocket_params.dart';
import 'package:roulette_clean/models/websocket/websocket_params_new.dart';
import 'package:roulette_clean/models/websocket/no_game_exception.dart';
import 'package:roulette_clean/services/webview/webview_service.dart';
import 'package:roulette_clean/services/session/session_manager.dart';
import 'package:roulette_clean/utils/logger.dart';

class TooManyRequestsException implements Exception {
  @override
  String toString() => 'Too many requests (HTTP 429)';
}

class RouletteService {
  final SessionManager _sessionManager;
  final WebViewService _webViewService;
  List<RouletteGame>? _cachedGames;
  DateTime? _lastFetchTime;
  static const _cacheDuration = Duration(minutes: 5);

  RouletteService({
    required SessionManager sessionManager,
    required WebViewService webViewService,
  })  : _sessionManager = sessionManager,
        _webViewService = webViewService;

  Future<List<RouletteGame>> fetchLiveRouletteGames() async {
    if (_cachedGames != null &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < _cacheDuration) {
      return _cachedGames!;
    }

    if (_lastFetchTime != null) {
      final elapsed = DateTime.now().difference(_lastFetchTime!);
      if (elapsed < Duration(seconds: 2)) {
        await Future.delayed(Duration(seconds: 2) - elapsed);
      }
    }

    final url = "$BASE_URL$GAMES_ENDPOINT";
    final response = await http.get(Uri.parse(url));

// Если неавторизован (403) — считаем, что ограничений нет
    if (response.statusCode == 403) {
      return Future.value([]);
    }

    if (response.statusCode == 429) {
      await Future.delayed(Duration(seconds: 5));
      return await fetchLiveRouletteGames();
    }

    if (response.statusCode != 200) {
      throw Exception("Error fetching games: ${response.statusCode}");
    }

    final root = json.decode(response.body) as Map<String, dynamic>;
    Map<String, dynamic> data;
    if (root.containsKey('CmsApiCmsV2GamesUAH')) {
      data = (root['CmsApiCmsV2GamesUAH']['data'] as Map<String, dynamic>);
    } else {
      data = root['data'] ?? root;
    }

    final allGames = data.values.map((g) => RouletteGame.fromJson(g)).toList();
    final rouletteGames = allGames
        .where((game) =>
            game.collections.contains('online_live_casino') &&
            game.collections.contains('live_roulette') &&
            game.slug.contains('online-live-casino') &&
            game.provider.toLowerCase() == 'evolution')
        .toList();

    final restrictions = await _fetchGameRestrictions();
    final restrictedProviders =
        List<String>.from(restrictions['producers'] ?? []);
    final restrictedGames = List<String>.from(restrictions['games'] ?? []);

    final filteredGames = rouletteGames.where((game) {
      final gameKey = game.identifier.replaceFirst('/', ':');
      final isRestricted = restrictedGames.contains(gameKey) ||
          restrictedProviders.contains(game.provider);
      return !isRestricted;
    }).toList();

    _cachedGames = filteredGames;
    _lastFetchTime = DateTime.now();
    return filteredGames;
  }

  Future<Map<String, dynamic>> _fetchGameRestrictions() async {
    final url = "$BASE_URL$BATCH_RESTRICTIONS";
    final response = await http.get(Uri.parse(url));
    // Если неавторизован (403) — считаем, что ограничений нет
    if (response.statusCode == 403) {
      return {};
    }
    if (response.statusCode != 200) {
      Logger.warning('Restrictions returned ${response.statusCode}');
      return {};
    }
    final Map<String, dynamic> jsonData = json.decode(response.body);
    return jsonData['restrictions'] ?? {};
  }

  Future<dynamic> extractWebSocketParams(RouletteGame game,
      {int retry = 0}) async {
    // await _webViewService.initialize();
    // final controller = _webViewService.controller;
    var webViewService = GetIt.I<WebViewService>();
    var controller = webViewService.controller;
    await webViewService.resetDomWithoutLogout();
    await Future.delayed(const Duration(seconds: 1));
    // await controller.loadRequest(Uri.parse(BASE_URL));

    final gamePageUrl = "${BASE_URL}${game.playUrl}";
    Logger.info("Loading game page: $gamePageUrl");
    try {
      // for (var attempt = 0; attempt < 3; attempt++) {
      // await controller.loadRequest(Uri.parse(gamePageUrl));
      await _loadOrError(controller, gamePageUrl);

      // ─── сразу после loadRequest(gamePageUrl) ─────────────────────────────
      // await Future.delayed(const Duration(seconds: 3));

      // await Future.delayed(const Duration(seconds: 5));
      const pollInterval = Duration(milliseconds: 150);
      const timeout = Duration(seconds: 10);
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        final currentUrl = (await controller
                .runJavaScriptReturningResult('window.location.href'))
            .toString()
            .replaceAll('"', '');

        if (currentUrl.contains('/errors/no-game') ||
            currentUrl
                .contains('/restricted?reason=game_restricted_in_country')) {
          Logger.warning('Game ${game.id} is disabled → skip');
          throw NoGameException(currentUrl);
        }
        final iframeSrc = (await controller.runJavaScriptReturningResult(r'''
      (() => {
        const f = document.querySelector('iframe');
        return f && f.src ? f.src : '';
      })();
    ''')).toString().replaceAll('"', '').trim();

        if (iframeSrc.startsWith('https://cdn-3.launcher') &&
            iframeSrc.contains('?options=')) {
          Logger.debug('Game iframe src ready: $iframeSrc');

          // ───── ДОБАВЛЯЕМ ЭТО ↓ ─────
          final evoSessionId = await _waitForEvoSessionId(controller);
          // await _webViewService.logCookies('https://royal.evo-games.com');

          Logger.debug('✅ EVOSESSIONID=$evoSessionId');

          return _buildParams(
            iframeSrc,
            game,
            controller,
            retry,
            evoSessionId, // передадим вниз
          );
        }

        await Future.delayed(pollInterval);
      }
      // }

      throw TimeoutException(
          'launcher iframe src not ready for game ${game.identifier}');
    } on TimeoutException catch (e) {
      // если это первый раз и мы не прошли CF-challenge, перезапускаем логин и пробуем ещё раз
      if (retry == 0) {
        Logger.warning('Timeout waiting for iframe → re-login & retry');
        await _loadOrError(controller, BASE_URL);

        // await _webViewService.startLoginProcess((jwt, cookies) {
        //   _sessionManager.saveSession(jwtToken: jwt, cookieHeader: cookies);
        // });
        // небольшая пауза, чтобы куки устаканились
        // await Future.delayed(const Duration(seconds: 1));
        // // рекурсивно вызываем с retry=1
        return extractWebSocketParams(game, retry: 1);
      }
      rethrow;
    } on TooManyRequestsException catch (e) {
      if (retry == 0) {
        Logger.error('429 — пересоздаём WebViewService и ре-логинимся');

        // a) удаляем старый сервис
        GetIt.I.unregister<WebViewService>();
        // б) регистрируем заново
        GetIt.I.registerLazySingleton<WebViewService>(() => WebViewService());

        // в) берём свежий экземпляр
        webViewService = GetIt.I<WebViewService>();
        controller = webViewService.controller;

        // г) делаем полный flow логина, чтобы восстановить куки/JWT
        await webViewService.startLoginProcess((jwt, cookies) {
          _sessionManager.saveSession(jwtToken: jwt, cookieHeader: cookies);
        });
        await Future.delayed(const Duration(seconds: 1));

        // д) и пробуем ещё раз уже на новом контроллере
        return extractWebSocketParams(game, retry: 1);
      }
      rethrow;
    }
  }

  Future<void> _loadOrError(WebViewController controller, String url) async {
    final comp = Completer<void>();

    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (!comp.isCompleted) {
            comp.complete();
          }
        },
        onHttpError: (HttpResponseError err) {
          final reqUrl = err.request?.uri.toString();
          final code = err.response?.statusCode ?? -1;

          if (reqUrl == url && code == 400) {
            Future.delayed(const Duration(seconds: 5), () {
              if (!comp.isCompleted) {
                comp.completeError(TimeoutException(url)); //NoGameException
              }
            });
          }
          if (code == 429) {
            // вместо ошибки — ждём 5 сек и повторяем загрузку
            Logger.warning('HTTP 429 on $url → retrying in 5s');
            Future.delayed(const Duration(seconds: 5), () {
              if (!comp.isCompleted) {
                comp.completeError(TooManyRequestsException());
              }
            });
          }
        },
        onWebResourceError: (_) {
          // можно по желанию comp.completeError(...)
        },
      ),
    );

    await controller.loadRequest(Uri.parse(url));
    // ждём либо onPageFinished, либо completeError
    return comp.future.timeout(
      const Duration(seconds: 7),
      onTimeout: () => throw TimeoutException('Load timed out for $url'),
    );
  }

  Future<String> _waitForEvoSessionId(WebViewController c) async {
    const timeout = Duration(seconds: 3);
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      // 1) сначала смотрим куки WebView (есть HttpOnly)
      final cookies = await _webViewService.cookieManager
          .getCookies('https://royal.evo-games.com');
      final evo = cookies.firstWhere(
        (ck) => ck.name == 'EVOSESSIONID' && ck.value.isNotEmpty,
        orElse: () => Cookie('', ''),
      );
      if (evo != null) return evo.value;

      // 2) fallback ­— берём из localStorage (старый способ)
      final ls = (await c.runJavaScriptReturningResult(
        'localStorage.getItem("evo.video.sessionId") ?? ""',
      ))
          .toString()
          .replaceAll('"', '');
      if (ls.isNotEmpty) return ls;

      await Future.delayed(const Duration(milliseconds: 250));
    }
    throw TimeoutException('Не получили EVOSESSIONID за $timeout');
  }

  Future<dynamic> _buildParams(
    String iframeSrc,
    RouletteGame game,
    WebViewController controller,
    int retry,
    String evoSessionId,
  ) async {
    // 1) разбираем launch_options (остаётся для загрузки gameUrl)
    final iframeUri = Uri.parse(iframeSrc);
    final optionsEncoded = iframeUri.queryParameters['options']!;
    final optionsJson =
        utf8.decode(base64.decode(_normalizeBase64(optionsEncoded)));
    final optionsMap = json.decode(optionsJson) as Map<String, dynamic>;
    final launchOpts = optionsMap['launch_options'] as Map<String, dynamic>;
    final gameUrl = launchOpts['game_url'] as String;
    Logger.debug("Parsed game_url: $gameUrl");

    Logger.info("Loading provider URL to obtain session...");

    final gameUri = Uri.parse(gameUrl);
    final paramsEncoded = gameUri.queryParameters['params'];
    if (paramsEncoded == null) {
      throw Exception('Параметр params не найден в game_url');
    }
    final paramsNorm = _normalizeBase64(paramsEncoded);
    final paramsJson = utf8.decode(base64.decode(paramsNorm));
    final paramsMap = _parseKeyValueString(paramsJson);

    final gameStr =
        paramsMap['game'] ?? (throw NoGameException('game missing'));
    final tableId =
        paramsMap['table_id'] ?? (throw NoGameException('table_id missing'));
    final tableConfig =
        paramsMap['vt_id'] ?? (throw NoGameException('vt_id missing'));

    // 5) собираем cookie‑header
    final rawCookies =
        (await controller.runJavaScriptReturningResult('document.cookie'))
            .toString();
    final cookieHeader = rawCookies.contains('EVOSESSIONID=')
        ? rawCookies
        : '$rawCookies; EVOSESSIONID=$evoSessionId';

    // 6) client_version фиксируем (из network‑логов)
    const clientVersion = '6.20250506.72419.51567-44abfa1805';
    final rnd = Random().nextInt(1 << 20).toRadixString(36);
    final instance = '$rnd-${evoSessionId.substring(0, 16)}-$tableConfig';
    await controller.loadRequest(Uri.parse('about:blank'));
    // если у вас уже открыт канал к этому tableId → закрыть
    await _webViewService.closeCurrentWebSocket();

// 1-секундная пауза, чтобы iframe успел зарегистрироваться
    await Future.delayed(const Duration(seconds: 1));
    // 7) возвращаем новый params
    return WebSocketParamsNew(
      game: gameStr,
      tableId: tableId,
      tableConfig: tableConfig,
      evoSessionId: evoSessionId,
      clientVersion: clientVersion,
      instance: instance,
      cookieHeader: cookieHeader,
    );
  }

// вспомогательный — убирает кавычки / null
  String _normalizeString(String v) => v.replaceAll('"', '').trim() == 'null'
      ? ''
      : v.replaceAll('"', '').trim();

  String _normalizeBase64(String input) {
    var cleaned = input.replaceAll(RegExp(r'[^A-Za-z0-9+/]'), '');
    final mod = cleaned.length % 4;
    if (mod != 0) cleaned += '=' * (4 - mod);
    return cleaned;
  }

  Map<String, String> _parseKeyValueString(String input) {
    final Map<String, String> result = {};
    for (var line in input.split('\n')) {
      if (!line.contains('=')) continue;
      final idx = line.indexOf('=');
      final key = line.substring(0, idx).trim();
      final value = line.substring(idx + 1).trim();
      result[key] = value;
    }
    return result;
  }
}
