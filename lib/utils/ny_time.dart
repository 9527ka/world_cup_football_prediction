/// 纽约(美东)时间助手。
///
/// 全站比赛时间 / 日期分组按"纽约时间"展示(运营所在时区),**不随用户设备时区变化**
/// (旧实现用 .toLocal(),中国用户看到的是 UTC+8 北京时间)。
///
/// ⚠️ [toNyWall] / [nyNow] 返回的是"把纽约挂钟值塞进 DateTime 字段"的对象 ——
/// 只能用于 DateFormat.format / 读 .year/.month/.day/.hour 显示与按天分组;
/// **绝不能**拿它去和真实 DateTime.now() 做 difference(它是位移过的瞬间)。
/// 直播分钟数等"时间差"计算仍用原始 m.date(真实瞬间)+ DateTime.now()。
library;

/// 美东夏令时规则:3 月第 2 个周日 02:00(EST)起 EDT(UTC-4),
/// 11 月第 1 个周日 02:00(EDT)止,其余时间 EST(UTC-5)。
int _easternOffsetHours(DateTime utc) {
  final y = utc.year;
  // 2nd Sunday of March 02:00 EST = 07:00 UTC
  final dstStart = _nthSunday(y, 3, 2).add(const Duration(hours: 7));
  // 1st Sunday of November 02:00 EDT = 06:00 UTC
  final dstEnd = _nthSunday(y, 11, 1).add(const Duration(hours: 6));
  final isDst = !utc.isBefore(dstStart) && utc.isBefore(dstEnd);
  return isDst ? -4 : -5;
}

/// 某年某月第 n 个周日(UTC 零点)。Dart weekday: 周一=1 … 周日=7。
DateTime _nthSunday(int year, int month, int n) {
  final first = DateTime.utc(year, month, 1);
  final firstSundayDay = 1 + ((7 - first.weekday) % 7);
  return DateTime.utc(year, month, firstSundayDay + (n - 1) * 7);
}

/// 把任意时刻转成"纽约挂钟" DateTime(仅用于显示 / 按天分组)。
DateTime toNyWall(DateTime t) {
  final u = t.toUtc();
  return u.add(Duration(hours: _easternOffsetHours(u)));
}

/// 当前纽约挂钟时间(替代 DateTime.now() 用于比赛列表"今天"分组 / 日期选择器)。
DateTime nyNow() => toNyWall(DateTime.now());
