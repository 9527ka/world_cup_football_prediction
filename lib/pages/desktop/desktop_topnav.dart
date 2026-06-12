import 'package:flutter/material.dart';

import '../../services/i18n.dart';
import '../../theme/tokens.dart';
import 'desktop_nav.dart';

/// 桌面顶部导航栏(替代左侧栏)。品牌 + 4 个横向 tab + 充值 CTA + 语言。
/// 在主区内次级页时,左侧改为「返回 + 标题」,tab 仍可点(点了清栈切 tab)。
class DesktopTopNav extends StatelessWidget {
  const DesktopTopNav({
    super.key,
    required this.current,
    required this.onSelect,
    required this.onDeposit,
    required this.onLanguage,
    this.subTitle,
    this.onBack,
  });

  final int current;
  final ValueChanged<int> onSelect;
  final VoidCallback onDeposit;
  final VoidCallback onLanguage;
  final String? subTitle;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final inSub = onBack != null;
    return Container(
      height: 60,
      decoration: const BoxDecoration(
        color: T.surface,
        border: Border(bottom: BorderSide(color: T.border)),
        boxShadow: [
          BoxShadow(color: Color(0x0A0E2238), blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
      // 背景条通栏,内容居中限宽(与页面内容对齐,不顶到两边)。
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
        children: [
          // 左:品牌 或 返回+标题
          if (inSub) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              color: T.ink,
              onPressed: onBack,
            ),
            if (subTitle != null)
              Text(subTitle!, style: T.h2.copyWith(fontSize: 16)),
          ] else
            _brand(),
          const SizedBox(width: 28),
          // 中:横向 tab
          _tab(DesktopTab.home, tr('nav.home'), Icons.home_rounded),
          _tab(DesktopTab.matches, tr('nav.matches'), Icons.sports_soccer),
          _tab(DesktopTab.leaderboard, tr('nav.leaderboard'), Icons.emoji_events),
          _tab(DesktopTab.profile, tr('nav.profile'), Icons.person),
          const Spacer(),
          // 右:充值 + 语言
          _depositBtn(),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Language',
            icon: const Icon(Icons.translate, size: 20),
            color: T.inkMd,
            onPressed: onLanguage,
          ),
        ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _brand() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: T.brandGradientShort,
            borderRadius: BorderRadius.circular(T.rSm),
          ),
          child: const Icon(Icons.sports_soccer, color: Colors.white, size: 19),
        ),
        const SizedBox(width: 10),
        Text(tr('home.title_a') + tr('home.title_b'),
            style: T.h2.copyWith(fontSize: 17)),
      ],
    );
  }

  Widget _tab(int index, String label, IconData icon) {
    final active = current == index;
    final color = active ? T.brandDeep : T.inkMd;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: active ? T.brandSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => onSelect(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight:
                            active ? FontWeight.w800 : FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _depositBtn() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onDeposit,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: T.brandGradientShort,
            borderRadius: BorderRadius.circular(999),
            boxShadow: T.shadowGlowBrand,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.account_balance_wallet, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(tr('nav.deposit'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.0,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}
