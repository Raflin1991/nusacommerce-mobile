import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../bloc/auth_cubit.dart';

/// LAYAR 1 — LAYAR PEMBUKA RESMI OXORA MOBILE
/// Mengikuti panduan visual resmi `LogoRebranding/Mobile splash screen.jpg`:
/// tema terang bersih, gelombang gradien biru & oranye di sudut, emblem X + wordmark OXORA,
/// indikator cincin biru-oranye, serta penanda "Versi 2.0 • Powered by Autonomous AI".
class SplashWelcomeScreen extends StatelessWidget {
  const SplashWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = context.watch<AuthCubit>().state.isAuthenticated;
    final tokens = NusaThemeTokens.of(context);
    final isDark = tokens.isDark;

    return Scaffold(
      backgroundColor: isDark ? tokens.bgPage : Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Soft ambient flowing blue (top-left) & orange/blue (bottom-right) waves
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _OxoraSplashWavesPainter(isDark: isDark),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(0, constraints.maxHeight - 48),
                      ),
                      child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 16),
                        // Center Brand Hero matching Mobile splash screen.jpg
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              'assets/images/oxora_icon.png',
                              width: 124,
                              height: 124,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(height: 10),
                            Image.asset(
                              isDark
                                  ? 'assets/images/oxora_splash_wordmark_dark.png'
                                  : 'assets/images/oxora_splash_wordmark_light.png',
                              height: 62,
                              fit: BoxFit.contain,
                              semanticLabel:
                                  'OXORA — THE AI-POWERED BUSINESS OPERATING SYSTEM',
                            ),
                            const SizedBox(height: 22),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 320),
                              child: Text(
                                'Pusat kendali kasir POS, inventaris FEFO & operasional multi-cabang real-time.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: tokens.textSecondary,
                                  height: 1.45,
                                ),
                              ),
                            ),
                            const SizedBox(height: 26),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 320),
                              child: SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF6B00),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: () =>
                                      context.go(isAuthenticated ? '/home' : '/login'),
                                  icon: const Icon(Icons.login_rounded, size: 20),
                                  label: Text(
                                    isAuthenticated
                                        ? 'Lanjutkan ke Ruang Kerja Toko'
                                        : 'Masuk ke Ruang Kerja Toko',
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (isAuthenticated) ...[
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () => context.go('/login'),
                                child: Text(
                                  'Ganti Akun atau Subdomain Toko',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: tokens.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        // Bottom signature block matching Mobile splash screen.jpg
                        Padding(
                          padding: const EdgeInsets.only(top: 28, bottom: 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 34,
                                height: 34,
                                child: CustomPaint(
                                  painter: _OxoraDualToneRingPainter(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Versi 2.0 • Powered by Autonomous AI',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? tokens.textSecondary
                                      : const Color(0xFF334155),
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OxoraDualToneRingPainter extends CustomPainter {
  const _OxoraDualToneRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - 2.5;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final bluePaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final orangePaint = Paint()
      ..color = const Color(0xFFFF6B00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    // Lower arc: vibrant blue
    canvas.drawArc(rect, 0.08, math.pi - 0.16, false, bluePaint);
    // Upper arc: signature OXORA orange
    canvas.drawArc(rect, -math.pi + 0.08, math.pi - 0.16, false, orangePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _OxoraSplashWavesPainter extends CustomPainter {
  final bool isDark;

  const _OxoraSplashWavesPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final opacityScale = isDark ? 0.22 : 1.0;

    // Top-left layered blue translucent ribbons
    final topPath1 = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.72, 0)
      ..quadraticBezierTo(
        size.width * 0.34,
        size.height * 0.14,
        0,
        size.height * 0.30,
      )
      ..close();
    canvas.drawPath(
      topPath1,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0052FF).withOpacity(0.28 * opacityScale),
            const Color(0xFF60A5FA).withOpacity(0.06 * opacityScale),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.35)),
    );

    final topPath2 = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.50, 0)
      ..quadraticBezierTo(
        size.width * 0.22,
        size.height * 0.11,
        0,
        size.height * 0.22,
      )
      ..close();
    canvas.drawPath(
      topPath2,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0052FF).withOpacity(0.55 * opacityScale),
            const Color(0xFF3B82F6).withOpacity(0.14 * opacityScale),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width * 0.55, size.height * 0.25)),
    );

    // Bottom-right soft blue under-ribbon + vibrant orange layered wave
    final botBlue = Path()
      ..moveTo(0, size.height)
      ..quadraticBezierTo(
        size.width * 0.45,
        size.height * 0.90,
        size.width,
        size.height * 0.74,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      botBlue,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [
            const Color(0xFF3B82F6).withOpacity(0.26 * opacityScale),
            const Color(0xFF93C5FD).withOpacity(0.05 * opacityScale),
          ],
        ).createShader(Rect.fromLTWH(0, size.height * 0.72, size.width, size.height * 0.28)),
    );

    final botOrange = Path()
      ..moveTo(size.width * 0.32, size.height)
      ..quadraticBezierTo(
        size.width * 0.68,
        size.height * 0.85,
        size.width,
        size.height * 0.65,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      botOrange,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            const Color(0xFFFF8C24).withOpacity(0.68 * opacityScale),
            const Color(0xFFFF5E00).withOpacity(0.32 * opacityScale),
          ],
        ).createShader(Rect.fromLTWH(size.width * 0.30, size.height * 0.65, size.width * 0.70, size.height * 0.35)),
    );
  }

  @override
  bool shouldRepaint(covariant _OxoraSplashWavesPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
