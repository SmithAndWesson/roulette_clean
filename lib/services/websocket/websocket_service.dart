import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/io.dart';
import 'package:roulette_clean/models/websocket/websocket_params.dart';
import 'package:roulette_clean/models/websocket/recent_results.dart';
import 'package:roulette_clean/utils/logger.dart';
import 'package:roulette_clean/core/constants/app_constants.dart';

class WebSocketService {
  IOWebSocketChannel? _channel;
  Timer? _timeoutTimer;

  Future<RecentResults?> fetchRecentResults(WebSocketParams params) async {
    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse(params.webSocketUrl),
        headers: {
          'Cookie': params.cookieHeader,
          'Origin': WS_ORIGIN,
        },
      );

      final completer = Completer<RecentResults?>();
      _timeoutTimer = Timer(WS_TIMEOUT, () {
        if (!completer.isCompleted) {
          Logger.warning("WebSocket recentResults timeout");
          completer.complete(null);
          _channel?.sink.close();
        }
      });

      _channel!.stream.listen(
        (message) {
          Logger.debug("WS ⇠ $message");
          Map<String, dynamic>? decoded;
          try {
            final tmp = jsonDecode(message);
            if (tmp is Map<String, dynamic>) decoded = tmp;
          } catch (_) {
            return;
          }

          if (decoded == null) return;
          if (decoded['type'] != 'roulette.recentResults') return;

          try {
            final results = RecentResults.fromJson(decoded);
            if (!completer.isCompleted) {
              completer.complete(results);
            }
          } catch (e, st) {
            Logger.error("Failed to parse recentResults", e, st);
          }
        },
        onError: (error, st) {
          Logger.error("WebSocket error", error, st);
          if (!completer.isCompleted) completer.complete(null);
        },
        onDone: () {
          Logger.info("WebSocket closed");
          if (!completer.isCompleted) completer.complete(null);
        },
      );

      return await completer.future;
    } catch (e) {
      Logger.error("WebSocket connection failed", e);
      rethrow;
    } finally {
      _timeoutTimer?.cancel();
      _channel?.sink.close();
    }
  }
}
