import 'package:flutter/foundation.dart';

/// 投注单中的一个 selection — 含足够的信息让前端在不重新拉接口的情况下
/// 构造串关 leg(matchId/marketType/score),并把队名/联赛展示到 BetSlip。
class BetSelection {
  final int matchId;
  final String home;
  final String away;
  final String leagueName;
  final String leagueSlug;
  final String marketType;
  final String score;
  final double price; // 加入时的赔率(参考用,真实结算以服务端为准)
  final String label; // 给用户看的中文 label,如 "波胆 2:1"、"大 2.5"

  const BetSelection({
    required this.matchId,
    required this.home,
    required this.away,
    required this.leagueName,
    required this.leagueSlug,
    required this.marketType,
    required this.score,
    required this.price,
    required this.label,
  });

  /// 单个 selection 在 BetSlip 中的唯一 key — 同一个 (match, market, score) 不重复加。
  String get key => '$matchId::$marketType::$score';
}

enum BetSlipMode { single, parlay }

/// 全局购物车 — ChangeNotifier 让任何 widget 都能 listen。
/// AppState 持有一个实例,常用方式:
///   AnimatedBuilder(animation: state.betSlip, builder: ...)
class BetSlip extends ChangeNotifier {
  final List<BetSelection> _items = [];
  BetSlipMode _mode = BetSlipMode.single;

  /// 单关时每个 selection 的独立 stake;串关时所有 selection 共用一个 stake。
  /// 这里都 keyed by selection.key — single 模式下从 map 里取,parlay 模式下取 _parlayStake。
  final Map<String, double> _singleStakes = {};
  double _parlayStake = 100;

  List<BetSelection> get items => List.unmodifiable(_items);
  BetSlipMode get mode => _mode;
  double get parlayStake => _parlayStake;
  int get count => _items.length;
  bool get isEmpty => _items.isEmpty;

  /// 串关累乘赔率 — 至少 2 关才有意义。
  double get parlayTotalOdds {
    if (_items.length < 2) return 0;
    return _items.fold<double>(1, (acc, x) => acc * x.price);
  }

  bool contains(BetSelection s) => containsKey(s.key);
  bool containsKey(String key) => _items.any((x) => x.key == key);

  void add(BetSelection s) {
    if (contains(s)) return;
    _items.add(s);
    _singleStakes.putIfAbsent(s.key, () => 100);
    notifyListeners();
  }

  /// 用最新赔率覆盖某个 selection 的 price。返回 true 表示价格确实变了。
  /// 找不到对应 key 则什么都不做,返回 false。
  bool updatePrice(String key, double newPrice) {
    final i = _items.indexWhere((x) => x.key == key);
    if (i < 0) return false;
    final old = _items[i];
    if ((old.price - newPrice).abs() < 0.0001) return false;
    _items[i] = BetSelection(
      matchId: old.matchId,
      home: old.home,
      away: old.away,
      leagueName: old.leagueName,
      leagueSlug: old.leagueSlug,
      marketType: old.marketType,
      score: old.score,
      price: newPrice,
      label: old.label,
    );
    notifyListeners();
    return true;
  }

  void remove(BetSelection s) {
    _items.removeWhere((x) => x.key == s.key);
    _singleStakes.remove(s.key);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _singleStakes.clear();
    notifyListeners();
  }

  void setMode(BetSlipMode m) {
    if (_mode == m) return;
    _mode = m;
    notifyListeners();
  }

  double singleStakeFor(BetSelection s) =>
      _singleStakes[s.key] ?? 100;

  void setSingleStake(BetSelection s, double v) {
    _singleStakes[s.key] = v;
    notifyListeners();
  }

  void setParlayStake(double v) {
    _parlayStake = v;
    notifyListeners();
  }
}
