import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:roulette_clean/core/constants/app_constants.dart';
import 'package:roulette_clean/models/roulette/roulette_game.dart';
import 'package:roulette_clean/models/websocket/websocket_params.dart';
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

  Future<WebSocketParams> extractWebSocketParams(RouletteGame game,
      {int retry = 0}) async {
    await _webViewService.initialize();
    await _webViewService.resetDomWithoutLogout();
    final controller = _webViewService.controller;

    final cookies = _sessionManager.cookieHeader;
    if (cookies != null && cookies.isNotEmpty) {
      await _webViewService.setCookies(cookies, domain: ".gizbo.casino");
      await _webViewService.setCookies(cookies, domain: ".evo-games.com");
    }

    // await controller.loadRequest(Uri.parse('about:blank'));
    // await Future.delayed(Duration(milliseconds: 500));

    final gamePageUrl = "${BASE_URL}${game.playUrl}";
    Logger.info("Loading game page: $gamePageUrl");
    await controller.loadRequest(Uri.parse(gamePageUrl));

    String iframeSrc = "";
    try {
      iframeSrc = (await controller.runJavaScriptReturningResult("""
          (function() {
            const iframe = document.querySelector('iframe');
            return iframe && iframe.src ? iframe.src : '';
          })();
          """)).toString();
    } catch (e) {
      throw Exception("Unable to get iframe src for game: $e");
    }

    try {
      iframeSrc = iframeSrc.replaceAll('"', '').trim();

      if (!iframeSrc.startsWith("http")) {
        throw Exception("Invalid iframe src: $iframeSrc");
      }
    } catch (e) {
      if (retry < 2) {
        Logger.warning(
            "Retrying extractWebSocketParams due to iframe error...");
        await Future.delayed(Duration(seconds: 1));
        await _webViewService.resetDomWithoutLogout();
        return await extractWebSocketParams(game, retry: retry + 1);
      } else {
        throw Exception("Failed to get iframe src after retries: $e");
      }
    }

    // iframeSrc = iframeSrc.replaceAll('"', '').trim();
    // if (!iframeSrc.startsWith("http")) {
    //   throw Exception("Invalid iframe src: $iframeSrc");
    // }

    Logger.debug("Game iframe src: $iframeSrc");

    final iframeUri = Uri.parse(iframeSrc);
    final optionsEncoded = iframeUri.queryParameters['options'];
    if (optionsEncoded == null) {
      throw Exception("Missing 'options' param in iframe URL");
    }

    final optionsJson =
        utf8.decode(base64.decode(_normalizeBase64(optionsEncoded)));
    final optionsMap = json.decode(optionsJson) as Map<String, dynamic>;
    final launchOpts = optionsMap['launch_options'] as Map<String, dynamic>?;
    if (launchOpts == null || launchOpts['game_url'] == null) {
      throw Exception("No game_url in launch_options");
    }

    final gameUrl = launchOpts['game_url'] as String;
    Logger.debug("Parsed game_url: $gameUrl");

    // Парсим params из gameUrl
    final gameUri = Uri.parse(gameUrl);
    final paramsEncoded = gameUri.queryParameters['params'];
    if (paramsEncoded == null) {
      throw Exception('Параметр params не найден в game_url');
    }
    final paramsNorm = _normalizeBase64(paramsEncoded);
    final paramsJson = utf8.decode(base64.decode(paramsNorm));
    final paramsMap = _parseKeyValueString(paramsJson);

    final tableId = paramsMap['table_id']!;
    final vtId = paramsMap['vt_id']!;
    final uaLaunchId = paramsMap['ua_launch_id'] ?? '';

    Logger.info("Loading provider URL to obtain session...");
    await controller.loadRequest(Uri.parse(gameUrl));

    final evoSessionId = await _waitForEvoSessionId(controller);
    final rawCookies =
        (await controller.runJavaScriptReturningResult('document.cookie'))
            .toString();
    String cookieHeader = rawCookies;
    if (!rawCookies.contains('EVOSESSIONID=')) {
      cookieHeader = "$rawCookies; EVOSESSIONID=$evoSessionId";
    }

//     await controller.loadRequest(Uri.parse(gamePageUrl));
//     await controller.runJavaScript('''
//   document.body.innerHTML = '';
// ''');

//     await controller.runJavaScript('''
//   const iframe = document.querySelector('iframe');
//   if (iframe) iframe.src = 'about:blank';
// ''');
//     await controller.loadRequest(Uri.parse('about:blank'));
//     await Future.delayed(Duration(seconds: 1));
//     await controller.runJavaScript('''
//   localStorage.clear();
//   sessionStorage.clear();
//   document.cookie.split(";").forEach(function(c) {
//     document.cookie = c.replace(/^ +/, "").replace(/=.*/, "=;expires=" + new Date().toUTCString() + ";path=/");
//   });
// ''');
//     await controller.reload();
    await Future.delayed(Duration(seconds: 1));
    await _webViewService.resetDomWithoutLogout();
    final rnd = Random().nextInt(1 << 20).toRadixString(36);
    final shortSess = evoSessionId.substring(0, 16);
    final instance = "$rnd-$shortSess-$vtId";

    return WebSocketParams(
      tableId: tableId,
      vtId: vtId,
      uaLaunchId: uaLaunchId,
      clientVersion: "6.20250415.70424.51183-8793aee83a",
      evoSessionId: evoSessionId,
      instance: instance,
      cookieHeader: cookieHeader,
    );
  }

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
