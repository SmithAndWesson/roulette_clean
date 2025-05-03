import 'package:audioplayers/audioplayers.dart';
import 'logger.dart';

class SoundPlayer {
  SoundPlayer._();

  /// Глобальный доступ: `SoundPlayer.i.playPing();`
  static final SoundPlayer i = SoundPlayer._();

  static const _pingAsset = 'sounds/ping.mp3';

  /// Один экземпляр плеера на всё приложение.
  final _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);

  /// Проиграть короткий «пинг».
  Future<void> playPing() async {
    try {
      if (_player.state == PlayerState.stopped) {
        await _player.play(AssetSource(_pingAsset), volume: 1.0);
      } else {
        await _player.resume();
      }
    } catch (e, st) {
      Logger.error('Ошибка воспроизведения звука', e, st);
    }
  }

  /// Clean up when your app shuts down
  void dispose() {
    _player.dispose();
  }
}
