import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'nusa_theme_tokens.dart';

/// Persists & broadcasts CDO Warm Linen Light, Dark, and High-Contrast Outdoor POS modes.
class ThemeCubit extends Cubit<NusaThemeMode> {
  static const String prefsKey = 'nusa_theme_mode_v1';

  final SharedPreferences? _prefs;

  ThemeCubit({SharedPreferences? prefs, NusaThemeMode? initialMode})
      : _prefs = prefs,
        super(
          initialMode ??
              NusaThemeModeMeta.fromStorageKey(prefs?.getString(prefsKey)),
        );

  Future<void> setThemeMode(NusaThemeMode mode) async {
    emit(mode);
    await _prefs?.setString(prefsKey, mode.storageKey);
  }

  Future<void> toggleOutdoorHighContrast() async {
    final next = state == NusaThemeMode.outdoorHighContrast
        ? NusaThemeMode.warmLinenLight
        : NusaThemeMode.outdoorHighContrast;
    await setThemeMode(next);
  }

  Future<void> cycleThemeMode() async {
    const order = NusaThemeMode.values;
    final nextIdx = (order.indexOf(state) + 1) % order.length;
    await setThemeMode(order[nextIdx]);
  }
}
