import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';

/// Map a league slug (e.g. `england-premier-league`) to an ISO country code
/// suitable for `CountryFlag.fromCountryCode`. Returns `null` if the league
/// has no clear country (e.g. continental tournaments — fall back to a globe).
///
/// Slugs come from the upstream odds-api.io and follow the pattern
/// `<country>-<competition>` for domestic leagues, or just the competition
/// name for cross-border tournaments.
String? leagueSlugToCountryCode(String slug) {
  if (slug.isEmpty) return null;
  final s = slug.toLowerCase();

  // Direct prefix match for domestic leagues.
  const prefixToCode = <String, String>{
    'england-':                 'GB-ENG',
    'scotland-':                'GB-SCT',
    'wales-':                   'GB-WLS',
    'spain-':                   'ES',
    'italy-':                   'IT',
    'germany-':                 'DE',
    'france-':                  'FR',
    'netherlands-':             'NL',
    'portugal-':                'PT',
    'belgium-':                 'BE',
    'turkey-':                  'TR',
    'turkiye-':                 'TR',
    'russia-':                  'RU',
    'ukraine-':                 'UA',
    'usa-':                     'US',
    'mexico-':                  'MX',
    'brazil-':                  'BR',
    'argentina-':               'AR',
    'japan-':                   'JP',
    'korea-':                   'KR',
    'republic-of-korea-':       'KR',
    'australia-':               'AU',
    'china-':                   'CN',
    'saudi-arabia-':            'SA',
    'saudi-':                   'SA',
    'uae-':                     'AE',
    'switzerland-':             'CH',
    'austria-':                 'AT',
    'denmark-':                 'DK',
    'sweden-':                  'SE',
    'norway-':                  'NO',
    'poland-':                  'PL',
    'greece-':                  'GR',
    'czechia-':                 'CZ',
    'czech-':                   'CZ',
    'romania-':                 'RO',
    'thailand-':                'TH',
    'vietnam-':                 'VN',
    'indonesia-':               'ID',
    'iran-':                    'IR',
    'egypt-':                   'EG',
    'hong-kong-china-':         'HK',
  };
  for (final entry in prefixToCode.entries) {
    if (s.startsWith(entry.key)) return entry.value;
  }

  // Continental / international tournaments — return null and the widget
  // will render a generic globe fallback instead of a country flag.
  return null;
}

/// 国际赛事 → api-sports 联赛 ID 映射,用于拉
/// `https://media.api-sports.io/football/leagues/{id}.png` 作为 logo。
/// 这些赛事没有"国家国旗"概念,但官方 CDN 上有冠名 logo。
const Map<String, int> _internationalLeagueLogoIDs = {
  'fifa-world-cup':                              1,
  'international-clubs-uefa-champions-league':   2,
  'international-clubs-uefa-europa-league':      3,
  'international-clubs-uefa-conference-league': 848,
  // 备用别名(后端有时省略 international-clubs- 前缀)
  'uefa-champions-league':   2,
  'uefa-europa-league':      3,
  'uefa-conference-league': 848,
};

String? leagueSlugToLogoUrl(String slug) {
  final id = _internationalLeagueLogoIDs[slug.toLowerCase()];
  if (id == null) return null;
  return 'https://media.api-sports.io/football/leagues/$id.png';
}

/// Small flag chip suitable for inline placement next to a league name.
/// Falls back to a globe icon when the league has no country mapping.
class LeagueFlag extends StatelessWidget {
  const LeagueFlag({
    super.key,
    required this.slug,
    this.height = 14,
    this.width = 20,
    this.borderRadius = 3,
  });

  final String slug;
  final double height;
  final double width;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final globeFallback = Container(
      height: height,
      width: width,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFE6ECF2),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(Icons.public, size: height - 2, color: const Color(0xFF8C9CB1)),
    );

    // 国际赛事(欧冠 / 世界杯 等)优先用 api-sports CDN 的官方 logo,
    // 没有"国家国旗"概念。
    final logoUrl = leagueSlugToLogoUrl(slug);
    if (logoUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: SizedBox(
          height: height,
          width: width,
          child: Image.network(
            logoUrl,
            fit: BoxFit.contain,
            cacheWidth: 64,
            cacheHeight: 64,
            errorBuilder: (_, __, ___) => globeFallback,
            loadingBuilder: (ctx, child, p) => p == null ? child : globeFallback,
          ),
        ),
      );
    }

    final code = leagueSlugToCountryCode(slug);
    if (code == null) return globeFallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CountryFlag.fromCountryCode(
        code,
        height: height,
        width: width,
      ),
    );
  }
}
