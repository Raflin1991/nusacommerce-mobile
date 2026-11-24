import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/nusa_theme_tokens.dart';
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
    final tokens = NusaThemeTokens.of(context);
    final radius = BorderRadius.circular(borderRadius);
    final effectiveBorderWidth = tokens.isHighContrast && borderWidth < tokens.borderWidth
        ? tokens.borderWidth
        : borderWidth;
    final decoration = BoxDecoration(
      color: backgroundColor ?? tokens.bgSurface,
      borderRadius: radius,
      border: Border.all(
        color: borderColor ?? tokens.borderSubtle,
        width: effectiveBorderWidth,
      ),
      boxShadow: elevated && !tokens.isHighContrast ? AppColors.cardShadow : null,
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
    final tokens = NusaThemeTokens.of(context);
    final disabled = onPressed == null || isLoading;
    Color bg;
    Color fg;
    BorderSide? border;

    switch (variant) {
      case NusaButtonVariant.primary:
        bg = tokens.accent;
        fg = Colors.white;
        break;
      case NusaButtonVariant.success:
        bg = tokens.positive;
        fg = Colors.white;
        break;
      case NusaButtonVariant.warning:
        bg = tokens.warning;
        fg = Colors.white;
        break;
      case NusaButtonVariant.danger:
        bg = tokens.danger;
        fg = Colors.white;
        break;
      case NusaButtonVariant.outline:
        bg = tokens.bgSurface;
        fg = tokens.textPrimary;
        border = BorderSide(
          color: tokens.isHighContrast ? tokens.borderDefault : tokens.borderSubtle,
          width: tokens.isHighContrast ? tokens.borderWidth : 1.2,
        );
        break;
      case NusaButtonVariant.ghost:
        bg = tokens.accentSoft;
        fg = tokens.accent;
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
    final tokens = NusaThemeTokens.of(context);
    late Color bg;
    late Color fg;

    switch (variant) {
      case NusaBadgeVariant.primary:
        bg = tokens.accentSoft;
        fg = tokens.accent;
        break;
      case NusaBadgeVariant.success:
        bg = tokens.positiveSoft;
        fg = tokens.positive;
        break;
      case NusaBadgeVariant.warning:
        bg = tokens.warningSoft;
        fg = tokens.warning;
        break;
      case NusaBadgeVariant.danger:
        bg = tokens.dangerSoft;
        fg = tokens.danger;
        break;
      case NusaBadgeVariant.navy:
        bg = tokens.isDark ? tokens.bgElevated : tokens.textPrimary;
        fg = Colors.white;
        break;
      case NusaBadgeVariant.neutral:
        bg = tokens.bgElevated;
        fg = tokens.textSecondary;
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
          Flexible(
            child: Text(
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
    final tokens = NusaThemeTokens.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: tokens.bgElevated,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
              ),
              child: Icon(icon, size: 30, color: tokens.textSecondary),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: tokens.textSecondary,
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
  final Color? color;
  final bool compact;
  final bool strikethrough;
  final String? prefix;
  final bool fitWidth;

  const NusaPriceTag({
    super.key,
    required this.amount,
    this.fontSize = 14,
    this.fontWeight = FontWeight.w800,
    this.color,
    this.compact = false,
    this.strikethrough = false,
    this.prefix,
    this.fitWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? NusaThemeTokens.of(context).textPrimary;
    final formatted = compact
        ? IdrCurrencyFormatter.formatCompact(amount)
        : IdrCurrencyFormatter.format(amount);
    final text = prefix != null ? '$prefix$formatted' : formatted;

    final widget = Text(
      text,
      maxLines: 1,
      overflow: fitWidth ? TextOverflow.visible : TextOverflow.ellipsis,
      softWrap: false,
      style: AppTheme.moneyStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: effectiveColor,
      ).copyWith(
        decoration: strikethrough ? TextDecoration.lineThrough : null,
      ),
    );

    if (fitWidth) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: widget,
      );
    }

    return widget;
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
    final tokens = NusaThemeTokens.of(context);
    final activeBg = selectedColor ?? tokens.accent;
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
            color: selected ? activeBg : tokens.bgElevated,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? activeBg : tokens.borderSubtle,
              width: tokens.borderWidth,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: selected ? Colors.white : tokens.textSecondary,
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : tokens.textPrimary,
                  ),
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
    final tokens = NusaThemeTokens.of(context);
    final Color bg;
    final Color border;
    final Color fg;
    final String label;

    if (isSyncing) {
      bg = tokens.accentSoft;
      border = tokens.accent.withOpacity(tokens.isHighContrast ? 0.9 : 0.35);
      fg = tokens.accentDark;
      label = 'Menyinkronkan Nota ke Cloud...';
    } else if (!isOnline) {
      bg = tokens.warningSoft;
      border = tokens.warning.withOpacity(tokens.isHighContrast ? 0.9 : 0.45);
      fg = tokens.warning;
      label = offlinePendingCount > 0
          ? 'Offline • $offlinePendingCount Nota Tersimpan di HP'
          : 'Offline • Mode Lokal Aktif';
    } else if (offlinePendingCount > 0) {
      bg = tokens.warningSoft;
      border = tokens.warning.withOpacity(tokens.isHighContrast ? 0.9 : 0.45);
      fg = tokens.warning;
      label = 'Online • $offlinePendingCount Nota Menunggu Sinkron';
    } else {
      bg = tokens.positiveSoft;
      border = tokens.positive.withOpacity(tokens.isHighContrast ? 0.9 : 0.35);
      fg = tokens.positive;
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

/// Self-contained official OXORA transparent Infinity logo widget.
/// Renders the official high-resolution transparent OXORA Infinity emblem with
/// a crisp vector fallback painter — zero dark/black box on Light Theme.
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
    this.padding = EdgeInsets.zero,
    this.backgroundColor = Colors.transparent,
    this.borderColor = Colors.transparent,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final hasBox = backgroundColor != Colors.transparent ||
        borderColor != Colors.transparent ||
        (boxShadow != null && boxShadow!.isNotEmpty);

    return Container(
      width: size,
      height: size,
      padding: padding,
      decoration: hasBox
          ? BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(borderRadius),
              border: borderColor != Colors.transparent
                  ? Border.all(color: borderColor)
                  : null,
              boxShadow: boxShadow,
            )
          : null,
      child: Image.asset(
        'assets/images/oxora_icon.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Padding(
          padding: EdgeInsets.all(4),
          child: CustomPaint(
            painter: _OxoraInfinityLogoPainter(),
          ),
        ),
      ),
    );
  }
}

class _OxoraInfinityLogoPainter extends CustomPainter {
  const _OxoraInfinityLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final strokeW = w * 0.16;

    final leftLoop = Path()
      ..moveTo(w * 0.50, h * 0.50)
      ..cubicTo(w * 0.34, h * 0.18, w * 0.08, h * 0.20, w * 0.08, h * 0.50)
      ..cubicTo(w * 0.08, h * 0.80, w * 0.34, h * 0.82, w * 0.50, h * 0.50);

    final rightLoop = Path()
      ..moveTo(w * 0.50, h * 0.50)
      ..cubicTo(w * 0.66, h * 0.18, w * 0.92, h * 0.20, w * 0.92, h * 0.50)
      ..cubicTo(w * 0.92, h * 0.80, w * 0.66, h * 0.82, w * 0.50, h * 0.50);

    final infinityPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [Color(0xFF00E5FF), Color(0xFF0055FF), Color(0xFF00C2FF)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawPath(leftLoop, infinityPaint);
    canvas.drawPath(rightLoop, infinityPaint);

    // Warm Amber/Orange center diamond
    final diamond = Path()
      ..moveTo(w * 0.50, h * 0.34)
      ..lineTo(w * 0.63, h * 0.50)
      ..lineTo(w * 0.50, h * 0.66)
      ..lineTo(w * 0.37, h * 0.50)
      ..close();

    final diamondPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFD000), Color(0xFFFF6D00)],
      ).createShader(Rect.fromLTWH(w * 0.35, h * 0.34, w * 0.30, h * 0.32));

    canvas.drawPath(diamond, diamondPaint);
  }

  @override
  bool shouldRepaint(covariant _OxoraInfinityLogoPainter oldDelegate) => false;
}
