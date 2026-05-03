class TeamScore {
  final int home;
  final int away;
  TeamScore({required this.home, required this.away});
  factory TeamScore.fromJson(Map<String, dynamic> j) =>
      TeamScore(home: (j['home'] ?? 0) as int, away: (j['away'] ?? 0) as int);
}

class MatchInfo {
  final int id;
  final String home;
  final String away;
  final DateTime date;
  final String status;
  final String leagueName;
  final String leagueSlug;
  final TeamScore? scores;

  MatchInfo({
    required this.id,
    required this.home,
    required this.away,
    required this.date,
    required this.status,
    required this.leagueName,
    required this.leagueSlug,
    this.scores,
  });

  factory MatchInfo.fromJson(Map<String, dynamic> j) {
    final league = (j['league'] ?? {}) as Map<String, dynamic>;
    return MatchInfo(
      id: (j['id'] as num).toInt(),
      home: j['home'] ?? '',
      away: j['away'] ?? '',
      date: DateTime.parse(j['date']).toLocal(),
      status: j['status'] ?? 'pending',
      leagueName: league['name'] ?? '',
      leagueSlug: league['slug'] ?? '',
      scores: j['scores'] == null
          ? null
          : TeamScore.fromJson(j['scores'] as Map<String, dynamic>),
    );
  }

  bool get isLive => status == 'live';
  bool get isPending => status == 'pending';
  bool get isSettled => status == 'settled';
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
class OverUnderLine {
  final double line;
  final double over;
  final double under;
  OverUnderLine({required this.line, required this.over, required this.under});
  factory OverUnderLine.fromJson(Map<String, dynamic> j) => OverUnderLine(
        line: (j['line'] ?? 2.5).toDouble(),
        over: (j['over'] ?? 0).toDouble(),
        under: (j['under'] ?? 0).toDouble(),
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

class OddsSnapshot {
  final int matchId;
  final String bookmaker;
  final DateTime updatedAt;
  final Outcome? moneyLine;
  final List<ScoreOption> correctScore;
  final OverUnderLine? overUnder;
  final BinaryMarket? btts;
  final Map<String, String> change;

  OddsSnapshot({
    required this.matchId,
    required this.bookmaker,
    required this.updatedAt,
    required this.moneyLine,
    required this.correctScore,
    required this.overUnder,
    required this.btts,
    required this.change,
  });

  factory OddsSnapshot.fromJson(Map<String, dynamic> j) {
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
      btts: j['btts'] == null
          ? null
          : BinaryMarket.fromJson(j['btts'] as Map<String, dynamic>),
      change: ((j['change'] ?? {}) as Map).cast<String, String>(),
    );
  }
}

/// 市场类型常量,与后端 models.MarketCorrectScore 等保持一致。
class MarketType {
  static const correctScore = 'correct_score';
  static const overUnder25 = 'over_under_2_5';
  static const btts = 'btts';
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
  final DateTime updatedAt;
  Wallet({
    required this.balance,
    required this.depositAddress,
    required this.ethDepositAddress,
    required this.btcDepositAddress,
    required this.lastWithdrawAddress,
    required this.updatedAt,
  });
  factory Wallet.fromJson(Map<String, dynamic> j) => Wallet(
        balance: (j['balance'] ?? 0).toDouble(),
        depositAddress: j['depositAddress'] ?? '',
        ethDepositAddress: j['ethDepositAddress'] ?? '',
        btcDepositAddress: j['btcDepositAddress'] ?? '',
        lastWithdrawAddress: j['lastWithdrawAddress'] ?? '',
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
  final int wins;
  final int total;
  final double payout;

  LeaderboardEntry({
    required this.userId,
    required this.username,
    required this.firstName,
    required this.wins,
    required this.total,
    required this.payout,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> j) => LeaderboardEntry(
        userId: (j['userId'] as num).toInt(),
        username: j['username'] ?? '',
        firstName: j['firstName'] ?? '',
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

/// Prediction enriched with home/away/league for the bet card.
class BetRow {
  final Prediction prediction;
  final String home;
  final String away;
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
  String get effectiveStatus {
    if (prediction.status == 'pending' && matchStatus == 'live') {
      return 'live';
    }
    return prediction.status;
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
  HomeConfig({required this.weeklyPool});
  factory HomeConfig.fromJson(Map<String, dynamic> j) =>
      HomeConfig(weeklyPool: (j['weeklyPool'] ?? 0).toDouble());
}
