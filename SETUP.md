# Video Downloader · 小白用户安装指南

> 给完全没用过命令行的人看的「一次配好，终身受用」清单。

---

## 总览（你需要做的事）

按下面 5 个步骤一次性配好，之后就**不用再管**。整个过程在 macOS 上大概需要 **5–10 分钟**（取决于 Homebrew 是否已装）。

| 步骤 | 做什么 | 是否必须 | 一次性？ |
|------|------|---------|---------|
| 1 | 装 Homebrew（包管理器） | 必须（如果没装过） | ✅ 一次性 |
| 2 | 装 yt-dlp + ffmpeg + aria2 | 必须 | ✅ 一次性 |
| 3 | 浏览器登录视频网站（B 站 / 小红书） | 仅下载 B 站/小红书时必须 | ✅ 一次性 |
| 4 | 处理 Mac 钥匙串弹窗（Chrome cookies） | 仅用 Chrome 下载 B 站/小红书时遇到 | ✅ 一次"始终允许"即可 |
| 5 | 选下载存储路径 | 推荐确认一次 | ✅ 一次性 |

---

## Step 1：安装 Homebrew（包管理器）

打开「终端」(Terminal.app)，粘贴这一行回车：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

中途会要求输一次 Mac 登录密码（`sudo` 用），这是**正常的**——Homebrew 需要把自己装到 `/opt/homebrew/`。

**如何确认装好了**：
```bash
brew --version
# 应该输出类似 "Homebrew 4.x.x"
```

> 已经有 Homebrew 的可以跳过本步。

---

## Step 2：安装下载工具（yt-dlp + ffmpeg + aria2）

在终端跑：

```bash
brew install yt-dlp ffmpeg aria2
```

| 工具 | 作用 | 是否必须 |
|------|-----|---------|
| `yt-dlp` | 解析视频网页、抓视频流 | ✅ 必须 |
| `ffmpeg` | 合并音视频、转码、提取分辨率信息 | ✅ 必须 |
| `aria2` | 16 路并行加速下载 | ⭐ 强烈推荐（不装会用单线程，慢很多） |

**确认装好**：
```bash
yt-dlp --version    # 应该输出 2025+ 的版本号
ffmpeg -version     # 应该输出 ffmpeg 版本信息
aria2c --version    # 应该输出 1.x.x
```

> Skill 在第一次运行时也会**自动检测并尝试安装缺失工具**，所以理论上你不手动跑也行；但提前跑一遍可以避免等待。

---

## Step 3：浏览器登录视频网站（按需）

| 你想下载… | 必须做的事 |
|---------|----------|
| YouTube / Twitter / Vimeo / 微博 / 快手 / 抖音 / 小红书（720p以下） | ❌ **不需要任何登录**，直接下 |
| **B 站 720P 及以上** | ✅ 在 Chrome（或其它常用浏览器）登录 [bilibili.com](https://www.bilibili.com)（不需要大会员，普通账号即可） |
| **小红书 4K / 1440p / 1080p HEVC** | ✅ 在 Chrome 里访问一次 [xiaohongshu.com](https://www.xiaohongshu.com) **即可**（不需要账号登录） |
| **小红书私密笔记** | ✅ 在 Chrome 里登录 [xiaohongshu.com](https://www.xiaohongshu.com) |

> ⚠️ 小红书的上限画质不需要账号登录，但需要 Chrome **访问过一次小红书**以获得匿名 `web_session` cookie。平时你用 Chrome 随便别一下小红书网页就够了，不需要主动账号登录。

### 小红书的额外注意

小红书必须用「**完整分享链接**」——必须包含 `xsec_token` 参数。**正确做法**：

✅ 用手机 App 的"分享"按钮 → 复制链接 → 粘贴给 AI  
❌ 不要从浏览器地址栏复制（地址栏的链接会丢 token，下载会失败）

---

## Step 4：处理 Mac 钥匙串弹窗

如果你下载 **小红书 4K / B 站 HD** 且让 skill 用 Chrome 的 cookies，**第一次**会弹这个：

```
"security 想要使用你储存在钥匙串的 Chrome Safe Storage 中的机密信息"
```

### 为什么弹

Chrome 把它的 cookies 用 AES-256 加密，密钥锁在 macOS 系统钥匙串里。yt-dlp 想读 cookies 解密 → 必须找系统拿密钥 → 弹窗找你授权。

### 本 skill 已优化：一次导出、后续免弹

本 skill 采用「**一次导出 → 本地复用**」策略：

1. 首次运行需要 Chrome cookies 时，弹一次钥匙串 → 立即导出到 `~/.cache/video-downloader/chrome-cookies.txt`（600 权限）
2. 后续 24 小时内，脚本都读本地文件（走 `--cookies <file>` 而不是 `--cookies-from-browser`）——**不再调用 `security` 命令、不再弹钥匙串**
3. 24 小时后文件过期，会再弹一次（用户可手动重置：`rm ~/.cache/video-downloader/chrome-cookies.txt`）

### 弹窗时怎么选（任选一种）

| 方案 | 操作 | 优点 | 缺点 |
|------|-----|------|------|
| **A（推荐）** | 弹窗输 Mac 密码，**点「始终允许」** | 一次性解决，隐式加下面的导出缓存 | — |
| **B（也很推荐）** | 点「允许」也行，然后依赖本 skill 的 24h 本地缓存 | 同样不会反复弹，过期后才会再弹一次 | 过期后会重弹 |
| **C** | 改用 Firefox：先在 Firefox 登录目标网站，执行时设 `VDL_BROWSER=firefox` | 完全没弹窗 | 要在第二个浏览器再登一次 |
| **D** | 设 `VDL_BROWSER=safari` | 同上 | 同上 |
| **E** | 完全不要登录态（B 站画质降到 480p，小红书画质降到 720p） | 零弹窗 | 拿不到 HD |

> ⚠️ **重要**：方案 A 点「**始终允许**」是「永久给 `security` 进入 Chrome 加密区块」；本 skill 的 chrome-cookies.txt 导出机制该点「允许」也能正确工作。两者不冲突。

### 一个错点了「允许」怎么补救

打开「钥匙串访问」(Keychain Access.app) → 搜 `Chrome Safe Storage` → 双击 → 「访问控制」标签 → 把 `/usr/bin/security` 拉进"始终允许的应用程序" → 保存。

或者更暴力：以后都加 `VDL_BROWSER=safari` 环境变量，永远不碰 Chrome。

---

## Step 5：确认下载存储路径

**默认路径**：`~/Downloads`（即 Mac Finder 侧栏的「下载」文件夹）

如果你想改成别的：

### 方法 1（推荐）：每次告诉 AI

> "下载到 `/Users/你的名字/Movies/video-archive/` 里"

AI 会带上自定义路径调用脚本。

### 方法 2：永久改默认值

编辑 `~/.zshrc`（或 `~/.bash_profile`），加一行：
```bash
export VDL_DEFAULT_OUT="$HOME/Movies/video-archive"
```
然后 `source ~/.zshrc`。

> 注意：当前脚本默认还是写死 `~/Downloads`。如果要让脚本读 `VDL_DEFAULT_OUT`，可以告诉 AI "请改 download.sh 默认路径读 VDL_DEFAULT_OUT 环境变量"。

### 几个推荐路径

| 路径 | 适合 |
|-----|------|
| `~/Downloads`（默认） | 偶尔下一两个临时看的视频 |
| `~/Movies/` | 长期收藏 |
| `~/Movies/youtube/`、`~/Movies/bilibili/` | 想分平台归档 |
| 外接硬盘 `/Volumes/MyDrive/videos/` | 视频量大，本地硬盘空间小 |

---

## 常见疑惑速查

### Q1：我装的是 M1/M2/M3 Mac，brew 装哪儿？
A：`/opt/homebrew/`。Intel Mac 是 `/usr/local/Homebrew/`。skill 不在乎，会自动找。

### Q2：之前装过老版本 `youtube-dl`，要卸吗？
A：不用，但**不会用它**。skill 只调 `yt-dlp`。`youtube-dl` 已经多年不更新，遇到 YouTube 新协议会失败。

### Q3：我没装 Homebrew，能用 pip 吗？
A：可以。`pip3 install -U yt-dlp` 装 yt-dlp。`ffmpeg` 必须用 brew/官网/MacPorts，pip 装不了（它是 C 程序不是 Python 包）。

### Q4：要我登录的网站会不会泄漏密码？
A：**不会**。skill 只读取浏览器存的 **cookies**（一串无意义的会话 token），不接触你的密码。cookies 也不会上传到任何地方，全程本地处理。

### Q5：可以一次下一整个播放列表吗？
A：当前 skill 默认 `--no-playlist`，**只下单个视频**。如果需要播放列表批量，可以告诉 AI "去掉 no-playlist"。

### Q6：下载会很慢，怎么办？
A：检查 3 件事：
1. 装了 `aria2c` 没？没装就单线程，慢得多。
2. YouTube 慢可以试试登录 cookie（看 Step 3 的 YouTube 部分）。
3. 国内网络下 YouTube/Twitter 可能需要科学上网工具。

### Q7：所有缓存/配置在哪？我想全部清掉重来
A：
```bash
rm -rf ~/.cache/video-downloader     # cookies 探测缓存
brew uninstall yt-dlp ffmpeg aria2   # 卸载工具
rm -rf ~/.codeflicker/skills/video-downloader  # 删除 skill 本身
```

### Q8：能在 Linux/Windows 上用吗？
A：脚本是 bash + macOS 命令（`security`、Homebrew 路径），没适配 Linux/Windows。Linux 用户可以自己改一下；Windows 用户建议直接用 yt-dlp 命令行或 yt-dlp-gui。

---

## 安装后自检脚本

把下面这段贴到终端跑，会一次性帮你检查所有依赖：

```bash
echo "=== Video Downloader 环境自检 ==="
for tool in brew yt-dlp ffmpeg aria2c; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "✅ $tool : $(command -v $tool)"
  else
    echo "❌ $tool : NOT INSTALLED"
  fi
done

echo ""
echo "=== Cookie 缓存状态 ==="
CACHE_DIR="$HOME/.cache/video-downloader"
if [[ -f "$CACHE_DIR/chrome-cookies.txt" ]]; then
  AGE_HOURS=$(( ($(date +%s) - $(stat -f %m "$CACHE_DIR/chrome-cookies.txt")) / 3600 ))
  echo "✅ Chrome cookies 已导出（${AGE_HOURS}h 前）——近期不会再弹钥匙串"
else
  echo "ℹ️ Chrome cookies 未导出（首次下 B站/小红书4K 时会弹一次钥匙串，点始终允许即可）"
fi

echo ""
echo "=== 默认下载目录 ==="
echo "📁 $HOME/Downloads"
ls -ld "$HOME/Downloads"
```

正常输出：
```
✅ brew : /opt/homebrew/bin/brew
✅ yt-dlp : /opt/homebrew/bin/yt-dlp
✅ ffmpeg : /opt/homebrew/bin/ffmpeg
✅ aria2c : /opt/homebrew/bin/aria2c
ℹ️ 缓存未生成（首次运行 skill 时会自动生成）
📁 /Users/你的名字/Downloads
```

全部 ✅ 就可以放心用了 🎉
