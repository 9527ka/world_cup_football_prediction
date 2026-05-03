import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';

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

/// 圆角矩形的队伍徽章 / 国旗。
///
/// 优先级:
///   1. 有 api-sports ID 映射 → 加载 CDN 上的俱乐部 PNG 徽章
///   2. 网络失败或没映射 → 该队联赛对应国家国旗
///   3. 都没有 → 灰色 globe 占位
class TeamCrest extends StatelessWidget {
  const TeamCrest({
    super.key,
    required this.name,
    required this.leagueSlug,
    this.size = 36,
    this.borderRadius = 8,
  });

  final String name;
  final String leagueSlug;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final id = _apiSportsTeamID[name];
    final fallback = _flagFallback();
    if (id == null) return fallback;
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          color: Colors.white,
          padding: EdgeInsets.all(size * 0.08),
          child: Image.network(
            'https://media.api-sports.io/football/teams/$id.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => fallback,
            // While loading, render the flag silhouette so layout doesn't
            // jump and the user gets context immediately.
            loadingBuilder: (ctx, child, p) =>
                p == null ? child : fallback,
          ),
        ),
      ),
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
