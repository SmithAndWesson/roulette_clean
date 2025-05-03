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
    Key? key,
    required this.game,
    required this.signals,
    required this.isConnecting,
    required this.isAnalyzing,
    required this.onConnect,
  }) : super(key: key);

  Widget _buildSequenceWidget(Signal signal) {
    final patternNums = <int>[];
    final parts = signal.message.split(':');
    if (parts.length > 1) {
      patternNums.addAll(
        parts[1].split(',').map((s) => int.tryParse(s.trim())).whereType<int>(),
      );
    }

    return Wrap(
      spacing: 4.0,
      runSpacing: 4.0,
      children: signal.lastNumbers.map((n) {
        final isPatternNum = patternNums.contains(n);
        return Chip(
          label: Text(
            '$n',
            style: TextStyle(
              color: isPatternNum ? Colors.black : Colors.white,
              fontWeight: isPatternNum ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          backgroundColor: isPatternNum ? Colors.amber : Colors.grey.shade600,
        );
      }).toList(),
    );
  }

  void _showSignalDetails(BuildContext context, Signal signal) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Детали сигнала"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              signal.message,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildSequenceWidget(signal),
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
  }

  @override
  Widget build(BuildContext context) {
    final hasSignal = signals.isNotEmpty;
    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(
        side: isAnalyzing
            ? BorderSide(color: Colors.blueAccent, width: 2)
            : BorderSide.none,
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: isAnalyzing ? 8 : 2,
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        game.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (isAnalyzing || isConnecting)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                Text(game.provider, style: TextStyle(fontSize: 12)),
                SizedBox(height: 8),
                if (hasSignal) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
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
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _showSignalDetails(context, signals.first),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            "Детали",
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      signals.first.message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                ],
                Spacer(),
                ElevatedButton(
                  onPressed: isConnecting ? null : onConnect,
                  child: isConnecting
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text("Подключить"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
