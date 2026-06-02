import '../services/i18n.dart';

class PeriodScore {
  final int home;
  final int away;
  const PeriodScore({required this.home, required this.away});
  factory PeriodScore.fromJson(Map<String, dynamic> j) =>
      PeriodScore(home: (j['home'] ?? 0) as int, away: (j['away'] ?? 0) as int);
}

class TeamScore {
  final int home;
  final int away;
  /// Per-period scores (keys: "1H", "FT", "ET", "PEN") populated by
  /// API-Football. Null when the upstream didn't report any.
  final Map<String, PeriodScore>? periods;

  TeamScore({required this.home, required this.away, this.periods});

  factory TeamScore.fromJson(Map<String, dynamic> j) {
    Map<String, PeriodScore>? parsedPeriods;
    final raw = j['periods'];
    if (raw is Map) {
      parsedPeriods = {};
      raw.forEach((k, v) {
        if (v is Map) {
          parsedPeriods![k as String] =
              PeriodScore.fromJson(v.cast<String, dynamic>());
        }
      });
      if (parsedPeriods.isEmpty) parsedPeriods = null;
    }
    return TeamScore(
      home: (j['home'] ?? 0) as int,
      away: (j['away'] ?? 0) as int,
      periods: parsedPeriods,
    );
  }
}

/// Per-fixture event timeline entry from API-Football's /fixtures/events.
/// Used by match detail to show "进球时间 / 判罚时间" rows.
class MatchEvent {
  final int minute;
  final int extra;
  final int teamId;
  final String type; // "Goal" | "Card" | "subst" | "Var"
  final String detail; // "Yellow Card" | "Normal Goal" | "Red Card" | ...
  final String player;
  final String? playerZh;

  MatchEvent({
    required this.minute,
    this.extra = 0,
    this.teamId = 0,
    this.type = '',
    this.detail = '',
    this.player = '',
    this.playerZh,
  });

  factory MatchEvent.fromJson(Map<String, dynamic> j) => MatchEvent(
        minute: (j['minute'] ?? 0) as int,
        extra: (j['extra'] ?? 0) as int,
        teamId: (j['teamId'] ?? 0) is num
            ? ((j['teamId'] ?? 0) as num).toInt()
            : 0,
        type: j['type'] ?? '',
        detail: j['detail'] ?? '',
        player: j['player'] ?? '',
        playerZh: j['playerZh'] as String?,
      );

  bool get isGoal => type == 'Goal';
  bool get isYellowCard => type == 'Card' && detail == 'Yellow Card';
  bool get isRedCard =>
      type == 'Card' && (detail == 'Red Card' || detail == 'Second Yellow card');
  bool get isSub => type == 'subst';

  String get displayMinute =>
      extra > 0 ? '$minute+$extra\'' : '$minute\'';
}

class LiveDetail {
  final int minute;
  final int extra;
  final String periodLabel;
  // 后端写入此记录时的 wall-clock 时间。前端用它做"分钟自走":
  // 当前显示分钟 = minute + ((now - asOf) seconds / 60),封顶 +2min,
  // 避免在两次 WS 推送之间画面静止,也不会像旧"从 kickoff 自走"那样
  // 把 开球延误 / 长中场 / VAR / 入场仪式 错算成比赛分钟。
  final DateTime? asOf;
  final bool statsAvailable;
  final int homeCorners;
  final int awayCorners;
  final int homeYellow;
  final int awayYellow;
  final int homeRed;
  final int awayRed;
  final String streamUrl;

  LiveDetail({
    this.minute = 0,
    this.extra = 0,
    this.periodLabel = '',
    this.asOf,
    this.statsAvailable = false,
    this.homeCorners = 0,
    this.awayCorners = 0,
    this.homeYellow = 0,
    this.awayYellow = 0,
    this.homeRed = 0,
    this.awayRed = 0,
    this.streamUrl = '',
  });

  factory LiveDetail.fromJson(Map<String, dynamic> j) {
    DateTime? asOf;
    final raw = j['asOf'];
    if (raw is String && raw.isNotEmpty) {
      asOf = DateTime.tryParse(raw)?.toLocal();
    }
    return LiveDetail(
      minute: (j['minute'] ?? 0) as int,
      extra: (j['extra'] ?? 0) as int,
      periodLabel: j['periodLabel'] ?? '',
      asOf: asOf,
      statsAvailable: j['statsAvailable'] == true,
      homeCorners: (j['homeCorners'] ?? 0) as int,
      awayCorners: (j['awayCorners'] ?? 0) as int,
      homeYellow: (j['homeYellow'] ?? 0) as int,
      awayYellow: (j['awayYellow'] ?? 0) as int,
      homeRed: (j['homeRed'] ?? 0) as int,
      awayRed: (j['awayRed'] ?? 0) as int,
      streamUrl: j['streamUrl'] ?? '',
    );
  }

  String get minuteDisplay {
    if (periodLabel == 'HT') return tr('live.minute_ht');
    if (periodLabel == 'PEN') return tr('live.minute_pen');
    if (extra > 0) return '$minute+$extra\'';
    if (minute > 0) return '$minute\'';
    return '';
  }

  bool get hasStream => streamUrl.isNotEmpty;
  int get totalCorners => homeCorners + awayCorners;
}

class MatchInfo {
  final int id;
  final String home;
  final String away;
  // Upstream apifootball team IDs — these double as api-sports CDN keys
  // (https://media.api-sports.io/football/teams/{id}.png),so we don't have
  // to maintain a name→id map for logo lookup.
  final int homeId;
  final int awayId;
  final DateTime date;
  final String status;
  final String leagueName;
  final String leagueSlug;
  final TeamScore? scores;
  final double? mlHome;
  final double? mlDraw;
  final double? mlAway;
  final LiveDetail? live;
  final bool pinned;
  final String? homeZh;
  final String? awayZh;

  MatchInfo({
    required this.id,
    required this.home,
    required this.away,
    required this.date,
    required this.status,
    required this.leagueName,
    required this.leagueSlug,
    this.homeId = 0,
    this.awayId = 0,
    this.scores,
    this.mlHome,
    this.mlDraw,
    this.mlAway,
    this.live,
    this.pinned = false,
    this.homeZh,
    this.awayZh,
  });

  factory MatchInfo.fromJson(Map<String, dynamic> j) {
    final league = (j['league'] ?? {}) as Map<String, dynamic>;
    final ml = j['moneyLine'] as Map<String, dynamic>?;
    final liveJson = j['live'] as Map<String, dynamic>?;
    return MatchInfo(
      id: (j['id'] as num).toInt(),
      home: j['home'] ?? '',
      away: j['away'] ?? '',
      homeId: (j['homeId'] as num?)?.toInt() ?? 0,
      awayId: (j['awayId'] as num?)?.toInt() ?? 0,
      date: DateTime.parse(j['date']).toLocal(),
      status: j['status'] ?? 'pending',
      leagueName: league['name'] ?? '',
      leagueSlug: league['slug'] ?? '',
      scores: j['scores'] == null
          ? null
          : TeamScore.fromJson(j['scores'] as Map<String, dynamic>),
      mlHome: ml == null ? null : (ml['home'] as num?)?.toDouble(),
      mlDraw: ml == null ? null : (ml['draw'] as num?)?.toDouble(),
      mlAway: ml == null ? null : (ml['away'] as num?)?.toDouble(),
      live: liveJson == null ? null : LiveDetail.fromJson(liveJson),
      pinned: j['pinned'] == true,
      homeZh: j['homeZh'] as String?,
      awayZh: j['awayZh'] as String?,
    );
  }

  bool get isLive => status == 'live';
  bool get isPending => status == 'pending';
  bool get isSettled => status == 'settled';
}

class LeagueInfo {
  final String slug;
  final String name;
  final int matchCount;
  const LeagueInfo({required this.slug, required this.name, required this.matchCount});
}

class MatchPage {
  final List<MatchInfo> matches;
  final int total;
  final int offset;
  final int limit;
  MatchPage({required this.matches, required this.total, required this.offset, required this.limit});
  bool get hasMore => offset + matches.length < total;
}

class Outcome {
  final double home;
  final double draw;
  final double away;
  Outcome({required this.home, required this.draw, required this.away});
  factory Outcome.fromJson(Map<String, dynamic> j) => Outcome(
        home: (j['home'] ?? 0).toDouble(),
        draw: (j['draw'] ?? 0).toDouble(),
        away: (j['away'] ?? 0).toDouble(),
      );
}

class ScoreOption {
  final String score;
  final double price;
  ScoreOption({required this.score, required this.price});
  factory ScoreOption.fromJson(Map<String, dynamic> j) => ScoreOption(
        score: j['score'] ?? '',
        price: (j['price'] ?? 0).toDouble(),
      );
}

/// 大小球(进球数 over/under) — 单线市场,通常 line=2.5。
// OverUnderLine 加 isWalking 标记 — 后端走地动态生成的滚球线,前端 UI 加"走地"小徽章。
class OverUnderLine {
  final double line;
  final double over;
  final double under;
  final bool isWalking; // 走地动态生成的 line
  OverUnderLine({required this.line, required this.over, required this.under, this.isWalking = false});
  factory OverUnderLine.fromJson(Map<String, dynamic> j) => OverUnderLine(
        line: (j['line'] ?? 2.5).toDouble(),
        over: (j['over'] ?? 0).toDouble(),
        under: (j['under'] ?? 0).toDouble(),
        isWalking: j['isWalking'] == true,
      );
}

/// 双方进球(BTTS) — yes/no 二元市场。
class BinaryMarket {
  final double yes;
  final double no;
  BinaryMarket({required this.yes, required this.no});
  factory BinaryMarket.fromJson(Map<String, dynamic> j) => BinaryMarket(
        yes: (j['yes'] ?? 0).toDouble(),
        no: (j['no'] ?? 0).toDouble(),
      );
}

/// 让球盘(Asian Handicap) — 单线半数,主队让球数 line(负=主让,正=主受让)
// HandicapMarket 加 isWalking — 后端走地动态生成的滚球让球线。
class HandicapMarket {
  final double line;
  final double home;
  final double away;
  final bool isWalking;
  HandicapMarket({required this.line, required this.home, required this.away, this.isWalking = false});
  factory HandicapMarket.fromJson(Map<String, dynamic> j) => HandicapMarket(
        line: (j['line'] ?? 0).toDouble(),
        home: (j['home'] ?? 0).toDouble(),
        away: (j['away'] ?? 0).toDouble(),
        isWalking: j['isWalking'] == true,
      );
}

class OddsSnapshot {
  final int matchId;
  final String bookmaker;
  final DateTime updatedAt;
  final Outcome? moneyLine;
  final List<ScoreOption> correctScore;
  final OverUnderLine? overUnder; // legacy line=2.5,继续读以兼容老前端代码
  final List<OverUnderLine> overUnders; // 多线 O/U(1.5/2.5/3.5)
  final List<OverUnderLine> htOverUnders; // 上半场大小球(走地,minute<42)
  final BinaryMarket? btts;
  final HandicapMarket? handicap;
  final List<HandicapMarket> handicaps; // 走地 3 条 line(fair±0.5)
  final Map<String, String> change;
  final bool isLive;
  final DateTime? lockUntil;
  /// 85+ 分钟 / 加时 → 整盘终场封盘:赔率仍可见(冻结在 84 分钟价位),
  /// 但任何下注 / cashout handler 会拒。前端按钮保留可见,tap 弹"已封盘"。
  final bool marketsClosedFinal;

  OddsSnapshot({
    required this.matchId,
    required this.bookmaker,
    required this.updatedAt,
    required this.moneyLine,
    required this.correctScore,
    required this.overUnder,
    this.overUnders = const [],
    this.htOverUnders = const [],
    required this.btts,
    required this.handicap,
    this.handicaps = const [],
    required this.change,
    this.isLive = false,
    this.lockUntil,
    this.marketsClosedFinal = false,
  });

  bool get isLocked {
    final lu = lockUntil;
    return lu != null && lu.isAfter(DateTime.now());
  }

  factory OddsSnapshot.fromJson(Map<String, dynamic> j) {
    DateTime? lu;
    if (j['lockUntil'] != null && j['lockUntil'] is String) {
      final s = j['lockUntil'] as String;
      // Go zero-time RFC marshals as "0001-01-01T00:00:00Z" — treat as null.
      if (s.isNotEmpty && !s.startsWith('0001-')) {
        lu = DateTime.tryParse(s)?.toLocal();
      }
    }
    return OddsSnapshot(
      matchId: (j['matchId'] as num).toInt(),
      bookmaker: j['bookmaker'] ?? '',
      updatedAt: DateTime.parse(j['updatedAt']).toLocal(),
      moneyLine: j['moneyLine'] == null
          ? null
          : Outcome.fromJson(j['moneyLine'] as Map<String, dynamic>),
      correctScore: ((j['correctScore'] ?? []) as List)
          .cast<Map<String, dynamic>>()
          .map(ScoreOption.fromJson)
          .toList(),
      overUnder: j['overUnder'] == null
          ? null
          : OverUnderLine.fromJson(j['overUnder'] as Map<String, dynamic>),
      overUnders: ((j['overUnders'] ?? []) as List)
          .cast<Map<String, dynamic>>()
          .map(OverUnderLine.fromJson)
          .toList(),
      htOverUnders: ((j['htOverUnders'] ?? []) as List)
          .cast<Map<String, dynamic>>()
          .map(OverUnderLine.fromJson)
          .toList(),
      btts: j['btts'] == null
          ? null
          : BinaryMarket.fromJson(j['btts'] as Map<String, dynamic>),
      handicap: j['handicap'] == null
          ? null
          : HandicapMarket.fromJson(j['handicap'] as Map<String, dynamic>),
      handicaps: ((j['handicaps'] ?? []) as List)
          .cast<Map<String, dynamic>>()
          .map(HandicapMarket.fromJson)
          .toList(),
      change: ((j['change'] ?? {}) as Map).cast<String, String>(),
      isLive: j['isLive'] == true,
      lockUntil: lu,
      marketsClosedFinal: j['marketsClosedFinal'] == true,
    );
  }
}

/// 市场类型常量,与后端 models.MarketCorrectScore 等保持一致。
class MarketType {
  static const correctScore = 'correct_score';
  static const overUnder25 = 'over_under_2_5';
  static const btts = 'btts';
  static const matchWinner = 'match_winner';
  static const asianHandicap = 'asian_handicap';
  static const htOverUnder = 'ht_over_under';
}

/// 单条赔率历史采样点。
class OddsPoint {
  final DateTime takenAt;
  final double price;
  OddsPoint({required this.takenAt, required this.price});
  factory OddsPoint.fromJson(Map<String, dynamic> j) => OddsPoint(
        takenAt: DateTime.parse(j['t']).toLocal(),
        price: (j['p'] ?? 0).toDouble(),
      );
}

/// 1X2 (moneyLine) 时序 — 用于赔率走势 sparkline。
class OddsHistory {
  final int matchId;
  final List<OddsPoint> home;
  final List<OddsPoint> draw;
  final List<OddsPoint> away;
  OddsHistory({
    required this.matchId,
    required this.home,
    required this.draw,
    required this.away,
  });
  factory OddsHistory.fromJson(Map<String, dynamic> j) {
    List<OddsPoint> arr(dynamic v) =>
        ((v ?? const []) as List).cast<Map<String, dynamic>>().map(OddsPoint.fromJson).toList();
    return OddsHistory(
      matchId: (j['matchId'] as num).toInt(),
      home: arr(j['home']),
      draw: arr(j['draw']),
      away: arr(j['away']),
    );
  }
  bool get hasData => home.isNotEmpty || draw.isNotEmpty || away.isNotEmpty;
}

/// 串关单 — 1 个 ticket,N 个 leg,全中才赢。
class Parlay {
  final int id;
  final double stake;
  final double totalOdds;
  final String status;
  final double payout;
  final DateTime createdAt;
  final DateTime? settledAt;
  final List<ParlayLeg> legs;

  Parlay({
    required this.id,
    required this.stake,
    required this.totalOdds,
    required this.status,
    required this.payout,
    required this.createdAt,
    required this.legs,
    this.settledAt,
  });

  factory Parlay.fromJson(Map<String, dynamic> j) => Parlay(
        id: (j['id'] as num).toInt(),
        stake: (j['stake'] ?? 0).toDouble(),
        totalOdds: (j['totalOdds'] ?? 0).toDouble(),
        status: j['status'] ?? 'pending',
        payout: (j['payout'] ?? 0).toDouble(),
        createdAt: DateTime.parse(j['createdAt']).toLocal(),
        settledAt: j['settledAt'] == null
            ? null
            : DateTime.parse(j['settledAt']).toLocal(),
        legs: ((j['legs'] ?? []) as List)
            .cast<Map<String, dynamic>>()
            .map(ParlayLeg.fromJson)
            .toList(),
      );
}

class ParlayLeg {
  final int id;
  final int matchId;
  final String marketType;
  final String score;
  final double odds;
  final String legStatus;
  final String home;
  final String away;
  final String? homeZh;
  final String? awayZh;
  final String leagueName;
  final String leagueSlug;

  ParlayLeg({
    required this.id,
    required this.matchId,
    required this.marketType,
    required this.score,
    required this.odds,
    required this.legStatus,
    required this.home,
    required this.away,
    this.homeZh,
    this.awayZh,
    required this.leagueName,
    required this.leagueSlug,
  });

  factory ParlayLeg.fromJson(Map<String, dynamic> j) => ParlayLeg(
        id: (j['id'] as num).toInt(),
        matchId: (j['matchId'] as num).toInt(),
        marketType: j['marketType'] ?? MarketType.correctScore,
        score: j['score'] ?? '',
        odds: (j['odds'] ?? 0).toDouble(),
        legStatus: j['legStatus'] ?? 'pending',
        home: j['home'] ?? '',
        away: j['away'] ?? '',
        homeZh: j['homeZh'] as String?,
        awayZh: j['awayZh'] as String?,
        leagueName: j['leagueName'] ?? '',
        leagueSlug: j['leagueSlug'] ?? '',
      );
}

class Prediction {
  final int id;
  final int matchId;
  final String marketType;
  final String score;
  final double oddsAtPlace;
  final double stake;
  final String status;
  final double payout;
  final DateTime createdAt;
  final DateTime? settledAt;

  Prediction({
    required this.id,
    required this.matchId,
    required this.marketType,
    required this.score,
    required this.oddsAtPlace,
    required this.stake,
    required this.status,
    required this.payout,
    required this.createdAt,
    this.settledAt,
  });

  factory Prediction.fromJson(Map<String, dynamic> j) => Prediction(
        id: (j['id'] as num).toInt(),
        matchId: (j['matchId'] as num).toInt(),
        marketType: j['marketType'] ?? MarketType.correctScore,
        score: j['score'] ?? '',
        oddsAtPlace: (j['oddsAtPlace'] ?? 0).toDouble(),
        stake: (j['stake'] ?? 0).toDouble(),
        status: j['status'] ?? 'pending',
        payout: (j['payout'] ?? 0).toDouble(),
        createdAt: DateTime.parse(j['createdAt']).toLocal(),
        settledAt: j['settledAt'] == null
            ? null
            : DateTime.parse(j['settledAt']).toLocal(),
      );
}

class Wallet {
  final double balance;
  final String depositAddress;
  final String ethDepositAddress;
  final String btcDepositAddress;
  final String lastWithdrawAddress;
  final bool hasPendingWithdrawal;
  final double withdrawFeeTRC20;
  final double withdrawFeeERC20;
  final double withdrawFeeBEP20;
  final int withdrawETAMinutes;
  final double minDeposit;
  final double maxDeposit;
  final double minWithdraw;
  final double maxWithdraw;
  final DateTime updatedAt;
  Wallet({
    required this.balance,
    required this.depositAddress,
    required this.ethDepositAddress,
    required this.btcDepositAddress,
    required this.lastWithdrawAddress,
    required this.hasPendingWithdrawal,
    required this.withdrawFeeTRC20,
    required this.withdrawFeeERC20,
    required this.withdrawFeeBEP20,
    required this.withdrawETAMinutes,
    required this.minDeposit,
    required this.maxDeposit,
    required this.minWithdraw,
    required this.maxWithdraw,
    required this.updatedAt,
  });
  factory Wallet.fromJson(Map<String, dynamic> j) => Wallet(
        balance: (j['balance'] ?? 0).toDouble(),
        depositAddress: j['depositAddress'] ?? '',
        ethDepositAddress: j['ethDepositAddress'] ?? '',
        btcDepositAddress: j['btcDepositAddress'] ?? '',
        lastWithdrawAddress: j['lastWithdrawAddress'] ?? '',
        hasPendingWithdrawal: j['hasPendingWithdrawal'] == true,
        withdrawFeeTRC20: double.tryParse('${j['withdrawFeeTRC20'] ?? '1'}') ?? 1,
        withdrawFeeERC20: double.tryParse('${j['withdrawFeeERC20'] ?? '12'}') ?? 12,
        withdrawFeeBEP20: double.tryParse('${j['withdrawFeeBEP20'] ?? '0.5'}') ?? 0.5,
        withdrawETAMinutes: int.tryParse('${j['withdrawETAMinutes'] ?? '30'}') ?? 30,
        minDeposit: double.tryParse('${j['minDeposit'] ?? '10'}') ?? 10,
        maxDeposit: double.tryParse('${j['maxDeposit'] ?? '1000000'}') ?? 1000000,
        minWithdraw: double.tryParse('${j['minWithdraw'] ?? '10'}') ?? 10,
        maxWithdraw: double.tryParse('${j['maxWithdraw'] ?? '1000000'}') ?? 1000000,
        updatedAt: DateTime.parse(j['updatedAt']).toLocal(),
      );
}

class Deposit {
  final int id;
  final double amount;
  final String txHash;
  final String proofUrl;
  final String status;
  final String rejectReason;
  final DateTime createdAt;
  final String username;

  Deposit({
    required this.id,
    required this.amount,
    required this.txHash,
    required this.proofUrl,
    required this.status,
    required this.rejectReason,
    required this.createdAt,
    required this.username,
  });

  factory Deposit.fromJson(Map<String, dynamic> j) => Deposit(
        id: (j['id'] as num).toInt(),
        amount: (j['amount'] ?? 0).toDouble(),
        txHash: j['txHash'] ?? '',
        proofUrl: j['proofUrl'] ?? '',
        status: j['status'] ?? 'pending',
        rejectReason: j['rejectReason'] ?? '',
        createdAt: DateTime.parse(j['createdAt']).toLocal(),
        username: j['username'] ?? '',
      );
}

class Withdrawal {
  final int id;
  final double amount;
  final String address;
  final String status;
  final String rejectReason;
  final DateTime createdAt;
  final String username;

  Withdrawal({
    required this.id,
    required this.amount,
    required this.address,
    required this.status,
    required this.rejectReason,
    required this.createdAt,
    required this.username,
  });

  factory Withdrawal.fromJson(Map<String, dynamic> j) => Withdrawal(
        id: (j['id'] as num).toInt(),
        amount: (j['amount'] ?? 0).toDouble(),
        address: j['address'] ?? '',
        status: j['status'] ?? 'pending',
        rejectReason: j['rejectReason'] ?? '',
        createdAt: DateTime.parse(j['createdAt']).toLocal(),
        username: j['username'] ?? '',
      );
}

class LeaderboardEntry {
  final int userId;
  final String username;
  final String firstName;
  final String photoUrl;
  final int wins;
  final int total;
  final double payout;

  LeaderboardEntry({
    required this.userId,
    required this.username,
    required this.firstName,
    this.photoUrl = '',
    required this.wins,
    required this.total,
    required this.payout,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> j) => LeaderboardEntry(
        userId: (j['userId'] as num).toInt(),
        username: j['username'] ?? '',
        firstName: j['firstName'] ?? '',
        photoUrl: j['photoUrl'] ?? '',
        wins: (j['wins'] ?? 0) as int,
        total: (j['total'] ?? 0) as int,
        payout: (j['payout'] ?? 0).toDouble(),
      );

  String get displayName => firstName.isNotEmpty
      ? firstName
      : username.isNotEmpty
          ? '@$username'
          : 'User#$userId';
}

class VipTierInfo {
  final String key;        // i18n key e.g. 'feat.rebate.tier_gold'
  final String rate;       // '0.5%'
  final double minStake;   // 月最低下注本金
  const VipTierInfo({required this.key, required this.rate, required this.minStake});
  factory VipTierInfo.fromJson(Map<String, dynamic> j) => VipTierInfo(
        key: (j['key'] ?? '') as String,
        rate: (j['rate'] ?? '') as String,
        minStake: (j['minStake'] ?? 0).toDouble(),
      );
}

class VipStatus {
  final double monthStake;
  final VipTierInfo currentTier;
  final int currentIdx;
  final List<VipTierInfo> tiers;
  final VipTierInfo? nextTier;
  final double needToNext;
  final double progress; // 0..1

  const VipStatus({
    required this.monthStake,
    required this.currentTier,
    required this.currentIdx,
    required this.tiers,
    this.nextTier,
    required this.needToNext,
    required this.progress,
  });

  factory VipStatus.fromJson(Map<String, dynamic> j) {
    final tiersJson = (j['tiers'] as List?) ?? [];
    final nextJson = j['nextTier'] as Map<String, dynamic>?;
    return VipStatus(
      monthStake: (j['monthStake'] ?? 0).toDouble(),
      currentTier: VipTierInfo.fromJson(j['currentTier'] as Map<String, dynamic>),
      currentIdx: (j['currentIdx'] ?? 0) as int,
      tiers: tiersJson.cast<Map<String, dynamic>>().map(VipTierInfo.fromJson).toList(),
      nextTier: nextJson == null ? null : VipTierInfo.fromJson(nextJson),
      needToNext: (j['needToNext'] ?? 0).toDouble(),
      progress: (j['progress'] ?? 0).toDouble(),
    );
  }
}

/// Aggregate prediction stats for the "我的预测" hero card.
class UserStats {
  final double balance;
  final int totalBets;
  final int won;
  final int lost;
  final int pending;
  final double stakeTotal;
  final double payoutTotal;
  final double hitRate; // 0..1
  final double monthIncome;
  final double monthExpense;
  final double monthProfit;
  final double todayProfit;

  UserStats({
    required this.balance,
    required this.totalBets,
    required this.won,
    required this.lost,
    required this.pending,
    required this.stakeTotal,
    required this.payoutTotal,
    required this.hitRate,
    required this.monthIncome,
    required this.monthExpense,
    required this.monthProfit,
    required this.todayProfit,
  });

  factory UserStats.fromJson(Map<String, dynamic> j) => UserStats(
        balance: (j['balance'] ?? 0).toDouble(),
        totalBets: (j['totalBets'] ?? 0) as int,
        won: (j['won'] ?? 0) as int,
        lost: (j['lost'] ?? 0) as int,
        pending: (j['pending'] ?? 0) as int,
        stakeTotal: (j['stakeTotal'] ?? 0).toDouble(),
        payoutTotal: (j['payoutTotal'] ?? 0).toDouble(),
        hitRate: (j['hitRate'] ?? 0).toDouble(),
        monthIncome: (j['monthIncome'] ?? 0).toDouble(),
        monthExpense: (j['monthExpense'] ?? 0).toDouble(),
        monthProfit: (j['monthProfit'] ?? 0).toDouble(),
        todayProfit: (j['todayProfit'] ?? 0).toDouble(),
      );

  static UserStats empty() => UserStats(
        balance: 0,
        totalBets: 0,
        won: 0,
        lost: 0,
        pending: 0,
        stakeTotal: 0,
        payoutTotal: 0,
        hitRate: 0,
        monthIncome: 0,
        monthExpense: 0,
        monthProfit: 0,
        todayProfit: 0,
      );
}

class LedgerEntry {
  final String type; // deposit | withdraw | bet | win | loss | rebate
  final String title;
  final String desc;
  final double amount; // signed
  final String status;
  final DateTime when;
  final int refId;

  LedgerEntry({
    required this.type,
    required this.title,
    required this.desc,
    required this.amount,
    required this.status,
    required this.when,
    required this.refId,
  });

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        type: j['type'] ?? '',
        title: j['title'] ?? '',
        desc: j['desc'] ?? '',
        amount: (j['amount'] ?? 0).toDouble(),
        status: j['status'] ?? '',
        when: DateTime.parse(j['when']).toLocal(),
        refId: (j['refId'] ?? 0) as int,
      );
}

class LedgerResult {
  final List<LedgerEntry> items;
  final String nextCursor;
  LedgerResult({required this.items, required this.nextCursor});
  bool get hasMore => nextCursor.isNotEmpty;
}

/// Prediction enriched with home/away/league for the bet card.
class BetRow {
  final Prediction prediction;
  final String home;
  final String away;
  final String? homeZh;
  final String? awayZh;
  final int homeId;
  final int awayId;
  final String leagueName;
  final String leagueSlug;
  final DateTime? matchDate;
  final String matchStatus;
  final int? liveHome;
  final int? liveAway;

  BetRow({
    required this.prediction,
    required this.home,
    required this.away,
    this.homeZh,
    this.awayZh,
    this.homeId = 0,
    this.awayId = 0,
    required this.leagueName,
    required this.leagueSlug,
    this.matchDate,
    this.matchStatus = '',
    this.liveHome,
    this.liveAway,
  });

  factory BetRow.fromJson(Map<String, dynamic> j) => BetRow(
        prediction: Prediction.fromJson(j),
        home: j['home'] ?? '',
        away: j['away'] ?? '',
        homeZh: j['homeZh'] as String?,
        awayZh: j['awayZh'] as String?,
        homeId: (j['homeId'] as num?)?.toInt() ?? 0,
        awayId: (j['awayId'] as num?)?.toInt() ?? 0,
        leagueName: j['leagueName'] ?? '',
        leagueSlug: j['leagueSlug'] ?? '',
        matchDate: j['matchDate'] == null
            ? null
            : DateTime.parse(j['matchDate']).toLocal(),
        matchStatus: j['matchStatus'] ?? '',
        liveHome:
            j['liveHome'] == null ? null : (j['liveHome'] as num).toInt(),
        liveAway:
            j['liveAway'] == null ? null : (j['liveAway'] as num).toInt(),
      );

  /// Effective display status: the match status takes priority over the
  /// prediction's "pending" when the match is live.
  /// Pred status 与 match status 合并的"用户视角真实状态"。
  ///
  /// 边界处理(防止 cache 陈旧 / 注入演示导致的状态错位):
  /// 1. 若 prediction 已结算(won/lost/cashed_out/void)→ 直接用 prediction.status
  /// 2. 否则 prediction 是 pending:
  ///    - matchStatus == 'live' → live (主路径)
  ///    - 下注晚于 kickoff → 必然滚球期下的注单,即使 matchStatus 现在显示 pending
  ///      (例如 redis 注入被覆盖、fetcher 重启短时空窗)也应显示 live
  ///    - kickoff 已过(用客户端钟比较)→ 至少应显示进行中而不是误导"待开赛"
  String get effectiveStatus {
    if (prediction.status != 'pending') return prediction.status;
    if (matchStatus == 'live') return 'live';
    final md = matchDate;
    if (md != null) {
      if (prediction.createdAt.isAfter(md)) return 'live';
      if (md.isBefore(DateTime.now())) return 'live';
    }
    return 'pending';
  }
}

class HotMatch {
  final MatchInfo match;
  final int picks;
  final String bestScore;
  final double bestOdds;

  HotMatch({
    required this.match,
    required this.picks,
    required this.bestScore,
    required this.bestOdds,
  });

  factory HotMatch.fromJson(Map<String, dynamic> j) => HotMatch(
        match: MatchInfo.fromJson(j),
        picks: (j['picks'] ?? 0) as int,
        bestScore: j['bestScore'] ?? '',
        bestOdds: (j['bestOdds'] ?? 0).toDouble(),
      );
}

class MyRank {
  final int rank;
  final double profit;
  final String period;
  MyRank({required this.rank, required this.profit, required this.period});
  factory MyRank.fromJson(Map<String, dynamic> j) => MyRank(
        rank: (j['rank'] ?? 0) as int,
        profit: (j['profit'] ?? 0).toDouble(),
        period: j['period'] ?? '',
      );
}

/// Home / global UI config the operator can edit in /admin/settings.
class HomeConfig {
  final double weeklyPool;
  final String customerService; // Telegram username, without leading '@'
  HomeConfig({required this.weeklyPool, required this.customerService});
  factory HomeConfig.fromJson(Map<String, dynamic> j) => HomeConfig(
        weeklyPool: (j['weeklyPool'] ?? 0).toDouble(),
        customerService:
            (j['customerService'] as String?)?.trim().isNotEmpty == true
                ? (j['customerService'] as String).trim()
                : 'espn_football',
      );
}
