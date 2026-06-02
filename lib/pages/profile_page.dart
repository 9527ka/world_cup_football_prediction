import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/match.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import '../services/auth_gate.dart';
import '../services/i18n.dart';
import '../services/toast.dart';
import '../theme/tokens.dart';
import '../widgets/language_picker.dart' show nativeLanguageNames;
import '../widgets/light_card.dart';
import '../widgets/login_wall.dart';
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
  static final _fmtBal = NumberFormat('#,##0.00');

  late Future<_ProfileBundle> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void _refreshStats() => setState(() => _future = _load());

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
    // 浏览器未登录:把页面替换为 Telegram 登录引导卡。
    // Mini App 内 initialize() 已自动登录,正常走 FutureBuilder 流程。
    if (!widget.state.isAuthenticated) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: 12),
          _profileHeader(null, null),
          LoginRequiredCard(
            state: widget.state,
            label: tr('nav.profile'),
            onLoggedIn: () => setState(() => _future = _load()),
          ),
        ],
      );
    }
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
              _menuGroupSettings(vip),
              // 邮箱账号才有密码可改;纯 TG 账号 user.email 为空,不显示。
              if ((user?['email'] as String?)?.isNotEmpty ?? false)
                _changePasswordButton(),
              // Mini App 内不显示退出按钮 —— Telegram 内退出后 Mini App
              // 关闭重开会自动重新授权,按钮反而让用户困惑;只在浏览器版显示。
              if (!isInMiniApp()) _logoutButton(),
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
    // 用户编码:6 位数字,后端 backfill + 注册时生成。前台展示这个而不是
     // 真实 user.id,既隐藏内部编号又方便客服报单。
    final userCode = (user?['userCode'] as String?) ?? '';

    // Telegram 头像 URL(用户头像直链, t.me/i/userpic/*),
    // 浏览器 widget 登录 + Mini App initData 登录都会带,
    // UpsertUser 每次覆盖到 DB,再回到前端。
    final photoUrl = (user?['photoUrl'] as String?) ?? '';

    Widget avatar() {
      final fallback = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: T.brandGradientShort,
        ),
        alignment: Alignment.center,
        child: Text(initial,
            style: const TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
      );
      return Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(
                color: Color(0x4D11BAD9),
                blurRadius: 10,
                offset: Offset(0, 4))
          ],
        ),
        child: ClipOval(
          child: photoUrl.isEmpty
              ? fallback
              : Image.network(
                  photoUrl,
                  fit: BoxFit.cover,
                  // 2x retina,避免按原图(可能 640px)解码占内存
                  cacheWidth: 112,
                  cacheHeight: 112,
                  errorBuilder: (_, __, ___) => fallback,
                ),
        ),
      );
    }

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
            avatar(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(username,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800, color: T.ink)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text('${tr('profile.tg_id')}  ${userCode.isEmpty ? '-' : userCode}',
                          style: const TextStyle(
                              fontSize: 11,
                              color: T.inkLo,
                              fontWeight: FontWeight.w600,
                              fontFamily: T.fontMono)),
                      if (userCode.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: userCode));
                            Toast.show(context, tr('common.copied'));
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(Icons.copy_rounded, size: 14, color: T.inkLo),
                          ),
                        ),
                      ],
                    ],
                  ),
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
              onPressed: () async {
                if (isInMiniApp()) {
                  await widget.state.tryTelegramLogin();
                } else {
                  final ok = await requireLogin(context, widget.state);
                  if (!ok) return;
                }
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
                Text(_fmtBal.format(s.balance),
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
                        _fmtBal.format(s.todayProfit),
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
                (s.monthProfit >= 0 ? '+' : '') + _fmtBal.format(s.monthProfit),
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
                    .replaceAll('{n}', _fmtBal.format(s.monthProfit)),
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

  Widget _menuGroupSettings(VipStatus? vip) {
    final vipLabel = vip != null
        ? '${tr(vip.currentTier.key)}${tr('profile.vip_member')}'
        : tr('profile.vip_badge_short');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: LightCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _settingItem(tr('profile.vip_level'), Icons.workspace_premium_outlined, vipLabel, _goVip),
            _settingItem(tr('profile.rules'), Icons.help_outline, null, _goRules),
            _settingItem(tr('profile.contact'), Icons.support_agent_outlined, tr('profile.online'), _goService),
            _settingItem(tr('profile.language'), Icons.language, _languageNote(), _showLanguagePicker),
            _settingItem(tr('profile.about'), Icons.info_outline, 'v1.0.1', _goAbout),
          ],
        ),
      ),
    );
  }

  /// 修改密码按钮(仅邮箱账号显示):弹对话框 → 旧/新/确认 三字段 → POST /api/me/password。
  /// 成功 toast + 关闭;失败按后端错码显示对应文案。token 不变(后端不要求重登)。
  Widget _changePasswordButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: OutlinedButton.icon(
          onPressed: _openChangePasswordDialog,
          style: OutlinedButton.styleFrom(
            foregroundColor: T.ink,
            side: const BorderSide(color: T.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.lock_outline_rounded, size: 18),
          label: Text(tr('profile.change_password'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Future<void> _openChangePasswordDialog() async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? hint;
    bool busy = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        Future<void> submit() async {
          final oldP = oldCtrl.text;
          final newP = newCtrl.text;
          final confirm = confirmCtrl.text;
          if (oldP.isEmpty) {
            setLocal(() => hint = tr('profile.cp.err_old_required'));
            return;
          }
          if (newP.length < 6 || newP.length > 72) {
            setLocal(() => hint = tr('profile.cp.err_new_length'));
            return;
          }
          if (newP != confirm) {
            setLocal(() => hint = tr('profile.cp.err_mismatch'));
            return;
          }
          setLocal(() {
            busy = true;
            hint = null;
          });
          try {
            await widget.state.api.changePassword(oldPassword: oldP, newPassword: newP);
            if (!ctx.mounted) return;
            Navigator.of(ctx).pop();
            if (mounted) Toast.show(context, tr('profile.cp.done'));
          } catch (e) {
            if (!ctx.mounted) return;
            // ApiException.message 是后端 raw 错码(json `error` 字段),
            // toString() 会被 _zhError 翻译,不能用来精确匹配。
            String h = tr('profile.cp.err_unknown');
            if (e is ApiException) {
              switch (e.message) {
                case 'invalid_credentials':
                  h = tr('profile.cp.err_wrong_old');
                case 'no_password_set':
                  h = tr('profile.cp.err_no_password');
                case 'invalid_password':
                  h = tr('profile.cp.err_new_length');
              }
            }
            setLocal(() {
              busy = false;
              hint = h;
            });
          }
        }

        Widget input(TextEditingController c, String label) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: c,
                obscureText: true,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: label,
                  hintStyle: const TextStyle(fontSize: 13, color: T.inkLo),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            );

        return AlertDialog(
          title: Text(tr('profile.change_password')),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                input(oldCtrl, tr('profile.cp.old_placeholder')),
                input(newCtrl, tr('profile.cp.new_placeholder')),
                input(confirmCtrl, tr('profile.cp.confirm_placeholder')),
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(hint!,
                        style: const TextStyle(fontSize: 12, color: T.down)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
              child: Text(tr('common.cancel')),
            ),
            TextButton(
              onPressed: busy ? null : submit,
              child: busy
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(tr('profile.cp.submit')),
            ),
          ],
        );
      }),
    );
    oldCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
  }

  /// 退出登录按钮:清 token + user,通知 AppState,profile 会自动重渲染为
  /// 登录引导卡(浏览器)或空白态(Mini App,用户得重开 bot 触发自动登录)。
  Widget _logoutButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: OutlinedButton.icon(
          onPressed: _confirmLogout,
          style: OutlinedButton.styleFrom(
            foregroundColor: T.down,
            side: BorderSide(color: T.down.withValues(alpha: 0.45)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: Text(tr('profile.logout'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('profile.logout_confirm_title')),
        content: Text(tr('profile.logout_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: T.down),
            child: Text(tr('profile.logout')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.state.api.logout();
    // 断开 WebSocket(token 已失效;新建无 token 连接)
    widget.state.stream.setToken(null);
    widget.state.notifyAuthChanged();
    if (!mounted) return;
    setState(() {
      _future = _load();
    });
    Toast.show(context, tr('profile.logout_done'));
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
      MaterialPageRoute(builder: (_) => RebatePage(state: widget.state))));
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
    if (!i18n.userOverride) return 'Auto';
    return nativeLanguageNames[i18n.locale] ?? i18n.locale;
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
                  final label = nativeLanguageNames[detected] ?? detected;
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
                              I18n.instance.resetToAuto();
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
                                'Auto · ${nativeLanguageNames[I18n.instance.detectedLocale] ?? I18n.instance.detectedLocale}',
                            code: null),
                        const Divider(height: 1, color: T.border),
                        for (final code in I18n.supported)
                          _langTile(ctx,
                              label: nativeLanguageNames[code] ?? code, code: code),
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
          I18n.instance.resetToAuto();
        } else {
          I18n.instance.setLocale(code);
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

  void _goDeposit() => AntiSpam.guard('nav_deposit', () {
    Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => DepositPage(state: widget.state))).then((popped) {
      if (popped == true) _refreshStats();
    });
  });
  void _goWithdraw() => AntiSpam.guard('nav_withdraw', () {
    Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => WithdrawPage(state: widget.state))).then((popped) {
      if (popped == true) _refreshStats();
    });
  });
  void _goLedger() => AntiSpam.guard('nav_ledger', () => Navigator.push(context,
      MaterialPageRoute(builder: (_) => LedgerPage(state: widget.state))));
  void _goBets() => AntiSpam.guard('nav_bets', () => Navigator.push(context,
      MaterialPageRoute(builder: (_) => PredictionsPage(state: widget.state))));
  void _goRank() => AntiSpam.guard('nav_rank', () => Navigator.push(context,
      MaterialPageRoute(builder: (_) => LeaderboardPage(state: widget.state))));
}
