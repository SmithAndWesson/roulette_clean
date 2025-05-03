import 'package:audioplayers/audioplayers.dart';
import 'package:roulette_clean/utils/logger.dart';

class SoundPlayer {
  SoundPlayer._();

  /// Глобальный доступ: `SoundPlayer.i.playPing();`
  static final SoundPlayer i = SoundPlayer._();

  static const _pingAsset = 'sounds/ping.mp3';

  /// Один экземпляр плеера на всё приложение.
  final _player = AudioPlayer()..setReleaseMode(ReleaseMode.loop);

  /// Проиграть короткий «пинг».
  Future<void> playPing() async {
    try {
      if (_player.state == PlayerState.stopped) {
        await _player.play(AssetSource(_pingAsset), volume: 1.0);
        // Останавливаем воспроизведение после 100мс
        Future.delayed(const Duration(milliseconds: 1000), () {
          _player.stop();
        });
      }
    } catch (e, st) {
      Logger.error('Ошибка воспроизведения звука', e, st);
    }
  }

  /// Освобождаем ресурсы при уничтожении
  void dispose() {
    _player.dispose();
  }
}
