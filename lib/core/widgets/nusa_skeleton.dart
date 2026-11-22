import 'package:flutter/material.dart';
import '../theme/nusa_theme_tokens.dart';

/// Dependency-free animated Shimmer Skeleton block synchronized to CDO Warm Linen tokens.
class NusaShimmerBox extends StatefulWidget {
  final double? width;
  final double height;
  final double borderRadius;

  const NusaShimmerBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 10,
  });

  @override
  State<NusaShimmerBox> createState() => _NusaShimmerBoxState();
}

class _NusaShimmerBoxState extends State<NusaShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final shift = (_controller.value * 2.0) - 1.0;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1.2 + shift, -0.2),
              end: Alignment(0.8 + shift, 0.2),
              colors: [
                tokens.shimmerBase,
                tokens.shimmerHighlight,
                tokens.shimmerBase,
              ],
              stops: const [0.15, 0.5, 0.85],
            ),
          ),
        );
      },
    );
  }
}

/// Full-page Shimmer Skeleton mirroring the Role-Adaptive Home Dashboard layout.
class NusaDashboardSkeleton extends StatelessWidget {
  final bool compactCashierLayout;

  const NusaDashboardSkeleton({
    super.key,
    this.compactCashierLayout = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    return Column(
      key: const Key('nusa_dashboard_skeleton'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Operator strip placeholder
        _skeletonSurface(
          tokens,
          child: const Row(
            children: [
              NusaShimmerBox(width: 38, height: 38, borderRadius: 10),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NusaShimmerBox(width: 170, height: 14, borderRadius: 6),
                    SizedBox(height: 6),
                    NusaShimmerBox(width: 120, height: 11, borderRadius: 6),
                  ],
                ),
              ),
              NusaShimmerBox(width: 66, height: 24, borderRadius: 8),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Primary action strip placeholder
        const Row(
          children: [
            Expanded(flex: 3, child: NusaShimmerBox(height: 50, borderRadius: 14)),
            SizedBox(width: 8),
            Expanded(flex: 2, child: NusaShimmerBox(height: 50, borderRadius: 14)),
          ],
        ),
        const SizedBox(height: 14),
        // Hero pulse card placeholder
        _skeletonSurface(
          tokens,
          padding: const EdgeInsets.all(18),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  NusaShimmerBox(width: 130, height: 12, borderRadius: 6),
                  NusaShimmerBox(width: 84, height: 22, borderRadius: 999),
                ],
              ),
              SizedBox(height: 12),
              NusaShimmerBox(width: 210, height: 30, borderRadius: 8),
              SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  NusaShimmerBox(width: 115, height: 12, borderRadius: 6),
                  NusaShimmerBox(width: 90, height: 12, borderRadius: 6),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (!compactCashierLayout) ...[
          // 2x2 metrics grid placeholder
          Row(
            children: [
              Expanded(child: _metricSkeleton(tokens)),
              const SizedBox(width: 10),
              Expanded(child: _metricSkeleton(tokens)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _metricSkeleton(tokens)),
              const SizedBox(width: 10),
              Expanded(child: _metricSkeleton(tokens)),
            ],
          ),
        ] else ...[
          // Cashier quick actions row placeholder
          _skeletonSurface(
            tokens,
            child: const Row(
              children: [
                Expanded(child: NusaShimmerBox(height: 62, borderRadius: 12)),
                SizedBox(width: 8),
                Expanded(child: NusaShimmerBox(height: 62, borderRadius: 12)),
                SizedBox(width: 8),
                Expanded(child: NusaShimmerBox(height: 62, borderRadius: 12)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _metricSkeleton(NusaThemeTokens tokens) {
    return _skeletonSurface(
      tokens,
      padding: const EdgeInsets.all(13),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NusaShimmerBox(width: 96, height: 11, borderRadius: 5),
          SizedBox(height: 10),
          NusaShimmerBox(width: 118, height: 18, borderRadius: 6),
        ],
      ),
    );
  }

  Widget _skeletonSurface(
    NusaThemeTokens tokens, {
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
      ),
      child: child,
    );
  }
}

/// Shimmer Skeleton for Shift & Blind Drop screen.
class NusaShiftSkeleton extends StatelessWidget {
  const NusaShiftSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    return SingleChildScrollView(
      key: const Key('nusa_shift_skeleton'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NusaShimmerBox(height: 162, borderRadius: 18),
          const SizedBox(height: 14),
          const Row(
            children: [
              Expanded(child: NusaShimmerBox(height: 48, borderRadius: 12)),
              SizedBox(width: 10),
              Expanded(child: NusaShimmerBox(height: 48, borderRadius: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tokens.bgSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NusaShimmerBox(width: 200, height: 16, borderRadius: 6),
                SizedBox(height: 8),
                NusaShimmerBox(width: 260, height: 12, borderRadius: 6),
                SizedBox(height: 14),
                NusaShimmerBox(height: 52, borderRadius: 12),
                SizedBox(height: 12),
                NusaShimmerBox(height: 48, borderRadius: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable Shimmer List Skeleton for Bottom Sheets & Directory Views.
class NusaListSkeleton extends StatelessWidget {
  final int itemCount;

  const NusaListSkeleton({super.key, this.itemCount = 4});

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tokens.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
        ),
        child: const Row(
          children: [
            NusaShimmerBox(width: 40, height: 40, borderRadius: 10),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NusaShimmerBox(width: 160, height: 13, borderRadius: 6),
                  SizedBox(height: 6),
                  NusaShimmerBox(width: 110, height: 11, borderRadius: 6),
                ],
              ),
            ),
            NusaShimmerBox(width: 68, height: 16, borderRadius: 6),
          ],
        ),
      ),
    );
  }
}
