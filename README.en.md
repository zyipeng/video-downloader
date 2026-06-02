# video-downloader

> An AI Agent **Skill** for the [CodeFlicker / MyFlicker IDE](https://github.com/CodeFlicker), letting your AI assistant download videos from 9 major platforms straight to your disk. Built on `yt-dlp` + custom SSR-page parsers, with a focus on **macOS one-click usability**, **quality presets**, and **parallel-fragment speed**.

[![version](https://img.shields.io/badge/version-2.7.0-blue.svg)](./CHANGELOG.md)
[![license](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)
[![platforms](https://img.shields.io/badge/platforms-9%20sites-orange.svg)](#supported-platforms)
[![CI](https://img.shields.io/badge/CI-bash%20syntax%20check-success.svg)](./.github/workflows/shellcheck.yml)

中文版 README 见 [`README.md`](./README.md)。

---

## ✨ Highlights

- 🎯 **9 platforms work out of the box**: YouTube / Bilibili / Douyin (TikTok-CN) / Xiaohongshu (RedNote) / Kuaishou / Weibo / Twitter (X) / Vimeo / TikTok
- 🎬 **Three quality presets**: Quality-First (up to 4K/8K AV1) / Speed-First (≤480p) / Compatible (1080p H.264, native QuickTime)
- 🚀 **16-way parallel downloads** via aria2c — easily saturate your bandwidth on YouTube/Bilibili
- 🍎 **macOS Keychain solved once**: first run prompts Keychain once, exports cookies to a local file, **no more prompts for 24 hours**
- 🛡️ **Auto-fallback when yt-dlp's built-in extractors break**: Douyin / Kuaishou use custom SSR share-page parsers — **no dependency on the often-broken built-in extractors**
- 🎓 **Xiaohongshu 4K verified**: tested 3840×2160 HEVC works with **no account login needed** (just one prior Chrome visit suffices)

---

## 🚀 Quick Start

### 1. Install this Skill

```bash
git clone https://github.com/<your-username>/video-downloader.git \
  ~/.codeflicker/skills/video-downloader
```

### 2. Install dependencies (one-time)

```bash
brew install yt-dlp ffmpeg aria2
```

> No Homebrew yet? Run: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`

### 3. Restart your IDE and tell the AI

> "Download this video: https://www.youtube.com/watch?v=xxx"

The AI will detect this Skill, ask which quality preset (A/B/C) you want, then run the download script. Files are saved to `~/Downloads/` by default.

For detailed install/permissions/path setup, see [`SETUP.md`](./SETUP.md).

---

## 📦 Supported Platforms

| Platform | URL patterns | Backend | Key notes |
|------|---|---|---|
| **YouTube** | `youtube.com/watch?v=` / `youtu.be/` / `/shorts/` | yt-dlp | Recommended: `--cookies-from-browser` to bypass throttling; up to 4K/8K AV1 |
| **Bilibili** | `bilibili.com/video/BVxxx` / `b23.tv/xxx` | yt-dlp | ⚠️ 720P+ requires login session; HEVC/4K needs Premium |
| **Douyin** (TikTok-CN) | `douyin.com/video/xxx` / `v.douyin.com/xxx` | **custom** SSR script | yt-dlp's built-in extractor broke in 2025 (needs `a_bogus` signing); this Skill uses the share page to fetch watermark-free streams. **quality fetches the original master file (up to 4K60 HEVC if the uploader provided it)**, compat gets 1080p H.264, speed gets 720p (via undocumented `/play/?ratio=default\|1080p\|720p` parameter) |
| **Xiaohongshu** (RedNote) | `xiaohongshu.com/discovery/item/<id>?xsec_token=...` | yt-dlp | Plain yt-dlp → 720p only; with Chrome's anonymous `web_session` cookie → **4K HEVC** (no account login needed) |
| **Kuaishou** | `kuaishou.com/short-video/<id>` / `v.kuaishou.com/<code>` | **custom** SSR script | yt-dlp has no built-in extractor; this Skill parses the share page, **no login needed** |
| **Weibo** | `weibo.com/.../xxx` / `m.weibo.cn/status/xxx` | yt-dlp | Public posts need no login, can fetch up to **4K (2160p60)** |
| **Twitter / X** | `x.com/.../status/` / `twitter.com/.../status/` | yt-dlp | Public tweets need no cookies |
| **Vimeo** | `vimeo.com/xxx` | yt-dlp | Private videos need a password |
| **TikTok** | `tiktok.com/@xxx/video/` | yt-dlp | China-region videos may need cookies |

> Plus any of the **1700+ sites yt-dlp supports** via the generic flow: `yt-dlp --list-extractors`.

---

## 🎬 Three Download Strategies

| Strategy | Quality ceiling | File size | macOS QuickTime |
|------|---------|---------|---|
| **A. Quality-First** | Platform max (4K/8K AV1/HEVC) | Largest | ⚠️ AV1/VP9/HEVC may need IINA/VLC |
| **B. Speed-First** | ≤480p | Smallest | ✅ Native |
| **C. Compatible** (recommended) | 1080p H.264 + AAC | Medium | ✅ Double-click to play |

The AI **always asks you** before downloading — it never picks a preset for you silently.

---

## 🎯 Use the script directly (without an AI Skill)

### Recommended: two-step workflow (probe first, then pick)

```bash
# Step 1: Probe (no download). Shows video info + all available qualities + size of each
bash scripts/probe.sh --human "https://www.youtube.com/watch?v=xxx"

# Output looks like:
# ================================================================
# Platform: youtube
# Title   : Big Buck Bunny
# Uploader: Blender Foundation
# Duration: 9m56s
# ----------------------------------------------------------------
#   # Quality        Codec        Ext    Size       Note
# ----------------------------------------------------------------
#   0 1080p AV1      av1+aac      mp4    52.3 MiB
#   1 1080p H264     h264+aac     mp4    78.1 MiB
#   2 720p H264      h264+aac     mp4    41.2 MiB
#   3 480p H264      h264+aac     mp4    18.4 MiB
# ================================================================

# Step 2: Download by row number
bash scripts/download.sh --format 1 "https://www.youtube.com/watch?v=xxx"
#                                ^^^ picks row #1 (1080p H264, 78.1 MiB)
```

### One-liner presets (no probe needed)

```bash
# quality / speed / compat
bash scripts/download.sh quality "https://www.youtube.com/watch?v=xxx"
bash scripts/download.sh compat  "https://www.bilibili.com/video/BV1xxx"
bash scripts/download.sh quality "https://www.xiaohongshu.com/discovery/item/xxx?xsec_token=xxx"

# Douyin / Kuaishou auto-delegate to their dedicated scripts
bash scripts/download.sh compat  "https://v.douyin.com/xxxxxxx/"
bash scripts/download.sh compat  "https://v.kuaishou.com/xxxxxxx"

# Custom output directory (default: ~/Downloads)
bash scripts/download.sh quality "<URL>" "$HOME/Movies/archive"
```

### Environment variables

| Variable | Effect |
|---|---|
| `VDL_BROWSER=safari\|firefox\|chrome` | Explicitly pick a browser to read cookies from |
| `VDL_USE_CHROME=1` | Force Chrome cookies even when the platform doesn't require login |

### Cache paths

```
~/.cache/video-downloader/
├── chrome-cookies.txt    # Exported Chrome cookies (24h TTL)
└── cookies.cache         # Browser-choice cache
```

Reset cache: `rm -rf ~/.cache/video-downloader`

---

## 🍎 macOS Keychain Prompt — What to Do?

The first time `yt-dlp` reads Chrome cookies on macOS, you'll see:

> "security wants to use the confidential information stored in Chrome Safe Storage in your keychain"

**This Skill optimizes that**: enter your Mac password, click **"Always Allow"** — cookies get exported immediately to `~/.cache/video-downloader/chrome-cookies.txt`. For the next 24 hours, **every run reads that local file and never prompts again**.

Don't want to see the prompt at all? Set:
- `VDL_BROWSER=safari` — use Safari, zero prompts
- `VDL_BROWSER=firefox` — use Firefox, zero prompts

Full guide in [`SETUP.md`](./SETUP.md).

---

## 📁 Project Structure

```
video-downloader/
├── README.md                       # Chinese version (default)
├── README.en.md                    # This file
├── SKILL.md                        # AI Skill entry (YAML frontmatter + workflow)
├── SETUP.md                        # End-user install guide
├── CHANGELOG.md                    # Version history
├── LICENSE                         # MIT
├── .github/workflows/
│   └── shellcheck.yml              # CI: bash -n + ShellCheck
├── scripts/
│   ├── download.sh                 # Unified entry: platform detection + delegation
│   ├── download-douyin.sh          # Douyin SSR parser
│   └── download-kuaishou.sh        # Kuaishou SSR parser
└── references/
    └── format-reference.md         # Per-platform codecs / format ids / selector cheatsheet
```

---

## 🤝 Contributing

Found a platform that broke? yt-dlp dropped some functionality? PRs welcome.

Especially appreciated:
- New platform SSR parsers (mirroring `download-douyin.sh` / `download-kuaishou.sh`)
- Platform compatibility updates (verified, then patch SKILL.md / format-reference.md)
- Localization (more English trigger phrases in SKILL.md, etc.)

### CI

Every push runs `bash -n` syntax checks on all `scripts/*.sh` via [`.github/workflows/shellcheck.yml`](./.github/workflows/shellcheck.yml). ShellCheck warnings are reported but non-blocking.

---

## 📜 License

[MIT](./LICENSE)

---

## ⚠️ Disclaimer

This tool only assists users in downloading content they have legitimate access to:
- ❌ Does NOT bypass paywalls
- ❌ Does NOT download DRM-protected content
- ❌ Does NOT crack member-only content
- ✅ Only packages existing yt-dlp capabilities + smooths macOS UX rough edges

Please respect each platform's Terms of Service and applicable copyright laws when downloading.
