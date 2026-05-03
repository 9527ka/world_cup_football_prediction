import 'package:flutter/material.dart';

import '../pages/bet_slip_sheet.dart';
import '../services/app_state.dart';
import '../theme/tokens.dart';

/// 跨所有页面常驻的悬浮购物车按钮。投注单空时隐藏。
/// 监听 BetSlip 的 ChangeNotifier,数量变了自动重绘。
class BetSlipFab extends StatelessWidget {
  const BetSlipFab({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state.betSlip,
      builder: (context, _) {
        final n = state.betSlip.count;
        if (n == 0) return const SizedBox.shrink();
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => BetSlipSheet.show(context, state),
            borderRadius: BorderRadius.circular(28),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: T.brandGradientShort,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x4D11BAD9),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.receipt_long, size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('投注单 $n',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
