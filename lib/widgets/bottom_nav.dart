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

class _CenterButton extends StatelessWidget {
  const _CenterButton({required this.onTap, required this.label, required this.active});
  final VoidCallback onTap;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 38),
            child: Text(label,
                style: const TextStyle(
                    color: T.brandDeep,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
          Positioned(
            top: -22,
            child: Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: T.brandGradient,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x732CD7FD),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}
