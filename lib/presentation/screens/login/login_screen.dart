import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:roulette_clean/core/di/service_locator.dart';
import 'package:roulette_clean/services/session/session_manager.dart';
import 'package:roulette_clean/services/webview/webview_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loggingIn = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    final session = getIt<SessionManager>();
    if (session.cookieHeader != null) {
      getIt<WebViewService>()
          .setCookies(session.cookieHeader!, domain: ".gizbo.casino");
    }
  }

  void _onLoginSuccess(String jwt, String cookies) {
    final sessionManager = getIt<SessionManager>();
    sessionManager.saveSession(jwtToken: jwt, cookieHeader: cookies);
    Navigator.pushReplacementNamed(context, "/main");
  }

  @override
  Widget build(BuildContext context) {
    final webViewService = getIt<WebViewService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Вход"),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: webViewService.controller),
          if (_loggingIn) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
