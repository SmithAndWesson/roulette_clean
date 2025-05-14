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
  final bool connectEnabled;

  const RouletteCard({
    super.key,
    required this.game,
    required this.signals,
    required this.isConnecting,
    required this.isAnalyzing,
    required this.onConnect,
    this.connectEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    // ── 1. Определяем цвет сообщения ────────────────────────────────
    Color msgColor = Colors.red; // дефолт
    if (signals.isNotEmpty) {
      final Signal first = signals.first;
      msgColor = switch (first.type) {
        SignalType.emptyAnalysis => Colors.green, // анализ без паттерна
        SignalType.connectionKickout => Colors.orange, // кик-аут
        SignalType.errorImConnection => Colors.grey, // кик-аут
        _ => Colors.red, // «боевые» сигналы
      };
    }

    // ── 2. Дальше идёт тот же build-код карточки ─────────────────────
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
            mainAxisSize: MainAxisSize.max,
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
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    signals.first.message,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: msgColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                if (signals.first.type != SignalType.connectionKickout)
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
                              Builder(
                                builder: (context) {
                                  final all = signals.first.lastNumbers;
                                  final patternPositions =
                                      signals.first.patternPositions;

                                  return Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: List.generate(all.length, (i) {
                                      final n = all[i];
                                      final isHighlight =
                                          patternPositions.contains(i);
                                      return Container(
                                        width: 28,
                                        height: 28,
                                        alignment: Alignment.center,
                                        margin: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: isHighlight
                                              ? Colors.orange
                                              : Colors.grey[300],
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        child: Text(
                                          '$n',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isHighlight
                                                ? Colors.white
                                                : Colors.black,
                                          ),
                                        ),
                                      );
                                    }),
                                  );
                                },
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
              const SizedBox(height: 8),
              const Spacer(),
              ElevatedButton(
                onPressed: (isConnecting || !connectEnabled) ? null : onConnect,
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
