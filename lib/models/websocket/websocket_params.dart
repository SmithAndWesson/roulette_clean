class WebSocketParams {
  final String tableId;
  final String vtId;
  final String uaLaunchId;
  final String clientVersion;
  final String evoSessionId;
  final String instance;
  final String cookieHeader;

  WebSocketParams({
    required this.tableId,
    required this.vtId,
    required this.uaLaunchId,
    required this.clientVersion,
    required this.evoSessionId,
    required this.instance,
    required this.cookieHeader,
  });

  String get webSocketUrl {
    return "wss://royal.evo-games.com/public/roulette/player/game/$tableId/socket"
        "?messageFormat=json"
        "&tableConfig=$vtId"
        "&EVOSESSIONID=$evoSessionId"
        "&client_version=$clientVersion"
        "&instance=$instance";
  }
}
