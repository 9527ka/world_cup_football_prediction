#!/usr/bin/env python3
"""
One-off corrections for Over/Under translations across all 14 non-zh/non-en
locales. The 2026-05-15 bulk gtx fan-out mistranslated 'goals' as 'targets'
(target/aim/objective) and treated short '大/小' (over/under) as literal
big/small in many languages, producing terms no Asian/Russian/Arab gambler
would recognise. Also fixes a few outright bugs:
  - ar detail.ou_hint_under uses ≥ instead of ≤
  - vi detail.ou_hint_under missing the ≤ symbol entirely
  - tr pred.ou_over/under contain a stray trailing backslash
  - several locales fell back to literal English 'Over {line}' / 'Under {line}'

Edits the language map blocks surgically — finds each `_<lang>` map, then
replaces single lines by exact key match. Run once; re-running is a no-op.
"""
import re, sys
from pathlib import Path

DART = Path(__file__).resolve().parent.parent / 'lib' / 'services' / 'i18n.dart'

# {locale: {key: corrected_value}}
FIX = {
    'ja': {
        'detail.ou_goals': 'ゴール',
        'detail.ou_over': 'オーバー',
        'detail.ou_under': 'アンダー',
        'detail.ou_hint_over': '合計ゴール ≥ 3',
        'detail.ou_hint_under': '合計ゴール ≤ 2',
        'detail.ou_over_label': 'オーバー {line}',
        'detail.ou_under_label': 'アンダー {line}',
        'pred.ou_over': 'オーバー 2.5',
        'pred.ou_under': 'アンダー 2.5',
    },
    'ko': {
        'detail.ou_goals': '골',
        'detail.ou_over': '오버',
        'detail.ou_under': '언더',
        'detail.ou_hint_over': '총 골 ≥ 3',
        'detail.ou_hint_under': '총 골 ≤ 2',
        'detail.ou_over_label': '오버 {line}',
        'detail.ou_under_label': '언더 {line}',
        'pred.ou_over': '오버 2.5',
        'pred.ou_under': '언더 2.5',
    },
    'ru': {
        'detail.ou_goals': 'голов',
        'detail.ou_over': 'Больше',
        'detail.ou_under': 'Меньше',
        'detail.ou_over_label': 'Больше {line}',
        'detail.ou_under_label': 'Меньше {line}',
    },
    'es': {
        'detail.ou_goals': 'goles',
        'detail.ou_over': 'Más',
        'detail.ou_under': 'Menos',
        'detail.ou_hint_under': 'Total de goles ≤ 2',
        'detail.ou_under_label': 'Menos de {line}',
    },
    'ar': {
        'detail.ou_goals': 'أهداف',
        'detail.ou_over': 'فوق',
        'detail.ou_hint_under': 'مجموع الأهداف ≤ 2',
    },
    'fa': {
        'detail.ou_goals': 'گل',
        'detail.ou_over': 'بالا',
    },
    'hi': {
        'detail.ou_goals': 'गोल',
        'detail.ou_under': 'कम',
        'detail.ou_hint_over': 'कुल गोल ≥ 3',
        'detail.ou_hint_under': 'कुल गोल ≤ 2',
        'detail.ou_over_label': 'ऊपर {line}',
        'detail.ou_under_label': 'कम {line}',
        'pred.ou_under': '2.5 से कम',
    },
    'id': {
        'detail.ou_goals': 'gol',
        'detail.ou_under': 'Bawah',
        'detail.ou_under_label': 'Bawah {line}',
    },
    'pt': {
        'detail.ou_goals': 'gols',
        'detail.ou_over': 'Mais',
        'detail.ou_under': 'Menos',
        'detail.ou_hint_under': 'Total de gols ≤ 2',
        'detail.ou_under_label': 'Abaixo de {line}',
    },
    'tr': {
        'detail.ou_goals': 'gol',
        'detail.ou_over': 'Üst',
        'detail.ou_under': 'Alt',
        'detail.ou_over_label': 'Üst {line}',
        'detail.ou_under_label': 'Alt {line}',
        'pred.ou_over': 'Üst 2,5',
        'pred.ou_under': 'Alt 2,5',
    },
    'vi': {
        'detail.ou_goals': 'bàn thắng',
        'detail.ou_over': 'Trên',
        'detail.ou_hint_under': 'Tổng số bàn thắng ≤ 2',
    },
    'fr': {
        'detail.ou_goals': 'buts',
        'detail.ou_over': 'Plus',
        'detail.ou_under': 'Moins',
        'detail.ou_hint_over': 'Buts totaux ≥ 3',
        'detail.ou_hint_under': 'Buts totaux ≤ 2',
        'detail.ou_under_label': 'Moins de {line}',
    },
    'de': {
        'detail.ou_goals': 'Tore',
        'detail.ou_hint_over': 'Tore gesamt ≥ 3',
        'detail.ou_hint_under': 'Tore gesamt ≤ 2',
    },
    'it': {
        'detail.ou_goals': 'gol',
        'detail.ou_hint_over': 'Gol totali ≥ 3',
        'detail.ou_hint_under': 'Gol totali ≤ 2',
        'detail.ou_over_label': 'Sopra {line}',
    },
}

def main():
    text = DART.read_text()
    out = text
    changes = 0
    for lang, fixes in FIX.items():
        # locate the language map block
        marker = f'const Map<String, String> _{lang} = {{'
        i = out.find(marker)
        if i < 0:
            print(f'!! cannot find map _{lang}', file=sys.stderr); continue
        j = out.find('\n};', i)
        if j < 0:
            print(f'!! cannot find end of _{lang}', file=sys.stderr); continue
        block = out[i:j]
        for key, new_val in fixes.items():
            # match `'key': '...anything not closing the quote...',`
            pat = re.compile(
                rf"('{re.escape(key)}'\s*:\s*)'((?:[^'\\]|\\.)*)'",
                re.MULTILINE,
            )
            new_block, n = pat.subn(
                lambda m: f"{m.group(1)}'{new_val}'", block, count=1)
            if n == 0:
                print(f'!! {lang}: key not found: {key}', file=sys.stderr)
            else:
                changes += 1
                block = new_block
        out = out[:i] + block + out[j:]
    DART.write_text(out)
    print(f'fixed {changes} entries across {len(FIX)} locales')

if __name__ == '__main__':
    main()
