import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'logger.dart';

class SoundPlayer {
  SoundPlayer._();
  static final SoundPlayer i = SoundPlayer._();

  /// Проиграть системный звук уведомления.
  Future<void> playPing() async {
    try {
      // FlutterRingtonePlayer().playAlarm(
      //   volume: 1.0,
      //   looping: false,
      //   asAlarm: false,
      // );
      // FlutterRingtonePlayer().playNotification(volume: 1.0, looping: false);
      await FlutterRingtonePlayer().play(
        android:
            AndroidSounds.notification, // стандартный звук уведомления Android
        ios: IosSounds.glass, // любой из предустановленных на iOS
        looping: false,
        volume: 1.0,
        asAlarm: false, // если true — звук как будильник
      );
    } catch (e, st) {
      Logger.error('Ошибка проигрывания системного звука', e, st);
    }
  }

  /// При необходимости вы можете «отрубить» плеер,
  /// но flutter_ringtone_player это не требует.
  void dispose() {
    // ничего не делаем
  }
}
