import 'package:flutter/material.dart';
import 'package:roulette_clean/models/roulette/roulette_game.dart';
import 'package:roulette_clean/models/signal.dart';

class RouletteCard extends StatelessWidget {
  final RouletteGame game;
  final List<Signal> signals;
  final bool isConnecting;
  final VoidCallback onConnect;

  const RouletteCard({
    super.key,
    required this.game,
    required this.signals,
    required this.isConnecting,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final hasSignal = signals.isNotEmpty;
    final theme = Theme.of(context);

    return Card(
      color: hasSignal ? Colors.yellow.shade100 : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              game.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              game.provider,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            if (hasSignal)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  "СИГНАЛ!",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.red.shade900,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: isConnecting ? null : onConnect,
              child: isConnecting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text("Подключить"),
            ),
          ],
        ),
      ),
    );
  }
}
