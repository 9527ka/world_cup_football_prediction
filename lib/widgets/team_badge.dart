import 'package:flutter/material.dart';

/// A rounded-square team badge: gradient fill, white border, first-letter mark.
/// Mirrors the JSX `TeamBadgeLight` / `TeamBadgeMd` family.
class TeamBadge extends StatelessWidget {
  const TeamBadge({
    super.key,
    required this.name,
    this.color,
    this.size = 36,
    this.borderRadius = 11,
    this.borderWidth = 2,
  });

  final String name;
  final Color? color;
  final double size;
  final double borderRadius;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final base = color ?? _palette[name.codeUnitAt(0) % _palette.length];
    final dark = _shade(base, -0.22);
    final letter = name.isEmpty ? '?' : name.characters.first;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, dark],
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.white, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: base.withValues(alpha: 0.30),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.44,
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
    );
  }
}

const List<Color> _palette = [
  Color(0xFFD9AB7A),
  Color(0xFF5FBDFD),
  Color(0xFF5DD394),
  Color(0xFFE07089),
  Color(0xFF8E7AD9),
];

Color _shade(Color c, double t) {
  // t > 0 lighten, t < 0 darken
  final a = (c.a * 255).round().clamp(0, 255);
  final r = (c.r * 255).round().clamp(0, 255);
  final g = (c.g * 255).round().clamp(0, 255);
  final b = (c.b * 255).round().clamp(0, 255);
  if (t < 0) {
    final f = 1 + t;
    return Color.fromARGB(
      a,
      (r * f).clamp(0, 255).round(),
      (g * f).clamp(0, 255).round(),
      (b * f).clamp(0, 255).round(),
    );
  }
  return Color.fromARGB(
    a,
    (r + (255 - r) * t).clamp(0, 255).round(),
    (g + (255 - g) * t).clamp(0, 255).round(),
    (b + (255 - b) * t).clamp(0, 255).round(),
  );
}
