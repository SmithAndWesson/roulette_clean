import 'package:audioplayers/audioplayers.dart';
import 'package:roulette_clean/utils/logger.dart';

class SoundPlayer {
  static final AudioPlayer _player = AudioPlayer();

  static Future<void> play(String assetFileName) async {
    try {
      await _player.play(AssetSource(assetFileName));
    } catch (e) {
      Logger.error("Failed to play sound $assetFileName", e);
    }
  }
}
