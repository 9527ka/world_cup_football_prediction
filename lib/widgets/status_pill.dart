import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum BetStatus { pending, live, won, lost, voided, cashedOut }

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, this.label});

  final BetStatus status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg(status);
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: cfg.bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == BetStatus.live)
            const _LivePulseDot()
          else
            Container(
              width: 5, height: 5,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(color: cfg.dot, shape: BoxShape.circle),
            ),
          Text(
            label ?? cfg.label,
            style: TextStyle(
              color: cfg.fg,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _LivePulseDot extends StatefulWidget {
  const _LivePulseDot();

  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        // 0..1 expanding ring
        final spread = 3 + 3 * t;
        final opacity = (1 - t).clamp(0.0, 1.0);
        return Container(
          width: 5, height: 5,
          margin: const EdgeInsets.only(right: 5),
          decoration: BoxDecoration(
            color: T.down,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: T.down.withValues(alpha: 0.30 * opacity),
                blurRadius: spread,
                spreadRadius: spread * 0.6,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PillCfg {
  final String label;
  final Color bg;
  final Color fg;
  final Color dot;
  const _PillCfg(this.label, this.bg, this.fg, this.dot);
}

_PillCfg _cfg(BetStatus s) {
  switch (s) {
    case BetStatus.pending:
      return const _PillCfg('待开赛', Color(0x24F5B544), Color(0xFFC7861E), T.warn);
    case BetStatus.live:
      return const _PillCfg('进行中', Color(0x1AE03E2D), T.down, T.down);
    case BetStatus.won:
      return const _PillCfg('已中奖', Color(0x242BD475), T.upDark, T.up);
    case BetStatus.lost:
      return const _PillCfg('未中奖', Color(0xFFEEF2F7), T.inkLo, T.inkLo);
    case BetStatus.voided:
      return const _PillCfg('已退还', Color(0x248C9CB1), T.inkMd, T.inkLo);
    case BetStatus.cashedOut:
      return const _PillCfg('已提结', Color(0x242CD7FD), T.brandDeep, T.brand);
  }
}

BetStatus betStatusFromString(String s) {
  switch (s) {
    case 'won':
      return BetStatus.won;
    case 'lost':
      return BetStatus.lost;
    case 'void':
    case 'voided':
      return BetStatus.voided;
    case 'live':
      return BetStatus.live;
    case 'cashed_out':
      return BetStatus.cashedOut;
    default:
      return BetStatus.pending;
  }
}
