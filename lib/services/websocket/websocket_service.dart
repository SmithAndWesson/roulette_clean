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
      await disconnect();
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
            Logger.debug("Decoded message type: ${decoded?['type']}");
          } catch (e) {
            Logger.error("Failed to decode message", e);
            return;
          }

          if (decoded == null) {
            Logger.warning("Decoded message is null");
            return;
          }

          if (decoded['type'] == 'connection.kickout') {
            final reason = decoded['args']?['reason'] as String? ?? 'unknown';
            Logger.warning("WebSocket kickout: $reason");
            if (!completer.isCompleted) {
              Logger.info("Completing with kickout reason: $reason");
              completer.complete(RecentResults(
                numbers: [],
                timestamp: DateTime.now(),
                kickoutReason: reason,
              ));
              Logger.info("Closing WebSocket connection after kickout");
              _channel?.sink.close();
              _channel = null;
            } else {
              Logger.warning("Completer already completed, ignoring kickout");
            }
          } else if (decoded['type'] != 'roulette.recentResults') {
            Logger.debug("Ignoring message of type: ${decoded['type']}");
          } else {
            try {
              final results = RecentResults.fromJson(decoded);
              if (!completer.isCompleted) {
                Logger.info("Completing with recent results");
                completer.complete(results);
                Logger.info("Closing WebSocket connection after results");
                _channel?.sink.close();
                _channel = null;
              } else {
                Logger.warning("Completer already completed, ignoring results");
              }
            } catch (e, st) {
              Logger.error("Failed to parse recentResults", e, st);
            }
          }
        },
        onError: (error, st) {
          Logger.error("WebSocket error", error, st);
          if (!completer.isCompleted) {
            Logger.info("Completing with error");
            completer.complete(null);
          }
        },
        onDone: () {
          Logger.info("WebSocket closed");
          if (!completer.isCompleted) {
            Logger.info("Completing after close");
            completer.complete(null);
          }
        },
      );

      return await completer.future;
    } catch (e) {
      Logger.error("WebSocket connection failed", e);
      rethrow;
    } finally {
      _timeoutTimer?.cancel();
      if (_channel != null) {
        Logger.info("Closing WebSocket connection in finally block");
        _channel?.sink.close();
        _channel = null;
      }
    }
  }

  Future<void> disconnect() async {
    if (_channel != null) {
      Logger.info("Manually closing existing WebSocket connection");
      await _channel!.sink.close(); // можно также передать статус close
      _channel = null;
    }
    _timeoutTimer?.cancel();
  }
}
