import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:roulette_clean/models/roulette/roulette_game.dart';
import 'package:roulette_clean/models/signal.dart';
import 'package:roulette_clean/core/constants/app_constants.dart';

class RouletteCard extends StatelessWidget {
  final RouletteGame game;
  final List<Signal> signals;
  final bool isConnecting;
  final bool isAnalyzing;
  final VoidCallback onConnect;

  const RouletteCard({
    super.key,
    required this.game,
    required this.signals,
    required this.isConnecting,
    required this.isAnalyzing,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      elevation: isAnalyzing ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isAnalyzing
            ? const BorderSide(color: Colors.blue, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () async {
          final url = Uri.parse('$BASE_URL${game.playUrl}');
          if (await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
          } else {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Не удалось открыть ${game.title}")),
              );
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      game.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (isAnalyzing || isConnecting)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                game.provider,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              if (signals.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    signals.first.message,
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text("Детали сигнала"),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(signals.first.message),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 4,
                              children: signals.first.lastNumbers.map((n) {
                                return Chip(
                                  label: Text('$n'),
                                  backgroundColor: Colors.grey[300],
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("Закрыть"),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text("Детали"),
                ),
              ],
              const Spacer(),
              ElevatedButton(
                onPressed: isConnecting ? null : onConnect,
                child: isConnecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Подключить"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
