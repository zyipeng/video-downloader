# Multi-Platform Format Reference

## YouTube

### 视频流编码

| 编码 | 说明 | 播放器兼容性 |
|------|------|-----------------|
| H.264 (AVC, `avc1.*`) | 最广泛兼容 | ✅ |
| VP9 (`vp9`) | 1080p 文件比 H.264 小 30–40% | ❌ |
| AV1 (`av01.*`) | 文件最小、画质最好 | ❌（需 IINA/VLC） |

### 音频流编码

| 编码 | 容器 | 播放器兼容性 |
|------|------|-----------|
| AAC (`mp4a.40.*`) | m4a | ✅ |
| Opus | webm | ❌ |

### 常用 format id

| ID | 分辨率 | 编码 |
|----|--------|------|
| 137 | 1080p | H.264 |
| 248 | 1080p | VP9 |
| 399 | 1080p | AV1 |
| 136 | 720p | H.264 |
| 140 | 音频 | AAC 128k m4a |
| 251 | 音频 | Opus 128k webm |

### 速度优化

| 选项 | 作用 |
|------|------|
| `--concurrent-fragments 16` | DASH 分片并发 |
| `--http-chunk-size 10M` | 单流走分块 |
| `--downloader aria2c` + `-x 16 -s 16` | 外部多线程 |
| `--extractor-args "youtube:player_client=ios,web_safari"` | 绕 web throttle |
| `--cookies-from-browser chrome` | 走登录态，限速更宽 |

---

## Bilibili (B 站)

### 视频流编码

| 编码 | 说明 | 播放器兼容性 |
|------|------|-----------------|
| H.264 / AVC (`avc1.*`) | 兼容性最好 | ✅ 任意播放器 |
| HEVC / H.265 (`hev1.*`, `hvc1.*`) | B 站主推，文件小 30–50% | ⚠️ 需现代播放器（IINA/VLC/PotPlayer）或新系统 |
| AV1 (`av01.*`) | 实验性 | ⚠️ 需现代播放器 |

### 关键限制 ⚠️

**未登录 / guest mode**：
- 最高分辨率：**480x640（小竖屏视频）**或 **480p（横屏）**
- 报错：`Format(s) 720P 准高清 are missing; you have to become a premium member to download them.`
- ❗ 这个报错**不准确** —— 实际只需要登录态，**不需要会员**

**登录态（`--cookies-from-browser`）**：
- 普通用户：可下 720P / 1080P
- 大会员：可下 4K / 杜比视界 / Hi-Res 音频

### 推荐 format selector

```bash
# 兼容（H.264 1080p） - 推荐
-f "bv*[vcodec^=avc1]+ba/b[ext=mp4]"

# 最高画质（可能是 HEVC 4K）
-f "bv*+ba/b"

# 限制 480p 快速下载
-f "bv*[height<=480]+ba/b[height<=480]"
```

### URL 模式

| URL | 类型 |
|-----|------|
| `bilibili.com/video/BV1xxx` | 单集视频 |
| `bilibili.com/video/BV1xxx?p=2` | 分 P 视频，`?p=N` 选第 N 集 |
| `b23.tv/xxx` | 短链，自动跳转 |
| `bilibili.com/bangumi/play/ssxxx` | 番剧（有 DRM 风险） |
| `bilibili.com/cheese/play/ssxxx` | 付费课程（不要尝试） |

---

## 抖音 (Douyin)

### 为什么不能用 yt-dlp 内置 extractor

2025 年起，抖音 web 接口 (`/aweme/v1/web/aweme/detail/`) 加入了 `a_bogus` 风控签名，需要从 JavaScript 执行出一个上百行混淆函数才能拿到。yt-dlp 2026.03.17 还没适配，报错：

```
ERROR: [Douyin] xxxx: Fresh cookies (not necessarily logged in) are needed
```

### 变通方案：走分享页 SSR

抖音为了让 iOS Safari / 微信内置浏览器能看视频，保留了一个 SSR 版本的分享页：

```
https://www.iesdouyin.com/share/video/{aweme_id}/
```

这个页面会直接把 `play_addr` 嵌在 HTML 里（用 iOS UA 请求），**不需要任何签名、不需要 cookies**。

### 抽取步骤

```bash
# 1) 短链 → aweme_id
curl -sIL "https://v.douyin.com/hzp-WF5AEBc/" -A "<iOS UA>" | grep -i location
# location: https://www.iesdouyin.com/share/video/7626335093930735461/?...

# 2) 请求分享页
curl -sL "https://www.iesdouyin.com/share/video/7626335093930735461/" -A "<iOS UA>" -o dy.html

# 3) 从 HTML 里 grep play_addr
grep -oE '"play_addr":\{[^}]+\}' dy.html
# 输出: "play_addr":{"uri":"v2800fgi0000d7b2ug7og65m3b02s19g",
#         "url_list":["https://aweme.snssdk.com/aweme/v1/playwm/?...&video_id=v2800fgi0000d7b2ug7og65m3b02s19g"]}

# 4) 下载（可选：把 playwm 换成 play 拿无水印版本）
curl -L -A "<iOS UA>" -o video.mp4 \
  "https://aweme.snssdk.com/aweme/v1/play/?line=0&video_id=v2800fgi0000d7b2ug7og65m3b02s19g"
```

### 画质三档（实测隐藏机制）

抖音 SSR 分享页本身只给一个 720p 带水印的 URL，但服务端背后有两个未公开参数可以解锁更高画质（被第三方卸水印站一直在用，稳定多年）：

| URL 路径 | ratio 参数 | 返回什么 | 备注 |
|---|---|---|---|
| `/playwm/` | （徽底忽略）| **总是 720p H.264 + 水印** | 默认分享 URL 用的路径 |
| `/play/` | `?ratio=720p` | **720p H.264 转码**、无水印 | 文件最小 |
| `/play/` | `?ratio=1080p` | **1080p H.264 转码**、无水印 | 任意播放器兼容 |
| `/play/` | **`?ratio=default`** | **原始 master 文件**、无水印 | 可能是 4K60 HEVC / 1080p H.264 / 任意上传码率 |

所以本 skill 的 mode 映射：
- `speed` → `ratio=720p`
- `compat` → `ratio=1080p`
- **`quality` → `ratio=default`**（**唯一能拿 4K 的路径**）

脚本会自动把 `playwm` 重写为 `play`、把 `ratio=720p` 重写为选定的值。

### 注意

- `quality` 拿到的是**上传者提供的原始文件**——如果原作者只传了 1080p，那拿到的就是 1080p；只有原作者传了 4K 才能拿 4K
- 原始 master 可能是 HEVC（部分播放器不支持）或 H.264，需要看 `ffprobe` 输出确认
- 不是所有视频都能拿到 4K，但 `ratio=default` 总是 >= `ratio=1080p` 的画质

### 原本该节原始记录（次序保留下方）

- 分享 API 原生只提供 720p H.264 + AAC（默认 URL）；该限制已被 `/play/?ratio=` 隐藏参数突破
- web detail API + a_bogus 签名则是拿 4K 的另一条路（本 skill 不走这条，太脆弱）
- 播放器兼容性：720p/1080p H.264 任意播放器可播；4K HEVC 需现代播放器（IINA / VLC / PotPlayer）或 macOS 14+

### URL 模式

| URL | 类型 |
|-----|------|
| `v.douyin.com/xxxxxxx/` | 短链，302 跳转到 `iesdouyin.com/share/video/xxx` |
| `iesdouyin.com/share/video/xxx/` | 分享页，可直接抽 `play_addr` |
| `www.douyin.com/video/xxx` | 正常 web 页，aweme_id 在 URL 里 |
| `www.douyin.com/?modal_id=xxx` | 从推荐流点进去的弹层，aweme_id 在 query 里 |

---

## Twitter / X

- 公开推文：直接下，不需 cookies
- 推文里有多个视频（图文混排）：yt-dlp 会全部下载或下第一个
- 自动选最高码率（一般是 1080p H.264）

```bash
yt-dlp "https://x.com/user/status/1234567890"
```

---

## 通用

### 容器对比

| 容器 | 适合 | 限制 |
|------|------|------|
| **mp4** | H.264/H.265 + AAC | 任意播放器都能播 |
| **mkv** | 任意编码（AV1/Opus 都行） | 需现代播放器（VLC/IINA/PotPlayer）|
| **webm** | VP9/AV1 + Opus | 需现代播放器（VLC/IINA/PotPlayer）|

### yt-dlp format selector 速查

```text
bv*+ba/b                                  # 最高码率（不限编码）
bv*[vcodec^=avc1]+ba[ext=m4a]/b[ext=mp4]  # 强制 H.264+AAC，macOS 友好
bv*[height<=720]+ba/b[height<=720]        # 限制最高 720p
bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]       # 强制 mp4 容器
137+140                                   # YouTube：直接指定 1080p H.264 + AAC
```

### 通用错误处理

| 错误 | 处理 |
|------|------|
| `Sign in to confirm` (YouTube) | `--cookies-from-browser` |
| `720P 准高清 are missing` (B 站) | 浏览器登录 B 站后重试 |
| `HTTP Error 403` | 等几分钟，或换 player_client |
| `Video unavailable` | 地区限制，换代理节点 |
| Deno JS challenge 失败 | `brew upgrade yt-dlp` |
| 下载慢 ~80 KB/s | 多半代理节点拥塞，先测节点裸速 |

---

## 小红书 / Xiaohongshu / RedNote

### 工作原理

yt-dlp 内置的 `XiaoHongShu` extractor：
1. GET 笔记网页（`xiaohongshu.com/explore/<id>` 或 `discovery/item/<id>?xsec_token=...`）
2. 从 HTML 里 grep 出 `window.__INITIAL_STATE__` 这个全局 JSON
3. 解析 `note.video.media.stream.{h264,h265,av1}[].master_url`
4. 用浏览器 cookies（关键是 `web_session`）获得授权，单流直接下 MP4

### 关于 `web_session` （重点）

`web_session` 是小红书服务端下发的一个 session token，**名字误导**。它有两种状态：

| 状态 | 调 `https://edith.xiaohongshu.com/api/sns/web/v2/user/me` | 能下什么 |
|------|----|------|
| **匿名 session**（用户没登录、但浏览器访过小红书） | `"guest": true`、有 user_id | **公开笔记的 4K/1440p/1080p HEVC 全部拿到手** ✅ |
| **登录 session**（用户点了登录按钮） | `"guest": false`、有 nickname | 上面那些 + 私密笔记 |

**实验验证结果**：

| Cookie 组合 | yt-dlp 看到的 formats | 最高能下 |
|---|---|---|
| 完全无 cookies | 1 档：720p H.264 | 720p |
| 只带 `a1`（设备指纹） | 1 档：720p H.264 | 720p |
| **只带 `web_session`（匿名）** | **15 档：720p ~ 4K HEVC 全套** | **4K** ✅ |
| 全套 chrome cookies | 15 档 | 4K |

结论：**4K 解锁的充分条件 = 带上任意一个 `web_session`**（匿名、登录都行）。这是平台对裸 yt-dlp 这种「无 session」请求的低画质降级，不是登录限制。

### 硬性前提

| 前提 | 说明 |
|------|------|
| Chrome 访问过小红书一次 | 服务端才会下发 `web_session`；不需账号登录 |
| URL 包含 `xsec_token` | discovery 链接不带 token 会拿不到流 URL |
| Chrome v10 cookie 可解密 | macOS 需要 keyring 权限（首次点「始终允许」即可）；如果失败可切 `safari` / `firefox` |

### URL 模式

| 类型 | 示例 |
|------|------|
| explore | `https://www.xiaohongshu.com/explore/<24位hex>` |
| discovery | `https://www.xiaohongshu.com/discovery/item/<id>?xsec_token=ABC...&xsec_source=pc_share` |
| 短链 | `http://xhslink.com/a/<短码>` |

### 重要：单流 MP4，不是分离 DASH

不像 YouTube 的 video-only + audio-only 分离流，小红书 extractor 直接返回**视频 + 音频已合并**的 MP4 单流：

```
# 带 web_session，15 个 formats（3 个 CDN 镜像 × 5 个画质档）
[xhs] format_id=0,1,2     720x1280   vcodec=h264  acodec=aac
[xhs] format_id=3,4,5     720x1280   vcodec=hevc  acodec=aac
[xhs] format_id=6,7,8     1080x1920  vcodec=hevc  acodec=aac
[xhs] format_id=9,10,11   1440x2560  vcodec=hevc  acodec=aac
[xhs] format_id=12,13,14  3840x2160  vcodec=hevc  acodec=aac  ← 4K
```

**所以选择器必须是 `b[...]` 格式，不能用 `bv*+ba` 合并选择器**（合并选择器会报 "Requested format is not available"）。

⚠️ vcodec 字段值是 `h264` / `hevc`（小写裸码字），**不是** `avc1.xxx` / `hev1.xxx`。所以过滤器要用 `vcodec*=h264` 而不是 `vcodec^=avc1`。

### 平台天花板

- 最高分辨率：**4K （ 3840×2160 ）**货真价实，仅 HEVC
- 最高帧率：47fps
- 编码：H.264（720p） / HEVC（1080p、 1440p、 4K）
- 音频：AAC 64kbps（h264 流） / 128kbps（hevc 流）

### 常见错误归因表

| stderr 关键词 | 原因 | 解决 |
|---------------|------|------|
| `Unable to extract initial state` | 触发了反爬 / 验证码 | 浏览器打开链接，过验证码后重试 |
| `Requested format is not available` + cookies 失败 | Chrome v10 解密失败 | `--cookies-from-browser safari/firefox` |
| `No video formats found` | URL 缺 `xsec_token` 或是私密笔记 | 从 App 重新分享拿带 xsec_token 的链接；私密笔记需登录 |
| 只拿到 720p，拿不到 4K | 没带 `web_session` cookie（裸 yt-dlp） | 设 `VDL_USE_CHROME=1` 走 chrome cookies；或者先用 Chrome 访问一次小红书以建立 session |
| `Extractor failed to obtain "title"` | URL 缺 `xsec_token` | 从 App 分享按钮重新复制，不要从浏览器地址栏 |
