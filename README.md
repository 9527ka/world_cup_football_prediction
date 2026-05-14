# Cup — Flutter Web Front-End

Telegram Mini App 前端,基于 Flutter Web。承接足球赛事列表、赔率展示、下注 /
串关 / cashout、走势图、个人钱包、充值提现等所有玩家侧界面。

后端在另一个仓库(Go + Postgres + Redis),通过 HTTPS REST + WebSocket 通信。

---

## 技术栈

| 层 | 技术 |
|---|---|
| 框架 | Flutter 3.27+(Web target) |
| 语言 | Dart ≥ 3.3 |
| 网络 | `http` + `web_socket_channel` |
| 状态 | 内置 `ChangeNotifier` + `AppState` 单例(无 Provider/Riverpod) |
| 多语言 | 自建 `services/i18n.dart`(zh / en,1700+ key) |
| 国旗 / 图标 | `country_flags`、`flutter_svg` |
| 部署 | Dockerfile(nginx:alpine 起静态),build 时注入 `API_BASE` / `WS_BASE` |
| 宿主 | Telegram Mini App + 常规浏览器双兼容 |

---

## 目录结构

```
frontend/
├── lib/
│   ├── main.dart                 入口 + ScrollBehavior(允许鼠标拖)+ API base 解析
│   ├── models/
│   │   └── match.dart            Match / OddsSnapshot / MarketType 常量 / Prediction
│   ├── pages/
│   │   ├── main_shell.dart       底部 Tab 容器
│   │   ├── home_page.dart        首页(banner + 直播浮窗 + 推荐)
│   │   ├── match_list_page.dart  赛事列表(按联赛分组,懂球帝风格横向卡片)
│   │   ├── match_detail_page.dart 单场比赛页 + 全部市场 + 走势图
│   │   ├── bet_slip_sheet.dart   下注弹窗(单注 / 串关)
│   │   ├── predictions_page.dart 我的注单(pending / settled / cashout)
│   │   ├── profile_page.dart     个人资料 + 钱包 + 历史
│   │   ├── deposit_page.dart     充值(USDT / ETH / BTC 截图审核)
│   │   ├── withdraw_page.dart    提现申请
│   │   ├── ledger_page.dart      资金流水
│   │   ├── leaderboard_page.dart 排行榜
│   │   ├── recent_settled_page.dart 最近赛果
│   │   ├── league_picker_page.dart  联赛筛选
│   │   └── feature_pages.dart       Sprint 1-4 玩法说明 / VIP / 月度返水
│   ├── services/
│   │   ├── api_client.dart       所有 REST 调用,JWT 管理,统一错误
│   │   ├── app_state.dart        全局状态(user / wallet / 配置)
│   │   ├── bet_slip.dart         串关注单组装
│   │   ├── i18n.dart             翻译表 + 当前语言
│   │   ├── odds_stream.dart      WebSocket 增量赔率推送
│   │   ├── stream_feed.dart      直播流(7t666 浮窗)
│   │   ├── telegram.dart         Telegram WebApp SDK 桥(用户身份 / 主题)
│   │   ├── team_overrides.dart   球队中文名 / logo URL 缓存
│   │   ├── player_names.dart     球员名翻译
│   │   ├── file_picker_web.dart  Web 选图(充值截图)
│   │   └── toast.dart            轻量 toast(无依赖)
│   ├── widgets/
│   │   ├── bet_slip_fab.dart     串关浮窗按钮
│   │   ├── bottom_nav.dart       底部 Tab 栏
│   │   ├── chain_icon.dart       串关链条图标
│   │   ├── language_picker.dart  顶部语言切换
│   │   ├── light_card.dart       通用浅色卡片
│   │   ├── odds_chip.dart        赔率 chip(含状态:up / down / locked)
│   │   ├── sparkline_chart.dart  迷你走势图
│   │   ├── status_pill.dart      状态徽章(进行中 / 赢 / 输半 / 退本…)
│   │   └── team_badge.dart       球队 logo + 名称组合
│   ├── theme/tokens.dart         设计 tokens(色板 / 间距 / 字号)
│   └── utils/                    联赛国旗 / 球队 crest / 球队名 i18n
├── web/                          index.html(开屏 loading 动画)+ manifest
├── assets/                       球队 logo + icon
├── scripts/build-web.sh          本地 build + 缓存破坏(Cloudflare cache bust)
├── test/                         单测
├── Dockerfile                    多阶段 build(flutter → nginx)
├── nginx.conf                    no-cache 头 + SPA fallback
└── pubspec.yaml
```

---

## 支持的玩法

7 种市场,与后端 / admin 后台口径一致:

| `MarketType` | 中文 | 选项 score 字段约定 |
|---|---|---|
| `correct_score` | 波胆(全场比分) | `"H:A"` 例:`"2:1"`、`"Other"` 兜底 |
| `over_under_2_5` | 大小球(多线 1.5 / 2.5 / 3.5) | `"over@2.5"` / `"under@1.5"` |
| `btts` | 双方都进球 | `"yes"` / `"no"` |
| `match_winner` | 独赢 1X2 | `"home"` / `"draw"` / `"away"` |
| `asian_handicap` | 亚盘让球 | `"home@-0.5"` / `"away@+1.5"`(支持四分线如 `"home@-0.25"`) |
| `double_chance` | 双胜 | `"1X"` / `"X2"` / `"12"` |
| `draw_no_bet` | 平局退本 | `"home"` / `"away"` |

注单状态(`Prediction.status`):
`pending` · `won` · `lost` · `void` · `pushed`(整数线平局退本) ·
`half_won` / `half_lost`(亚盘四分线半赢半输) · `cashed_out`

---

## 本地运行

需要 Flutter SDK ≥ 3.27.0(主要为了 `Color.withValues` / `Color.r/g/b` API)。

```bash
cd frontend
flutter pub get
flutter run -d chrome \
  --dart-define=API_BASE=https://cup.douwen.me \
  --dart-define=WS_BASE=wss://cup.douwen.me/ws
```

留空 `API_BASE` 时,代码会回退到当前页面 origin(部署在同域时自然 work)。

### 跑测试

```bash
flutter test
```

### 本地构建 Web 产物

```bash
bash scripts/build-web.sh --dart-define=API_BASE=https://cup.douwen.me
```

产物在 `build/web/`,包含 `flutter_bootstrap.js` 时间戳后缀防 Cloudflare 缓存。

---

## Docker 构建

```bash
docker build -t cup-frontend \
  --build-arg API_BASE=https://cup.douwen.me \
  --build-arg WS_BASE=wss://cup.douwen.me/ws .
docker run -p 8080:80 cup-frontend
```

镜像基于 `nginx:1.27-alpine`,`nginx.conf` 已设置:
- entry-point 文件(`index.html` / `flutter_bootstrap.js` / `main.dart.js`)`no-cache`
- 其它资源 `immutable max-age=31536000`(配合 build-time 版本戳)
- SPA fallback:任何未匹配路径返回 `index.html`

---

## Telegram Mini App 适配要点

- `web/index.html` 引入 `telegram-web-app.js`,`services/telegram.dart` 桥接
  `Telegram.WebApp.initData` 拿 telegram_id 完成无密码登录
- `ScrollBehavior` 在 `main.dart` 全局放开 mouse / trackpad 拖动,默认 Material
  scroll 会禁掉 desktop / Mini App WebView 的鼠标拖,导致"滚不动"
- 主题颜色与 Telegram 暗色风格匹配(`background: #0a1929`),开屏 loading
  做了一个跳动足球的 CSS 动画占位

---

## 常见踩坑(实际遇到过的)

1. **`Container(alignment:)` 撑屏** — Container 同时设 `alignment` + 子组件
   `Expanded` 时会强制占满父 constraint,横向卡片会被拉伸成全屏。改用
   `Align` + `Padding` 而不是 Container 的 alignment 属性。
2. **`Chip(...).withLimit` 限宽** — 用 `ConstrainedBox(maxWidth: ...)` 包,
   不要给 Chip 直接设 `width`(Chip 会忽略)。
3. **`league.name` 双格式** — 后端有时返回 `"Spain - LaLiga"`,有时
   `"LaLiga"`。在 `utils/league_flags.dart` 里两种都映射。
4. **`Color.withOpacity` 过时** — Flutter 3.27 改成 `Color.withValues(alpha: x)`。
   `flutter analyze` 会告警 deprecated,新写法用 `withValues`。
5. **球队 logo 跨域** — 上游 API-Football logo 用 CDN URL,Flutter Web 在
   Telegram WebView 内偶尔会被 CORS 拦。本地缓存到 `assets/team_logos/` 加
   一层 fallback 兜底。

---

## 与后端的契约

| 路径 | 用途 |
|---|---|
| `GET /api/matches` | 赛事列表(支持 `status=pending\|live\|all`) |
| `GET /api/matches/:id` | 单场详情 |
| `GET /api/odds/:matchID` | 实时赔率快照(7 市场全) |
| `GET /api/odds/:matchID/history` | 走势图历史点 |
| `POST /api/predictions` | 下单注 |
| `POST /api/parlays` | 下串关 |
| `POST /api/predictions/:id/cashout` | 提前结算 |
| `POST /api/parlays/:id/cashout` | 串关提前结算 |
| `WS  /ws` | 增量赔率 + 比分推送 |

完整接口在后端 `internal/api/handlers.go`。前端调用集中在
`lib/services/api_client.dart`,任何字段变化必须同步两端。

---

## 部署

前端会随 backend 一起,通过 `docker-compose` 在生产服一键起栈。详情见根目录
的 `docker-compose.yml`。Cloudflare CDN 在前面做边缘缓存。
