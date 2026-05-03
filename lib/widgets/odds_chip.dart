import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Compact odds value with arrow when the price moved.
class OddsChip extends StatelessWidget {
  const OddsChip({
    super.key,
    required this.label,
    required this.price,
    this.change,
  });

  final String label;
  final double price;
  final String? change; // 'up' | 'down' | 'same' | null

  @override
  Widget build(BuildContext context) {
    final isUp = change == 'up';
    final isDown = change == 'down';
    final fg = isUp ? T.up : isDown ? T.down : T.ink;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: T.fill,
        border: Border.all(color: T.border),
        borderRadius: BorderRadius.circular(T.rSm),
      ),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  color: T.inkLo,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4)),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                price > 0 ? price.toStringAsFixed(2) : '—',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: fg,
                  fontFamily: T.fontMono,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (isUp || isDown) ...[
                const SizedBox(width: 3),
                Icon(
                  isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  size: 14,
                  color: fg,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
