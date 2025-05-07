class WebSocketParamsNew {
  final String tableId;
  final String tableConfig; // бывший vt_id
  final String evoSessionId;
  final String clientVersion;
  final String instance;
  final String cookieHeader;

  WebSocketParamsNew({
    required this.tableId,
    required this.tableConfig,
    required this.evoSessionId,
    required this.clientVersion,
    required this.instance,
    required this.cookieHeader,
  });

  Uri buildUri() => Uri(
        scheme: 'wss',
        host: 'royal.evo-games.com',
        path: '/public/roulette/player/game/$tableId/socket',
        queryParameters: {
          'messageFormat': 'json',
          'tableConfig': tableConfig,
          'EVOSESSIONID': evoSessionId,
          'client_version': clientVersion,
          'instance': instance,
        },
      );
}
