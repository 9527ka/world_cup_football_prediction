import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/match.dart';
import '../services/app_state.dart';
import '../services/auth_gate.dart';
import '../services/bet_slip.dart';
import '../services/i18n.dart';
import '../theme/tokens.dart';
import '../utils/team_names.dart';

/// 16-byte hex 幂等 key —— 同一逻辑投注意图跨重试复用。
String _genIdempKey() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// 底部弹出的投注单 — 单/串关切换、列出 selections、提交。
/// 调用方式: BetSlipSheet.show(context, state).
class BetSlipSheet {
  static void show(BuildContext context, AppState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BetSlipSheetBody(state: state),
    );
  }
}

final _fmtBal = NumberFormat('#,##0.00');
final _fmtInt = NumberFormat('#,##0');

class _BetSlipSheetBody extends StatefulWidget {
  const _BetSlipSheetBody({required this.state});
  final AppState state;
  @override
  State<_BetSlipSheetBody> createState() => _BetSlipSheetBodyState();
}

class _BetSlipSheetBodyState extends State<_BetSlipSheetBody> {
  bool _submitting = false;
  String? _error;
  String? _ok;
  bool _refreshing = false;
  bool _priceDrifted = false;

  /// 串关下单的幂等 key —— 同一次"投注意图"跨多次 retry 复用,成功后清空。
  /// 弱网用户点投注 → 等待 → 超时 → 再点 → 同 key 命中后端 cache,不会重复扣钱。
  String? _parlayIdempotencyKey;

  /// 当前钱包余额 — 提交前预检用。null 表示还没加载到。
  double? _balance;

  /// 全局最小投注额(对齐后端 placePrediction 的 fallback,但显式校验给 UX)。
  static const double _minStake = 10;

  @override
  void initState() {
    super.initState();
    // 打开 sheet 时一次性同步赔率 + 余额。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshOdds();
      _refreshBalance();
    });
  }

  Future<void> _refreshBalance() async {
    try {
      final w = await widget.state.api.getWallet();
      if (mounted) setState(() => _balance = w.balance);
    } catch (_) {/* 余额拿不到就降级 — 不阻塞下注流程 */}
  }

  /// 拉取每个 unique match 的最新赔率,把 BetSlip 内对应 selection 的 price
  /// 改成当前真实价。任何一项变化即设 _priceDrifted = true 给用户提示。
  Future<void> _refreshOdds() async {
    final slip = widget.state.betSlip;
    if (slip.isEmpty) return;
    setState(() {
      _refreshing = true;
      _priceDrifted = false;
    });
    final matchIds = slip.items.map((s) => s.matchId).toSet();
    bool anyChanged = false;
    final oddsFutures = <Future<MapEntry<int, OddsSnapshot?>>>[];
    for (final mid in matchIds) {
      oddsFutures.add(
        widget.state.api.getOdds(mid)
            .then<MapEntry<int, OddsSnapshot?>>((o) => MapEntry(mid, o))
            .catchError((_) => MapEntry<int, OddsSnapshot?>(mid, null)),
      );
    }
    final results = await Future.wait(oddsFutures);
    for (final entry in results) {
      final mid = entry.key;
      final odds = entry.value;
      if (odds == null) continue;
      try {
        for (final s in List.of(slip.items.where((x) => x.matchId == mid))) {
          double? newPrice;
          switch (s.marketType) {
            case MarketType.correctScore:
              for (final o in odds.correctScore) {
                if (o.score == s.score) { newPrice = o.price; break; }
              }
              break;
            case MarketType.overUnder25:
              // score 可能是 'over'/'under' (line=2.5) 或 'over@1.5'/'under@3.5'。
              // 多线时需要从 odds.overUnders 找 line 对应的那条;legacy 单线
              // 时退到 odds.overUnder(也就是 line=2.5)。
              final at = s.score.lastIndexOf('@');
              final side = at > 0 ? s.score.substring(0, at) : s.score;
              final line = at > 0 ? double.tryParse(s.score.substring(at + 1)) ?? 2.5 : 2.5;
              OverUnderLine? ouLine;
              for (final ou in odds.overUnders) {
                if ((ou.line - line).abs() < 0.01) { ouLine = ou; break; }
              }
              ouLine ??= (line == 2.5 ? odds.overUnder : null);
              if (ouLine != null) {
                if (side == 'over') newPrice = ouLine.over;
                if (side == 'under') newPrice = ouLine.under;
              }
              break;
            case MarketType.btts:
              if (odds.btts != null) {
                if (s.score == 'yes') newPrice = odds.btts!.yes;
                if (s.score == 'no') newPrice = odds.btts!.no;
              }
              break;
            case MarketType.matchWinner:
              if (odds.moneyLine != null) {
                if (s.score == 'home') newPrice = odds.moneyLine!.home;
                if (s.score == 'draw') newPrice = odds.moneyLine!.draw;
                if (s.score == 'away') newPrice = odds.moneyLine!.away;
              }
              break;
            case MarketType.htOverUnder:
              final atH = s.score.lastIndexOf('@');
              if (atH > 0) {
                final sideH = s.score.substring(0, atH);
                final lineH = double.tryParse(s.score.substring(atH + 1));
                if (lineH != null) {
                  for (final ou in odds.htOverUnders) {
                    if ((ou.line - lineH).abs() < 0.01) {
                      if (sideH == 'over') newPrice = ou.over;
                      if (sideH == 'under') newPrice = ou.under;
                      break;
                    }
                  }
                }
              }
              break;
            case MarketType.asianHandicap:
              // s.score "home@-0.5" / "away@+1.5" — 解析 side + line。
              final at = s.score.lastIndexOf('@');
              final side = at > 0 ? s.score.substring(0, at) : s.score;
              double? line;
              if (at > 0) line = double.tryParse(s.score.substring(at + 1));
              // 先在 walking handicaps 多线找,然后 fallback 到单线 handicap。
              if (line != null) {
                for (final h in odds.handicaps) {
                  if ((h.line - line).abs() < 0.01) {
                    if (side == 'home') newPrice = h.home;
                    if (side == 'away') newPrice = h.away;
                    break;
                  }
                }
              }
              if (newPrice == null && odds.handicap != null &&
                  (line == null || (odds.handicap!.line - line).abs() < 0.01)) {
                if (side == 'home') newPrice = odds.handicap!.home;
                if (side == 'away') newPrice = odds.handicap!.away;
              }
              break;
          }
          if (newPrice != null && slip.updatePrice(s.key, newPrice)) {
            anyChanged = true;
          }
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _refreshing = false;
        _priceDrifted = anyChanged;
      });
    }
  }

  Future<void> _submit() async {
    final slip = widget.state.betSlip;
    if (slip.isEmpty) return;
    // 浏览器未登录:先走 Telegram 授权;登录成功后才进真实提交。
    if (!widget.state.isAuthenticated) {
      final ok = await requireLogin(context, widget.state);
      if (!ok || !mounted) return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _ok = null;
    });
    try {
      if (slip.mode == BetSlipMode.single) {
        // 多个独立 single 串行提交。失败的留在 slip 里,成功的移除。
        int ok = 0;
        final failures = <String>[];
        for (final s in List.of(slip.items)) {
          final stake = slip.singleStakeFor(s);
          if (stake < 10) {
            failures.add('${s.label}(${tr('slip.amount_invalid')})');
            continue;
          }
          try {
            await widget.state.api.placePrediction(
              matchId: s.matchId,
              marketType: s.marketType,
              score: s.score,
              stake: stake,
            );
            ok++;
            slip.remove(s);
          } catch (e) {
            failures.add('${s.label}: ${e.toString()}');
          }
        }
        setState(() {
          if (failures.isEmpty) {
            _ok = tr('slip.ok_single').replaceAll('{n}', '$ok');
          } else if (ok == 0) {
            _error = failures.join(' · ');
          } else {
            _ok = tr('slip.ok_partial').replaceAll('{n}', '$ok');
            _error = '${tr('slip.fail_prefix')}: ${failures.join(' · ')}';
          }
        });
        if (failures.isEmpty && ok > 0) _autoClose();
      } else {
        if (slip.items.length < 2) {
          setState(() => _error = tr('slip.parlay_min'));
          return;
        }
        final legs = slip.items
            .map((s) => {
                  'matchId': s.matchId,
                  'marketType': s.marketType,
                  'score': s.score,
                })
            .toList();
        // 首次进入(或上次成功后)→ 生成新 key;失败重试时复用同一 key。
        _parlayIdempotencyKey ??= _genIdempKey();
        final p = await widget.state.api.submitParlay(
          stake: slip.parlayStake,
          legs: legs,
          idempotencyKey: _parlayIdempotencyKey,
        );
        _parlayIdempotencyKey = null; // 成功后丢弃,下次是新意图
        slip.clear();
        setState(() => _ok = tr('slip.ok_parlay')
            .replaceAll('{id}', '${p.id}')
            .replaceAll('{odds}', p.totalOdds.toStringAsFixed(2))
            .replaceAll('{stake}', p.stake.toStringAsFixed(0)));
        _autoClose();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
      // 提交后(无论部分成功/全成功/全失败)余额都可能变,刷新一次。
      _refreshBalance();
    }
  }

  /// 成功后 1.5s 自动关闭抽屉,让用户感受到流畅的成功反馈。
  void _autoClose() {
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final slip = widget.state.betSlip;
    return AnimatedBuilder(
      animation: slip,
      builder: (context, _) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollCtrl) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                _grabber(),
                _header(slip),
                _modeSwitch(slip),
                Expanded(child: _list(slip, scrollCtrl)),
                _summary(slip),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _grabber() => Container(
        width: 36, height: 4,
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFD9DEE5),
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _header(BetSlip slip) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.receipt_long, size: 18, color: T.brandDeep),
                const SizedBox(width: 8),
                Text('${tr('slip.title')} (${slip.count})',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: T.ink)),
                const SizedBox(width: 8),
                if (_refreshing)
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: T.brandDeep),
                  )
                else if (!slip.isEmpty)
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18, color: T.inkMd),
                    tooltip: tr('slip.refresh_tooltip'),
                    visualDensity: VisualDensity.compact,
                    onPressed: _refreshOdds,
                  ),
                const Spacer(),
                if (!slip.isEmpty)
                  TextButton(
                    onPressed: slip.clear,
                    child: Text(tr('slip.clear'),
                        style: TextStyle(color: T.inkLo)),
                  ),
                IconButton(
                  icon: const Icon(Icons.close, color: T.inkMd),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          if (_priceDrifted)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0x14F5B544),
                border: Border.all(color: const Color(0x40F5B544)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: Color(0xFFC7861E)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(tr('slip.price_drifted'),
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFC7861E))),
                  ),
                ],
              ),
            ),
        ],
      );

  Widget _modeSwitch(BetSlip slip) {
    Widget chip(String label, BetSlipMode m) {
      final on = slip.mode == m;
      return Expanded(
        child: InkWell(
          onTap: () => slip.setMode(m),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: on ? T.brandGradientShort : null,
              color: on ? null : const Color(0xFFF4F8FC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: on ? Colors.transparent : T.border),
            ),
            child: Text(label,
                style: TextStyle(
                    color: on ? Colors.white : T.inkMd,
                    fontWeight: FontWeight.w800,
                    fontSize: 13)),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [chip(tr('slip.single'), BetSlipMode.single), chip(tr('slip.parlay'), BetSlipMode.parlay)],
      ),
    );
  }

  Widget _list(BetSlip slip, ScrollController ctrl) {
    if (slip.isEmpty) {
      return ListView(
        controller: ctrl,
        children: [
          const SizedBox(height: 80),
          Center(
            child: Column(
              children: [
                const Icon(Icons.receipt_long, size: 36, color: T.inkSubtle),
                const SizedBox(height: 8),
                Text(tr('slip.empty_title'),
                    style: const TextStyle(color: T.inkLo, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(tr('slip.empty_hint'),
                    style: const TextStyle(color: T.inkSubtle, fontSize: 12)),
              ],
            ),
          ),
        ],
      );
    }
    final isParlay = slip.mode == BetSlipMode.parlay;
    return ListView.separated(
      controller: ctrl,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      itemCount: slip.items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _row(slip, slip.items[i], isParlay),
    );
  }

  Widget _row(BetSlip slip, BetSelection s, bool parlay) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: T.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${localizedTeam(s.home, apiZh: s.homeZh)} vs ${localizedTeam(s.away, apiZh: s.awayZh)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800, color: T.ink),
                    overflow: TextOverflow.ellipsis),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16, color: T.inkLo),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => slip.remove(s),
              ),
            ],
          ),
          Text(localizedLeague(s.leagueName),
              style: const TextStyle(
                  fontSize: 11, color: T.inkLo, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F8FE),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF9DE3F4)),
                ),
                child: Text(s.label,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: T.brandDeep)),
              ),
              const SizedBox(width: 8),
              Text('@ ${s.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: T.gold,
                      fontFamily: T.fontMono)),
              const Spacer(),
              if (!parlay)
                _StakeField(
                  initial: slip.singleStakeFor(s),
                  onChange: (v) => slip.setSingleStake(s, v),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summary(BetSlip slip) {
    final isParlay = slip.mode == BetSlipMode.parlay;
    double totalStake;
    double potentialPayout;
    String? hint;
    bool stakeValid = true;

    if (slip.isEmpty) {
      totalStake = 0;
      potentialPayout = 0;
    } else if (isParlay) {
      if (slip.items.length < 2) {
        hint = tr('slip.parlay_min');
        totalStake = slip.parlayStake;
        potentialPayout = 0;
      } else if (slip.parlayStake < _minStake) {
        hint = tr('slip.min_stake').replaceAll('{n}', _minStake.toStringAsFixed(0));
        totalStake = slip.parlayStake;
        potentialPayout = 0;
        stakeValid = false;
      } else {
        totalStake = slip.parlayStake;
        potentialPayout = slip.parlayStake * slip.parlayTotalOdds;
      }
    } else {
      totalStake = slip.items.fold<double>(0, (a, x) => a + slip.singleStakeFor(x));
      potentialPayout = slip.items.fold<double>(
          0, (a, x) => a + slip.singleStakeFor(x) * x.price);
      // 任一 single stake 低于最低额 → 阻塞提交
      final hasLowStake = slip.items.any((x) => slip.singleStakeFor(x) < _minStake);
      if (hasLowStake) {
        hint = tr('slip.each_min').replaceAll('{n}', _minStake.toStringAsFixed(0));
        stakeValid = false;
      }
    }

    // 余额预检 — 已知余额且不够 → 阻塞 + 中文提示。
    bool balanceOK = true;
    if (_balance != null && totalStake > _balance! && !slip.isEmpty) {
      balanceOK = false;
      hint = tr('slip.insufficient_detail').replaceAll('{n}', _fmtBal.format(_balance!));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: T.border)),
        boxShadow: [
          BoxShadow(color: Color(0x140E2238), blurRadius: 12, offset: Offset(0, -4))
        ],
      ),
      child: Column(
        children: [
          if (isParlay && slip.items.length >= 2) ...[
            Row(
              children: [
                Text(tr('slip.combo_odds'),
                    style: TextStyle(color: T.inkLo, fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(slip.parlayTotalOdds.toStringAsFixed(2),
                    style: const TextStyle(
                        color: T.gold,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        fontFamily: T.fontMono)),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (isParlay) ...[
            Row(
              children: [
                Text(tr('slip.stake'),
                    style: TextStyle(color: T.inkLo, fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                _StakeField(
                  initial: slip.parlayStake,
                  onChange: slip.setParlayStake,
                ),
              ],
            ),
            const SizedBox(height: 8),
          ] else if (!slip.isEmpty) ...[
            Row(
              children: [
                Text(tr('slip.total_stake'),
                    style: TextStyle(color: T.inkLo, fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${_fmtInt.format(totalStake)} USDT',
                    style: const TextStyle(
                        color: T.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        fontFamily: T.fontMono)),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Text(tr('slip.payout'),
                  style: TextStyle(color: T.inkLo, fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('+${_fmtBal.format(potentialPayout)} USDT',
                  style: const TextStyle(
                      color: T.up,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      fontFamily: T.fontMono)),
            ],
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(hint,
                  style: const TextStyle(color: T.gold, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error!, style: const TextStyle(color: T.down, fontSize: 12)),
            ),
          if (_ok != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_ok!, style: const TextStyle(color: T.upDark, fontSize: 12)),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _submitting ||
                          slip.isEmpty ||
                          (isParlay && slip.items.length < 2) ||
                          !stakeValid ||
                          !balanceOK
                  ? null
                  : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.lock_outline, size: 16),
              label: Text(
                _submitting
                    ? tr('slip.submitting')
                    : !balanceOK
                        ? tr('slip.insufficient')
                        : isParlay
                            ? tr('slip.submit_parlay')
                            : tr('slip.submit_single').replaceAll('{n}', '${slip.items.length}'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: T.brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 紧凑的金额输入 — 数字键盘,失焦后回写。
class _StakeField extends StatefulWidget {
  const _StakeField({required this.initial, required this.onChange});
  final double initial;
  final ValueChanged<double> onChange;
  @override
  State<_StakeField> createState() => _StakeFieldState();
}

class _StakeFieldState extends State<_StakeField> {
  late TextEditingController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial.toStringAsFixed(0));
  }
  @override
  void didUpdateWidget(covariant _StakeField old) {
    super.didUpdateWidget(old);
    if (widget.initial != old.initial &&
        double.tryParse(_ctrl.text) != widget.initial) {
      _ctrl.text = widget.initial.toStringAsFixed(0);
    }
  }
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      child: TextField(
        controller: _ctrl,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: false),
        style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w800, color: T.ink, fontFamily: T.fontMono),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          suffixText: 'USDT',
          suffixStyle: const TextStyle(fontSize: 10, color: T.inkLo),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onChanged: (v) {
          final d = double.tryParse(v.trim()) ?? 0;
          widget.onChange(d);
        },
      ),
    );
  }
}
