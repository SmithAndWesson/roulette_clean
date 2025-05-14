import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:roulette_clean/models/websocket/websocket_params.dart';
import 'package:roulette_clean/models/websocket/websocket_params_new.dart';
import 'package:roulette_clean/models/websocket/recent_results.dart';
import 'package:roulette_clean/models/websocket/kickout_exception.dart';
import 'package:roulette_clean/utils/logger.dart';
import 'package:roulette_clean/core/constants/app_constants.dart';

class WebSocketService {
  IOWebSocketChannel? _channel;
  Timer? _timeoutTimer;

  Future<RecentResults?> fetchRecentResults(dynamic params) async {
    try {
      await disconnect();

      // params может быть старым или новым
      Uri uri;
      String cookies;

      // if (params is WebSocketParamsNew) {
      //   uri = params.buildUri();
      //   cookies = params.cookieHeader;
      // } else {
      //   uri = Uri.parse(params.webSocketUrl);
      //   cookies = params.cookieHeader;
      // }
      uri = params.buildUri();
      cookies = params.cookieHeader;

      // 1) Хендшейк – там, где WebSocketException гарантированно бросается в await
      WebSocket rawSocket;
      try {
        rawSocket = await WebSocket.connect(
          uri.toString(),
          headers: {
            'Origin': WS_ORIGIN,
            'Cookie': cookies,
          },
        );
      } on WebSocketException catch (e, st) {
        Logger.error('WS.connect handshake failed', e, st);
        return null;
      } catch (e, st) {
        Logger.error('Unexpected error during WS.connect', e, st);
        return null;
      }

      // 2) Если дошли сюда – handshake прошёл успешно
      _channel = IOWebSocketChannel(rawSocket);
      // _channel = IOWebSocketChannel.connect(
      //   uri,
      //   headers: {
      //     'Cookie': cookies,
      //     'Origin': WS_ORIGIN,
      //   },
      // );

      final completer = Completer<RecentResults?>();
      _timeoutTimer = Timer(WS_TIMEOUT, () {
        if (!completer.isCompleted) {
          Logger.warning("WebSocket recentResults timeout");
          completer.complete(null);
          _channel?.sink.close();
        }
      });

      _channel!.stream.listen(
        (message) async {
          Logger.debug("WS ⇠ $message");
          Map<String, dynamic>? decoded;
          try {
            final tmp = jsonDecode(message);
            if (tmp is Map<String, dynamic>) decoded = tmp;
            // Logger.debug("Decoded message type: ${decoded?['type']}");
          } catch (e) {
            Logger.error("Failed to decode message", e);
            return;
          }

          if (decoded == null) {
            Logger.warning("Decoded message is null");
            return;
          }

          if (decoded['type'] == 'connection.kickout') {
            final reason = decoded['args']?['reason']?.toString() ?? 'unknown';
            await _channel?.sink.close();
            Logger.debug('KickoutException: $reason');
            // } else if (decoded['type'] != '${params.game}.recentResults') {
            //   Logger.debug("Ignoring message of type: ${decoded['type']}");
          } else if (decoded['type'].toString().contains('.recentResults')) {
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
      return null; // gracefully exit
      // rethrow;
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
      await _channel!.sink.close();
      _channel = null;
    }
    _timeoutTimer?.cancel();
  }
}
