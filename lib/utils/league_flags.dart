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
    final code = leagueSlugToCountryCode(slug);
    if (code == null) {
      return Container(
        height: height,
        width: width,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFE6ECF2),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: Icon(Icons.public, size: height - 2, color: const Color(0xFF8C9CB1)),
      );
    }
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
