import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/currency_formatter.dart';

/// NusaCommerce Enterprise Design System — Atomic Reusable Widgets
/// High-density, 1px bordered flat surfaces, >= 44dp touch targets, tabular figures.

class NusaCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final bool elevated;
  final VoidCallback? onTap;

  const NusaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    this.borderRadius = 14,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1.0,
    this.elevated = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final decoration = BoxDecoration(
      color: backgroundColor ?? AppColors.surface,
      borderRadius: radius,
      border: Border.all(
        color: borderColor ?? AppColors.border,
        width: borderWidth,
      ),
      boxShadow: elevated ? AppColors.cardShadow : null,
    );

    final content = Container(
      padding: padding,
      decoration: decoration,
      child: child,
    );

    if (onTap == null) {
      return margin != null ? Padding(padding: margin!, child: content) : content;
    }

    final clickable = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: content,
      ),
    );

    return margin != null ? Padding(padding: margin!, child: clickable) : clickable;
  }
}

enum NusaButtonVariant { primary, success, warning, danger, outline, ghost }

class NusaButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final NusaButtonVariant variant;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool isLoading;
  final bool fullWidth;
  final double minHeight;
  final double borderRadius;

  const NusaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = NusaButtonVariant.primary,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.fullWidth = true,
    this.minHeight = 48,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;
    Color bg;
    Color fg;
    BorderSide? border;

    switch (variant) {
      case NusaButtonVariant.primary:
        bg = AppColors.primary;
        fg = Colors.white;
        break;
      case NusaButtonVariant.success:
        bg = AppColors.successDark;
        fg = Colors.white;
        break;
      case NusaButtonVariant.warning:
        bg = AppColors.warningDark;
        fg = Colors.white;
        break;
      case NusaButtonVariant.danger:
        bg = AppColors.dangerDark;
        fg = Colors.white;
        break;
      case NusaButtonVariant.outline:
        bg = Colors.white;
        fg = AppColors.navyDark;
        border = const BorderSide(color: AppColors.border, width: 1.2);
        break;
      case NusaButtonVariant.ghost:
        bg = AppColors.primarySoft;
        fg = AppColors.primary;
        break;
    }

    if (disabled && variant != NusaButtonVariant.outline) {
      bg = bg.withOpacity(0.5);
    }

    final child = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(fg),
            ),
          ),
          const SizedBox(width: 10),
        ] else if (icon != null) ...[
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
        if (!isLoading && trailingIcon != null) ...[
          const SizedBox(width: 8),
          Icon(trailingIcon, size: 18, color: fg),
        ],
      ],
    );

    final btn = SizedBox(
      width: fullWidth ? double.infinity : null,
      height: minHeight < 44 ? 44 : minHeight,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: border ?? BorderSide.none,
        ),
        child: InkWell(
          onTap: disabled ? null : onPressed,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(child: child),
          ),
        ),
      ),
    );

    return btn;
  }
}

enum NusaBadgeVariant { primary, success, warning, danger, neutral, navy }

class NusaBadge extends StatelessWidget {
  final String label;
  final NusaBadgeVariant variant;
  final IconData? icon;
  final double fontSize;

  const NusaBadge({
    super.key,
    required this.label,
    this.variant = NusaBadgeVariant.neutral,
    this.icon,
    this.fontSize = 10.5,
  });

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;

    switch (variant) {
      case NusaBadgeVariant.primary:
        bg = AppColors.primarySoft;
        fg = AppColors.primary;
        break;
      case NusaBadgeVariant.success:
        bg = AppColors.successSoft;
        fg = AppColors.successDark;
        break;
      case NusaBadgeVariant.warning:
        bg = AppColors.warningSoft;
        fg = AppColors.warningDark;
        break;
      case NusaBadgeVariant.danger:
        bg = AppColors.dangerSoft;
        fg = AppColors.dangerDark;
        break;
      case NusaBadgeVariant.navy:
        bg = AppColors.navyDark;
        fg = Colors.white;
        break;
      case NusaBadgeVariant.neutral:
        bg = const Color(0xFFF1F5F9);
        fg = AppColors.slate700;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 1.5, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: fg,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

class NusaEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const NusaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, size: 30, color: AppColors.slate500),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.navyDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.slate500,
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              NusaButton(
                label: actionLabel!,
                onPressed: onAction,
                fullWidth: false,
                minHeight: 44,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class NusaPriceTag extends StatelessWidget {
  final dynamic amount;
  final double fontSize;
  final FontWeight fontWeight;
  final Color color;
  final bool compact;
  final bool strikethrough;
  final String? prefix;

  const NusaPriceTag({
    super.key,
    required this.amount,
    this.fontSize = 14,
    this.fontWeight = FontWeight.w800,
    this.color = AppColors.navyDark,
    this.compact = false,
    this.strikethrough = false,
    this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    final formatted = compact
        ? IdrCurrencyFormatter.formatCompact(amount)
        : IdrCurrencyFormatter.format(amount);
    final text = prefix != null ? '$prefix$formatted' : formatted;

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTheme.moneyStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      ).copyWith(
        decoration: strikethrough ? TextDecoration.lineThrough : null,
      ),
    );
  }
}

/// Non-clipping horizontal filter pill optimized for Web CanvasKit and Android touch targets.
class NusaPillFilter extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? selectedColor;

  const NusaPillFilter({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    final activeBg = selectedColor ?? AppColors.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? activeBg : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? activeBg : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: selected ? Colors.white : AppColors.slate600,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.slate700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reactive Connectivity & Offline-Sync Status Pill displayed in headers/AppBars.
class NusaSyncStatusPill extends StatelessWidget {
  final bool isOnline;
  final bool isSyncing;
  final int offlinePendingCount;
  final VoidCallback? onTap;
  final bool compact;

  const NusaSyncStatusPill({
    super.key,
    required this.isOnline,
    required this.isSyncing,
    required this.offlinePendingCount,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color border;
    final Color fg;
    final String label;

    if (isSyncing) {
      bg = AppColors.primarySoft;
      border = AppColors.primary.withOpacity(0.35);
      fg = AppColors.primaryDark;
      label = 'Menyinkronkan Nota ke Cloud...';
    } else if (!isOnline || offlinePendingCount > 0) {
      bg = AppColors.warningSoft;
      border = AppColors.warning.withOpacity(0.45);
      fg = AppColors.warningDark;
      label = !isOnline
          ? 'Offline • $offlinePendingCount Nota Tersimpan di HP'
          : 'Offline • $offlinePendingCount Nota Tersimpan di HP';
    } else {
      bg = AppColors.successSoft;
      border = AppColors.success.withOpacity(0.35);
      fg = AppColors.successDark;
      label = 'Online • Tersinkron';
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 4 : 5,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSyncing)
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.8, color: fg),
              )
            else
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
              ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 10.5 : 11,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Self-contained official NusaCommerce 3D ribbon "N" logo widget rendered directly
/// via CustomPainter so Web hot-restart and Android APK never suffer asset 404 errors.
class NusaBrandLogo extends StatelessWidget {
  final double size;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final Color borderColor;
  final List<BoxShadow>? boxShadow;

  const NusaBrandLogo({
    super.key,
    this.size = 52,
    this.borderRadius = 14,
    this.padding = const EdgeInsets.all(7),
    this.backgroundColor = Colors.white,
    this.borderColor = AppColors.border,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor),
        boxShadow: boxShadow,
      ),
      child: const CustomPaint(
        painter: _NusaRibbonLogoPainter(),
      ),
    );
  }
}

class _NusaRibbonLogoPainter extends CustomPainter {
  const _NusaRibbonLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    Offset pt(double x, double y) => Offset(x * w, y * h);

    // 1. Left vertical pillar (behind the top-left arch)
    final leftPillar = Path()
      ..moveTo(0.03 * w, 0.21 * h)
      ..lineTo(0.03 * w, 0.955 * h)
      ..quadraticBezierTo(0.03 * w, 0.978 * h, 0.058 * w, 0.962 * h)
      ..lineTo(0.225 * w, 0.858 * h)
      ..quadraticBezierTo(0.252 * w, 0.838 * h, 0.252 * w, 0.785 * h)
      ..lineTo(0.252 * w, 0.16 * h)
      ..close();

    final leftPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [
          Color(0xFF00E1FF),
          Color(0xFF0297E6),
          Color(0xFF0C348F),
        ],
        stops: [0.0, 0.58, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(leftPillar, leftPaint);

    // Subtle sheen near bottom-left bevel of left pillar
    final leftLowerSheen = Path()
      ..moveTo(0.03 * w, 0.76 * h)
      ..lineTo(0.252 * w, 0.56 * h)
      ..lineTo(0.252 * w, 0.785 * h)
      ..quadraticBezierTo(0.252 * w, 0.838 * h, 0.225 * w, 0.858 * h)
      ..lineTo(0.058 * w, 0.962 * h)
      ..quadraticBezierTo(0.03 * w, 0.978 * h, 0.03 * w, 0.955 * h)
      ..close();
    canvas.drawPath(
      leftLowerSheen,
      Paint()..color = const Color(0xFF38BDF8).withOpacity(0.18),
    );

    // 2. Right vertical pillar (mirrored top-right bevel tip)
    final rightPillar = Path()
      ..moveTo(0.97 * w, 0.79 * h)
      ..lineTo(0.97 * w, 0.045 * h)
      ..quadraticBezierTo(0.97 * w, 0.022 * h, 0.942 * w, 0.038 * h)
      ..lineTo(0.775 * w, 0.142 * h)
      ..quadraticBezierTo(0.748 * w, 0.162 * h, 0.748 * w, 0.215 * h)
      ..lineTo(0.748 * w, 0.84 * h)
      ..close();

    final rightPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF1D4ED8),
          Color(0xFF0F258C),
          Color(0xFF0A4DA2),
        ],
        stops: [0.0, 0.65, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(rightPillar, rightPaint);

    // 3. Lower / inner folded S-band creating 3D ribbon depth
    final underBand = Path()
      ..moveTo(0.19 * w, 0.17 * h)
      ..cubicTo(0.25 * w, 0.25 * h, 0.32 * w, 0.35 * h, 0.33 * w, 0.56 * h)
      ..quadraticBezierTo(0.335 * w, 0.635 * h, 0.39 * w, 0.695 * h)
      ..lineTo(0.61 * w, 0.915 * h)
      ..cubicTo(0.73 * w, 1.01 * h, 0.94 * w, 0.97 * h, 0.97 * w, 0.76 * h)
      ..cubicTo(0.93 * w, 0.86 * h, 0.78 * w, 0.86 * h, 0.66 * w, 0.74 * h)
      ..lineTo(0.35 * w, 0.38 * h)
      ..close();

    final underPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF0E47B5),
          Color(0xFF0284C7),
          Color(0xFF0F1F7A),
        ],
        stops: [0.0, 0.55, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(underBand, underPaint);

    // 4. Primary luminous top-left to bottom-right ribbon crest
    final frontRibbon = Path()
      ..moveTo(0.03 * w, 0.21 * h)
      ..cubicTo(0.025 * w, 0.04 * h, 0.22 * w, -0.02 * h, 0.37 * w, 0.14 * h)
      ..lineTo(0.74 * w, 0.56 * h)
      ..cubicTo(0.84 * w, 0.68 * h, 0.93 * w, 0.73 * h, 0.97 * w, 0.62 * h)
      ..lineTo(0.97 * w, 0.79 * h)
      ..cubicTo(0.90 * w, 0.92 * h, 0.74 * w, 0.89 * h, 0.61 * w, 0.75 * h)
      ..lineTo(0.27 * w, 0.34 * h)
      ..cubicTo(0.18 * w, 0.23 * h, 0.08 * w, 0.14 * h, 0.03 * w, 0.21 * h)
      ..close();

    final frontPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [
          Color(0xFF33F3FF),
          Color(0xFF00C2FF),
          Color(0xFF0284C7),
          Color(0xFF1D4ED8),
        ],
        stops: const [0.0, 0.30, 0.68, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(frontRibbon, frontPaint);

    // 5. Crisp diagonal specular ridge glow
    final ridgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (w * 0.026).clamp(1.0, 3.0)
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.55),
          const Color(0xFF7DD3FC).withOpacity(0.65),
          Colors.white.withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final ridgePath = Path()
      ..moveTo(pt(0.24, 0.22).dx, pt(0.24, 0.22).dy)
      ..quadraticBezierTo(pt(0.52, 0.52).dx, pt(0.52, 0.52).dy, pt(0.78, 0.78).dx, pt(0.78, 0.78).dy);
    canvas.drawPath(ridgePath, ridgePaint);
  }

  @override
  bool shouldRepaint(covariant _NusaRibbonLogoPainter oldDelegate) => false;
}
