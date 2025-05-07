import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:roulette_clean/core/constants/app_constants.dart';
import 'package:roulette_clean/models/roulette/roulette_game.dart';
import 'package:roulette_clean/models/websocket/websocket_params.dart';
import 'package:roulette_clean/models/websocket/websocket_params_new.dart';
import 'package:roulette_clean/services/webview/webview_service.dart';
import 'package:roulette_clean/services/session/session_manager.dart';
import 'package:roulette_clean/utils/logger.dart';

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
    await _webViewService.initialize();
    final controller = _webViewService.controller;

    final cookies = _sessionManager.cookieHeader;
    if (cookies != null && cookies.isNotEmpty) {
      await _webViewService.setCookies(cookies, domain: ".gizbo.casino");
      await _webViewService.setCookies(cookies, domain: ".evo-games.com");
    }

    final gamePageUrl = "${BASE_URL}${game.playUrl}";
    Logger.info("Loading game page: $gamePageUrl");

    const timeout = Duration(seconds: 20);
    for (var attempt = 0; attempt < 3; attempt++) {
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        final iframeSrc = (await controller.runJavaScriptReturningResult(r'''
          (() => {
            const f = document.querySelector('iframe');
            return f && f.src ? f.src : '';
          })();
        ''')).toString().replaceAll('"', '').trim();

        if (iframeSrc.startsWith('http') && iframeSrc.contains('?options=')) {
          Logger.debug('Game iframe src ready: $iframeSrc');
          return _buildParams(iframeSrc, game, controller, retry);
        }

        await Future.delayed(const Duration(milliseconds: 300));
      }

      // iframe не появился — попробуем ещё раз
      await controller.loadRequest(Uri.parse('about:blank'));
      await Future.delayed(const Duration(seconds: 1));
      await controller.loadRequest(Uri.parse(gamePageUrl));
    }

    throw TimeoutException(
        'launcher iframe src not ready for game ${game.identifier}');
  }

  Future<bool> _loadEntryAndCheckAuth(WebViewController c, String url) async {
    final Completer<bool> ok =
        Completer(); // «true» – всё норм, «false» – EV.12

    // временный делегат
    c.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) async {
          final body = (await c.runJavaScriptReturningResult(
                  'document.body && document.body.innerText ? document.body.innerText : ""'))
              .toString()
              .replaceAll('"', '')
              .toLowerCase();

          final isEv12 = body.contains('ev.12') ||
              body.contains('user authentication failed');

          if (!ok.isCompleted) ok.complete(!isEv12);
        },
        onWebResourceError: (WebResourceError e) {
          // safety‑net: если придёт 403 в onWebResourceError
          if (!ok.isCompleted) ok.complete(false);
        },
      ),
    );

    await c.loadRequest(Uri.parse(url));

    // ждём, но не дольше 15 с
    return ok.future
        .timeout(const Duration(seconds: 15), onTimeout: () => false);
  }

  Future<dynamic> _buildParams(
    String iframeSrc,
    RouletteGame game,
    WebViewController controller,
    int retry,
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

    // // 2) переходим на provider‑страницу, чтобы в localStorage появился EvoLastAppUri
    // Logger.info("Loading provider URL to obtain session...");
    // await controller.loadRequest(Uri.parse(gameUrl));
// 2) переходим на provider‑страницу, чтобы в localStorage появился EvoLastAppUri
    Logger.info("Loading provider URL to obtain session...");

    final ok = await _loadEntryAndCheckAuth(controller, gameUrl);

    if (!ok) {
      // получили EV.12 – пытаемся перелогиниться один раз
      if (retry >= 1) {
        throw Exception('EV.12 even after relogin');
      }
      Logger.warning('EV.12 detected ➜ relogin & retry');

      await _webViewService.startLoginProcess((jwt, cookies) {
        _sessionManager.saveSession(jwtToken: jwt, cookieHeader: cookies);
      });

      // небольшая пауза, чтобы куки установились
      await Future.delayed(const Duration(seconds: 1));

      return extractWebSocketParams(game, retry: retry + 1);
    }

    // 3) ждём evo.video.sessionId (как раньше)
    final evoSessionId = await _waitForEvoSessionId(controller);

    // 4) читаем EvoLastAppUri из localStorage royal.evo-games.com
    final evoLastUriRaw = await controller.runJavaScriptReturningResult('''
    localStorage.getItem("EvoLastAppUri") ?? ""
  ''');
    final evoLastUri = _normalizeString(evoLastUriRaw.toString());
    if (evoLastUri.isEmpty) {
      throw Exception("EvoLastAppUri not found in localStorage");
    }
    final evoUri = Uri.parse(evoLastUri);
    // параметры находятся после '#'
    final frag = evoUri.fragment; // "provider=evolution&vt_id=…&table_id=…"
    final fragParams = Uri.splitQueryString(frag);

    final tableId =
        fragParams['table_id'] ?? (throw Exception('table_id missing'));
    final tableConfig =
        fragParams['vt_id'] ?? (throw Exception('vt_id missing'));
    // final uaLaunchId = fragParams['ua_launch_id'] ?? '';

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

    // 7) возвращаем новый params
    return WebSocketParamsNew(
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

  Future<void> _waitForIframeContextReset(
      WebViewController controller, String oldIframeSrc) async {
    const timeout = Duration(seconds: 10);
    final deadline = DateTime.now().add(timeout);
    Logger.info("Waiting for iframe src to reset...");

    while (DateTime.now().isBefore(deadline)) {
      final currentSrc = (await controller.runJavaScriptReturningResult('''
      (function() {
        const iframe = document.querySelector('iframe');
        return iframe && iframe.src ? iframe.src : '';
      })();
    ''')).toString().replaceAll('"', '');

      Logger.debug("Current iframe src: $currentSrc");
      if (currentSrc != oldIframeSrc && currentSrc.isNotEmpty) {
        Logger.info("Iframe context updated");
        return;
      }

      await Future.delayed(Duration(milliseconds: 300));
    }

    Logger.warning("Timeout: iframe src did not change");
  }

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

  Future<String> _waitForEvoSessionId(WebViewController controller) async {
    const timeout = Duration(seconds: 10);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final sessionId = (await controller.runJavaScriptReturningResult(
              'localStorage.getItem("evo.video.sessionId") ?? ""'))
          .toString()
          .replaceAll('"', '');
      if (sessionId.isNotEmpty) {
        return sessionId;
      }
      await Future.delayed(Duration(milliseconds: 250));
    }
    throw Exception("Timeout waiting for evo.video.sessionId");
  }
}
