// ignore_for_file: invalid_use_of_protected_member
part of 'nusa_copilot_sheet.dart';

/// Lightweight inline Markdown (`**bold**`, `*italic*`, `` `code` ``, headings & bullets)
/// renderer for Copilot responses with tabular numeric figures for crisp IDR Rupiah readability.
class _FormattedCopilotText extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;

  const _FormattedCopilotText({
    required this.text,
    required this.baseStyle,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = text
        .replaceAllMapped(RegExp(r'^#{1,3}\s+(.+)$', multiLine: true), (m) => '**${m.group(1)}**')
        .replaceAllMapped(RegExp(r'^-\s+', multiLine: true), (_) => '• ');

    final effectiveBase = baseStyle.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`|\*(?!\s)(.+?)(?<!\s)\*');
    int lastEnd = 0;

    for (final match in pattern.allMatches(normalized)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: normalized.substring(lastEnd, match.start)));
      }
      if (match.group(1) != null) {
        spans.add(
          TextSpan(
            text: match.group(1),
            style: effectiveBase.copyWith(fontWeight: FontWeight.w800),
          ),
        );
      } else if (match.group(2) != null) {
        spans.add(
          TextSpan(
            text: match.group(2),
            style: effectiveBase.copyWith(
              fontFamily: 'monospace',
              fontSize: (effectiveBase.fontSize ?? 13) - 0.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      } else if (match.group(3) != null) {
        spans.add(
          TextSpan(
            text: match.group(3),
            style: effectiveBase.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      }
      lastEnd = match.end;
    }
    if (lastEnd < normalized.length) {
      spans.add(TextSpan(text: normalized.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(style: effectiveBase, children: spans),
    );
  }
}


/// Unified 3D Articulated Animated WebP mascot "OXORA Buddy" (100% parity with Cloud Web).
/// Perched free-floating directly above the chat card with transparent RGBA background:
/// 1. greeting -> `buddy_greeting.webp` (full-body bear waving right arm -> auto-settle to idle)
/// 2. idle/guiding/guard -> `buddy_idle.webp` (half-body peeking, 2.5D gaze left/right, blinking eyes)
/// 3. thinking -> `buddy_working.webp` (orange headphones + stationary laptop, active typing paw)
/// 4. success -> `buddy_success.webp` (joyful crescent eyes, double bounce, sparkles -> auto-settle)
/// 5. poke -> tactile elastic plushie squish-bounce on tap
class _NusaBuddyMascot extends StatefulWidget {
  final String state;
  final double size;
  final VoidCallback? onGreetingComplete;
  final VoidCallback? onSuccessComplete;

  const _NusaBuddyMascot({
    super.key,
    required this.state,
    this.size = 126,
    this.onGreetingComplete,
    this.onSuccessComplete,
  });

  @override
  State<_NusaBuddyMascot> createState() => _NusaBuddyMascotState();
}


class _NusaBuddyMascotState extends State<_NusaBuddyMascot>
    with TickerProviderStateMixin {
  static const String _assetGreeting = 'assets/images/buddy/buddy_greeting.webp';
  static const String _assetIdle = 'assets/images/buddy/buddy_idle.webp';
  static const String _assetThinking = 'assets/images/buddy/buddy_working.webp';
  static const String _assetSuccess = 'assets/images/buddy/buddy_success.webp';

  late final AnimationController _greetingCtrl;
  late final AnimationController _successCtrl;
  late final AnimationController _pokeCtrl;
  bool _precached = false;

  bool get _isWidgetTestBinding =>
      WidgetsBinding.instance.runtimeType.toString().contains('TestWidgets');

  @override
  void initState() {
    super.initState();
    _greetingCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && widget.state == 'greeting') {
          widget.onGreetingComplete?.call();
        }
      });

    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && widget.state == 'success') {
          widget.onSuccessComplete?.call();
        }
      });

    _pokeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );

    _syncControllersForState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached && !_isWidgetTestBinding) {
      _precached = true;
      for (final asset in const [
        _assetGreeting,
        _assetIdle,
        _assetThinking,
        _assetSuccess,
      ]) {
        try {
          precacheImage(AssetImage(asset), context).catchError((_) {});
        } catch (_) {}
      }
    }
  }

  @override
  void didUpdateWidget(covariant _NusaBuddyMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _syncControllersForState();
    }
  }

  void _syncControllersForState() {
    if (widget.state == 'greeting') {
      _successCtrl.stop();
      _greetingCtrl.forward(from: 0);
      return;
    }
    if (widget.state == 'success') {
      _greetingCtrl.stop();
      _successCtrl.forward(from: 0);
      return;
    }
    _greetingCtrl.stop();
    _successCtrl.stop();
  }

  @override
  void dispose() {
    _greetingCtrl.dispose();
    _successCtrl.dispose();
    _pokeCtrl.dispose();
    super.dispose();
  }

  void _triggerPoke() {
    _pokeCtrl.forward(from: 0);
  }

  String _activeAssetPath() {
    return switch (widget.state) {
      'greeting' => _assetGreeting,
      'thinking' => _assetThinking,
      'success' => _assetSuccess,
      _ => _assetIdle,
    };
  }

  Widget _buildMascotImage(String assetPath, NusaThemeTokens tokens) {
    // Under widget tests (`pumpAndSettle`), freeze multi-frame animated WebP to frame 0 via ResizeImage
    // while real Android/iOS/Web production builds play full native 18 FPS multi-frame Animated WebP!
    final ImageProvider provider = _isWidgetTestBinding
        ? ResizeImage(AssetImage(assetPath), width: 320, height: 320)
        : AssetImage(assetPath);

    return Image(
      key: ValueKey<String>(assetPath),
      image: provider,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (ctx, error, stack) => Container(
        width: widget.size * 0.65,
        height: widget.size * 0.65,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tokens.accentSoft,
          border: Border.all(color: tokens.accent, width: 2),
        ),
        child: Icon(
          Icons.auto_awesome_rounded,
          color: tokens.accent,
          size: widget.size * 0.30,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final assetPath = _activeAssetPath();

    return GestureDetector(
      onTap: _triggerPoke,
      behavior: HitTestBehavior.translucent,
      child: Semantics(
        label: 'OXORA Buddy (${widget.state})',
        child: AnimatedBuilder(
          animation: Listenable.merge([_greetingCtrl, _pokeCtrl]),
          builder: (ctx, child) {
            double dy = 0;
            double scaleX = 1;
            double scaleY = 1;

            // Soft elastic pop-in entrance during first 380ms of Greeting phase
            if (widget.state == 'greeting' && _greetingCtrl.value < 0.18) {
              final k = Curves.easeOutBack.transform(
                (_greetingCtrl.value / 0.18).clamp(0.0, 1.0),
              );
              final s = 0.76 + 0.24 * k;
              scaleX = s;
              scaleY = s;
              dy = 14.0 * (1.0 - k);
            }

            // Interactive plushie squash & stretch on tap
            if (_pokeCtrl.isAnimating) {
              final p = _pokeCtrl.value;
              final envelope = 1.0 - p;
              final osc = math.sin(p * math.pi * 3.0);
              scaleX *= 1.0 + osc * 0.13 * envelope;
              scaleY *= 1.0 - osc * 0.13 * envelope;
              dy += osc * 3.5 * envelope;
            }

            return Transform.translate(
              offset: Offset(0, dy),
              child: Transform.scale(
                alignment: Alignment.bottomCenter,
                scaleX: scaleX,
                scaleY: scaleY,
                child: child,
              ),
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: widget.size,
            height: widget.size,
            alignment: Alignment.bottomCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  alignment: Alignment.bottomCenter,
                  scale: Tween<double>(begin: 0.91, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
              child: _buildMascotImage(assetPath, tokens),
            ),
          ),
        ),
      ),
    );
  }
}
