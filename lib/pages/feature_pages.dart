import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/match.dart';
import '../services/app_state.dart';
import '../services/i18n.dart';
import '../services/telegram.dart';
import '../services/toast.dart';
import '../theme/tokens.dart';
import '../widgets/light_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

PreferredSizeWidget _appBar(BuildContext context, String title) {
  return AppBar(
    leading: IconButton(
      icon: const Icon(Icons.chevron_left, size: 28),
      onPressed: () => Navigator.of(context).pop(),
    ),
    title: Text(title),
    centerTitle: true,
  );
}

BoxDecoration get _pageBg => const BoxDecoration(gradient: T.pageGradient);

Widget _sectionLabel(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(text,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: T.ink)),
    );

// ═════════════════════════════════════════════════════════════════════════════
// 1. ShareEarnPage — 分享赚钱 / 邀请返佣
// ═════════════════════════════════════════════════════════════════════════════

class ShareEarnPage extends StatefulWidget {
  const ShareEarnPage({super.key, required this.state});
  final AppState state;

  @override
  State<ShareEarnPage> createState() => _ShareEarnPageState();
}

class _ShareEarnPageState extends State<ShareEarnPage> {
  static const _botUsername = 'this_hai_wang_bot';
  Future<({String inviteCode, int invitedCount, double totalCommission})>?
      _future;

  @override
  void initState() {
    super.initState();
    _future = widget.state.api.getReferrals();
  }

  String _link(String code) =>
      code.isEmpty ? '' : 'https://t.me/$_botUsername?start=$code';

  void _copy(String text) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    Toast.show(context, tr('common.copied'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _appBar(context, tr('feat.share.title')),
      body: DecoratedBox(
        decoration: _pageBg,
        child: SafeArea(
          child: FutureBuilder<({String inviteCode, int invitedCount, double totalCommission})>(
            future: _future,
            builder: (ctx, snap) {
              final code = snap.data?.inviteCode ?? '';
              final invited = snap.data?.invitedCount ?? 0;
              final earned = snap.data?.totalCommission ?? 0.0;
              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  // ── invite code card ──
                  LightCard(
                    gradient: T.brandGradient,
                    child: Column(
                      children: [
                        Text(tr('feat.share.invite_code'),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70)),
                        const SizedBox(height: 6),
                        Text(code.isEmpty ? '——' : code,
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 4,
                                color: Colors.white)),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _ActionBtn(
                                label: tr('feat.share.copy_code'),
                                icon: Icons.copy_rounded,
                                onTap: () => _copy(code),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _ActionBtn(
                                label: tr('feat.share.copy_link'),
                                icon: Icons.link_rounded,
                                onTap: () => _copy(_link(code)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── rules: rate follows MY VIP tier (0.3% – 1.0%) ──
                  _sectionLabel(tr('feat.share.rules')),
                  LightCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('feat.share.rule_rate'),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: T.ink)),
                        const SizedBox(height: 4),
                        Text(tr('feat.share.rule_desc'),
                            style: const TextStyle(fontSize: 12, color: T.inkMd)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── stats ──
                  _sectionLabel(tr('feat.share.stats')),
                  LightCard(
                    child: Row(
                      children: [
                        Expanded(child: _StatItem(value: '$invited', label: tr('feat.share.stat_invited'))),
                        Expanded(child: _StatItem(value: earned.toStringAsFixed(2), label: tr('feat.share.stat_earnings'))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white24,
      borderRadius: BorderRadius.circular(T.rSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(T.rSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: T.ink)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: T.inkMd)),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 2. RebatePage — 返水中心
// ═════════════════════════════════════════════════════════════════════════════

class RebatePage extends StatelessWidget {
  const RebatePage({super.key});

  static const _vipTiers = <_VipTier>[
    _VipTier('feat.rebate.tier_normal', '0.3%', '0'),
    _VipTier('feat.rebate.tier_silver', '0.4%', '5,000'),
    _VipTier('feat.rebate.tier_gold', '0.5%', '20,000'),
    _VipTier('feat.rebate.tier_platinum', '0.6%', '80,000'),
    _VipTier('feat.rebate.tier_diamond', '0.8%', '200,000'),
    _VipTier('feat.rebate.tier_supreme', '1.0%', '500,000'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _appBar(context, tr('feat.rebate.title')),
      body: DecoratedBox(
        decoration: _pageBg,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // ── current rate ──
              LightCard(
                gradient: T.goldGradient,
                child: Column(
                  children: [
                    Text(tr('feat.rebate.current'),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xCC5A3A10))),
                    const SizedBox(height: 4),
                    const Text('0.5%',
                        style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF5A3A10))),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0x335A3A10),
                        borderRadius: BorderRadius.circular(T.rXs),
                      ),
                      child: Text(tr('feat.rebate.gold'),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF5A3A10))),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── pending rebate ──
              _sectionLabel(tr('feat.rebate.pending')),
              LightCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('0.00 USDT',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: T.ink)),
                          const SizedBox(height: 2),
                          Text(tr('feat.rebate.auto'),
                              style: const TextStyle(fontSize: 12, color: T.inkMd)),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: T.inkSubtle,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(T.rSm)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                      ),
                      child: Text(tr('feat.rebate.claim'),
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── tier table ──
              _sectionLabel(tr('feat.rebate.tier_table')),
              LightCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    // header
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: const BoxDecoration(
                        color: T.fill,
                        borderRadius: BorderRadius.vertical(
                            top: Radius.circular(T.rMd)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                              flex: 2,
                              child: Text(tr('feat.rebate.col_level'),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: T.inkLo))),
                          Expanded(
                              flex: 2,
                              child: Text(tr('feat.rebate.col_rate'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: T.inkLo))),
                          Expanded(
                              flex: 3,
                              child: Text(tr('feat.rebate.col_min'),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: T.inkLo))),
                        ],
                      ),
                    ),
                    // rows
                    for (var i = 0; i < _vipTiers.length; i++)
                      _RebateRow(
                          tier: _vipTiers[i],
                          highlighted: _vipTiers[i].name == 'feat.rebate.tier_gold',
                          last: i == _vipTiers.length - 1),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── history ──
              _sectionLabel(tr('feat.rebate.history')),
              LightCard(
                child: SizedBox(
                  height: 80,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.receipt_long_rounded,
                            size: 28, color: T.inkSubtle),
                        const SizedBox(height: 6),
                        Text(tr('feat.rebate.history_empty'),
                            style: const TextStyle(fontSize: 13, color: T.inkLo)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _VipTier {
  const _VipTier(this.name, this.rate, this.minBet);
  final String name;
  final String rate;
  final String minBet;
}

class _RebateRow extends StatelessWidget {
  const _RebateRow(
      {required this.tier, this.highlighted = false, this.last = false});
  final _VipTier tier;
  final bool highlighted;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: highlighted ? T.brand.withValues(alpha: 0.06) : null,
        border: last
            ? null
            : const Border(bottom: BorderSide(color: T.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Text(tr(tier.name),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            highlighted ? FontWeight.w700 : FontWeight.w500,
                        color: highlighted ? T.brandDeep : T.ink)),
                if (highlighted) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_left_rounded,
                      size: 16, color: T.brandDeep),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(tier.rate,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: highlighted ? T.brandDeep : T.ink)),
          ),
          Expanded(
            flex: 3,
            child: Text('≥ ${tier.minBet}',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: highlighted ? T.brandDeep : T.inkMd)),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 3. VipPage — VIP 等级
// ═════════════════════════════════════════════════════════════════════════════

class VipPage extends StatefulWidget {
  const VipPage({super.key, required this.state});
  final AppState state;

  @override
  State<VipPage> createState() => _VipPageState();
}

class _VipPageState extends State<VipPage> {
  // 等级图标按服务器返回的 idx 映射(顺序与 vipTiers 对齐)。
  static const _icons = <IconData>[
    Icons.person_outline_rounded,
    Icons.shield_outlined,
    Icons.star_rounded,
    Icons.diamond_outlined,
    Icons.diamond_rounded,
    Icons.workspace_premium_rounded,
  ];

  Future<VipStatus>? _future;
  final _money = NumberFormat('#,##0');

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() => _future = widget.state.api.getVip());
  }

  IconData _iconFor(int idx) =>
      idx >= 0 && idx < _icons.length ? _icons[idx] : Icons.person_outline_rounded;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _appBar(context, tr('feat.vip.title')),
      body: DecoratedBox(
        decoration: _pageBg,
        child: SafeArea(
          child: FutureBuilder<VipStatus>(
            future: _future,
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator(color: T.brandDeep));
              }
              if (snap.hasError || !snap.hasData) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${tr('common.error')}: ${snap.error ?? ''}',
                          style: const TextStyle(color: T.down)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _refresh, child: Text(tr('common.retry'))),
                    ],
                  ),
                );
              }
              return _content(snap.data!);
            },
          ),
        ),
      ),
    );
  }

  Widget _content(VipStatus vip) {
    final cur = vip.currentTier;
    final next = vip.nextTier;
    return RefreshIndicator(
      color: T.brandDeep,
      onRefresh: () async {
        _refresh();
        await _future;
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ── current level hero ──
          LightCard(
            gradient: T.goldGradient,
            child: Column(
              children: [
                Icon(_iconFor(vip.currentIdx), size: 40, color: const Color(0xFF5A3A10)),
                const SizedBox(height: 6),
                Text(tr('feat.vip.current_member').replaceAll('{name}', tr(cur.key)),
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF5A3A10))),
                const SizedBox(height: 4),
                Text(tr('feat.vip.rebate_rate').replaceAll('{rate}', cur.rate),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xCC5A3A10))),
              ],
            ),
          ),

          if (next != null) ...[
            const SizedBox(height: 16),
            _sectionLabel(tr('feat.vip.upgrade_progress')),
            LightCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(tr('feat.vip.next').replaceAll('{name}', tr(next.key)),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: T.inkMd)),
                      Text(tr('feat.vip.month_min').replaceAll('{n}', _money.format(next.minStake)),
                          style: const TextStyle(
                              fontSize: 12, color: T.inkLo)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: vip.progress,
                      minHeight: 8,
                      backgroundColor: T.fill,
                      valueColor: const AlwaysStoppedAnimation(T.brand),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(tr('feat.vip.bet_progress')
                          .replaceAll('{cur}', _money.format(vip.monthStake))
                          .replaceAll('{total}', _money.format(next.minStake)),
                      style: const TextStyle(fontSize: 12, color: T.inkLo)),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
            LightCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.workspace_premium_rounded, color: T.brandDeep, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(tr('feat.vip.maxed'),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600, color: T.ink)),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // ── tier list ──
          _sectionLabel(tr('feat.vip.list')),
          for (var i = 0; i < vip.tiers.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: LightCard(
                border: i == vip.currentIdx
                    ? Border.all(color: T.brand, width: 1.5)
                    : null,
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: i == vip.currentIdx
                            ? T.brand.withValues(alpha: 0.12)
                            : T.fill,
                        borderRadius: BorderRadius.circular(T.rSm),
                      ),
                      alignment: Alignment.center,
                      child: Icon(_iconFor(i),
                          size: 22,
                          color: i == vip.currentIdx ? T.brandDeep : T.inkLo),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(tr(vip.tiers[i].key),
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: i == vip.currentIdx
                                          ? T.brandDeep
                                          : T.ink)),
                              if (i == vip.currentIdx) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: T.brand.withValues(alpha: 0.12),
                                    borderRadius:
                                        BorderRadius.circular(4),
                                  ),
                                  child: Text(tr('feat.vip.current'),
                                      style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: T.brandDeep)),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                              tr('feat.vip.month_min').replaceAll('{n}', _money.format(vip.tiers[i].minStake)),
                              style: const TextStyle(
                                  fontSize: 12, color: T.inkLo)),
                        ],
                      ),
                    ),
                    Text(vip.tiers[i].rate,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: i == vip.currentIdx
                                ? T.brandDeep
                                : T.inkMd)),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          // ── benefits ──
          _sectionLabel(tr('feat.vip.benefits')),
          LightCard(
            child: Column(
              children: [
                _BenefitItem(
                    icon: Icons.percent_rounded,
                    text: tr('feat.vip.b1')),
                const SizedBox(height: 10),
                _BenefitItem(
                    icon: Icons.bolt_rounded,
                    text: tr('feat.vip.b2')),
                const SizedBox(height: 10),
                _BenefitItem(
                    icon: Icons.card_giftcard_rounded,
                    text: tr('feat.vip.b3')),
                const SizedBox(height: 10),
                _BenefitItem(
                    icon: Icons.support_agent_rounded,
                    text: tr('feat.vip.b4')),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _BenefitItem extends StatelessWidget {
  const _BenefitItem({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: T.brand.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: T.brandDeep),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w500, color: T.ink)),
        ),
        const Icon(Icons.check_circle_rounded,
            size: 18, color: T.up),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 4. CustomerServicePage — 在线客服
// ═════════════════════════════════════════════════════════════════════════════

void _openTelegramChat(BuildContext ctx, String username) {
  Telegram.openTelegramLink('https://t.me/$username');
  Toast.show(ctx, tr('feat.cs.opening'));
}

class CustomerServicePage extends StatelessWidget {
  const CustomerServicePage({super.key});

  static const _faqKeys = <List<String>>[
    ['feat.cs.q1', 'feat.cs.a1'],
    ['feat.cs.q2', 'feat.cs.a2'],
    ['feat.cs.q3', 'feat.cs.a3'],
    ['feat.cs.q4', 'feat.cs.a4'],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _appBar(context, tr('feat.cs.title')),
      body: DecoratedBox(
        decoration: _pageBg,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // ── contact card ──
              LightCard(
                gradient: T.brandGradient,
                child: Column(
                  children: [
                    const Icon(Icons.headset_mic_rounded,
                        size: 44, color: Colors.white),
                    const SizedBox(height: 8),
                    Text(tr('feat.cs.header_title'),
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(tr('feat.cs.header_sub'),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.white70)),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(T.rSm),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.telegram, size: 20, color: Colors.white),
                          SizedBox(width: 6),
                          Text('@go_home_007',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── working hours ──
              LightCard(
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: T.up.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(T.rSm),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.access_time_rounded,
                          size: 22, color: T.up),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('feat.cs.hours_title'),
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: T.ink)),
                          const SizedBox(height: 2),
                          Text(tr('feat.cs.hours_desc'),
                              style: const TextStyle(fontSize: 12, color: T.inkMd)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: T.up.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(T.rXs),
                      ),
                      child: Text(tr('feat.cs.online_badge'),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: T.up)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── FAQ ──
              _sectionLabel(tr('feat.cs.faq')),
              ..._faqKeys.map((kv) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _FaqCard(faq: _FaqItem(q: tr(kv[0]), a: tr(kv[1]))),
                  )),

              const SizedBox(height: 16),

              // ── open TG button ──
              SizedBox(
                width: double.infinity,
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: T.brandGradientShort,
                    borderRadius: BorderRadius.circular(T.rSm),
                    boxShadow: T.shadowGlowBrand,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _openTelegramChat(context, 'go_home_007'),
                      borderRadius: BorderRadius.circular(T.rSm),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.send_rounded,
                                size: 18, color: Colors.white),
                            const SizedBox(width: 8),
                            Text(tr('feat.cs.open_tg'),
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _FaqItem {
  const _FaqItem({required this.q, required this.a});
  final String q;
  final String a;
}

class _FaqCard extends StatefulWidget {
  const _FaqCard({required this.faq});
  final _FaqItem faq;

  @override
  State<_FaqCard> createState() => _FaqCardState();
}

class _FaqCardState extends State<_FaqCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return LightCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              borderRadius: BorderRadius.circular(T.rMd),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.help_outline_rounded,
                        size: 20, color: T.brand),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(widget.faq.q,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: T.ink)),
                    ),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.expand_more_rounded,
                          size: 22, color: T.inkLo),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(widget.faq.a,
                  style: const TextStyle(
                      fontSize: 13, height: 1.5, color: T.inkMd)),
            ),
            crossFadeState:
                _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 5. RulesPage — 竞猜规则
// ═════════════════════════════════════════════════════════════════════════════

class RulesPage extends StatelessWidget {
  const RulesPage({super.key});

  static const _sections = <_RuleSection>[
    _RuleSection(
      title: 'feat.rules.s1.title',
      icon: Icons.sports_soccer_rounded,
      items: ['feat.rules.s1.i1', 'feat.rules.s1.i2', 'feat.rules.s1.i3'],
    ),
    _RuleSection(
      title: 'feat.rules.s2.title',
      icon: Icons.account_balance_wallet_rounded,
      items: ['feat.rules.s2.i1', 'feat.rules.s2.i2', 'feat.rules.s2.i3'],
    ),
    _RuleSection(
      title: 'feat.rules.s3.title',
      icon: Icons.calculate_rounded,
      items: ['feat.rules.s3.i1', 'feat.rules.s3.i2', 'feat.rules.s3.i3'],
    ),
    _RuleSection(
      title: 'feat.rules.s4.title',
      icon: Icons.undo_rounded,
      items: ['feat.rules.s4.i1', 'feat.rules.s4.i2', 'feat.rules.s4.i3'],
    ),
    _RuleSection(
      title: 'feat.rules.s5.title',
      icon: Icons.warning_amber_rounded,
      items: [
        'feat.rules.s5.i1',
        'feat.rules.s5.i2',
        'feat.rules.s5.i3',
        'feat.rules.s5.i4',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _appBar(context, tr('feat.rules.title')),
      body: DecoratedBox(
        decoration: _pageBg,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // ── header banner ──
              LightCard(
                gradient: T.heroGradient,
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: T.brand.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(T.rSm),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.menu_book_rounded,
                          size: 26, color: T.brandDeep),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('feat.rules.header_title'),
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: T.ink)),
                          const SizedBox(height: 2),
                          Text(tr('feat.rules.header_sub'),
                              style: const TextStyle(fontSize: 12, color: T.inkMd)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── rule sections ──
              for (final section in _sections)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: LightCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: T.brand.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Icon(section.icon,
                                  size: 18, color: T.brandDeep),
                            ),
                            const SizedBox(width: 10),
                            Text(tr(section.title),
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: T.ink)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        for (final item in section.items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.only(top: 6),
                                  decoration: BoxDecoration(
                                    color: T.brand,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(tr(item),
                                      style: const TextStyle(
                                          fontSize: 13,
                                          height: 1.5,
                                          color: T.inkMd)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleSection {
  const _RuleSection(
      {required this.title, required this.icon, required this.items});
  final String title;
  final IconData icon;
  final List<String> items;
}
