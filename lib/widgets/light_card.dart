import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// White rounded card with subtle border + soft shadow. Used everywhere the
/// design calls for `.light-card`.
class LightCard extends StatelessWidget {
  const LightCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
    this.radius = T.rMd,
    this.color = T.surface,
    this.border,
    this.gradient,
    this.onTap,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final double radius;
  final Color color;
  final BoxBorder? border;
  final Gradient? gradient;
  final VoidCallback? onTap;
  // shadow=false 用于长列表项:阴影是 Flutter Web 最贵的合成操作,关掉显著提升滚动性能。
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: border ?? Border.all(color: T.border),
        boxShadow: shadow ? T.shadowSoft : null,
      ),
      child: child,
    );
    final wrapped = onTap == null
        ? box
        : Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radius),
              child: box,
            ),
          );
    return Padding(padding: margin, child: wrapped);
  }
}

/// Section title with the brand-cyan vertical accent bar.
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3,
            height: 22,
            decoration: BoxDecoration(
              color: T.brand,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800, color: T.ink)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: T.inkLo)),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
