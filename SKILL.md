---
name: video-downloader
description: |
  This skill should be used when the user asks to download a video and save it locally.
  It auto-detects the platform, installs dependencies (yt-dlp, ffmpeg, optionally aria2),
  interactively asks the user to choose between Quality-First / Speed-First / Compatible,
  handles per-platform quirks (Bilibili 720P+ needs login, Xiaohongshu needs xsec_token in URL,
  Douyin and Kuaishou use custom SSR-page parsers instead of yt-dlp), prints platform-specific
  actionable hints when downloads fail, and uses parallel-fragment downloading to maximize speed.

  Trigger phrases (English):
  "download a video", "download this video", "save this video", "save video locally",
  "grab this video", "rip this video", "fetch this video", "download YouTube video",
  "download YT video", "download from YouTube", "download Bilibili video", "download B site video",
  "download Douyin video", "download TikTok video", "download from TikTok",
  "download Xiaohongshu video", "download RedNote video", "download xhs video",
  "download Kuaishou video", "download from Kuaishou", "download Weibo video",
  "download Twitter video", "download X video", "download Vimeo video",
  "save this clip", "archive this video", "back up this video offline",
  "yt-dlp this", "use yt-dlp", "pull this video down".

  Trigger phrases (Chinese):
  "下载视频", "下载这个视频", "保存视频", "存到本地", "存这个视频",
  "下载 YouTube 视频", "下载油管视频", "油管下载", "下载 YT",
  "下载 B 站视频", "下载哔哩哔哩视频", "B站下载", "下载 bilibili",
  "下载抖音视频", "下载 Douyin", "抖音下载",
  "下载小红书视频", "下载 xhs", "下载 RedNote", "小红书下载",
  "下载快手视频", "下载 Kuaishou", "快手下载",
  "下载微博视频", "微博下载",
  "下载推特视频", "下载 Twitter", "下载 X 视频",
  "下载 Vimeo", "下载 TikTok",
  "保存这个视频到本地", "把这个视频存下来", "扒这个视频", "归档这个视频".

  Or whenever the user provides any URL from these video platforms:
  youtube.com / youtu.be / youtube.com/shorts / bilibili.com / b23.tv /
  douyin.com / v.douyin.com / iesdouyin.com /
  xiaohongshu.com / xhslink.com /
  kuaishou.com / v.kuaishou.com / m.gifshow.com /
  twitter.com / x.com /
  weibo.com / weibo.cn / video.weibo.com /
  vimeo.com / tiktok.com
  and expresses intent to save it to disk.
version: 2.7.0
---

# Video Downloader

支持从多个视频平台下载视频到本地，基于 `yt-dlp` 实现。下载前先和用户确认偏好（质量 / 速度 / 兼容），自动应用平台特定优化。

> 📘 **新用户必读**：完整的安装/权限/路径配置指南见 [`SETUP.md`](./SETUP.md)。
> 第一次使用本 skill 时，AI 助手应主动跑「Step 0：环境自检」，确认依赖到位再继续。

## Step 0：环境自检（首次使用必做）

在执行任何下载前，AI 助手必须先跑这段自检脚本：

```bash
echo "=== video-downloader 环境自检 ==="
MISSING=()
for tool in yt-dlp ffmpeg; do
  if ! command -v "$tool" >/dev/null 2>&1; then MISSING+=("$tool"); fi
done
command -v aria2c >/dev/null 2>&1 || echo "ℹ️ aria2c 未装（可选，装了会快 10x）：brew install aria2"

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "❌ 缺少必需工具: ${MISSING[*]}"
  echo "   请跑：brew install ${MISSING[*]}"
  echo "   （没 Homebrew 先跑：/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"）"
  exit 1
fi
echo "✅ 必需工具齐全"
echo "📁 默认下载目录：$HOME/Downloads"
```

**用户首次使用时必须额外告知**（一次性 onboarding）：

> 这是你第一次用 video-downloader skill。开始前我需要确认 4 件事：
>
> 1. **依赖是否已装**：刚才的自检脚本输出全部 ✅ 了吗？没装的话需要先 `brew install yt-dlp ffmpeg aria2`。
> 2. **下载到哪里**：默认存到 `~/Downloads`。要换路径吗？比如 `~/Movies/`、外接硬盘？
> 3. **要下 B 站/小红书吗**：这两个网站需要登录态。请在 Chrome 里登录对应网站，否则 B 站只能拿 480p、小红书会失败。
> 4. **是否有 Mac 钥匙串弹窗顾虑**：第一次让 yt-dlp 读 Chrome cookies 会弹一次密码框。点「始终允许」一次以后就不再弹了。
>     如果你想完全避开，可以改用 Firefox（在 Firefox 里登录），跑下载时加 `VDL_BROWSER=firefox`。
>
> 完整说明见 `SETUP.md`。

## 支持的平台

通过 `yt-dlp` 内置的 extractor + 自研抖音脚本，本 skill 已验证支持：

| 平台 | URL 模式 | 后端 | 特殊说明 |
|------|---------|------|----------|
| **YouTube** | `youtube.com/watch?v=` / `youtu.be/` / `youtube.com/shorts/` | yt-dlp | 推荐 `--cookies-from-browser` 走登录态绕限速 |
| **Bilibili (B 站)** | `bilibili.com/video/BVxxx` / `b23.tv/xxx` | yt-dlp | ⚠️ **720P+ 必须登录** —— 否则最多只能拿 480x640 |
| **抖音 (Douyin)** | `douyin.com/video/xxx` / `v.douyin.com/xxx` / `iesdouyin.com/share/video/xxx` | **自研脚本** | yt-dlp 内置 extractor 已失效（2025 起需要复杂的 a_bogus 风控签名）；本 skill 走移动端分享页 SSR 接口。**画质分三档**：speed=720p、compat=1080p H.264、**quality=原始 master 文件（上传者提供什么就下什么，可能是 4K60 HEVC 或 1080p H.264）**，均为无水印版本（隐藏参数 `/play/?ratio=default` 解锁） |
| **小红书 (Xiaohongshu / RedNote)** | `xiaohongshu.com/explore/<id>` / `xiaohongshu.com/discovery/item/<id>?xsec_token=...` / `xhslink.com/a/<id>` | yt-dlp | URL **必须包含 `xsec_token`**。**画质分两档**：<br>• 裸 yt-dlp（无任何 cookies）→ **720p H.264**<br>• 带 Chrome 里的匿名 **`web_session` cookie**（匿名 session、**不需登录**，只要你用 Chrome 访过一次小红书就有）→ **最高 4K (3840×2160) HEVC**，含 1440p/1080p/720p、H.264/HEVC 多档<br>• 私密笔记才需要真正登录态
| **快手 (Kuaishou)** | `kuaishou.com/f/<token>` / `kuaishou.com/short-video/<photoId>` / `v.kuaishou.com/<code>` / `m.gifshow.com/fw/photo/<id>` | **自研脚本** | yt-dlp 无内置 extractor。脚本走 SSR 分享页解析 inline 的 mp4 直链，**无需登录**，已验证可下 720p HEVC
| **Twitter / X** | `twitter.com/.../status/` / `x.com/.../status/` | yt-dlp | 部分私密推文需 cookies |
| **Vimeo** | `vimeo.com/xxx` | yt-dlp | 私密视频需密码 |
| **微博** | `weibo.com/xxx/<id>` / `video.weibo.com/show?fid=...` / `m.weibo.cn/status/<id>` | yt-dlp | ⚡ 本平台是**全 skill 里画质上限最高**的之一：实测可拿到 **2160p60 (4K)**。**公开资源游客模式即可下**（yt-dlp 会自动帮你拿 guest cookies）；只有限粉丝 / 仅可见的动态才需要登录 cookies
| **TikTok** | `tiktok.com/@xxx/video/` | yt-dlp | 国区视频可能需要 cookies |
| **其他 1700+ 站点** | 见 `yt-dlp --list-extractors` | yt-dlp | 通用流程一致 |

## 核心流程

### Step 1：识别下载请求并提取 URL
触发信号：
- 用户消息中出现任意支持平台的 URL
- 中文：`下载视频`、`下载 B 站`、`下载油管`、`保存这个视频`、`存到本地`
- 英文：`download video`、`save this video`、`grab this video`

从用户消息中抽取**第一个**有效 URL。如果有多个 URL，逐个询问或用列表批量处理。

### Step 2：识别平台 + 检查依赖

```bash
which yt-dlp ffmpeg aria2c 2>&1
```

- 缺 `yt-dlp` / `ffmpeg` → `brew install yt-dlp ffmpeg`
- `aria2c` 可选（加速）：`brew install aria2`
- 没 Homebrew → 用 `pip3 install -U yt-dlp`

平台识别（脚本内自动完成，仅需识别影响交互的特殊情况）：
- URL 含 `bilibili.com` 或 `b23.tv` → **B 站**：必须提示用户"720P+ 需要登录态，建议从浏览器读 cookies"
- URL 含 `youtube.com` 或 `youtu.be` → **YouTube**：建议走登录 cookies 提速
- URL 含 `douyin.com` / `v.douyin.com` / `iesdouyin.com` → **抖音**：脚本会自动委派到 `download-douyin.sh`。**画质三档**：**`quality` 拿原始 master 文件（可能 4K60 HEVC，取决于上传者原始画质）**、`compat` 拿 1080p H.264、`speed` 拿 720p。均为无水印版本（隐藏参数 `/play/?ratio=default|1080p|720p` 解锁）
- URL 含 `xiaohongshu.com` / `xhslink.com` → **小红书**：
  - 检查 URL 含 `xsec_token`（从 App 分享按钮复制，**不要**从浏览器地址栏复制）
  - ⚠️ 画质分两档：**裸 yt-dlp 最高 720p**，**要 4K/1440p/1080p HEVC 必须读 Chrome 的匿名 `web_session` cookie**。这个 `web_session` 是**匿名 session，不是登录态**——只要用户用 Chrome 访问过小红书就会被服务端下发，服务端看到它就敢返回高画质清单（应对爬虫的阶梯限制）
  - 验证方法：调 `https://edith.xiaohongshu.com/api/sns/web/v2/user/me`，返回 `"guest":true` 则是匿名、`"guest":false` + `nickname` 则是真登录
  - 如果用户选 `quality` 模式下小红书动态，主动提示：“小红书裸 yt-dlp 只能拿 720p，要 4K 需要读取 Chrome 的匿名 session cookie（第一次会弹一次钥匙串请点『始终允许』）”，默认 NEEDS_LOGIN=yes（quality 下）或 NEEDS_LOGIN=no（speed/compat 下）
- URL 含 `kuaishou.com` / `v.kuaishou.com` / `m.gifshow.com` → **快手**：脚本会自动委派到 `download-kuaishou.sh`，无需登录，无需特殊提示
- URL 含 `weibo.com` / `weibo.cn` / `video.weibo.com` → **微博**：yt-dlp 内置 extractor 已能自动拿 guest cookies，**公开微博无需登录**，可拿到最高 4K (2160p60)。提醒用户 `quality` 模式可能下到 300+MB 的大文件
- 其他 → 通用流程

### Step 3：**先探测，把档位给用户挑**（**必须做**，新核心流程）

⚠️ **不要直接下载**。**必须**先调 probe 拿到「视频基本信息 + 全部可下载档位 + 每档大小」，把表格展示给用户，让用户**自己选**。

```bash
bash "<skill_directory>/scripts/probe.sh" --human "<URL>"
```

会输出类似这样的表：

```
================================================================
平台    : douyin
标题    : XXX 教你 3 步做出网红甜品
作者    : 美食小当家
发布日期: 20260530
时长    : 0m45s
URL     : https://v.douyin.com/abcdef/
----------------------------------------------------------------
  # 画质           编码         容器   大小      备注
----------------------------------------------------------------
  0 原画 master    ?+aac        mp4   18.4 MiB  上传者原始文件（可能 4K60 HEVC）
  1 1080p          h264+aac     mp4   12.1 MiB  H.264 转码（QuickTime 原生）
  2 720p           h264+aac     mp4    6.3 MiB  H.264 转码（体积最小）
================================================================
```

把上面这张表**直接展示给用户**，然后问：

> 已解析视频信息（标题：xxx，作者：xxx）。检测到 N 个画质档位：
>
> - **#0 原画 master** — 18.4 MiB（4K60 HEVC，QuickTime 可能不支持）← 画质优先建议
> - **#1 1080p** — 12.1 MiB（H.264，QuickTime 原生）← 兼容优先建议
> - **#2 720p** — 6.3 MiB（H.264，最小最快）← 速度优先建议
>
> 你想下载哪一档？(回复行号 0 / 1 / 2，或者输入 quality / compat / speed 用预设规则)
>
> 保存位置默认 `~/Downloads`，如需修改请告诉我目录。

#### 如果用户给的是 B 站 / 小红书等需要登录态的平台

- B 站：`probe.sh` 在 guest 模式只会看到 480p 档；先告知用户「想看到更高档位需要 Chrome 已登录 bilibili.com，是否要尝试？」如果是 → 设 `VDL_USE_CHROME=1` 重跑 probe
- 小红书：guest 默认只见 720p 档；提示「要拿 4K HEVC 档位需要 Chrome 访问过 xiaohongshu.com（一次即可，不需要登录账号）」

### Step 4：执行下载（按用户选择）

**三种下载语法**（任选一种）：

```bash
# 方式 A：用户挑了 probe 表里的行号（推荐 — 与 probe 强对齐）
bash "<skill_directory>/scripts/download.sh" --format <#> "<URL>" [output_dir]

# 方式 B：用户输入了 quality/speed/compat 预设
bash "<skill_directory>/scripts/download.sh" <MODE> "<URL>" [output_dir]

# 方式 C：高级用户直接传 yt-dlp -f 表达式
bash "<skill_directory>/scripts/download.sh" --format-arg "<expr>" "<URL>" [output_dir]
```

参数：
- `<#>`：probe `--human` 输出里的行号
- `MODE`：`quality` | `speed` | `compat`（预设规则，不需要先 probe）
- `URL`：视频链接
- `output_dir`：可选，**默认 `~/Downloads`**

`download.sh` 已经内嵌平台委派逻辑——抖音 / 快手会自动走对应的专用脚本，不需要 Agent 操心。

#### 三档预设语义（不调 probe 的快捷路径）

| 维度 | quality (A) | speed (B) | compat (C) |
|------|-------------|-----------|------------|
| 格式选择 `-f` | `bv*+ba/b`（最高码率） | `bv*[height<=480]+ba/b[height<=480]` | `bv*[vcodec^=avc1][height<=1080]+ba/b[ext=mp4][height<=1080]` |
| 容器 | `mkv`（兼容 AV1/Opus/HEVC） | `mp4` | `mp4` |
| 并发分片 | 16 | 16 | 16 |
| Cookies | 默认游客；quality 下遇到 小红书/B站 才读 Chrome cookies | 同左 | 同左 |
| 外部下载器 | aria2c（如已安装） | 同左 | 同左 |

#### macOS 钥匙串弹窗说明（**必须主动告知**）

如果用户的目标是 **小红书（quality 模式） / B 站** 这类需要读 Chrome cookies 的场景，**第一次**运行会弹出系统弹窗：

> security 想要使用你储存在钥匙串的 "Chrome Safe Storage" 中的机密信息

**用户必须知道的事**：

1. **为什么弹**：macOS Chrome 把 cookies 用 v10 AES 加密，密钥存在系统钥匙串里。yt-dlp（通过 `security` 命令）需要用户授权才能读这把密钥来解密 cookies。
2. **本 skill 已做的优化**：**一次导出、永久免弹**——首次读 cookies 后会导出到 `~/.cache/video-downloader/chrome-cookies.txt`，后续 24 小时内走 `--cookies <file>` 而不是 `--cookies-from-browser`，不再调 `security`、不再弹钥匙串
3. **替代方案**：用 **Safari** 或 **Firefox** 替代（这两家不弹钥匙串密码框），设 `VDL_BROWSER=safari` / `VDL_BROWSER=firefox`
4. **怎么重置缓存**：`rm ~/.cache/video-downloader/chrome-cookies.txt`

### Step 5：监控 + 汇报

后台执行 + 每 30s 轮询：
```bash
ls -lh "<output_dir>"/*.part 2>/dev/null
ps -p <PID> >/dev/null && echo RUNNING || echo DONE
```

下载完成用 `ffprobe` 抓出分辨率 / 编码 / 大小，汇报给用户。

### Step 6：兼容性自检（quality 模式）

如果 `ffprobe` 输出的视频编码是 `vp9` / `av01` / `hevc`，**必须额外提醒**：

> 这个文件是 `<编码>` 编码，macOS QuickTime/Finder 空格预览**可能无法播放**。建议用 IINA（`brew install --cask iina`）或 VLC 打开。
>
> 如果想要原生兼容版本，可以用"兼容优先"模式重新下一份。

## 平台特定要点

### YouTube
- 必备 `--extractor-args "youtube:player_client=ios,web_safari"` 绕 throttle
- 限速主要靠 cookies + iOS 客户端 + 分片并发解决
- AV1 / VP9 是默认最高画质，**macOS 原生不支持**

### Bilibili (B 站)
- ⚠️ **720P / 1080P / 4K 必须登录**，否则只能拿 480x640
- HEVC（hev1.*）是 B 站主推，文件小但 macOS QuickTime 不直接支持
- 如果用户没登录浏览器：建议先去浏览器登录 B 站（`https://www.bilibili.com`）再重试
- B 站有"番剧"（bangumi）、"课程"（cheese）、"音频"等专门 extractor，URL 格式会自动识别

### 抖音 (Douyin)
- ⚠️ **yt-dlp 内置 extractor 自 2025 年起已失效**（需要复杂的 `a_bogus` 风控签名）
- 本 skill 走 **移动端分享页 SSR 接口**：`https://www.iesdouyin.com/share/video/{aweme_id}/`
- 流程：
  1. 用户给的 URL（短链 `v.douyin.com/xxx` / 长链 `douyin.com/video/xxx`）→ 提取 `aweme_id`
  2. 用 iOS UA 请求分享页 → 解析 HTML 中的 `play_addr` JSON
  3. 优先尝试 `play`（无水印）版本，回退到 `playwm`（带水印）
- **画质三档（通过隐藏的 `/play/?ratio=` 参数解锁）**：
  - `speed` → `ratio=720p` → 720p H.264 转码，文件最小
  - `compat` → `ratio=1080p` → 1080p H.264 转码，macOS QuickTime 原生支持
  - **`quality` → `ratio=default` → 原始 master 文件（上传者提供什么就下什么）**，实测可以拿到 **4K60 HEVC**，也可能是 1080p H.264——**这是唯一拿 4K 的路径**
  - 关键隐藏机制：`/playwm/` 端点徽底忽略 ratio 参数只返 720p水印版；`/play/` 端点才看 ratio；分享 URL 默认写死 `ratio=720p`，脚本会自动重写
- 自动尝试无水印版本（把 URL 里的 `playwm` 换成 `play`，并改写 ratio 参数）
- 不需要登录、不需要 cookies

### Twitter / X
- 大部分公开推文不需要 cookies
- 包含视频的推文会自动抽取最高码率版本
- 引用了 video 的转推也能下

### 通用
- 任何 yt-dlp 支持的站点都能跑：`yt-dlp --list-extractors` 查列表
- 遇到不认识的 URL 直接传给 yt-dlp 试一下，多数情况能下

## 错误处理

| 错误 | 处理 |
|------|------|
| `yt-dlp not found` | 自动 `brew install yt-dlp` |
| `ffmpeg not found` | 自动 `brew install ffmpeg` |
| YouTube `Sign in to confirm you're not a bot` | 提示用 `--cookies-from-browser` |
| B 站 `Format(s) 720P 准高清 are missing; you have to become a premium member` | **不是真要会员**，是要登录态。提示用户在浏览器登录 B 站后重试 |
| B 站 `404 / 视频已失效` | 视频被删 / 下架 |
| 抖音 `Fresh cookies (not necessarily logged in) are needed` | 这是 yt-dlp 内置 extractor 失效的报错；本 skill 已自动改走 `download-douyin.sh` 绕开该问题 |
| 抖音 `cannot extract aweme_id` | URL 格式不识别，请用户检查链接是否完整（`v.douyin.com/xxx` / `douyin.com/video/xxx`） |
| 抖音 `cannot find play_addr in share page` | 抖音分享页结构变了；可能需要更新脚本里的正则表达式 |
| `Video unavailable` / 地区限制 | 提示用户切换代理节点 |
| `HTTP Error 403` | 等待几分钟重试，YouTube 可换 `tv_embedded` 客户端 |
| Deno JS challenge 失败 | `brew upgrade yt-dlp` 或 `pip3 install -U yt-dlp` |

## 注意事项

1. **必须先问用户偏好**，不要默认替用户选择 quality / speed / compat
2. **B 站链接必须额外提示登录态**
3. **大文件下载用后台执行 + 轮询**，不要阻塞对话
4. **下载到 `~/Downloads`**（除非用户指定）
5. **版权声明**：仅协助下载用户有权访问的内容；本 skill 不绕过付费墙、不下载受 DRM 保护的内容、不破解会员专享内容
6. **进度反馈**：每 30–60 秒向用户汇报一次进度，避免长时间静默
7. ⚠️ 旧版本叫 `youtube-downloader`，已升级为多平台 `video-downloader`

## 支持文件

- `references/format-reference.md` —— 各平台编码 / format id / 容器选择速查
- `scripts/probe.sh` —— **🆕 链接解析（不下载）**，输出视频元数据 + 可下载画质档位 + 每档大小（JSON 或人类表格）
- `scripts/download.sh` —— 统一下载入口（自动平台识别 + 多线程加速 + 自动委派抖音 / 快手）。支持 `--format <#>`（probe 行号）/ `--format-arg <expr>` / `quality|speed|compat` 三种语法
- `scripts/_probe_format_ytdlp.py` —— yt-dlp -J → 统一 probe JSON
- `scripts/_probe_render_human.py` —— probe JSON → 人类表格
- `scripts/download-douyin.sh` —— 抖音专用下载器（绕开 yt-dlp 失效的 extractor，走分享页 SSR API），支持 `--probe-only` / `--ratio <r>`
- `scripts/download-kuaishou.sh` —— 快手专用下载器（yt-dlp 无内置 extractor，走分享页 SSR，无需登录），支持 `--probe-only`
