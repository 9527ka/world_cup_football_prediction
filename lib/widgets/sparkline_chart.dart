import 'package:flutter/material.dart';

import '../models/match.dart';
import '../theme/tokens.dart';

/// 1X2 赔率走势的 sparkline — 三条线(主/平/客)叠在同一 Y 轴。
/// 自动按所有点的 min/max 做归一化,起点/终点对齐画布。
/// 空数据返回 SizedBox.shrink。
class OddsSparklineChart extends StatelessWidget {
  const OddsSparklineChart({super.key, required this.history, this.height = 56});

  final OddsHistory history;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (!history.hasData) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _SparkPainter(
          home: history.home.map((p) => p.price).toList(),
          draw: history.draw.map((p) => p.price).toList(),
          away: history.away.map((p) => p.price).toList(),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.home, required this.draw, required this.away});

  final List<double> home;
  final List<double> draw;
  final List<double> away;

  @override
  void paint(Canvas canvas, Size size) {
    // Compute global min/max across all 3 series for shared Y axis.
    double? minV, maxV;
    void scan(List<double> xs) {
      for (final v in xs) {
        if (minV == null || v < minV!) minV = v;
        if (maxV == null || v > maxV!) maxV = v;
      }
    }
    scan(home); scan(draw); scan(away);
    if (minV == null || maxV == null) return;
    if ((maxV! - minV!).abs() < 1e-6) {
      // Flat data — pad slightly so we still see a horizontal line.
      maxV = minV! + 0.01;
    }

    // Subtle baseline + grid: draw a soft horizontal mid line for orientation.
    final gridPaint = Paint()
      ..color = const Color(0xFFE6ECF2)
      ..strokeWidth = 0.6;
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), gridPaint);

    void plot(List<double> xs, Color color) {
      if (xs.length < 2) return;
      final path = Path();
      for (int i = 0; i < xs.length; i++) {
        final x = i / (xs.length - 1) * size.width;
        // y inverted: lower price = higher on screen (more "favored")
        final norm = (xs[i] - minV!) / (maxV! - minV!);
        final y = size.height - norm * size.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, paint);
      // Highlight last point.
      final last = Offset(size.width, size.height - (xs.last - minV!) / (maxV! - minV!) * size.height);
      canvas.drawCircle(last, 2.2, Paint()..color = color);
    }

    plot(home, T.brandDeep);          // 主胜 — 品牌深蓝
    plot(draw, const Color(0xFF8C9CB1)); // 平局 — 中性灰
    plot(away, const Color(0xFFE03E2D));  // 客胜 — 红
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) {
    return _diff(old.home, home) || _diff(old.draw, draw) || _diff(old.away, away);
  }

  bool _diff(List<double> a, List<double> b) {
    if (a.length != b.length) return true;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return true;
    }
    return false;
  }
}
