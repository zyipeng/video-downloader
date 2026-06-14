---
name: video-downloader
description: Downloads videos from YouTube, Bilibili, Douyin, Xiaohongshu, Kuaishou, Twitter/X, Weibo, Vimeo, TikTok, and 1700+ other sites to local disk. Handles per-platform quirks (Bilibili login for 720P+, Xiaohongshu xsec_token, custom parsers for Douyin/Kuaishou). Use when the user asks to download, save, grab, rip, or archive a video, or provides a video URL with intent to save it locally.
---

# Video Downloader

支持从多个视频平台下载视频到本地，基于 `yt-dlp` + 自研脚本实现。下载前先解析所有可下载档位让用户挑选，自动应用平台特定优化。

> 📘 **新用户必读**：完整安装 / 权限 / 路径配置见 [`SETUP.md`](./SETUP.md)。
> 📘 **平台细节 / 错误处理速查**：见 [`references/platform-notes.md`](./references/platform-notes.md)。

## Step 0：环境自检（首次使用必做）

```bash
MISSING=()
for tool in yt-dlp ffmpeg; do
  command -v "$tool" >/dev/null 2>&1 || MISSING+=("$tool")
done
command -v aria2c >/dev/null 2>&1 || echo "ℹ️ aria2c 未装（可选，装了会快 10x）：brew install aria2"

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "❌ 缺少必需工具: ${MISSING[*]}"
  echo "   请跑：brew install ${MISSING[*]}"
  exit 1
fi
echo "✅ 必需工具齐全；默认下载目录：$HOME/Downloads"
```

依赖缺失时引导用户去 [`SETUP.md`](./SETUP.md)。

## 核心流程

### Step 1：识别下载请求并提取 URL

从用户消息中抽取**第一个**视频平台 URL。如果有多个 URL，逐个询问或批量处理。

如果用户没有给 URL，而是要求先找出含视频的公开 X/Twitter 推文，可以在用户明确同意后使用已安装的 TweetClaw/OpenClaw 工作流做 URL 发现：

```bash
openclaw plugins install npm:@xquik/tweetclaw@1.6.31
```

只把 TweetClaw 产出的公开视频推文 URL、作者 handle、公开文本、媒体提示、抓取时间和检索条件当作下载前的 source packet。不要在本 Skill 内执行发推、回复、关注、私信、媒体上传、监控、webhook、私密账号数据读取或账号设置变更。拿到用户确认的 URL 后，继续 Step 2 和 Step 3。

### Step 2：识别平台 + 检查依赖

```bash
which yt-dlp ffmpeg aria2c 2>&1
```

平台特定的登录态 / cookies / 特殊脚本逻辑见 [`references/platform-notes.md`](./references/platform-notes.md)。下面只列出**影响交互**的关键提示：

- B 站 → 必须提示用户"720P+ 需要登录态"
- 小红书 → 必须确认 URL 含 `xsec_token`；`quality` 模式必须提示"4K 需要 Chrome 匿名 session cookie"
- 抖音 / 快手 → `download.sh` 会自动委派到对应专用脚本，无需 Agent 操心
- 微博 → `quality` 模式可能下到 300+ MB 大文件，提前告知

### Step 3：先探测，把档位给用户挑（**必须做**）

⚠️ **不要直接下载**。**必须**先调 probe 拿到档位表，让用户**自己选**。

**B 站 / 小红书 probe 前必须先问一句**（默认 guest 只能看 480p / 720p）：

> 想要 1080p+ 高清吗？需要读 Chrome 登录态 cookies（首次会弹一次 macOS 钥匙串，点「始终允许」即永久免弹）。**(1) 要高清** / **(2) 不用，guest 就行**

用户选 (1) → 命令前缀加 `VDL_USE_CHROME=1`；选 (2) 或其他平台 → 直接跑：

```bash
bash "<skill_directory>/scripts/probe.sh" --human "<URL>"
# B 站 / 小红书要高清：
VDL_USE_CHROME=1 bash "<skill_directory>/scripts/probe.sh" --human "<URL>"
```

把 probe 输出的档位表**直接展示给用户**，加一句推荐（兼容优先 = H.264 / 画质优先 = HEVC 或 AV1 / 速度优先 = 最低分辨率），然后问：

> 你想下载哪一档？(回复行号，或输入 quality / compat / speed 用预设规则)。保存位置默认 `~/Downloads`，如需修改请告诉我目录。

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
- `MODE`：`quality` | `speed` | `compat`（预设规则，可跳过 probe）
- `URL`：视频链接
- `output_dir`：可选，**默认 `~/Downloads`**

`download.sh` 已内嵌平台委派逻辑——抖音 / 快手会自动走对应的专用脚本。

#### 三档预设语义（不调 probe 的快捷路径）

| 维度 | quality | speed | compat |
|------|---------|-------|--------|
| 格式选择 `-f` | `bv*+ba/b` | `bv*[height<=480]+ba/b[height<=480]` | `bv*[vcodec^=avc1][height<=1080]+ba/b[ext=mp4][height<=1080]` |
| 容器 | `mkv` | `mp4` | `mp4` |
| 并发分片 | 16 | 16 | 16 |
| Cookies | 默认游客；遇到小红书/B 站才读 Chrome | 同左 | 同左 |
| 外部下载器 | aria2c（如已安装） | 同左 | 同左 |

#### macOS 钥匙串弹窗

> ℹ️ B 站 / 小红书 quality 模式首次会触发 macOS 钥匙串弹窗（点「始终允许」即可），完整说明见 [`SETUP.md`](./SETUP.md)。

### Step 5：监控 + 汇报

后台执行 + 每 30s 轮询：

```bash
ls -lh "<output_dir>"/*.part 2>/dev/null
ps -p <PID> >/dev/null && echo RUNNING || echo DONE
```

下载完成用 `ffprobe` 抓出分辨率 / 编码 / 大小，汇报给用户。

### Step 6：兼容性自检（quality 模式）

如果 `ffprobe` 输出的视频编码是 `vp9` / `av01` / `hevc`，**必须额外提醒**：

> 这个文件是 `<编码>` 编码，**部分播放器 / 移动端 / 网页可能无法直接播放**（例如 macOS QuickTime / Windows 资源管理器缩略图 / Office 插入视频）。建议用现代播放器：macOS = IINA / VLC，Windows = PotPlayer / VLC / MPV，跨平台 = VLC / mpv / IINA。
>
> 如果需要**任意环境都能直接播放**的文件，重选「兼容优先」模式下一遍（1080p H.264 + MP4）。

## 注意事项

1. **必须先问用户偏好**，不要默认替用户选 quality / speed / compat
2. **B 站链接必须额外提示登录态**
3. **大文件下载用后台执行 + 轮询**，不要阻塞对话
4. **下载到 `~/Downloads`**（除非用户指定）
5. **版权声明**：仅协助下载用户有权访问的内容；不绕过付费墙、不下载受 DRM 保护的内容、不破解会员专享内容
6. **进度反馈**：每 30–60 秒向用户汇报一次进度，避免长时间静默

## 支持文件

- `references/platform-notes.md` —— 各平台要点 + 错误处理速查
- `references/format-reference.md` —— 各平台编码 / format id / 容器选择速查
- `scripts/probe.sh` —— 链接解析（不下载），输出元数据 + 档位表
- `scripts/download.sh` —— 统一下载入口（自动平台识别 + 多线程 + 自动委派抖音 / 快手）
- `scripts/_probe_format_ytdlp.py` —— yt-dlp `-J` → 统一 probe JSON
- `scripts/_probe_render_human.py` —— probe JSON → 人类表格
- `scripts/download-douyin.sh` —— 抖音专用（绕开 yt-dlp 失效 extractor，走分享页 SSR）
- `scripts/download-kuaishou.sh` —— 快手专用（yt-dlp 无内置 extractor，走分享页 SSR）
