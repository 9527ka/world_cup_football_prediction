import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';

import '../services/team_overrides.dart';
import 'league_flags.dart';

/// 队伍徽章 / 国旗显示。优先用 api-sports.io CDN 上的真实俱乐部徽章
/// (`https://media.api-sports.io/football/teams/{id}.png`),没有映射的队伍
/// 退回到该队所属联赛的国旗。
///
/// api-sports 的 ID 是手工维护的(训练知识),CDN 有 CORS 允许浏览器直载,
/// 图片是稳定的 PNG 透明底,150×150。Cloudflare 在中间作为 CDN,国内可达。
const Map<String, int> _apiSportsTeamID = {
  // ─── England - Premier League ──────────────────────────────────────────
  'Manchester United':    33,
  'Newcastle United':     34,
  'AFC Bournemouth':      35,
  'Fulham FC':            36,
  'Wolverhampton Wanderers': 39,
  'Liverpool FC':         40,
  'Arsenal FC':           42,
  'Burnley FC':           44,
  'Everton FC':           45,
  'Tottenham Hotspur':    47,
  'West Ham United':      48,
  'Chelsea FC':           49,
  'Manchester City':      50,
  'Brighton & Hove Albion': 51,
  'Crystal Palace':       52,
  'Brentford FC':         55,
  'Leeds United':         63,
  'Nottingham Forest':    65,
  'Aston Villa':          66,
  'Sunderland AFC':       746,

  // ─── Spain - LaLiga ────────────────────────────────────────────────────
  'Atletico Madrid':           530,
  'CA Osasuna':                727,
  'RC Celta de Vigo':          538,
  'Real Sociedad San Sebastian': 548,
  'Sevilla FC':                536,
  'FC Barcelona':              529,
  'Valencia CF':               532,
  'Villarreal CF':             533,
  'Getafe CF':                 546,
  'Levante UD':                539,
  'Real Madrid':               541,
  'Espanyol Barcelona':        540,
  'Athletic Bilbao':           531,
  'Rayo Vallecano':            728,
  'Deportivo Alaves':          542,
  'RCD Mallorca':              798,
  'Real Betis Seville':        543,
  'Girona FC':                 547,
  'Real Oviedo':               7398,
  'Elche CF':                  797,

  // ─── Italy - Serie A ───────────────────────────────────────────────────
  'AS Roma':         497,
  'Atalanta BC':     499,
  'Juventus Turin':  496,
  'AC Milan':        489,
  'SSC Napoli':      492,
  'Inter Milano':    505,
  'Lazio Rome':      487,
  'Torino FC':       503,
  'ACF Fiorentina':  502,
  'Bologna FC':      500,
  'Genoa CFC':       495,
  'Cagliari Calcio': 490,
  'US Lecce':        867,
  'Hellas Verona':   504,
  // 'Pisa SC':      ?    // api-sports ID unknown, fall back to Italy flag
  'Parma Calcio':    523,
  'Como 1907':       895,
  'Sassuolo Calcio': 488,
  'Udinese Calcio':  494,
  'US Cremonese':    520,

  // ─── Germany - Bundesliga ──────────────────────────────────────────────
  'FC Augsburg':              170,
  '1. FC Cologne':            192,
  'Werder Bremen':            162,
  'SC Freiburg':              160,
  'Hamburger SV':             176,
  'TSG Hoffenheim':           167,
  'RB Leipzig':               173,
  'Bayer Leverkusen':         168,
  'FSV Mainz':                164,
  'Borussia Monchengladbach': 163,
  'Bayern Munich':            157,
  'FC St. Pauli':             186,
  'Borussia Dortmund':        165,
  'Eintracht Frankfurt':      169,
  'VfB Stuttgart':            172,
  'Union Berlin':             182,
  'VFL Wolfsburg':            161,
  '1. FC Heidenheim':         180,

  // ─── China - Chinese Super League (中超) ──────────────────────────────
  // 已 curl 验证返回非 90381 占位的 PNG。剩余 8 队没找到稳定的 api-sports ID,
  // 退到中国国旗 fallback。
  'Beijing Guoan':            832,   // 21538b
  'Shanghai Shenhua FC':      833,   // 9665b  ← 视觉对比验证
  'Shandong Taishan FC':      836,   // 23111b
  'Shanghai Port FC':         837,   // 33002b
  'Henan':                    2737,  // 3024b
  'Zhejiang FC':              4358,  // 25032b
  'Tianjin Jinmen Tiger':     4361,  // 23738b
  'Wuhan Three Towns FC':     5183,  // 16110b
  'Chengdu Rongcheng':        5188,  // 24357b
  // 中甲 China League 1
  'Changchun Yatai':          834,   // 8126b

  // ─── Japan - J.League (J1 + J2) ───────────────────────────────────────
  // 通过下载 PNG + 视觉对比逐个核实。原代码里 14 个 ID 全错了,以下是更正版。
  // J1
  'Kashiwa Reysol':            281,
  'Sanfrecce Hiroshima':       282,
  'Shimizu S-Pulse':           283,
  'Shonan Bellmare':           284,
  'Urawa Red Diamonds':        287,
  'Nagoya Grampus':            288,
  'Vissel Kobe':               289,
  'Kashima Antlers':           290,
  'Cerezo Osaka':              291,
  'FC Tokyo':                  292,
  'Gamba Osaka':               293,
  'Kawasaki Frontale':         294,
  'Yokohama F Marinos':        296,
  'Kyoto Sanga FC':            302,
  'Machida Zelvia':            303,
  'Tokyo Verdy':               306,
  'Yokohama FC':               307,
  'Fagiano Okayama':           310,
  'Avispa Fukuoka':            316,
  // J2 / 升降级常客
  'Jubilo Iwata':              280,
  'V-Varen Nagasaki':          285,
  'Vegalta Sendai':            286,
  'Sagan Tosu':                295,
  'FC Gifu':                   297,
  'Oita Trinita':              298,
  'Tokushima Vortis':          299,
  'Zweigen Kanazawa':          300,
  'Matsumoto Yamaga FC':       304,
  'Mito Hollyhock':            305,
  'Ventforet Kofu':            308,
  'Renofa Yamaguchi':          309,
  'Albirex Niigata':           311,
  'Montedio Yamagata':         312,
  'RB Omiya Ardija':           313,
  'Roasso Kumamoto':           314,
  'Tochigi SC':                315,
  'Kamatamare Sanuki':         317,
  'Ehime FC':                  318,

  // ─── Norway - Eliteserien (挪威超) ─────────────────────────────────────
  'SK Brann':                  319,
  'Kristiansund BK':           320,
  'Lillestroem SK':            321,
  'Tromsoe IL':                325,
  'Vaalerenga IF':             326,
  'Bodoe/Glimt':               327,
  'Molde FK':                  329,
  'Rosenborg BK':              331,
  'Sandefjord Fotball':        332,
  'Sarpsborg 08':              333,
  'IK Start':                  334,

  // ─── USA - MLS (美职) ──────────────────────────────────────────────────
  // 通过下载 PNG + 视觉对比核实。剩余 20 队没找到 ID,退到美国国旗 fallback。
  'San Jose Earthquakes':      1596,
  'Orlando City SC':            1598,
  'Houston Dynamo':            1600,
  'Toronto FC':                1601,
  'Vancouver Whitecaps FC':    1603,
  'Chicago Fire':              1607,
  'CF Montreal':               1614,
  'Inter Miami CF':            9568,
  'Nashville SC':              9569,
  'Austin FC':                 16489,

  // ─── France - Ligue 1 ──────────────────────────────────────────────────
  'AS Monaco':           91,
  'Olympique Marseille': 81,
  'Olympique Lyon':      80,
  'Stade Rennais FC':    94,
  'Paris Saint-Germain': 85,
  'Stade Brest 29':      106,
  'Lille OSC':           79,
  'OGC Nice':            84,
  'FC Nantes':           83,
  'Toulouse FC':         96,
  'AJ Auxerre':          108,
  'Strasbourg Alsace':   95,
  'Le Havre AC':         111,
  'FC Lorient':          97,
  'FC Metz':             112,
  'Angers SCO':          77,
  'Racing Club De Lens': 116,
  'Paris FC':            93,
};

/// 144 个本地打包的徽章 ID(由 scripts/download_team_logos 下载并验证非占位)。
/// 在这个集合里的优先用 assets/team_logos/{id}.png(零延迟,免 CDN 依赖,
/// 国内不被 Cloudflare 速率限制),其它仍走 CDN 兜底。
const _localLogoIDs = <int>{
  34, 35, 36, 39, 40, 42, 44, 47, 48, 49, 50, 51, 63, 66,
  77, 79, 80, 83, 84, 85, 91, 93, 94, 95, 96, 97, 106, 111, 116,
  160, 161, 162, 163, 164, 165, 167, 168, 169, 170, 172, 173, 176, 180, 182, 186, 192,
  280, 281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296,
  297, 298, 299, 300, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314,
  315, 316, 317, 318, 319, 320, 321, 325, 326, 327, 329, 331, 332, 333, 334,
  489, 490, 494, 495, 497, 499, 500, 503, 505, 523,
  529, 530, 531, 532, 533, 536, 538, 539, 540, 541, 542, 543, 546, 547, 548,
  727, 728, 746, 797, 798,
  832, 833, 834, 836, 837, 867,
  1598, 1600, 1601, 1603, 1607, 1614,
  2737, 4358, 4361, 5183, 5188, 7398, 16489,
};

/// 圆角矩形的队伍徽章 / 国旗。
///
/// 加载顺序:
///   1. 本地 assets/team_logos/{id}.png — 144 个验证过的(零网络)
///   2. api-sports.io CDN(给将来新加未打包的)
///   3. 联赛对应国家国旗
///   4. 灰色 globe 占位
class TeamCrest extends StatelessWidget {
  const TeamCrest({
    super.key,
    required this.name,
    required this.leagueSlug,
    this.id,
    this.size = 36,
    this.borderRadius = 8,
  });

  final String name;
  final String leagueSlug;
  /// Upstream team ID (apifootball / api-sports). When provided, used to
  /// build the CDN logo URL directly — no NAME→ID lookup needed.
  final int? id;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final fallback = _flagFallback();
    // Priority: admin override > upstream id (CDN) > legacy NAME-map > flag.
    final override = TeamOverrides.instance.logoUrl(name);
    if (override != null) {
      return SizedBox(
        width: size,
        height: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Container(
            color: Colors.white,
            padding: EdgeInsets.all(size * 0.08),
            child: Image.network(
              override,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => fallback,
              loadingBuilder: (ctx, child, p) => p == null ? child : fallback,
            ),
          ),
        ),
      );
    }
    // Resolve effective id: caller-provided wins; fall back to legacy map
    // for matches whose upstream payload pre-dates the homeId/awayId field.
    final effectiveId =
        (id != null && id! > 0) ? id : _apiSportsTeamID[name];
    if (effectiveId == null) return fallback;
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          color: Colors.white,
          padding: EdgeInsets.all(size * 0.08),
          child: _localLogoIDs.contains(effectiveId)
              ? Image.asset(
                  'assets/team_logos/$effectiveId.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => _cdnImage(effectiveId, fallback),
                )
              : _cdnImage(effectiveId, fallback),
        ),
      ),
    );
  }

  Widget _cdnImage(int id, Widget fallback) {
    return Image.network(
      'https://media.api-sports.io/football/teams/$id.png',
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => fallback,
      loadingBuilder: (ctx, child, p) => p == null ? child : fallback,
    );
  }

  Widget _flagFallback() {
    final code = leagueSlugToCountryCode(leagueSlug);
    if (code == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFE6ECF2),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.public,
            size: size * 0.55, color: const Color(0xFF8C9CB1)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: CountryFlag.fromCountryCode(
          code,
          height: size,
          width: size,
        ),
      ),
    );
  }
}
