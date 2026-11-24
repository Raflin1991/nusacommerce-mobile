import 'package:flutter/services.dart';

class VoiceCaptureResult {
  final bool supported;
  final String? transcript;
  final String? infoMessage;

  const VoiceCaptureResult({
    required this.supported,
    this.transcript,
    this.infoMessage,
  });
}

/// Platform-channel speech capture bridge for OXORA Copilot Mobile Voice Input (`id-ID`).
/// Gracefully handles Android devices with native RecognizerIntent as well as Web/Desktop/Test
/// environments where native speech recognition plugin is unavailable.
class NusaVoiceInputService {
  static const MethodChannel _channel = MethodChannel('com.nusacommerce.mobile/voice');

  /// Optional test/override handler for deterministic verification.
  static Future<VoiceCaptureResult> Function({String locale})? debugCaptureOverride;

  Future<bool> isAvailable() async {
    if (debugCaptureOverride != null) return true;
    try {
      final ok = await _channel.invokeMethod<bool>('isVoiceRecognitionAvailable');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<VoiceCaptureResult> listenOnce({String locale = 'id-ID'}) async {
    if (debugCaptureOverride != null) {
      return debugCaptureOverride!(locale: locale);
    }

    try {
      final result = await _channel.invokeMethod<dynamic>(
        'startVoiceRecognition',
        {'locale': locale, 'prompt': 'Ucapkan pertanyaan untuk OXORA Buddy...'},
      );
      final text = (result ?? '').toString().trim();
      if (text.isEmpty) {
        return const VoiceCaptureResult(
          supported: true,
          transcript: null,
          infoMessage: 'Tidak ada suara terdeteksi. Coba ucapkan kembali atau pilih perintah suara cepat.',
        );
      }
      return VoiceCaptureResult(
        supported: true,
        transcript: text,
      );
    } on MissingPluginException {
      return const VoiceCaptureResult(
        supported: false,
        transcript: null,
        infoMessage: 'Pengenalan suara native tidak aktif di perangkat ini — gunakan perintah suara cepat di bawah atau ketik langsung.',
      );
    } on PlatformException catch (e) {
      return VoiceCaptureResult(
        supported: false,
        transcript: null,
        infoMessage: e.message ?? 'Layanan mikrofon tidak tersedia saat ini.',
      );
    } catch (_) {
      return const VoiceCaptureResult(
        supported: false,
        transcript: null,
        infoMessage: 'Gunakan perintah suara cepat atau ketik pertanyaan Anda.',
      );
    }
  }
}
