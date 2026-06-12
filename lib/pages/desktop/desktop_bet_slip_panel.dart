import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/match.dart';
import '../../services/app_state.dart';
import '../../services/auth_gate.dart';
import '../../services/bet_slip.dart';
import '../../services/i18n.dart';
import '../../theme/tokens.dart';
import '../../utils/team_names.dart';

/// 桌面右侧常驻投注单栏(340)。监听 [BetSlip],有注单时显示,空时由
/// [DesktopShell] 收起。
///
/// 单/串切换、内联金额输入、刷新赔率、汇总、提交 —— **逐字复用** BetSlipSheet
/// 的 `_refreshOdds` / `_submit` / 校验逻辑(同一 placePrediction / submitParlay
/// API),与手机端下注链路一致,绝不旁路。
class DesktopBetSlipPanel extends StatefulWidget {
  const DesktopBetSlipPanel({super.key, required this.state});
  final AppState state;

  @override
  State<DesktopBetSlipPanel> createState() => _DesktopBetSlipPanelState();
}

String _genIdempKey() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

final _fmtBal = NumberFormat('#,##0.00');
final _fmtInt = NumberFormat('#,##0');

class _DesktopBetSlipPanelState extends State<DesktopBetSlipPanel> {
  /// 单次下注金额限制 — 从后台「系统设置」读取(wallet 接口下发)。
  /// _betMin 默认 10;_betMax=0 表示不限上限。后端会再做权威校验。
  double _betMin = 10;
  double _betMax = 0;

  bool _submitting = false;
  String? _error;
  String? _ok;
  bool _refreshing = false;
  bool _priceDrifted = false;
  String? _parlayIdempotencyKey;
  double? _balance;

  BetSlip get _slip => widget.state.betSlip;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshOdds();
      _refreshBalance();
    });
  }

  Future<void> _refreshBalance() async {
    try {
      final w = await widget.state.api.getWallet();
      if (mounted) {
        setState(() {
          _balance = w.balance;
          _betMin = w.betStakeMin > 0 ? w.betStakeMin : 10;
          _betMax = w.betStakeMax; // 0 = 不限
        });
      }
    } catch (_) {}
  }

  Future<void> _refreshOdds() async {
    final slip = _slip;
    if (slip.isEmpty) return;
    setState(() {
      _refreshing = true;
      _priceDrifted = false;
    });
    final matchIds = slip.items.map((s) => s.matchId).toSet();
    bool anyChanged = false;
    final oddsFutures = <Future<MapEntry<int, OddsSnapshot?>>>[];
    for (final mid in matchIds) {
      oddsFutures.add(widget.state.api
          .getOdds(mid)
          .then<MapEntry<int, OddsSnapshot?>>((o) => MapEntry(mid, o))
          .catchError((_) => MapEntry<int, OddsSnapshot?>(mid, null)));
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
                if (o.score == s.score) {
                  newPrice = o.price;
                  break;
                }
              }
              break;
            case MarketType.overUnder25:
              final at = s.score.lastIndexOf('@');
              final side = at > 0 ? s.score.substring(0, at) : s.score;
              final line = at > 0
                  ? double.tryParse(s.score.substring(at + 1)) ?? 2.5
                  : 2.5;
              OverUnderLine? ouLine;
              for (final ou in odds.overUnders) {
                if ((ou.line - line).abs() < 0.01) {
                  ouLine = ou;
                  break;
                }
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
              final at = s.score.lastIndexOf('@');
              final side = at > 0 ? s.score.substring(0, at) : s.score;
              double? line;
              if (at > 0) line = double.tryParse(s.score.substring(at + 1));
              if (line != null) {
                for (final h in odds.handicaps) {
                  if ((h.line - line).abs() < 0.01) {
                    if (side == 'home') newPrice = h.home;
                    if (side == 'away') newPrice = h.away;
                    break;
                  }
                }
              }
              if (newPrice == null &&
                  odds.handicap != null &&
                  (line == null ||
                      (odds.handicap!.line - line).abs() < 0.01)) {
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
    final slip = _slip;
    if (slip.isEmpty) return;
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
        int ok = 0;
        final failures = <String>[];
        for (final s in List.of(slip.items)) {
          final stake = slip.singleStakeFor(s);
          if (stake < _betMin || (_betMax > 0 && stake > _betMax)) {
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
        _parlayIdempotencyKey ??= _genIdempKey();
        final p = await widget.state.api.submitParlay(
          stake: slip.parlayStake,
          legs: legs,
          idempotencyKey: _parlayIdempotencyKey,
        );
        _parlayIdempotencyKey = null;
        slip.clear();
        setState(() => _ok = tr('slip.ok_parlay')
            .replaceAll('{id}', '${p.id}')
            .replaceAll('{odds}', p.totalOdds.toStringAsFixed(2))
            .replaceAll('{stake}', p.stake.toStringAsFixed(0)));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
      _refreshBalance();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: T.surface,
        border: Border(left: BorderSide(color: T.border)),
      ),
      child: AnimatedBuilder(
        animation: _slip,
        builder: (context, _) {
          final slip = _slip;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(slip),
              const Divider(height: 1, color: T.border),
              _modeSwitch(slip),
              Expanded(
                child: slip.isEmpty
                    ? _empty()
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: slip.items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _row(slip, slip.items[i]),
                      ),
              ),
              if (!slip.isEmpty) _summary(slip),
            ],
          );
        },
      ),
    );
  }

  Widget _header(BetSlip slip) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Row(
        children: [
          const Icon(Icons.receipt_long, size: 18, color: T.brandDeep),
          const SizedBox(width: 8),
          Text('${tr('slip.title')} (${slip.count})',
              style: T.h2.copyWith(fontSize: 16)),
          const SizedBox(width: 6),
          if (_refreshing)
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: T.brandDeep))
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
                  style: const TextStyle(color: T.inkLo)),
            ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long, size: 40, color: T.inkSubtle),
            const SizedBox(height: 12),
            Text(tr('slip.empty_title'),
                textAlign: TextAlign.center, style: T.bodyMd),
            const SizedBox(height: 4),
            Text(tr('slip.empty_hint'),
                textAlign: TextAlign.center,
                style: T.cap.copyWith(color: T.inkLo)),
          ],
        ),
      ),
    );
  }

  Widget _modeSwitch(BetSlip slip) {
    Widget chip(String label, BetSlipMode m) {
      final on = slip.mode == m;
      return Expanded(
        child: InkWell(
          onTap: () => slip.setMode(m),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 9),
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(children: [
        chip(tr('slip.single'), BetSlipMode.single),
        chip(tr('slip.parlay'), BetSlipMode.parlay),
      ]),
    );
  }

  Widget _row(BetSlip slip, BetSelection s) {
    final parlay = slip.mode == BetSlipMode.parlay;
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
                child: Text(
                    '${localizedTeam(s.home, apiZh: s.homeZh)} vs ${localizedTeam(s.away, apiZh: s.awayZh)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800, color: T.ink),
                    maxLines: 1,
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11, color: T.inkLo, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6F8FE),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF9DE3F4)),
                  ),
                  child: Text(s.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: T.brandDeep)),
                ),
              ),
              const SizedBox(width: 8),
              Text('@ ${s.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: T.gold,
                      fontFamily: T.fontMono)),
            ],
          ),
          if (!parlay) ...[
            const SizedBox(height: 8),
            _StakeField(
              initial: slip.singleStakeFor(s),
              onChange: (v) => slip.setSingleStake(s, v),
            ),
          ],
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

    if (isParlay) {
      if (slip.items.length < 2) {
        hint = tr('slip.parlay_min');
        totalStake = slip.parlayStake;
        potentialPayout = 0;
      } else if (slip.parlayStake < _betMin) {
        hint = tr('slip.min_stake').replaceAll('{n}', _betMin.toStringAsFixed(0));
        totalStake = slip.parlayStake;
        potentialPayout = 0;
        stakeValid = false;
      } else if (_betMax > 0 && slip.parlayStake > _betMax) {
        hint = tr('slip.max_stake').replaceAll('{n}', _betMax.toStringAsFixed(0));
        totalStake = slip.parlayStake;
        potentialPayout = 0;
        stakeValid = false;
      } else {
        totalStake = slip.parlayStake;
        potentialPayout = slip.parlayStake * slip.parlayTotalOdds;
      }
    } else {
      totalStake =
          slip.items.fold<double>(0, (a, x) => a + slip.singleStakeFor(x));
      potentialPayout = slip.items
          .fold<double>(0, (a, x) => a + slip.singleStakeFor(x) * x.price);
      if (slip.items.any((x) => slip.singleStakeFor(x) < _betMin)) {
        hint = tr('slip.each_min').replaceAll('{n}', _betMin.toStringAsFixed(0));
        stakeValid = false;
      } else if (_betMax > 0 &&
          slip.items.any((x) => slip.singleStakeFor(x) > _betMax)) {
        hint = tr('slip.max_stake').replaceAll('{n}', _betMax.toStringAsFixed(0));
        stakeValid = false;
      }
    }

    bool balanceOK = true;
    if (_balance != null && totalStake > _balance! && !slip.isEmpty) {
      balanceOK = false;
      hint = tr('slip.insufficient_detail')
          .replaceAll('{n}', _fmtBal.format(_balance!));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: T.border)),
      ),
      child: Column(
        children: [
          if (_priceDrifted)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: Color(0xFFC7861E)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(tr('slip.price_drifted'),
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFFC7861E))),
                  ),
                ],
              ),
            ),
          if (isParlay && slip.items.length >= 2) ...[
            _sumRow(tr('slip.combo_odds'),
                slip.parlayTotalOdds.toStringAsFixed(2), T.gold),
            const SizedBox(height: 6),
          ],
          if (isParlay)
            Row(
              children: [
                Text(tr('slip.stake'),
                    style: const TextStyle(
                        color: T.inkLo, fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                _StakeField(
                    initial: slip.parlayStake, onChange: slip.setParlayStake),
              ],
            )
          else
            _sumRow(tr('slip.total_stake'),
                '${_fmtInt.format(totalStake)} USDT', T.ink),
          const SizedBox(height: 6),
          _sumRow(tr('slip.payout'),
              '+${_fmtBal.format(potentialPayout)} USDT', T.up),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(hint,
                  style: const TextStyle(
                      color: T.gold, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error!,
                  style: const TextStyle(color: T.down, fontSize: 12)),
            ),
          if (_ok != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_ok!,
                  style: const TextStyle(color: T.upDark, fontSize: 12)),
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
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.lock_outline, size: 16),
              label: Text(
                _submitting
                    ? tr('slip.submitting')
                    : !balanceOK
                        ? tr('slip.insufficient')
                        : isParlay
                            ? tr('slip.submit_parlay')
                            : tr('slip.submit_single')
                                .replaceAll('{n}', '${slip.items.length}'),
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: T.brand,
                foregroundColor: Colors.white,
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sumRow(String label, String value, Color valueColor) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                color: T.inkLo, fontSize: 12, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                color: valueColor,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                fontFamily: T.fontMono)),
      ],
    );
  }
}

/// 紧凑金额输入(复用自 BetSlipSheet)。
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
      width: 120,
      child: TextField(
        controller: _ctrl,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: false),
        style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: T.ink,
            fontFamily: T.fontMono),
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          suffixText: 'USDT',
          suffixStyle: const TextStyle(fontSize: 10, color: T.inkLo),
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onChanged: (v) => widget.onChange(double.tryParse(v.trim()) ?? 0),
      ),
    );
  }
}
