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
            game.slug.contains('online-live-casino'))
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
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode != 200) return {};
      final root = json.decode(resp.body);
      if (root is Map<String, dynamic>) {
        final restrictKey = root.keys.firstWhere(
            (k) => k.toLowerCase().contains('restrictions'),
            orElse: () => '');
        if (restrictKey.isNotEmpty) {
          return root[restrictKey]['data'] ?? {};
        }
      }
      return {};
    } catch (e) {
      Logger.error("Failed to fetch restrictions", e);
      return {};
    }
  }

  Future<WebSocketParams> extractWebSocketParams(RouletteGame game) async {
    await _webViewService.initialize();
    final controller = _webViewService.controller;

    final cookies = _sessionManager.cookieHeader;
    if (cookies != null && cookies.isNotEmpty) {
      await _webViewService.setCookies(cookies, domain: ".gizbo.casino");
      await _webViewService.setCookies(cookies, domain: ".evo-games.com");
    }

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

    iframeSrc = iframeSrc.trim();
    if (!iframeSrc.startsWith("http")) {
      throw Exception("Invalid iframe src: $iframeSrc");
    }

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

    final gameUri = Uri.parse(gameUrl);
    final paramsEncoded = gameUri.queryParameters['params'];
    if (paramsEncoded == null) {
      throw Exception("Missing 'params' in game_url");
    }

    final paramsJson =
        utf8.decode(base64.decode(_normalizeBase64(paramsEncoded)));
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

  String _normalizeBase64(String b64) {
    final padLength = (4 - b64.length % 4) % 4;
    return b64.replaceAll('-', '+').replaceAll('_', '/') + ('=' * padLength);
  }

  Map<String, String> _parseKeyValueString(String input) {
    final map = <String, String>{};
    for (var pair in input.split(';')) {
      if (pair.isEmpty) continue;
      final idx = pair.indexOf('=');
      if (idx == -1) continue;
      final key = pair.substring(0, idx).trim();
      final value = pair.substring(idx + 1).trim();
      if (key.isNotEmpty) map[key] = value;
    }
    return map;
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
