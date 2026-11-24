import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/offline_database.dart';
import '../network/api_client.dart';
import '../network/repositories/sale_repository.dart';
import '../theme/nusa_theme_tokens.dart';
import '../../features/auth/bloc/auth_cubit.dart';

/// Hardening #4: Shift Inactivity PIN Auto-Lock Guard.
///
/// Automatically overlays a non-dismissible PIN lock screen after configurable idle
/// duration without logging out or clearing the active POS cart, table, or shift.
class ShiftInactivityLockGuard extends StatefulWidget {
  static const String prefsKeyMinutes = 'nusa_shift_inactivity_lock_minutes';
  static const int defaultIdleMinutes = 15;

  final ApiClient apiClient;
  final OfflineDatabase offlineDb;
  final Widget child;
  final Duration? idleTimeoutOverride;

  const ShiftInactivityLockGuard({
    super.key,
    required this.apiClient,
    required this.offlineDb,
    required this.child,
    this.idleTimeoutOverride,
  });

  static int getConfiguredMinutes(SharedPreferences prefs) {
    return prefs.getInt(prefsKeyMinutes) ?? defaultIdleMinutes;
  }

  static Future<void> setConfiguredMinutes(SharedPreferences prefs, int minutes) async {
    await prefs.setInt(prefsKeyMinutes, minutes.clamp(0, 120));
  }

  @override
  State<ShiftInactivityLockGuard> createState() => _ShiftInactivityLockGuardState();
}

class _ShiftInactivityLockGuardState extends State<ShiftInactivityLockGuard> {
  Timer? _idleTimer;
  bool _isLocked = false;
  bool _isVerifying = false;
  String? _inlineError;
  final TextEditingController _pinCtrl = TextEditingController();

  @override
  void dispose() {
    _idleTimer?.cancel();
    _pinCtrl.dispose();
    super.dispose();
  }

  Duration? _resolveIdleDuration(bool isAuthenticated) {
    if (!isAuthenticated) return null;
    if (widget.idleTimeoutOverride != null) {
      return widget.idleTimeoutOverride!.inMilliseconds > 0
          ? widget.idleTimeoutOverride
          : null;
    }
    final mins = ShiftInactivityLockGuard.getConfiguredMinutes(widget.offlineDb.prefs);
    if (mins <= 0) return null;
    return Duration(minutes: mins);
  }

  void _resetIdleTimer(bool isAuthenticated) {
    _idleTimer?.cancel();
    if (_isLocked || !isAuthenticated) return;
    final duration = _resolveIdleDuration(isAuthenticated);
    if (duration == null) return;

    _idleTimer = Timer(duration, () {
      if (!mounted) return;
      final authed = context.read<AuthCubit>().state.isAuthenticated;
      if (!authed) return;
      setState(() {
        _isLocked = true;
        _inlineError = null;
        _pinCtrl.clear();
      });
    });
  }

  Future<void> _handleUnlock() async {
    final pin = _pinCtrl.text.trim();
    if (pin.length < 4) {
      setState(() {
        _inlineError = 'Masukkan minimal 4 digit PIN Kasir atau Supervisor.';
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _inlineError = null;
    });

    final authCubit = context.read<AuthCubit>();
    final session = authCubit.state.session;

    try {
      bool unlocked = false;

      if (session.isLocalTrial && authCubit.hasStandalonePin) {
        unlocked = authCubit.verifyStandaloneCashierPin(pin);
        if (!unlocked) {
          setState(() {
            _isVerifying = false;
            _inlineError = 'PIN Kasir Offline tidak sesuai. Silakan coba kembali.';
          });
          return;
        }
      } else {
        try {
          final res = await SaleRepository.resolve(widget.apiClient).verifySupervisorPin(
            pin,
            action: 'unlock_idle_screen',
          );
          final body = res.data;
          unlocked = res.statusCode == 200 &&
              (body is! Map || body['success'] != false);
        } catch (e) {
          if (ApiClient.isNetworkOfflineError(e) && authCubit.hasStandalonePin) {
            unlocked = authCubit.verifyStandaloneCashierPin(pin);
          } else {
            setState(() {
              _isVerifying = false;
              _inlineError = ApiClient.extractErrorMessage(e);
            });
            return;
          }
        }
      }

      if (!mounted) return;
      if (unlocked) {
        setState(() {
          _isVerifying = false;
          _isLocked = false;
          _inlineError = null;
          _pinCtrl.clear();
        });
        _resetIdleTimer(true);
      } else {
        setState(() {
          _isVerifying = false;
          _inlineError = 'PIN otorisasi tidak valid.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _inlineError = ApiClient.extractErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    if (!authState.isAuthenticated) {
      _idleTimer?.cancel();
      if (_isLocked) {
        _isLocked = false;
      }
      return widget.child;
    }

    if (!_isLocked && (_idleTimer == null || !_idleTimer!.isActive)) {
      _resetIdleTimer(true);
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetIdleTimer(authState.isAuthenticated),
      onPointerMove: (_) => _resetIdleTimer(authState.isAuthenticated),
      onPointerSignal: (_) => _resetIdleTimer(authState.isAuthenticated),
      child: Stack(
        children: [
          widget.child,
          if (_isLocked) _buildLockOverlay(context, authState),
        ],
      ),
    );
  }

  Widget _buildLockOverlay(BuildContext context, AuthState authState) {
    final tokens = NusaThemeTokens.of(context);
    final userName = authState.session.userName.trim().isEmpty
        ? 'Operator Kasir'
        : authState.session.userName.trim();
    final storeName = authState.session.activeStore.name.trim().isEmpty
        ? 'Cabang Aktif'
        : authState.session.activeStore.name.trim();

    return Positioned.fill(
      child: Material(
        key: const Key('shift_inactivity_lock_overlay'),
        color: tokens.bgPage.withOpacity(0.96),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: tokens.bgSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
                    boxShadow: tokens.isDark || tokens.isHighContrast ? null : tokens.cardShadow,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: tokens.accentSoft,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.lock_clock_rounded, color: tokens.accent, size: 22),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Layar Kasir Dikunci Otomatis',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: tokens.textPrimary,
                                ),
                              ),
                              Text(
                                '$userName • $storeName',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Sesi kasir dikunci karena perangkat tidak aktif. Keranjang belanja, meja aktif, dan shift Anda tetap aman.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: tokens.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        key: const Key('shift_inactivity_pin_input'),
                        controller: _pinCtrl,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        maxLength: 8,
                        enabled: !_isVerifying,
                        onSubmitted: (_) => _handleUnlock(),
                        decoration: const InputDecoration(
                          labelText: 'PIN Supervisor / Kasir',
                          hintText: 'Masukkan PIN otorisasi',
                          prefixIcon: Icon(Icons.pin_outlined),
                          counterText: '',
                        ),
                      ),
                      if (_inlineError != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          key: const Key('shift_inactivity_unlock_error'),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: tokens.dangerSoft,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: tokens.danger.withOpacity(0.45)),
                          ),
                          child: Text(
                            _inlineError!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: tokens.danger,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          key: const Key('shift_inactivity_unlock_button'),
                          onPressed: _isVerifying ? null : _handleUnlock,
                          icon: _isVerifying
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.lock_open_rounded, size: 18),
                          label: Text(_isVerifying ? 'Memverifikasi...' : 'Buka Kunci Kasir'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
