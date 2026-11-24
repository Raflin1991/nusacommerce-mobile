import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/business_vertical_config.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../bloc/auth_cubit.dart';

part 'login_screen_part1.dart';
part 'login_screen_part2.dart';
part 'login_screen_part3.dart';

/// Multi-Tenant Cloud & Day-0 Standalone Login Screen
class LoginScreen extends StatefulWidget {
  final ApiClient apiClient;

  const LoginScreen({super.key, required this.apiClient});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}


enum _LoginEntryMode { cloud, standalone }


class _LoginScreenState extends State<LoginScreen> {
  final _tenantController = TextEditingController();

  final _emailController = TextEditingController();

  final _passwordController = TextEditingController();


  final _storeNameController = TextEditingController(text: 'Toko Saya');

  final _openingCashController = TextEditingController(text: '100000');

  final _standalonePinController = TextEditingController();


  _LoginEntryMode _entryMode = _LoginEntryMode.cloud;

  BusinessVertical _selectedVertical = BusinessVertical.retail;

  bool _obscurePassword = true;

  bool _obscurePin = true;

  bool _startingStandalone = false;

  String? _standaloneError;


  @override
  void initState() {
    super.initState();
    // Pre-fill only last non-trial cloud subdomain if user previously logged into one,
    // never hardcoding another tenant's email or password by default.
    final lastSlug = widget.apiClient.getTenantSlug();
    final hasCloudSlug = lastSlug != null &&
        lastSlug.trim().isNotEmpty &&
        lastSlug.trim().toLowerCase() != 'local-trial';
    if (hasCloudSlug) {
      _tenantController.text = lastSlug.trim();
    }
    // Bug 1 Fix: If a standalone offline store already exists on this device (e.g. after logout),
    // automatically land on the Saved Offline Store card instead of showing a blank setup wizard.
    final db = _offlineDb;
    if (db != null && db.hasExistingStandaloneStore && !hasCloudSlug) {
      _entryMode = _LoginEntryMode.standalone;
    }
  }


  @override
  void dispose() {
    _tenantController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _storeNameController.dispose();
    _openingCashController.dispose();
    _standalonePinController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final isDark = tokens.isDark;
    final apiHost = Uri.tryParse(widget.apiClient.baseUrl)?.host ??
        widget.apiClient.baseUrl;
    final serverChipLabel = _formatServerChipLabel(apiHost);

    return Scaffold(
      backgroundColor: isDark ? tokens.bgPage : Colors.white,
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        backgroundColor: isDark ? tokens.bgSurface : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Info OXORA',
          icon: Icon(Icons.info_outline_rounded, color: tokens.textSecondary),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: InkWell(
              onTap: _showServerUrlModal,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 140),
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? tokens.bgElevated : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isDark ? tokens.borderSubtle : const Color(0xFFE2E8F0),
                    width: tokens.borderWidth,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.language_rounded,
                        size: 14, color: Color(0xFF0052FF)),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        serverChipLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? tokens.textPrimary
                              : const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Soft bottom ambient blue & orange wave ribbon matching Mobil POS Login.jpg
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 150,
            child: IgnorePointer(
              child: CustomPaint(
                painter: _OxoraLoginBottomWavesPainter(isDark: isDark),
              ),
            ),
          ),
          BlocBuilder<AuthCubit, AuthState>(
            builder: (context, state) {
              return SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildBrandHeader(),
                          const SizedBox(height: 18),
                          _buildModeSwitcher(),
                          const SizedBox(height: 16),
                          if (state.errorMessage != null &&
                              _entryMode == _LoginEntryMode.cloud) ...[
                            _buildErrorBanner(state.errorMessage!),
                            const SizedBox(height: 12),
                          ],
                          if (_entryMode == _LoginEntryMode.cloud)
                            _buildCloudLoginSection(state)
                          else
                            _buildStandaloneSetupSection(),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}


class _ModeTabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  const _ModeTabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected && !tokens.isDark && !tokens.isHighContrast
              ? [
                  BoxShadow(
                    color: accentColor.withOpacity(0.24),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : tokens.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? Colors.white : tokens.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _OxoraLoginBottomWavesPainter extends CustomPainter {
  final bool isDark;

  const _OxoraLoginBottomWavesPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final opacityScale = isDark ? 0.16 : 1.0;

    // Flowing blue wave bottom-left
    final bluePath = Path()
      ..moveTo(0, size.height * 0.22)
      ..quadraticBezierTo(
        size.width * 0.32,
        size.height * 0.42,
        size.width * 0.68,
        size.height,
      )
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      bluePath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [
            const Color(0xFF0052FF).withOpacity(0.42 * opacityScale),
            const Color(0xFF60A5FA).withOpacity(0.10 * opacityScale),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width * 0.70, size.height)),
    );

    // Flowing orange wave bottom-right
    final orangePath = Path()
      ..moveTo(size.width * 0.44, size.height)
      ..quadraticBezierTo(
        size.width * 0.72,
        size.height * 0.46,
        size.width,
        size.height * 0.28,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      orangePath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomRight,
          end: Alignment.topLeft,
          colors: [
            const Color(0xFFFF6B00).withOpacity(0.55 * opacityScale),
            const Color(0xFFFFA94D).withOpacity(0.16 * opacityScale),
          ],
        ).createShader(Rect.fromLTWH(size.width * 0.42, 0, size.width * 0.58, size.height)),
    );
  }

  @override
  bool shouldRepaint(covariant _OxoraLoginBottomWavesPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
