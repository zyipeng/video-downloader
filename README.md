# video-downloader

> 一个为 [CodeFlicker / MyFlicker IDE](https://github.com/CodeFlicker) 设计的 AI Agent **Skill**，让 AI 助手帮你从 9 个主流视频平台下载视频到本地。基于 `yt-dlp` + 自研脚本，主打 **macOS 一键可用**、**画质可选**、**速度优先** 三档预设。

[![version](https://img.shields.io/badge/version-2.7.0-blue.svg)](./CHANGELOG.md)
[![license](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)
[![platforms](https://img.shields.io/badge/platforms-9%20sites-orange.svg)](#%E6%94%AF%E6%8C%81%E7%9A%84%E5%B9%B3%E5%8F%B0)

---

## ✨ 亮点

- 🎯 **9 个主流平台开箱即用**：YouTube / Bilibili / 抖音 / 小红书 / 快手 / 微博 / Twitter(X) / Vimeo / TikTok
- 🎬 **三档画质策略**：质量优先（最高 4K/8K AV1）/ 速度优先（≤480p）/ 兼容优先（macOS QuickTime 原生支持）
- 🚀 **16 路并行下载**：自动用 aria2c 分片加速，YouTube/B 站轻松跑满带宽
- 🍎 **macOS Keychain 一次性解决**：第一次弹一次钥匙串，导出 cookies 到本地复用，**24 小时内不再弹**
- 🛡️ **官方 yt-dlp 失效时自动接管**：抖音 / 快手走自研 SSR 分享页解析器，**不依赖会过期的内置 extractor**
- 🎓 **小红书 4K 已验证**：实测可下 3840×2160 HEVC，**不需要登录账号**（仅需 Chrome 访问过一次）

---

## 🚀 快速开始

### 1. 安装本 Skill

```bash
# 克隆到 CodeFlicker 的 skills 目录
git clone https://github.com/<your-username>/video-downloader.git \
  ~/.codeflicker/skills/video-downloader
```

### 2. 安装依赖（一次性）

```bash
brew install yt-dlp ffmpeg aria2
```

> 没装过 Homebrew 先跑：`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`

### 3. 重启 IDE，对 AI 说

> "下载这个视频：https://www.youtube.com/watch?v=xxx"

AI 会自动识别本 Skill、问你要哪种画质（A/B/C），然后跑下载脚本。文件默认保存到 `~/Downloads/`。

详细安装/权限/路径配置见 [`SETUP.md`](./SETUP.md)。

---

## 📦 支持的平台

| 平台 | URL 模式示例 | 后端 | 关键说明 |
|------|---|---|---|
| **YouTube** | `youtube.com/watch?v=` / `youtu.be/` / `/shorts/` | yt-dlp | 推荐 `--cookies-from-browser` 走登录态绕限速；可达 4K/8K AV1 |
| **Bilibili** | `bilibili.com/video/BVxxx` / `b23.tv/xxx` | yt-dlp | ⚠️ 720P+ 必须登录态；HEVC/4K 需大会员 |
| **抖音 (Douyin)** | `douyin.com/video/xxx` / `v.douyin.com/xxx` | **自研** SSR 脚本 | yt-dlp 内置 extractor 2025 起失效；本 Skill 走分享页获取无水印版本。**quality 拿原始 master（可能 4K60 HEVC）**、compat 拿 1080p、speed 拿 720p（隐藏 `/play/?ratio=default\|1080p\|720p` 参数解锁）|
| **小红书 (RedNote)** | `xiaohongshu.com/discovery/item/<id>?xsec_token=...` | yt-dlp | 裸跑 720p；带 Chrome 的匿名 `web_session` cookie 即可拿到 **4K HEVC**（无需账号登录）|
| **快手 (Kuaishou)** | `kuaishou.com/short-video/<id>` / `v.kuaishou.com/<code>` | **自研** SSR 脚本 | yt-dlp 无内置 extractor；本 Skill 走分享页 SSR，**无需登录** |
| **微博** | `weibo.com/.../xxx` / `m.weibo.cn/status/xxx` | yt-dlp | 公开微博无需登录，可拿到 **4K (2160p60)** |
| **Twitter / X** | `x.com/.../status/` / `twitter.com/.../status/` | yt-dlp | 公开推文无需 cookies |
| **Vimeo** | `vimeo.com/xxx` | yt-dlp | 私密视频需密码 |
| **TikTok** | `tiktok.com/@xxx/video/` | yt-dlp | 国区视频可能需要 cookies |

> 此外，凡是 yt-dlp 支持的 1700+ 站点都能跑通用流程：`yt-dlp --list-extractors`。

---

## 🎬 三种下载策略

| 策略 | 画质上限 | 文件大小 | macOS QuickTime |
|------|---------|---------|---|
| **A. 质量优先** | 平台最高（4K/8K AV1/HEVC）| 最大 | ⚠️ AV1/VP9/HEVC 可能要 IINA/VLC |
| **B. 速度优先** | ≤480p | 最小 | ✅ 原生 |
| **C. 兼容优先**（推荐）| 1080p H.264 + AAC | 适中 | ✅ 双击即播 |

每次下载前 AI 都会**主动询问你**选哪一档，不会替你做决定。

---

## 🎯 直接用脚本（不通过 AI Skill）

### 推荐：两步法（先解析再选档）

```bash
# Step 1: 解析（不下载），查看视频信息 + 所有可下档位 + 每档大小
bash scripts/probe.sh --human "https://www.youtube.com/watch?v=xxx"

# 输出类似：
# ================================================================
# 平台    : youtube
# 标题    : Big Buck Bunny
# 作者    : Blender Foundation
# 时长    : 9m56s
# ----------------------------------------------------------------
#   # 画质           编码         容器   大小      备注
# ----------------------------------------------------------------
#   0 1080p AV1      av1+aac      mp4    52.3 MiB
#   1 1080p H264     h264+aac     mp4    78.1 MiB
#   2 720p H264      h264+aac     mp4    41.2 MiB
#   3 480p H264      h264+aac     mp4    18.4 MiB
# ================================================================

# Step 2: 按上面看到的行号下载
bash scripts/download.sh --format 1 "https://www.youtube.com/watch?v=xxx"
#                                ^^^ 选第 1 行 (1080p H264, 78.1 MiB)
```

### 一键预设（不需要先 probe）

```bash
# quality / speed / compat
bash scripts/download.sh quality "https://www.youtube.com/watch?v=xxx"
bash scripts/download.sh compat  "https://www.bilibili.com/video/BV1xxx"
bash scripts/download.sh quality "https://www.xiaohongshu.com/discovery/item/xxx?xsec_token=xxx"

# 抖音 / 快手会自动委派到对应专用脚本
bash scripts/download.sh compat  "https://v.douyin.com/xxxxxxx/"
bash scripts/download.sh compat  "https://v.kuaishou.com/xxxxxxx"

# 自定义输出目录（默认 ~/Downloads）
bash scripts/download.sh quality "<URL>" "$HOME/Movies/archive"
```

### 环境变量

| 变量 | 作用 |
|---|---|
| `VDL_BROWSER=safari\|firefox\|chrome` | 显式指定从哪个浏览器读 cookies |
| `VDL_USE_CHROME=1` | 强制使用 Chrome（即使平台不需要登录） |

### 缓存路径

```
~/.cache/video-downloader/
├── chrome-cookies.txt    # 一次导出的 Chrome cookies (24h TTL)
└── cookies.cache         # 浏览器选择缓存
```

清缓存：`rm -rf ~/.cache/video-downloader`

---

## 🍎 macOS Keychain 弹窗，怎么办？

第一次让 yt-dlp 读 Chrome cookies 时，macOS 会弹一次 **「security 想要使用 Chrome Safe Storage」** 的钥匙串密码框。

**本 Skill 已优化**：弹窗时输 Mac 密码点 **「始终允许」**，cookies 会立刻导出到 `~/.cache/video-downloader/chrome-cookies.txt`，后续 24 小时内**所有运行都读这个本地文件，永远不再弹**。

不想看到弹窗？设环境变量：
- `VDL_BROWSER=safari` —— 用 Safari，零弹窗
- `VDL_BROWSER=firefox` —— 用 Firefox，零弹窗

完整说明见 [`SETUP.md`](./SETUP.md#step-4处理-mac-钥匙串弹窗)。

---

## 📁 项目结构

```
video-downloader/
├── README.md                       # 你正在看的这个
├── SKILL.md                        # AI 用的 Skill 主入口（YAML frontmatter + 工作流）
├── SETUP.md                        # 小白用户安装指南
├── CHANGELOG.md                    # 版本变更记录
├── LICENSE                         # MIT
├── scripts/
│   ├── download.sh                 # 统一入口：自动平台识别 + 委派
│   ├── download-douyin.sh          # 抖音 SSR 解析器
│   └── download-kuaishou.sh        # 快手 SSR 解析器
└── references/
    └── format-reference.md         # 各平台编码 / format id / 选择器速查
```

---

## 🤝 贡献

发现某个平台失效了？yt-dlp 升级后某个特性变了？欢迎提 Issue 或 PR。

特别欢迎：
- 新平台的 SSR 解析器（仿 `download-douyin.sh` / `download-kuaishou.sh` 写法）
- 平台兼容性更新（验证后改 SKILL.md / format-reference.md）
- 国际化（让 SKILL.md 也支持英文触发词）

---

## 📜 License

[MIT](./LICENSE)

---

## ⚠️ 免责声明

本工具仅协助用户下载有权访问的内容：
- ❌ 不绕过付费墙
- ❌ 不下载受 DRM 保护的内容
- ❌ 不破解会员专享内容
- ✅ 仅整理 yt-dlp 已有能力 + 解决 macOS 上的体验摩擦

下载内容请遵守对应平台的服务条款与版权法。
