# Changelog

本项目所有显著的变更都会记录在这里。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本 (SemVer)](https://semver.org/lang/zh-CN/)。

## [2.8.1] - 2026-06-02

### Added
- **B 站 / 小红书 probe 流程**：probe 前 Agent 必须先询问用户「是否启用 Chrome 登录态」，由用户决定走 guest（B 站 480p / 小红书 720p）还是登录态（B 站 1080p+ / 小红书 4K）
- `probe.sh` 新增 `VDL_USE_CHROME=1` 开关，启用后会读取 Chrome cookies 并复用 download.sh 的缓存文件（24h 一次钥匙串弹窗永久免弹）
- `probe.sh` 在 B 站 / 小红书 guest 模式下输出明确提示：`>>> [probe] bilibili guest mode (HD/4K hidden). To unlock: VDL_USE_CHROME=1 bash ...`

### Fixed
- `probe.sh` 之前在 B 站只能拿到 480p，因为只读已存在的 cookie 缓存文件、不主动调 cookies-from-browser

### Changed
- SKILL.md Step 3 增加 3a / 3b 子步骤：先询问用户登录态偏好，再 probe

## [2.8.0] - 2026-06-02

### Changed (Anthropic Skill 规范对齐 — 重大重构)
- **SKILL.md 大瘦身**：320 行 → 169 行（–47%），20 KB → 7.9 KB（–61%）
- **YAML `description` 重写**：2040 字符 → 386 字符，符合 Anthropic 规范的 ≤1024 字符上限；删除了冗长的触发词列表 + URL 域名穷举，改为"能做什么 + 何时用"的标准第三人称写法
- **删除 YAML `version` 字段**：Anthropic 规范的 frontmatter 仅认 `name` + `description`；版本号仅在 git tag / CHANGELOG 中维护，不再写入 SKILL.md
- **正文 onboarding 长文挪到 `SETUP.md`**：包括「首次使用 4 个确认」+「钥匙串弹窗完整说明」
- **新增 `references/platform-notes.md`**：把 SKILL.md 里的「平台特定要点」「错误处理速查」「平台速查表」整段搬出，应用 Anthropic 推荐的 progressive disclosure 模式
- **删除正文重复内容**：触发词列表（与 description 重复）、平台特定要点（已挪到 references）、错误处理表（已挪到 references）、Step 0 装饰性 echo
- **SKILL.md 主文件改为"导航式"结构**：每个细节都指向独立 reference 文件，避免一次性加载所有内容

### Rationale
依据 Anthropic 官方 [Agent Skills authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/authoring-best-practices)：
- description ≤ 1024 字符，第三人称
- SKILL.md 正文 ≤ 500 行
- 用 progressive disclosure 把不常用的细节搬到附加文件
- 简洁是王道：默认 Claude 已经很聪明，只写它不知道的东西

## [2.7.0] - 2026-06-02

### Added (Major workflow change — "先解析后选档"两步流)
- **`scripts/probe.sh`** —— 新增链接解析脚本（不下载），输出：
  - 视频元数据（平台 / 标题 / 作者 / 发布日期 / 时长 / 封面）
  - 全部可下载画质档位（label / 编码 / 容器 / 大小 / 备注）
  - 两种输出：`--human` 给人看的表格 / 默认 JSON 给程序消费
- **`scripts/_probe_format_ytdlp.py`** —— 把 yt-dlp `-J` 大对象统一映射成 probe schema（包含格式去重、video-only + best-audio 合并大小计算、HEVC/AV1/H264 别名化）
- **`scripts/_probe_render_human.py`** —— probe JSON → 人类表格
- **抖音 probe**：通过对 `/play/?ratio=720p|1080p|default` 三档 HEAD 拿 Content-Length，三档大小一次性给出
- **快手 probe**：枚举分享页里所有 mp4 直链，HEAD 探每个的大小，HD/SD 标签化

### Changed
- **`scripts/download.sh`** —— 改为多语法入口：
  - `download.sh --format <#> <URL>` —— 按 probe 表行号下载（推荐，与 probe 强对齐）
  - `download.sh --format-id <id> <URL>` —— 按 yt-dlp format-id 下载
  - `download.sh --format-arg "<expr>" <URL>` —— 直接传 `-f` 表达式
  - `download.sh <quality|speed|compat> <URL>` —— 旧预设语法仍保留
- 抖音脚本新增 `--ratio <r>` 显式画质指定参数（来自 probe → 用户选行 → download 解析 → 抖音脚本）
- 抖音 / 快手脚本均新增 `--probe-only` 子命令
- **`SKILL.md` Step 3 大改**：从"询问用户 quality/speed/compat 偏好"改为"先调 probe 把全部档位 + 大小给用户挑"

### Why
- 用户原话：「下载分两步，第一步链接解析（作者/标题/时间/可下档位/各档大小），第二步把档位给用户选」
- 解决问题：预设三档可能不符合用户预期（如视频原始就是 720p 时 quality 无意义；如用户想精准要 5 MB 以内的版本）
- 透明度：用户能看到「具体能拿到什么 + 多大」再决定，不再黑盒

## [2.6.0] - 2026-06-02

### Added
- **抖音 4K/原画支持**：`download-douyin.sh` 新增 3 档画质映射，利用 SSR 分享 API 的 `/play/?ratio=` 隐藏参数
  - `speed` → `ratio=720p` → 720p H.264 转码（最小）
  - `compat` → `ratio=1080p` → 1080p H.264 转码（macOS 原生）
  - **`quality` → `ratio=default` → 原始 master 文件**（可达 4K60 HEVC，取决于上传者原始画质）
- 关键发现：`/playwm/` 端点永远忽略 ratio 参数只返 720p 水印版；只有 `/play/` 端点配合 `ratio=` 才会真正改变画质
- `references/format-reference.md` 抖音章节大改：从「上限 720p」更正为「3 档可解锁」，含完整 URL 路径 × ratio 参数对照表

### Changed
- SKILL.md / README.md / README.en.md 抖音相关描述同步更新

## [2.5.0] - 2026-06-01

### Added
- **小红书 4K 支持**：实测可下 3840×2160 HEVC（quality 模式）
- **Chrome cookies 一次导出、永久免弹**机制：首次弹一次钥匙串后导出到 `~/.cache/video-downloader/chrome-cookies.txt`，24 小时内复用本地文件、不再触发 macOS Keychain 弹窗
- 新增项目根级 `README.md`、`LICENSE`(MIT)、`.gitignore`、`CHANGELOG.md`，准备开源到 GitHub

### Changed
- **修正小红书机制描述**：之前文档错误地把 `web_session` cookie 称为「登录态」，实际它是**匿名 session token**。验证：调 `user/me` API 返回 `"guest":true` 仍能拿到 4K formats。无需账号登录，仅需 Chrome 访问过一次小红书即可
- `download.sh` 重写 cookie 选择逻辑：非登录平台默认 guest 模式不碰 Chrome；只有 quality 模式下小红书 / B 站等需要登录态的场景才走 Chrome cookies
- `SETUP.md` 平台支持表细化：把 YouTube/Twitter/Vimeo 之外补上「微博 / 快手 / 抖音 / 小红书 720p」都不需要登录的事实
- `references/format-reference.md` 小红书章节更新：从「上限 1080p」更正为「上限 4K」，并补充 5 档画质 × 3 个 CDN 镜像 = 15 个 formats 的实际结构

## [2.4.0] - 2026-05

### Added
- **快手专用脚本** `download-kuaishou.sh`：yt-dlp 没有内置快手 extractor，本脚本走分享页 SSR 解析 inline 的 mp4 直链，无需登录
- 微博支持：yt-dlp 内置 extractor 已能自动拿 guest cookies，公开微博无需登录可拿到 4K (2160p60)

### Changed
- Skill 改名：`youtube-downloader` → `video-downloader`，从单平台扩展为多平台

## [2.3.0] - 2026-04

### Added
- **抖音专用脚本** `download-douyin.sh`：绕开 yt-dlp 内置 extractor（2025 起需要 `a_bogus` 风控签名失效），走移动端分享页 SSR 接口，已验证 720p H.264 无水印版本

### Fixed
- 抖音 `Fresh cookies (not necessarily logged in) are needed` 报错

## [2.2.0]

### Added
- 三档下载策略：quality / speed / compat
- aria2c 16 路并行加速
- 平台特定的错误归因（B 站 720p+ 提示登录态、小红书 xsec_token 缺失提示等）

## [2.1.0]

### Added
- 多浏览器自动嗅探（chrome / safari / firefox / brave / edge）
- 浏览器选择缓存到 `~/.cache/video-downloader/cookies.cache`

## [2.0.0]

### Added
- 初版：YouTube + Bilibili 双平台支持
