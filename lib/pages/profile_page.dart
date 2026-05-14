import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/match.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import '../services/i18n.dart';
import '../services/toast.dart';
import '../theme/tokens.dart';
import '../widgets/light_card.dart';
import 'deposit_page.dart';
import 'feature_pages.dart';
import 'ledger_page.dart';
import 'predictions_page.dart';
import 'leaderboard_page.dart';
import 'withdraw_page.dart';

/// 07 · 我的 — 用户头像 + USDT 钱包黑卡 + 战绩 + 菜单组。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.state});
  final AppState state;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfileBundle {
  final UserStats stats;
  final VipStatus? vip; // null when user not authenticated
  const _ProfileBundle(this.stats, this.vip);
}

class _ProfilePageState extends State<ProfilePage> {
  late Future<_ProfileBundle> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ProfileBundle> _load() async {
    if (!widget.state.isAuthenticated) {
      return _ProfileBundle(UserStats.empty(), null);
    }
    final stats = await widget.state.api.getStats();
    VipStatus? vip;
    try {
      vip = await widget.state.api.getVip();
    } catch (_) {
      // 401/降级时不阻塞,只是不显示 VIP 徽章
    }
    return _ProfileBundle(stats, vip);
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.state.user;
    return RefreshIndicator(
      color: T.brandDeep,
      onRefresh: () async {
        setState(() => _future = _load());
        await _future;
      },
      child: FutureBuilder<_ProfileBundle>(
        future: _future,
        builder: (_, snap) {
          final bundle = snap.data;
          final s = bundle?.stats ?? UserStats.empty();
          final vip = bundle?.vip;
          final authErr = snap.hasError &&
              snap.error is ApiException &&
              (snap.error as ApiException).statusCode == 401;
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              const SizedBox(height: 12),
              _profileHeader(user, vip),
              if (authErr) _authErrorBanner() else _walletCard(s),
              _statsRow(s),
              _menuGroupBets(s),
              _menuGroupSettings(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: TextButton(
                  onPressed: () async {
                    await widget.state.api.logout();
                    if (mounted) setState(() => _future = _load());
                  },
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    backgroundColor: Colors.white,
                    foregroundColor: T.down,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: T.border),
                    ),
                  ),
                  child: Text(tr('profile.logout'),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _profileHeader(Map<String, dynamic>? user, VipStatus? vip) {
    final username = user == null
        ? tr('profile.guest')
        : (user['firstName'] as String?)?.isNotEmpty == true
            ? user['firstName'] as String
            : (user['username'] as String?)?.isNotEmpty == true
                ? '@${user['username']}'
                : 'User#${user['id']}';
    final initial = username.isEmpty ? '?' : username.characters.first.toUpperCase();
    final tid = user == null ? '-' : '${user['telegramId']}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: LightCard(
        padding: const EdgeInsets.all(14),
        radius: 16,
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFF4F8FC)],
        ),
        child: Row(
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: T.brandGradientShort,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x4D11BAD9),
                      blurRadius: 10,
                      offset: Offset(0, 4))
                ],
              ),
              alignment: Alignment.center,
              child: Text(initial,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(username,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800, color: T.ink)),
                  const SizedBox(height: 2),
                  Text('${tr('profile.tg_id')}  $tid',
                      style: const TextStyle(
                          fontSize: 11,
                          color: T.inkLo,
                          fontWeight: FontWeight.w600,
                          fontFamily: T.fontMono)),
                  const SizedBox(height: 4),
                  // VIP 徽章 — 优先用 /api/me/vip 实时数据,未到货时回退到默认 (普通会员 0.3%)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0x1FD9AB7A),
                      border: Border.all(color: const Color(0x4DD9AB7A)),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      vip == null
                          ? tr('profile.vip_badge')
                          : '${tr(vip.currentTier.key)} · ${tr('profile.vip_rebate')} ${vip.currentTier.rate}',
                      style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFFA87644),
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (vip != null && vip.nextTier != null) ...[
                    const SizedBox(height: 4),
                    // 进度条 + 距离下一档剩多少
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: vip.progress,
                              minHeight: 4,
                              backgroundColor: const Color(0x14D9AB7A),
                              valueColor: const AlwaysStoppedAnimation(Color(0xFFD9AB7A)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          tr('profile.vip_to_next')
                              .replaceAll('{tier}', tr(vip.nextTier!.key))
                              .replaceAll('{n}', vip.needToNext.toStringAsFixed(0)),
                          style: const TextStyle(
                              fontSize: 9,
                              color: Color(0xFFA87644),
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: T.inkLo, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _authErrorBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFC7C2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: T.down, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr('profile.session_expired'),
                style: const TextStyle(
                    color: T.down, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() => _future = _load());
              },
              style: TextButton.styleFrom(
                minimumSize: const Size(56, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                backgroundColor: T.down,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(tr('profile.retry'),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _walletCard(UserStats s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF0E2238), Color(0xFF1B3358), Color(0xFF2A4870)],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(color: Color(0x330E2238), blurRadius: 24, offset: Offset(0, 8))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(tr('profile.balance'),
                    style: const TextStyle(
                        color: Color(0xFF9DE5F8),
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(tr('profile.usdt_wallet'),
                    style: const TextStyle(
                        color: Color(0xFF9DE5F8),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(NumberFormat('#,##0.00').format(s.balance),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        fontFamily: T.fontMono)),
                const SizedBox(width: 6),
                const Text('USDT',
                    style: TextStyle(
                        color: T.brand,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Text(tr('profile.today_pl'),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                  Text(
                    (s.todayProfit >= 0 ? '+' : '') +
                        NumberFormat('#,##0.00').format(s.todayProfit),
                    style: TextStyle(
                        color: s.todayProfit >= 0 ? const Color(0xFF5DD394) : T.down,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        fontFamily: T.fontMono),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                    child: _walletAction(
                        tr('profile.deposit'), Icons.add, primary: true, onTap: _goDeposit)),
                const SizedBox(width: 8),
                Expanded(
                    child: _walletAction(tr('profile.withdraw'), Icons.arrow_outward,
                        primary: false, onTap: _goWithdraw)),
                const SizedBox(width: 8),
                Expanded(
                    child: _walletAction(tr('profile.ledger'), Icons.menu,
                        primary: false, onTap: _goLedger)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _walletAction(String label, IconData icon,
      {required bool primary, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          gradient: primary ? T.brandGradientShort : null,
          color: primary ? null : const Color(0x1AFFFFFF),
          border: Border.all(
              color: primary ? Colors.transparent : const Color(0x29FFFFFF)),
          borderRadius: BorderRadius.circular(10),
          boxShadow: primary
              ? const [
                  BoxShadow(
                      color: Color(0x6611BAD9),
                      blurRadius: 12,
                      offset: Offset(0, 4))
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _statsRow(UserStats s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: LightCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _heroStat(tr('profile.month_pl'),
                (s.monthProfit >= 0 ? '+' : '') + NumberFormat('#,##0.00').format(s.monthProfit),
                s.monthProfit >= 0 ? T.upDark : T.down),
            _divider(),
            _heroStat(tr('profile.hit_rate'),
                '${(s.hitRate * 100).round()}%', T.ink),
            _divider(),
            _heroStat(tr('profile.won'), '${s.won}', T.gold),
          ],
        ),
      ),
    );
  }

  Widget _heroStat(String label, String value, Color color) => Expanded(
        child: Column(
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 9, color: T.inkLo, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontFamily: T.fontMono)),
          ],
        ),
      );

  Widget _divider() => Container(
        width: 1, height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: const Color(0x140E2238),
      );

  Widget _menuGroupBets(UserStats s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: LightCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _menuItem(tr('profile.my_bets'),
                tr('profile.pending_count').replaceAll('{n}', '${s.pending}'),
                Icons.bookmark_outline,
                T.brand, T.brandDeep, _goBets),
            _menuItem(tr('profile.leaderboard'),
                tr('profile.leaderboard_pl')
                    .replaceAll('{n}', NumberFormat('#,##0.00').format(s.monthProfit)),
                Icons.emoji_events_outlined,
                const Color(0xFFFFD66E), T.gold, _goRank),
            _menuItem(tr('profile.rebate_center'), tr('profile.rebate_pending'), Icons.percent,
                const Color(0xFFC7B5F4), const Color(0xFF8E7AD9),
                _goRebate,
                highlightNote: true),
            _menuItem(tr('profile.invite'), tr('profile.invite_sub'), Icons.favorite_border,
                const Color(0xFFF4A8B8), const Color(0xFFE07089),
                _goShareEarn),
          ],
        ),
      ),
    );
  }

  Widget _menuGroupSettings() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: LightCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _settingItem(tr('profile.vip_level'), Icons.workspace_premium_outlined, tr('profile.vip_gold'), _goVip),
            _settingItem(tr('profile.rules'), Icons.help_outline, null, _goRules),
            _settingItem(tr('profile.contact'), Icons.support_agent_outlined, tr('profile.online'), _goService),
            _settingItem(tr('profile.language'), Icons.language, _languageNote(), _showLanguagePicker),
            _settingItem(tr('profile.about'), Icons.info_outline, 'v0.2.0', _goAbout),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(String label, String note, IconData icon, Color c1, Color c2,
      VoidCallback onTap, {bool highlightNote = false}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [c1, c2]),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: T.ink)),
            ),
            Container(
              padding: highlightNote
                  ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
                  : EdgeInsets.zero,
              decoration: highlightNote
                  ? BoxDecoration(
                      color: const Color(0x24D9AB7A),
                      borderRadius: BorderRadius.circular(999),
                    )
                  : null,
              child: Text(note,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: highlightNote ? const Color(0xFFA87644) : T.inkLo)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: T.inkSubtle, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _settingItem(String label, IconData icon, [String? note, VoidCallback? onTap]) => InkWell(
        onTap: onTap ??
            () => _snack(tr('profile.feature_disabled').replaceAll('{name}', label)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: T.fill,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: T.brandDeep, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: T.ink)),
              ),
              if (note != null)
                Text(note,
                    style: const TextStyle(
                        fontSize: 10,
                        color: T.inkLo,
                        fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: T.inkSubtle, size: 16),
            ],
          ),
        ),
      );

  void _snack(String m) => Toast.show(context, m);

  void _goRebate() => AntiSpam.guard('nav_rebate', () => Navigator.push(context,
      MaterialPageRoute(builder: (_) => const RebatePage())));
  void _goShareEarn() => AntiSpam.guard('nav_share', () => Navigator.push(context,
      MaterialPageRoute(builder: (_) => ShareEarnPage(state: widget.state))));
  void _goVip() => AntiSpam.guard('nav_vip', () => Navigator.push(context,
      MaterialPageRoute(builder: (_) => VipPage(state: widget.state))));
  void _goRules() => AntiSpam.guard('nav_rules', () => Navigator.push(context,
      MaterialPageRoute(builder: (_) => const RulesPage())));
  void _goService() => AntiSpam.guard('nav_service', () => Navigator.push(context,
      MaterialPageRoute(builder: (_) => CustomerServicePage(state: widget.state))));
  void _goAbout() => _showAbout();

  void _showAbout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('profile.about_title'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: T.ink)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('profile.about_app'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: T.ink)),
            const SizedBox(height: 8),
            Text(tr('profile.about_desc'),
                style: const TextStyle(fontSize: 13, color: T.inkMd, height: 1.5)),
            const SizedBox(height: 12),
            Text(tr('profile.about_contact')
                    .replaceAll('{handle}', '@${widget.state.customerServiceTG}'),
                style: const TextStyle(fontSize: 12, color: T.inkLo)),
            Text(tr('profile.about_copyright'),
                style: const TextStyle(fontSize: 12, color: T.inkLo)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('common.confirm'), style: const TextStyle(color: T.brandDeep)),
          ),
        ],
      ),
    );
  }

  String _languageNote() {
    final i18n = I18n.instance;
    if (!i18n.userOverride) return tr('profile.language_auto');
    return tr('profile.language_${i18n.locale}');
  }

  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: T.inkSubtle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(tr('profile.language_picker_title'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800, color: T.ink)),
                const SizedBox(height: 6),
                Builder(builder: (_) {
                  final i18n = I18n.instance;
                  final detected = i18n.detectedLocale;
                  final raw = i18n.detectedRaw.isEmpty ? '—' : i18n.detectedRaw;
                  final label = tr('profile.language_$detected');
                  // Show a small banner when an explicit override blocks the
                  // current Telegram language. One-tap "switch to {tg}" so the
                  // user doesn't need to know what "auto" means.
                  if (i18n.userOverride && detected != i18n.locale) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                      decoration: BoxDecoration(
                        color: const Color(0x142CD7FD),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF9DE3F4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.translate, size: 14, color: T.brandDeep),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Telegram: $label ($raw)',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: T.brandDeep,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              await I18n.instance.resetToAuto();
                              if (mounted) Navigator.pop(ctx);
                              if (mounted) setState(() {});
                            },
                            style: TextButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(label,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: T.brandDeep,
                                    fontWeight: FontWeight.w800,
                                    decoration: TextDecoration.underline)),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                }),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _langTile(ctx,
                            label:
                                '${tr('profile.language_auto')} · ${tr('profile.language_${I18n.instance.detectedLocale}')}',
                            code: null),
                        const Divider(height: 1, color: T.border),
                        for (final code in I18n.supported)
                          _langTile(ctx,
                              label: tr('profile.language_$code'), code: code),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _langTile(BuildContext ctx, {required String label, required String? code}) {
    final i18n = I18n.instance;
    final selected = code == null ? !i18n.userOverride : (i18n.userOverride && i18n.locale == code);
    return InkWell(
      onTap: () async {
        if (code == null) {
          await I18n.instance.resetToAuto();
        } else {
          await I18n.instance.setLocale(code);
        }
        if (mounted) Navigator.pop(ctx);
        if (mounted) setState(() {});
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, color: T.ink, fontWeight: FontWeight.w600)),
            ),
            if (selected) const Icon(Icons.check, color: T.brandDeep, size: 18),
          ],
        ),
      ),
    );
  }

  void _goDeposit() => AntiSpam.guard('nav_deposit', () => Navigator.push(context,
      MaterialPageRoute(builder: (_) => DepositPage(state: widget.state))));
  void _goWithdraw() => AntiSpam.guard('nav_withdraw', () => Navigator.push(context,
      MaterialPageRoute(builder: (_) => WithdrawPage(state: widget.state))));
  void _goLedger() => AntiSpam.guard('nav_ledger', () => Navigator.push(context,
      MaterialPageRoute(builder: (_) => LedgerPage(state: widget.state))));
  void _goBets() => AntiSpam.guard('nav_bets', () => Navigator.push(context,
      MaterialPageRoute(builder: (_) => PredictionsPage(state: widget.state))));
  void _goRank() => AntiSpam.guard('nav_rank', () => Navigator.push(context,
      MaterialPageRoute(builder: (_) => LeaderboardPage(state: widget.state))));
}
