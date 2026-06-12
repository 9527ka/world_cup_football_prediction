import 'package:flutter/widgets.dart';

/// 桌面"主区内切换"导航契约。
///
/// 桌面布局不走全屏 Navigator.push,而是把次级页(充值/详情/明细等)压进
/// 主内容区的一个栈里,侧栏与投注单右栏始终保持可见。
class DesktopNav {
  const DesktopNav({
    required this.open,
    required this.back,
    required this.selectTab,
  });

  /// 在主内容区打开一个次级页(压栈)。[title] 用于次级页顶部返回条。
  final void Function(Widget page, {String? title}) open;

  /// 返回上一层(出栈)。
  final VoidCallback back;

  /// 切换顶层 tab(同时清空主区次级页栈)。
  /// 0=首页 1=赛事 2=排行榜 3=个人中心。
  final void Function(int tab) selectTab;
}

/// 顶层 tab 索引常量,侧栏与各页跳转统一引用。
class DesktopTab {
  DesktopTab._();
  static const home = 0;
  static const matches = 1;
  static const leaderboard = 2;
  static const profile = 3;
}
