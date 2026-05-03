import '../services/i18n.dart';

/// 队名本地化 — 仅 zh 提供翻译,其他语言保留原英文(足球语境英文通用)。
///
/// 数据范围:5 大欧洲联赛(英超/西甲/意甲/德甲/法甲)的现有 96 支球队 + 常见
/// 备用名。新球队进入 feed 时(转会/升降级)直接显示英文,补到这张表即可。
const Map<String, String> _zh = {
  // England - Premier League
  'AFC Bournemouth': '伯恩茅斯',
  'Arsenal FC': '阿森纳',
  'Aston Villa': '阿斯顿维拉',
  'Brentford FC': '布伦特福德',
  'Brighton & Hove Albion': '布莱顿',
  'Burnley FC': '伯恩利',
  'Chelsea FC': '切尔西',
  'Crystal Palace': '水晶宫',
  'Everton FC': '埃弗顿',
  'Fulham FC': '富勒姆',
  'Leeds United': '利兹联',
  'Liverpool FC': '利物浦',
  'Manchester City': '曼城',
  'Manchester United': '曼联',
  'Newcastle United': '纽卡斯尔',
  'Nottingham Forest': '诺丁汉森林',
  'Sunderland AFC': '桑德兰',
  'Tottenham Hotspur': '热刺',
  'West Ham United': '西汉姆联',
  'Wolverhampton Wanderers': '狼队',

  // Spain - LaLiga
  'Athletic Bilbao': '毕尔巴鄂竞技',
  'Atletico Madrid': '马德里竞技',
  'CA Osasuna': '奥萨苏纳',
  'Deportivo Alaves': '阿拉维斯',
  'Elche CF': '埃尔切',
  'Espanyol Barcelona': '西班牙人',
  'FC Barcelona': '巴塞罗那',
  'Getafe CF': '赫塔费',
  'Girona FC': '赫罗纳',
  'Levante UD': '莱万特',
  'RC Celta de Vigo': '塞尔塔',
  'RCD Mallorca': '马洛卡',
  'Rayo Vallecano': '巴列卡诺',
  'Real Betis Seville': '皇家贝蒂斯',
  'Real Madrid': '皇家马德里',
  'Real Oviedo': '皇家奥维耶多',
  'Real Sociedad San Sebastian': '皇家社会',
  'Sevilla FC': '塞维利亚',
  'Valencia CF': '瓦伦西亚',
  'Villarreal CF': '比利亚雷亚尔',

  // Italy - Serie A
  'AC Milan': 'AC 米兰',
  'ACF Fiorentina': '佛罗伦萨',
  'AS Roma': '罗马',
  'Atalanta BC': '亚特兰大',
  'Bologna FC': '博洛尼亚',
  'Cagliari Calcio': '卡利亚里',
  'Como 1907': '科莫',
  'Genoa CFC': '热那亚',
  'Hellas Verona': '维罗纳',
  'Inter Milano': '国际米兰',
  'Juventus Turin': '尤文图斯',
  'Lazio Rome': '拉齐奥',
  'Parma Calcio': '帕尔马',
  'Pisa SC': '比萨',
  'SSC Napoli': '那不勒斯',
  'Sassuolo Calcio': '萨索洛',
  'Torino FC': '都灵',
  'US Cremonese': '克雷莫纳',
  'US Lecce': '莱切',
  'Udinese Calcio': '乌迪内斯',

  // Germany - Bundesliga
  '1. FC Cologne': '科隆',
  '1. FC Heidenheim': '海登海姆',
  'Bayer Leverkusen': '勒沃库森',
  'Bayern Munich': '拜仁慕尼黑',
  'Borussia Dortmund': '多特蒙德',
  'Borussia Monchengladbach': '门兴格拉德巴赫',
  'Eintracht Frankfurt': '法兰克福',
  'FC Augsburg': '奥格斯堡',
  'FC St. Pauli': '圣保利',
  'FSV Mainz': '美因茨',
  'Hamburger SV': '汉堡',
  'RB Leipzig': '莱比锡红牛',
  'SC Freiburg': '弗赖堡',
  'TSG Hoffenheim': '霍芬海姆',
  'Union Berlin': '柏林联合',
  'VFL Wolfsburg': '沃尔夫斯堡',
  'VfB Stuttgart': '斯图加特',
  'Werder Bremen': '不来梅',

  // France - Ligue 1
  'AJ Auxerre': '欧塞尔',
  'AS Monaco': '摩纳哥',
  'Angers SCO': '昂热',
  'FC Lorient': '洛里昂',
  'FC Metz': '梅斯',
  'FC Nantes': '南特',
  'Le Havre AC': '勒阿弗尔',
  'Lille OSC': '里尔',
  'OGC Nice': '尼斯',
  'Olympique Lyon': '里昂',
  'Olympique Marseille': '马赛',
  'Paris FC': '巴黎 FC',
  'Paris Saint-Germain': '巴黎圣日耳曼',
  'Racing Club De Lens': '朗斯',
  'Stade Brest 29': '布雷斯特',
  'Stade Rennais FC': '雷恩',
  'Strasbourg Alsace': '斯特拉斯堡',
  'Toulouse FC': '图卢兹',
};

/// 联赛名翻译(zh)。原数据格式: "England - Premier League"。
const Map<String, String> _zhLeague = {
  'England - Premier League': '英超',
  'England - Championship': '英冠',
  'Spain - LaLiga': '西甲',
  'Spain - LaLiga 2': '西乙',
  'Italy - Serie A': '意甲',
  'Italy - Serie B': '意乙',
  'Germany - Bundesliga': '德甲',
  'Germany - 2. Bundesliga': '德乙',
  'France - Ligue 1': '法甲',
  'France - Ligue 2': '法乙',
  'Netherlands - Eredivisie': '荷甲',
  'Portugal - Liga Portugal': '葡超',
  'Turkiye - Super Lig': '土超',
  'Brazil - Brasileiro Serie A': '巴甲',
  'Scotland - Premiership': '苏超',
  'Belgium - Pro League': '比甲',
  'UEFA - Champions League': '欧冠',
};

/// Localize a team name. Falls back to the original English when no mapping
/// exists or the active locale isn't zh.
String localizedTeam(String original) {
  if (original.isEmpty) return original;
  if (I18n.instance.locale == 'zh') {
    return _zh[original] ?? original;
  }
  return original;
}

/// Localize a league name. Same fallback behavior as [localizedTeam].
String localizedLeague(String original) {
  if (original.isEmpty) return original;
  if (I18n.instance.locale == 'zh') {
    return _zhLeague[original] ?? original;
  }
  return original;
}
