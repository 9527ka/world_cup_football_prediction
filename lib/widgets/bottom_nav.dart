import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/i18n.dart';
import '../theme/tokens.dart';

/// 5-tab bottom nav with the brand-cyan center "+" coin bumped above.
/// Mirrors the JSX `BottomNavLight` used on home / list / profile.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final items = [
      _NavSpec(tr('nav.home'), Icons.home_outlined, Icons.home_rounded),
      _NavSpec(tr('nav.matches'), Icons.sports_soccer_outlined, Icons.sports_soccer),
      _NavSpec(tr('nav.deposit'), null, null, center: true),
      _NavSpec(tr('nav.leaderboard'), Icons.emoji_events_outlined, Icons.emoji_events),
      _NavSpec(tr('nav.profile'), Icons.person_outline, Icons.person),
    ];

    return Container(
      height: 78,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
      decoration: const BoxDecoration(
        color: Color(0xEBFFFFFF),
        border: Border(top: BorderSide(color: T.border)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0F0E2238),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: items[i].center
                  ? _CenterButton(
                      onTap: () => onTap(i),
                      label: items[i].label,
                      active: currentIndex == i,
                    )
                  : _SideTab(
                      spec: items[i],
                      active: currentIndex == i,
                      onTap: () => onTap(i),
                    ),
            ),
        ],
      ),
    );
  }
}

class _NavSpec {
  final String label;
  final IconData? icon;
  final IconData? activeIcon;
  final bool center;
  const _NavSpec(this.label, this.icon, this.activeIcon, {this.center = false});
}

class _SideTab extends StatelessWidget {
  const _SideTab({required this.spec, required this.active, required this.onTap});
  final _NavSpec spec;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? T.brandDeep : T.inkLo;
    return InkResponse(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(active ? spec.activeIcon : spec.icon, color: color, size: 24),
          const SizedBox(height: 2),
          Text(spec.label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Center deposit button — 1:1 visual port of the reference site:
///   - 76px circular icon (assets/icons/deposit.png)
///   - white-gradient "scanLight" sweep clipped to the circle (1.2s loop)
///   - top-right speech-bubble badge ("送1%") composited from 3 sliced PNGs
class _CenterButton extends StatefulWidget {
  const _CenterButton({required this.onTap, required this.label, required this.active});
  final VoidCallback onTap;
  final String label;
  final bool active;

  @override
  State<_CenterButton> createState() => _CenterButtonState();
}

class _CenterButtonState extends State<_CenterButton>
    with TickerProviderStateMixin {
  /// scanLight 高光扫光,1.2s 单向循环
  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  /// Q 弹缩放周期 — 弹出 → 回压 → 小回弹 → 稳态停顿,1.4s 一轮
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  late final Animation<double> _depositScale = TweenSequence<double>([
    // 0 → 25%:从 1 弹出到 1.10
    TweenSequenceItem(
      tween: Tween(begin: 1.00, end: 1.10).chain(CurveTween(curve: Curves.easeOut)),
      weight: 25,
    ),
    // 25 → 43%:回弹过冲到 0.94(挤压)
    TweenSequenceItem(
      tween: Tween(begin: 1.10, end: 0.94).chain(CurveTween(curve: Curves.easeIn)),
      weight: 18,
    ),
    // 43 → 57%:再次小幅弹起到 1.04
    TweenSequenceItem(
      tween: Tween(begin: 0.94, end: 1.04).chain(CurveTween(curve: Curves.easeOut)),
      weight: 14,
    ),
    // 57 → 67%:小回压到 0.98
    TweenSequenceItem(
      tween: Tween(begin: 1.04, end: 0.98).chain(CurveTween(curve: Curves.easeIn)),
      weight: 10,
    ),
    // 67 → 75%:平复回 1.0
    TweenSequenceItem(
      tween: Tween(begin: 0.98, end: 1.00).chain(CurveTween(curve: Curves.easeOut)),
      weight: 8,
    ),
    // 75 → 100%:稳态停顿(看着不会一直抖)
    TweenSequenceItem(tween: ConstantTween(1.00), weight: 25),
  ]).animate(_pulse);

  @override
  void dispose() {
    _scan.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: widget.onTap,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 50),
            child: Text(widget.label,
                style: const TextStyle(
                    color: T.brandDeep,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
          // 主圆形按钮:存款图标 + scanLight 高光扫光
          Positioned(
            top: -28,
            child: SizedBox(
              width: 76,
              height: 76,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 阴影底
                  Container(
                    width: 76, height: 76,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x1F2CD7FD),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  // 圆底光晕背景图(icon_btm_cz_1)
                  ClipOval(
                    child: SizedBox(
                      width: 76, height: 76,
                      child: Image.asset(
                        'assets/icons/deposit_bg.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  // 存款图标(icon_btm_cz_2,前景),Q 弹放大缩小循环
                  Positioned.fill(
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _depositScale,
                        builder: (_, child) => Transform.scale(
                          scale: _depositScale.value,
                          child: child,
                        ),
                        child: SizedBox(
                          width: 76, height: 76,
                          child: ClipOval(
                            child: Image.asset(
                              'assets/icons/deposit.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // scanLight — 白色斜向高光从左上扫到右下,循环 1.2s
                  Positioned.fill(
                    child: ClipOval(
                      child: AnimatedBuilder(
                        animation: _scan,
                        builder: (_, __) {
                          // 0% → 70% 走完移动,70%-100% 停在屏外等待下一轮(原 keyframe 也是 0→70 then 70→100 不变)
                          final p = _scan.value;
                          final t = p < 0.7 ? p / 0.7 : 1.0;
                          final dx = -0.8 + 1.85 * t; // -80% → +105%
                          final dy = -0.25 + 0.45 * t; // -25% → +20%
                          return FractionalTranslation(
                            translation: Offset(dx, dy),
                            child: Transform.rotate(
                              angle: 15 * math.pi / 180,
                              child: Container(
                                width: 84, height: 120,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    stops: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
                                    colors: [
                                      Color(0x00FFFFFF),
                                      Color(0x66FFFFFF),
                                      Color(0xB3FFFFFF),
                                      Color(0xB3FFFFFF),
                                      Color(0x66FFFFFF),
                                      Color(0x00FFFFFF),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
