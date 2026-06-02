# 平台特定要点 + 错误处理

本文件汇总各视频平台的下载要点、URL 模式、登录态要求、画质上限、以及常见错误的修复方式。SKILL.md 主流程会在需要时引用本文件。

## 平台速查表

| 平台 | URL 模式 | 后端 | 登录态 | 画质上限 |
|------|---------|------|--------|---------|
| YouTube | `youtube.com/watch?v=` / `youtu.be/` / `youtube.com/shorts/` | yt-dlp | 推荐（绕限速） | 4K/8K AV1 |
| Bilibili | `bilibili.com/video/BV*` / `b23.tv/*` | yt-dlp | **720P+ 必须** | 4K HEVC |
| 抖音 | `douyin.com/video/*` / `v.douyin.com/*` / `iesdouyin.com/share/video/*` | **自研脚本** | 无需 | 4K60 HEVC（取决于上传者）|
| 小红书 | `xiaohongshu.com/explore/*` / `xhslink.com/a/*` | yt-dlp | 匿名 web_session 即可 | 4K HEVC |
| 快手 | `kuaishou.com/f/*` / `v.kuaishou.com/*` / `m.gifshow.com/fw/photo/*` | **自研脚本** | 无需 | 720p HEVC |
| 微博 | `weibo.com/*/<id>` / `video.weibo.com/show?fid=*` | yt-dlp | 公开内容无需 | 2160p60 |
| Twitter/X | `twitter.com/.../status/` / `x.com/.../status/` | yt-dlp | 部分私密推文需 | 平台最高 |
| Vimeo | `vimeo.com/*` | yt-dlp | 私密视频需密码 | 平台最高 |
| TikTok | `tiktok.com/@*/video/` | yt-dlp | 国区可能需 | 平台最高 |
| 其他 1700+ 站点 | 见 `yt-dlp --list-extractors` | yt-dlp | 视具体而定 | 视具体而定 |

---

## YouTube

- 必备 `--extractor-args "youtube:player_client=ios,web_safari"` 绕 throttle
- 限速主要靠 cookies + iOS 客户端 + 分片并发解决
- AV1 / VP9 是默认最高画质，部分播放器 / 移动端不支持（如 macOS QuickTime、Windows 资源管理器缩略图）

## Bilibili (B 站)

- ⚠️ **720P / 1080P / 4K 必须登录**，否则只能拿 480x640
- HEVC（hev1.*）是 B 站主推，文件小但部分播放器不直接支持
- 用户没登录浏览器：建议先去浏览器登录 B 站再重试
- B 站有"番剧"（bangumi）、"课程"（cheese）、"音频"等专门 extractor，URL 格式会自动识别

## 抖音 (Douyin)

- ⚠️ **yt-dlp 内置 extractor 自 2025 年起已失效**（需要复杂的 `a_bogus` 风控签名）
- 本 skill 走 **移动端分享页 SSR 接口**：`https://www.iesdouyin.com/share/video/{aweme_id}/`
- 流程：
  1. 用户给的 URL（短链 `v.douyin.com/xxx` / 长链 `douyin.com/video/xxx`）→ 提取 `aweme_id`
  2. 用 iOS UA 请求分享页 → 解析 HTML 中的 `play_addr` JSON
  3. 优先尝试 `play`（无水印）版本，回退到 `playwm`（带水印）
- **画质三档（通过隐藏的 `/play/?ratio=` 参数解锁）**：
  - `speed` → `ratio=720p` → 720p H.264 转码，文件最小
  - `compat` → `ratio=1080p` → 1080p H.264 转码，任意播放器兼容
  - **`quality` → `ratio=default` → 原始 master 文件（上传者提供什么就下什么）**，实测可拿 **4K60 HEVC**——这是唯一拿 4K 的路径
  - 关键隐藏机制：`/playwm/` 端点彻底忽略 ratio 参数只返 720p 水印版；`/play/` 端点才看 ratio；分享 URL 默认写死 `ratio=720p`，脚本会自动重写
- 自动尝试无水印版本（把 URL 里的 `playwm` 换成 `play`，并改写 ratio 参数）
- 不需要登录、不需要 cookies

## 小红书 (Xiaohongshu / RedNote)

- URL **必须包含 `xsec_token`**（从 App 分享按钮复制，不要从浏览器地址栏复制）
- 画质两档：
  - 裸 yt-dlp（无任何 cookies）→ **720p H.264**
  - 带 Chrome 里的匿名 `web_session` cookie（**匿名 session、不需登录**，只要用 Chrome 访过一次小红书就有）→ **最高 4K (3840×2160) HEVC**，含 1440p/1080p/720p、H.264/HEVC 多档
  - 私密笔记才需要真正登录态
- 服务端验证方法：调 `edith.xiaohongshu.com/api/sns/web/v2/user/me`，返回 `"guest":true` 是匿名、`"guest":false` + `nickname` 是真登录
- 用户选 `quality` 模式下小红书时，主动提示："小红书裸 yt-dlp 只能拿 720p，要 4K 需要读取 Chrome 的匿名 session cookie（第一次会弹一次钥匙串请点『始终允许』）"

## 快手 (Kuaishou)

- yt-dlp 无内置 extractor，本 skill 走 SSR 分享页解析 inline 的 mp4 直链
- 无需登录，已验证可下 720p HEVC

## 微博

- yt-dlp 内置 extractor 已能自动拿 guest cookies，**公开微博无需登录**，可拿到最高 4K (2160p60)
- 是全 skill 里画质上限最高的之一
- 提醒用户 `quality` 模式可能下到 300+ MB 的大文件
- 仅限粉丝 / 仅可见的动态才需要登录 cookies

## Twitter / X

- 大部分公开推文不需要 cookies
- 包含视频的推文会自动抽取最高码率版本
- 引用了 video 的转推也能下

## 通用

- 任何 yt-dlp 支持的站点都能跑：`yt-dlp --list-extractors` 查列表
- 遇到不认识的 URL 直接传给 yt-dlp 试一下，多数情况能下

---

## 错误处理速查

| 错误 | 处理 |
|------|------|
| `yt-dlp not found` / `ffmpeg not found` | `brew install yt-dlp ffmpeg` |
| YouTube `Sign in to confirm you're not a bot` | 用 `--cookies-from-browser` |
| B 站 `Format(s) 720P 准高清 are missing; you have to become a premium member` | **不是真要会员**，是要登录态。提示用户在浏览器登录 B 站后重试 |
| B 站 `404 / 视频已失效` | 视频被删 / 下架 |
| 抖音 `Fresh cookies (not necessarily logged in) are needed` | yt-dlp 内置 extractor 失效；本 skill 已自动改走 `download-douyin.sh` 绕开 |
| 抖音 `cannot extract aweme_id` | URL 格式不识别，请用户检查链接是否完整 |
| 抖音 `cannot find play_addr in share page` | 抖音分享页结构变了；可能需要更新脚本里的正则 |
| `Video unavailable` / 地区限制 | 提示用户切换代理节点 |
| `HTTP Error 403` | 等待几分钟重试，YouTube 可换 `tv_embedded` 客户端 |
| Deno JS challenge 失败 | `brew upgrade yt-dlp` 或 `pip3 install -U yt-dlp` |
